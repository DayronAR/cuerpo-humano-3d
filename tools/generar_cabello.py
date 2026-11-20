"""
generar_cabello.py — Genera el cabello del cuerpo femenino sobre su cuero cabelludo.

  1. Carga la piel femenina ajustada (ya en coordenadas finales).
  2. Elige los vértices del cuero cabelludo con una línea de nacimiento del pelo: más alta en la
     frente, bajando por los lados (por encima de las orejas) hasta la nuca.
  3. Crea una capa de pelo desplazada hacia afuera (más gruesa arriba, fina en el borde).
  4. Agrega una melena suelta que cae por detrás de las orejas hasta media espalda y se apoya
     sobre los hombros y la espalda (detecta la piel para no atravesarla).
Uso:
    blender -b --factory-startup --python tools/generar_cabello.py
Salida: assets_fuente/hra-femenino/Cabello_generado.glb
"""

import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

PIEL = "assets_fuente/hra-femenino/VH_F_Skin_ajustada.glb"
SALIDA = "assets_fuente/hra-femenino/Cabello_generado.glb"
GROSOR = 0.013          # Volumen del pelo en la coronilla (m)
GROSOR_BORDE = 0.0015   # En la línea de nacimiento
COLUMNAS = 120          # Resolución de la melena alrededor de la cabeza
ABERTURA = 95          # Grados a cada lado desde la nuca (cubre por detrás de las orejas)
LARGO_ATRAS = 1.15      # Altura (m) a la que llegan las puntas en la espalda
LARGO_LADOS = 1.24      # ... y a los lados, sobre los hombros
PASO = 0.006            # Distancia entre filas
SEPARACION = 0.006      # Distancia mínima entre el pelo y la piel


