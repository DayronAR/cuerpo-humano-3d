"""
ajustar_piel_femenina.py — Da a la piel femenina una complexión delgada y saludable.

La piel del Visible Human Female corresponde a una mujer con obesidad. Este script reduce la
grasa subcutánea donde corresponde (abdomen, cintura, brazos, piernas) y CONSERVA la
distribución femenina típica (caderas, glúteos, muslos y mamas), que da la silueta natural.

Cómo funciona:
  1. Carga Z-Anatomy (músculos y huesos) con la misma escala y pose de brazos del cuerpo femenino.
  2. Para cada vértice de la piel mide la distancia a la superficie muscular u ósea más cercana
     (= grosor de grasa + piel en ese punto).
  3. Si es mayor que el grosor objetivo de esa zona, acerca el vértice hacia el músculo hasta ese
     grosor. Nunca lo aleja ni lo mete dentro de la anatomía.
  4. Suaviza el desplazamiento para que la superficie quede lisa.

Uso:
    blender -b -Y assets_fuente/z-anatomy/plantilla/Z-Anatomy/Startup.blend \\
        --python tools/ajustar_piel_femenina.py
Salida: assets_fuente/hra-femenino/VH_F_Skin_ajustada.glb (en coordenadas finales del cuerpo).
"""

import json
import math
import os
import re
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import procesar_modelo as pm  # noqa: E402  (reutiliza la escala y la rotación de brazos)

MAPEO = "tools/mapeo_zanatomy_femenino.json"
PIEL = "assets_fuente/hra-femenino/VH_F_Skin.glb"
SALIDA = "assets_fuente/hra-femenino/VH_F_Skin_ajustada.glb"
COLECCIONES = ["4: Muscular system", "1: Skeletal system"]
ITERACIONES_SUAVIZADO = 120

# Grosor objetivo de grasa + piel (m) según la altura (z, con los pies en 0)
PERFIL_GROSOR = [  # (z, grosor)
    (0.00, 1.0), (0.50, 1.0),                                      # piernas: sin cambio
    (0.62, 0.030), (0.78, 0.034),                                  # muslos algo más delgados
    (0.86, 0.045), (0.95, 0.042),                                  # caderas y glúteos: casi sin cambio (curvas)
    (1.03, 0.016), (1.10, 0.012), (1.20, 0.013), (1.32, 0.016),    # cintura y abdomen
]
Z_DESDE = (0.50, 0.62)       # Transición suave entre las piernas (sin cambio) y los muslos
GROSOR_BRAZO = 0.003
Z_SIN_CAMBIO = 1.42          # Cuello y cabeza quedan igual
RADIO_MAMA = (0.08, 0.13)    # Alrededor del pezón: sin cambio hasta 8 cm, transición hasta 13 cm
# Torso: cintura y vientre por franjas de altura (deformación suave, sin bordes)
Z_TORSO = (0.92, 1.00, 1.12, 1.22)   # Entra entre 0,92-1,00 y sale entre 1,12-1,22 (bajo las mamas)
MARGEN_FRENTE = -0.012       # El vientre queda 6 mm por DETRÁS del contorno delgado de referencia
MARGEN_LADO = -0.014         # La cintura queda 8 mm por dentro del contorno delgado
K_ESPALDA = 0.86             # La mitad posterior del torso (espalda, flancos) se reduce al 90 %
# Caderas y piernas: escala de la sección alrededor del eje (x, y) de cada pierna
ESCALA_PIERNA = [(0.10, 1.00), (0.30, 0.93), (0.50, 0.86), (0.66, 0.85), (0.80, 0.96)]   # (z, factor)
ESCALA_CADERA = 0.985        # Caderas (z 0,80-0,95): escala alrededor del eje del cuerpo
Z_CADERA = (0.78, 0.82, 0.95, 1.02)


def perfil_torso_delgado(escala):
    """Por franjas de 2 cm de altura: frente (y mínima) y ancho (|x| máximo) del tronco de la piel
    de Z-Anatomy, escalada como el cuerpo femenino."""
    franjas = {}
    for o in bpy.data.collections["9: Regions of human body"].all_objects:
        if o.type != "MESH" or pm.EXCLUIR.search(o.name):
            continue
        m = pm.Matrix.Scale(escala, 4) @ o.matrix_world
        for v in o.data.vertices:
            p = m @ v.co
            if abs(p.x) > 0.20 or not 0.85 < p.z < 1.45:
                continue
            k = round(p.z / 0.02)
            f = franjas.setdefault(k, [0.0, 0.0])
            if abs(p.x) < 0.06:
                f[0] = min(f[0], p.y)                   # Frente en la línea media
            if abs(p.y - 0.0) < 0.04:
                f[1] = max(f[1], abs(p.x))              # Ancho a media profundidad (cintura)
    return franjas


