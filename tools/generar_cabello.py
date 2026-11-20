"""
generar_cabello.py — Genera el cabello del cuerpo femenino sobre su cuero cabelludo.

  1. Carga la piel femenina ajustada (ya en coordenadas finales).
  2. Elige los vértices del cuero cabelludo con una línea de nacimiento del pelo: más alta en la
     frente, bajando por los lados (por encima de las orejas) hasta la nuca.
  3. Crea una capa de pelo desplazada hacia afuera (más gruesa arriba, fina en el borde).
  4. Agrega una cola de caballo desde la parte posterior de la cabeza, con su liga.
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

    # Cola de caballo: tubo que nace atrás de la cabeza y cae sobre la espalda
    inicio = Vector((0.0, y_atras + 0.006, z_top - 0.085))
    puntos = [inicio, inicio + Vector((0, 0.03, -0.035)), inicio + Vector((0, 0.048, -0.09)),
              inicio + Vector((0.006, 0.05, -0.16)), inicio + Vector((-0.004, 0.044, -0.22)),
              inicio + Vector((0, 0.036, -0.26))]
    radios = [0.026, 0.034, 0.033, 0.027, 0.018, 0.004]   # Cola llena que se afina al final
    curva = bpy.data.curves.new("cola", "CURVE")
    curva.dimensions = "3D"
    curva.bevel_depth = 1.0
    curva.bevel_resolution = 4
    curva.resolution_u = 10
    tramo = curva.splines.new("BEZIER")
    tramo.bezier_points.add(len(puntos) - 1)
    for bp, p, r in zip(tramo.bezier_points, puntos, radios):
        bp.co = p
        bp.radius = r
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    temporal = bpy.data.objects.new("temporal", curva)
    bpy.context.scene.collection.objects.link(temporal)
    dg = bpy.context.evaluated_depsgraph_get()
    cola = bpy.data.objects.new("VH_F_ponytail", bpy.data.meshes.new_from_object(temporal.evaluated_get(dg), depsgraph=dg))
    bpy.context.scene.collection.objects.link(cola)
    bpy.data.objects.remove(temporal, do_unlink=True)

    # Liga del pelo
    lb = bmesh.new()
    bmesh.ops.create_cone(lb, cap_ends=True, segments=20, radius1=0.029, radius2=0.029, depth=0.012)
    eje = (puntos[1] - puntos[0]).normalized()
    rot = eje.to_track_quat("Z", "Y").to_matrix().to_4x4()
    bmesh.ops.transform(lb, matrix=Matrix.Translation(inicio + eje * 0.012) @ rot, verts=lb.verts[:])
    ml = bpy.data.meshes.new("VH_F_hair_tie")
    lb.to_mesh(ml)
    lb.free()
    liga = bpy.data.objects.new("VH_F_hair_tie", ml)
    bpy.context.scene.collection.objects.link(liga)

    bpy.data.objects.remove(piel, do_unlink=True)
    for o in (capa, cola, liga):
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(SALIDA), export_format="GLB", use_selection=True,
                              export_yup=True)
    print(f"[OK] Cabello generado en {SALIDA}")


if __name__ == "__main__":
    main()