def suave(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(PIEL))
    piel = next(o for o in bpy.data.objects if o.type == "MESH")
    bm = bmesh.new()
    bm.from_mesh(piel.data)
    bm.transform(piel.matrix_world)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bm.normal_update()

    cabeza = [v.co for v in bm.verts if v.co.z > 1.50 and abs(v.co.x) < 0.13]
    z_top = max(p.z for p in cabeza)
    y_frente = min(p.y for p in cabeza)
    y_atras = max(p.y for p in cabeza)
    ancho = max(abs(p.x) for p in cabeza if p.z > z_top - 0.08)
    cy = (y_frente + y_atras) / 2
    medio = (y_atras - y_frente) / 2
    print(f"  cabeza: altura {z_top:.3f}, profundidad {2 * medio * 100:.1f} cm, ancho {2 * ancho * 100:.1f} cm")

    def nacimiento(p):
        """Altura de la línea de nacimiento del pelo según qué tan adelante está el punto."""
        frente = (p.y - cy) / medio                     # -1 = frente, +1 = nuca
        atras = suave(-0.55, 0.65, frente)
        # Frente redondeada: el nacimiento baja hacia las sienes (curva y no línea recta)
        sienes = 0.032 * min(1.0, abs(p.x) / (ancho * 0.75)) ** 2 * (1.0 - atras)
        return z_top - (0.055 + 0.12 * atras + sienes)

    def es_oreja(p):
        frente = (p.y - cy) / medio
        return abs(p.x) > ancho * 0.84 and -0.40 < frente < 0.35 and p.z < z_top - 0.078

    cuero_estricto = {v for v in bm.verts if v.co.z > 1.45 and abs(v.co.x) < 0.14
                      and v.co.z > nacimiento(v.co) and not es_oreja(v.co)}
    # Se incluyen también las caras del borde; sus vértices de fuera se llevan exactamente a la
    # línea de nacimiento, así el borde queda como una curva lisa y no dentado
    caras = [f for f in bm.faces if any(v in cuero_estricto for v in f.verts)
             and not any(es_oreja(v.co) for v in f.verts)]
    cuero = {v for f in caras for v in f.verts}

    # Capa de pelo: copia de las caras del cuero cabelludo desplazada hacia afuera
    pelo = bmesh.new()
    mapa = {}
    for v in cuero:
        borde = suave(0.0, 0.035, v.co.z - nacimiento(v.co))
        grosor = GROSOR_BORDE + (GROSOR - GROSOR_BORDE) * borde
        base = v.co.copy()
        if v not in cuero_estricto:
            base.z = max(base.z, nacimiento(base))   # Borde llevado a la línea de nacimiento
        mapa[v] = pelo.verts.new(base + v.normal * grosor)
    for f in caras:
        try:
            pelo.faces.new([mapa[v] for v in f.verts])
        except ValueError:
            pass
    # Suavizar el contorno de la capa (sin escalones en el borde)
    for _ in range(4):
        bmesh.ops.smooth_vert(pelo, verts=pelo.verts[:], factor=0.5, use_axis_x=True, use_axis_y=True,
                              use_axis_z=True)
    malla = bpy.data.meshes.new("VH_F_hair_scalp")
    pelo.to_mesh(malla)
    pelo.free()
    capa = bpy.data.objects.new("VH_F_hair_scalp", malla)
    bpy.context.scene.collection.objects.link(capa)
    print(f"  cuero cabelludo: {len(caras)} caras")

    # Melena suelta: columnas que bajan desde la parte más ancha de la cabeza (por detrás de las
    # orejas) y se apoyan sobre los hombros y la espalda sin atravesar la piel
    from mathutils.bvhtree import BVHTree
    arbol = BVHTree.FromBMesh(bm)
    z_ecuador = z_top - 0.035   # Nace cerca de la coronilla y baja abrazando la cabeza
    centro = Vector((0.0, cy, z_ecuador))
    columnas = []
    for c in range(COLUMNAS):
        theta = math.radians(-ABERTURA + 2 * ABERTURA * c / (COLUMNAS - 1))   # 0 = atrás
        d = Vector((math.sin(theta), math.cos(theta), 0.0))
        golpe, _, _, _ = arbol.ray_cast(centro + d * 0.3, -d, 0.4)
        if golpe is None:
            continue
        mechon = 0.0012 * math.sin(theta * 47.0) + 0.0008 * math.sin(theta * 113.0)   # Relieve de mechones
        punto = golpe + d * (GROSOR + 0.003 + mechon)
        # Más largo atrás que a los lados; puntas irregulares
        z_fin = LARGO_ATRAS + (LARGO_LADOS - LARGO_ATRAS) * abs(math.sin(theta)) ** 2 + 0.006 * math.sin(theta * 9.0)
        columna = [punto.copy()]
        pasos = 0
        siguiendo = True   # Sobre la cabeza: la sigue mientras se ensancha; después cae recto
        while punto.z > z_fin and pasos < 400:
            pasos += 1
            punto = punto + Vector((0, 0, -PASO))
            radial = Vector((punto.x, punto.y - cy, 0.0))
            cercano, normal, _, _ = arbol.find_nearest(punto)
            if cercano is None:
                columna.append(punto.copy())
                continue
            if siguiendo:
                propuesto = cercano + normal * (GROSOR + 0.003)
                r_nuevo = Vector((propuesto.x, propuesto.y - cy, 0.0)).length
                if r_nuevo >= radial.length - 0.0015 or (punto - cercano).dot(normal) < GROSOR:
                    punto = Vector((propuesto.x, propuesto.y, punto.z))
                else:
                    siguiendo = False   # La cabeza se estrecha (nuca, mandíbula): el pelo cae libre
            else:
                # Al caer, el pelo se junta un poco detrás de la cabeza (no se abre como capa)
                punto.x *= 0.996
                falta = SEPARACION - (punto - cercano).dot(normal)
                if falta > 0:   # Apoyado en hombros o espalda: resbala hacia atrás
                    punto = punto + Vector((0.0, 1.0, 0.0)) * falta * 1.6
            columna.append(punto.copy())
        columnas.append(columna)
    filas = min(len(c) for c in columnas)
    mb = bmesh.new()
    vert = [[mb.verts.new(c[min(k, len(c) - 1)]) for k in range(max(len(c) for c in columnas))] for c in columnas]
    for a, b in zip(vert, vert[1:]):
        for k in range(min(len(a), len(b)) - 1):
            mb.faces.new([a[k], b[k], b[k + 1], a[k + 1]])
    bmesh.ops.remove_doubles(mb, verts=mb.verts[:], dist=1e-5)
    mm = bpy.data.meshes.new("VH_F_hair_loose")
    mb.to_mesh(mm)
    mb.free()
    melena_obj = bpy.data.objects.new("VH_F_hair_loose", mm)
    bpy.context.scene.collection.objects.link(melena_obj)
    print(f"  melena: {len(columnas)} columnas, hasta {filas} filas")

    bpy.data.objects.remove(piel, do_unlink=True)
    for o in (capa, melena_obj):
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(SALIDA), export_format="GLB", use_selection=True,
                              export_yup=True)
    print(f"[OK] Cabello generado en {SALIDA}")


if __name__ == "__main__":
    main()