def es_brazo(p):
    """Los brazos están abiertos ~19° (eje del hombro (0,16; 1,33) hacia abajo y afuera); el
    límite interno sigue ese ángulo para no confundir el costado del muslo con la mano."""
    return p.z > 0.70 and abs(p.x) > 0.11 + (1.33 - p.z) * 0.35


def grosor_objetivo(p):
    if es_brazo(p):
        return GROSOR_BRAZO
    for (z0, g0), (z1, g1) in zip(PERFIL_GROSOR, PERFIL_GROSOR[1:]):
        if z0 <= p.z <= z1:
            return g0 + (g1 - g0) * (p.z - z0) / (z1 - z0)
    return PERFIL_GROSOR[-1][1]


def suave(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def torso_por_franjas(pts, franjas, pezones):
    """Para cada altura z: el frente del torso (mitad anterior) se comprime hacia el plano medio
    y el ancho se escala hacia el eje, hasta el contorno delgado + margen. Los factores se
    interpolan entre franjas y se mezclan con un peso suave en z: la superficie queda lisa."""
    zs = sorted(franjas)
    medida = {}
    for k in zs:
        sel = [p for p in pts if round(p.z / 0.02) == k and not es_brazo(p)]
        centro = [p for p in sel if abs(p.x) < 0.06]
        lado = [p for p in sel if abs(p.y + 0.02) < 0.05]
        if not centro or not lado:
            continue
        frente, atras = min(p.y for p in centro), max(p.y for p in centro)
        medio = (frente + atras) / 2
        ancho = max(abs(p.x) for p in lado)
        f_obj = min(medio - 0.01, franjas[k][0] - MARGEN_FRENTE)
        a_obj = franjas[k][1] + MARGEN_LADO
        ky = min(1.0, (medio - f_obj) / max(1e-4, medio - frente)) * 0.97
        kx = min(1.0, a_obj / max(1e-4, ancho)) if franjas[k][1] > 0 else 1.0
        medida[k] = (medio, ky, kx)
    claves = sorted(medida)
    # Suavizar los factores entre franjas vecinas (evita escalones horizontales)
    for _ in range(6):
        nuevo = {}
        for idx, k in enumerate(claves):
            vecinos = [medida[claves[j]] for j in range(max(0, idx - 1), min(len(claves), idx + 2))]
            nuevo[k] = tuple(sum(v[c] for v in vecinos) / len(vecinos) for c in range(3))
        medida = nuevo

    def factores(z):
        x = z / 0.02
        if x <= claves[0]:
            return medida[claves[0]]
        if x >= claves[-1]:
            return medida[claves[-1]]
        k0 = max(k for k in claves if k <= x)
        k1 = min(k for k in claves if k >= x)
        t = 0.0 if k1 == k0 else (x - k0) / (k1 - k0)
        return tuple(a + (b - a) * t for a, b in zip(medida[k0], medida[k1]))

    resultado = np.zeros((len(pts), 3))
    for i, p in enumerate(pts):
        if es_brazo(p) or not Z_TORSO[0] < p.z < Z_TORSO[3]:
            continue
        w = suave(Z_TORSO[0], Z_TORSO[1], p.z) * (1.0 - suave(Z_TORSO[2], Z_TORSO[3], p.z))
        for pz in pezones:
            w *= suave(*RADIO_MAMA, (p - pz).length)
        medio, ky, kx = factores(p.z)
        nx = p.x * kx
        ny = medio + (p.y - medio) * (ky if p.y < medio else K_ESPALDA)
        resultado[i] = np.array([(nx - p.x) * w, (ny - p.y) * w, 0.0])
    print(f"[OK] Torso: cintura x{min(m[2] for m in medida.values()):.2f}, vientre x{min(m[1] for m in medida.values()):.2f}")
    return resultado


# Tono muscular: la piel se acerca a los músculos en el abdomen y los brazos (definición ligera)
TONO = {"abdomen": (0.0075, 0.55), "brazo": (0.0035, 0.4)}   # zona: (grosor objetivo, intensidad)
ITERACIONES_TONO = 6         # Suavizado corto: conserva el relieve de los músculos


def tono_muscular(pts, desplazamiento, arbol, pezones):
    resultado = np.zeros((len(pts), 3))
    for i, p0 in enumerate(pts):
        p = p0 + Vector(desplazamiento[i])
        if es_brazo(p0) and p0.z < 1.28:
            zona = "brazo"
            w = 1.0 - suave(1.02, 1.24, p0.z)   # Transición larga hacia el hombro (sin escalón)
        elif 0.96 < p0.z < 1.20 and abs(p0.x) < 0.13 and p0.y < 0.0:
            zona = "abdomen"
            w = suave(0.96, 1.00, p0.z) * (1.0 - suave(1.14, 1.20, p0.z)) * (1.0 - suave(0.10, 0.13, abs(p0.x)))
            for pz in pezones:
                w *= suave(*RADIO_MAMA, (p0 - pz).length)
        else:
            continue
        cercano, normal, _, distancia = arbol.find_nearest(p)
        if cercano is None or (p - cercano).dot(normal) < 0:
            continue
        grosor, intensidad = TONO[zona]
        exceso = distancia - grosor
        if exceso > 0:
            resultado[i] = np.array((cercano - p).normalized()) * exceso * intensidad * w
    return resultado


def interpolar(tabla, z):
    if z <= tabla[0][0]:
        return tabla[0][1]
    for (z0, a), (z1, b) in zip(tabla, tabla[1:]):
        if z0 <= z <= z1:
            return a + (b - a) * (z - z0) / (z1 - z0)
    return tabla[-1][1]


def caderas_y_piernas(pts):
    """Muslos y piernas: cada sección horizontal se escala hacia el eje de SU pierna (centro de
    la franja en ese lado). Caderas: hacia el eje del cuerpo. Todo con pesos suaves en z."""
    centros = {}
    for p in pts:
        if p.z > Z_CADERA[1] or es_brazo(p) or abs(p.x) < 0.005:
            continue
        clave = (round(p.z / 0.02), 1 if p.x > 0 else -1)
        c = centros.setdefault(clave, [0.0, 0.0, 0])
        c[0] += p.x
        c[1] += p.y
        c[2] += 1
    # Centros suavizados entre franjas vecinas (evita bandas horizontales)
    suavizados = {}
    for (k, lado), c in centros.items():
        vecinos = [centros[(k + d, lado)] for d in range(-4, 5) if (k + d, lado) in centros]
        n = sum(v[2] for v in vecinos)
        suavizados[(k, lado)] = [sum(v[0] for v in vecinos), sum(v[1] for v in vecinos), n]
    centros = suavizados
    resultado = np.zeros((len(pts), 3))
    for i, p in enumerate(pts):
        if es_brazo(p) or p.z > Z_CADERA[3]:
            continue
        # Pierna (hasta la ingle), mezclada con la cadera
        k_pierna = interpolar(ESCALA_PIERNA, p.z)
        c = centros.get((round(p.z / 0.02), 1 if p.x > 0 else -1))
        destino = Vector(p)
        w_cadera = suave(Z_CADERA[0], Z_CADERA[1], p.z) * (1.0 - suave(Z_CADERA[2], Z_CADERA[3], p.z))
        if c and c[2] > 0 and p.z < Z_CADERA[1]:
            cx, cy = c[0] / c[2], c[1] / c[2]
            pierna = Vector((cx + (p.x - cx) * k_pierna, cy + (p.y - cy) * k_pierna, p.z))
            destino = pierna
        if w_cadera > 0:
            cadera = Vector((p.x * ESCALA_CADERA, p.y * ESCALA_CADERA + 0.004, p.z))
            destino = destino.lerp(cadera, w_cadera)
        resultado[i] = np.array(destino - p)
    return resultado


def main():
    mapeo = pm.mezclar(json.load(open(pm_ruta("tools/mapeo_zanatomy.json"))), json.load(open(MAPEO)))
    pm.BRAZOS = mapeo.get("brazos")
    pm.EXCLUIR = re.compile(mapeo["excluir_regex"])
    escala = mapeo.get("escala", 1.0)
    base = pm.Matrix.Scale(escala, 4)

    # --- Superficie interna (músculos y huesos) en coordenadas finales ---
    dg = bpy.context.evaluated_depsgraph_get()
    vertices, caras = [], []
    for nombre in COLECCIONES:
        for o in bpy.data.collections[nombre].all_objects:
            if o.type != "MESH" or pm.EXCLUIR.search(o.name):
                continue
            m = pm.ajuste_de(o, base) @ o.matrix_world
            inicio = len(vertices)
            vertices += [m @ v.co for v in o.data.vertices]
            # Los objetos reflejados (escala negativa, la mitad de Z-Anatomy) tienen las caras al
            # revés: se invierte su orden para que las normales apunten hacia afuera
            invertir = m.determinant() < 0
            caras += [[inicio + i for i in (reversed(p.vertices) if invertir else p.vertices)]
                      for p in o.data.polygons]
    arbol = BVHTree.FromPolygons(vertices, caras)
    print(f"[OK] Anatomía interna: {len(caras)} caras")

    # --- Piel femenina en su ubicación final ---
    desplazamiento_piel = Vector((0.0, -0.058, 0.795))   # Pies en 0 y centrada (ver mapeo femenino)
    for o in list(bpy.data.objects):
        o.hide_viewport = True
    antes = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(PIEL))
    piel = next(o for o in bpy.data.objects if o not in antes and o.type == "MESH")
    piel.matrix_world = pm.Matrix.Translation(desplazamiento_piel) @ piel.matrix_world
    piel.data.transform(piel.matrix_world)
    piel.matrix_world = pm.Matrix.Identity(4)
    malla = piel.data
    # glTF duplica vértices en las costuras de UV: se unen para que el suavizado no abra grietas
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(malla)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bm.to_mesh(malla)
    bm.free()

    # Pezones (para no tocar las mamas): punto más adelantado del pecho a cada lado
    pts = [v.co for v in malla.vertices]
    pezones = [min((p for p in pts if 1.15 < p.z < 1.36 and 0.05 < p.x * s < 0.17), key=lambda p: p.y)
               for s in (1, -1)]

    franjas = perfil_torso_delgado(escala)
    n = len(pts)
    desplazamiento = np.zeros((n, 3))
    peso = np.zeros(n)
    for i, p in enumerate(pts):
        if p.z > Z_SIN_CAMBIO + 0.04:
            continue
        cercano, normal, _, distancia = arbol.find_nearest(p)
        if cercano is None or (p - cercano).dot(normal) < 0:
            continue   # Fuera de alcance o la piel ya está por dentro: no se toca
        exceso = distancia - grosor_objetivo(p)
        if exceso <= 0 or not es_brazo(p):
            continue   # El primer paso solo adelgaza los brazos; el torso se hace por franjas
        w = 1.0 - suave(1.27, 1.37, p.z)   # Hombros y cuello sin cambio (evita pliegues)
        if not es_brazo(p):
            w *= suave(*Z_DESDE, p.z)
        for pz in pezones:
            w *= suave(*RADIO_MAMA, (p - pz).length)
        direccion = (cercano - p).normalized()
        desplazamiento[i] = np.array(direccion) * exceso * w
        peso[i] = w

    # Segundo paso (después del suavizado, ver abajo): torso por franjas
    desplazamiento += torso_por_franjas(pts, franjas, pezones)
    desplazamiento += caderas_y_piernas(pts)

    # Suavizado del desplazamiento (promedio con los vecinos) para que no queden bultos ni bandas
    aristas = np.array([e.vertices[:] for e in malla.edges])
    grado = np.bincount(aristas.ravel(), minlength=n).astype(float)
    grado[grado == 0] = 1
    for _ in range(ITERACIONES_SUAVIZADO):
        suma = np.zeros((n, 3))
        np.add.at(suma, aristas[:, 0], desplazamiento[aristas[:, 1]])
        np.add.at(suma, aristas[:, 1], desplazamiento[aristas[:, 0]])
        desplazamiento = 0.5 * desplazamiento + 0.5 * suma / grado[:, None]


    # Tono muscular sobre la forma ya adelgazada, con un suavizado corto
    tono = tono_muscular(pts, desplazamiento, arbol, pezones)
    for _ in range(ITERACIONES_TONO):
        suma = np.zeros((n, 3))
        np.add.at(suma, aristas[:, 0], tono[aristas[:, 1]])
        np.add.at(suma, aristas[:, 1], tono[aristas[:, 0]])
        tono = 0.5 * tono + 0.5 * suma / grado[:, None]
    desplazamiento += tono

    for i, v in enumerate(malla.vertices):
        v.co += Vector(desplazamiento[i])
    malla.update()
    mov = np.linalg.norm(desplazamiento, axis=1)
    print(f"[OK] Piel ajustada: desplazamiento medio {mov[mov > 0].mean() * 100:.1f} cm, "
          f"máximo {mov.max() * 100:.1f} cm")

    for o in bpy.data.objects:
        o.select_set(o == piel)
    bpy.context.view_layer.objects.active = piel
    piel.hide_viewport = False
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(SALIDA), export_format="GLB", use_selection=True,
                              export_yup=True)
    print(f"[OK] Exportada {SALIDA}")


def pm_ruta(ruta):
    return os.path.abspath(ruta)


if __name__ == "__main__":
    main()
