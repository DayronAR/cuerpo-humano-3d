import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

PIEL = "assets_fuente/hra-femenino/VH_F_Skin_ajustada.glb"
DESPLAZAMIENTO_PIEL = Vector((0.0, 0.0, 0.0))
SALIDA = "assets_fuente/hra-femenino/Mamas_generadas.glb"
LOBULOS = 16


def cargar_piel():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(PIEL))
    piel = next(o for o in bpy.data.objects if o.type == "MESH")
    piel.matrix_world = Matrix.Translation(DESPLAZAMIENTO_PIEL) @ piel.matrix_world
    bpy.context.view_layer.update()
    return [(piel.matrix_world @ v.co, (piel.matrix_world.to_3x3() @ v.normal).normalized())
            for v in piel.data.vertices]


def medir_mama(vertices, signo):
    pecho = [(p, n) for p, n in vertices if 1.15 < p.z < 1.36 and 0.05 < p.x * signo < 0.17]
    pezon, normal = min(pecho, key=lambda pn: pn[0].y)
    arriba = [p for p, _ in vertices if abs(p.x - pezon.x) < 0.012 and abs(p.z - (pezon.z + 0.11)) < 0.012]
    pared_y = min(p.y for p in arriba) if arriba else pezon.y + 0.06
    proyeccion = max(0.035, pared_y - pezon.y + 0.015)
    print(f"  lado {'izq' if signo > 0 else 'der'}: pezón {tuple(round(c, 3) for c in pezon)}, "
          f"proyección {proyeccion * 100:.1f} cm")
    return pezon, normal, proyeccion


def elipsoide(nombre, centro, radios, eje_largo, segmentos=12):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segmentos, v_segments=segmentos // 2 + 2, radius=1.0)
    rot = eje_largo.to_track_quat("Z", "Y").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(centro) @ rot @ Matrix.Diagonal((*radios, 1)),
                        verts=bm.verts[:])
    malla = bpy.data.meshes.new(nombre)
    bm.to_mesh(malla)
    bm.free()
    return malla


def unir(nombre, mallas):
    bm = bmesh.new()
    for m in mallas:
        bm.from_mesh(m)
    final = bpy.data.meshes.new(nombre)
    bm.to_mesh(final)
    bm.free()
    obj = bpy.data.objects.new(nombre, final)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def grasa(vertices, pezon, eje, proyeccion, radio, sufijo):
    base = pezon - eje * proyeccion
    puntos = []
    for p, n in vertices:
        delante = (p - base).dot(eje)
        lateral = ((p - base) - eje * delante).length
        mismo_lado = p.x * math.copysign(1, pezon.x) > 0.02
        if 0.0 < delante < proyeccion + 0.01 and lateral < radio and n.dot(eje) > 0.1 and mismo_lado:
            interior = p - n * 0.002
            puntos.append(interior)
            puntos.append(interior - eje * (interior - base).dot(eje))
    bm = bmesh.new()
    for p in puntos:
        bm.verts.new(p)
    resultado = bmesh.ops.convex_hull(bm, input=bm.verts[:])
    sobrantes = list({v for v in resultado["geom_interior"] + resultado["geom_unused"] if isinstance(v, bmesh.types.BMVert)})
    bmesh.ops.delete(bm, geom=sobrantes, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    malla = bpy.data.meshes.new(f"VH_F_breast_fat_{sufijo}")
    bm.to_mesh(malla)
    bm.free()
    obj = bpy.data.objects.new(malla.name, malla)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def construir_mama(vertices, pezon, normal, proyeccion, sufijo):
    eje = (normal + Vector((0, -1, 0))).normalized()
    base = pezon - eje * proyeccion
    u = eje.cross(Vector((0, 0, 1))).normalized()
    v = eje.cross(u).normalized()
    radio_base = proyeccion * 1.15
    lobulos, conductos = [], []
    for i in range(LOBULOS):
        ang = math.tau * i / LOBULOS
        radial = u * math.cos(ang) + v * math.sin(ang)
        externo = max(0.0, radial.dot(Vector((math.copysign(1, pezon.x), 0, 0.6)).normalized()))
        largo = proyeccion * (0.42 + 0.18 * externo)
        centro = base + eje * proyeccion * 0.38 + radial * radio_base * 0.55
        direccion = (pezon - centro).normalized()
        lobulos.append(elipsoide(f"lobulo{i}", centro, (proyeccion * 0.11, proyeccion * 0.08, largo * 0.5), direccion))
        seno = pezon - eje * proyeccion * 0.12 + radial * proyeccion * 0.08
        conductos.append([centro + direccion * largo * 0.35, (centro + seno) / 2, seno, pezon - eje * 0.002])
    lob = unir(f"VH_F_mammary_gland_lobes_{sufijo}", lobulos)
    for m in lobulos:
        bpy.data.meshes.remove(m)
    curva = bpy.data.curves.new(f"VH_F_lactiferous_ducts_{sufijo}", "CURVE")
    curva.dimensions = "3D"
    curva.bevel_depth = max(0.0012, proyeccion * 0.02)
    curva.bevel_resolution = 2
    curva.resolution_u = 6
    for pts in conductos:
        tramo = curva.splines.new("BEZIER")
        tramo.bezier_points.add(len(pts) - 1)
        for bp, p in zip(tramo.bezier_points, pts):
            bp.co = p
            bp.handle_left_type = bp.handle_right_type = "AUTO"
    temporal = bpy.data.objects.new("temporal", curva)
    bpy.context.scene.collection.objects.link(temporal)
    dg = bpy.context.evaluated_depsgraph_get()
    malla = bpy.data.meshes.new_from_object(temporal.evaluated_get(dg), depsgraph=dg)
    bpy.data.objects.remove(temporal, do_unlink=True)
    duc = bpy.data.objects.new(f"VH_F_lactiferous_ducts_{sufijo}", malla)
    bpy.context.scene.collection.objects.link(duc)
    areola = elipsoide("areola", pezon - eje * 0.003, (0.019, 0.019, 0.0025), eje, 24)
    pezon_m = elipsoide("pezon", pezon - eje * 0.0005, (0.0055, 0.0055, 0.006), eje, 16)
    are = unir(f"VH_F_areola_and_nipple_{sufijo}", [areola, pezon_m])
    fat = grasa(vertices, pezon, eje, proyeccion, proyeccion * 1.3, sufijo)
    return [lob, duc, are, fat]


def main():
    vertices = cargar_piel()
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    objetos = []
    for signo, sufijo in [(1, "L"), (-1, "R")]:
        objetos += construir_mama(vertices, *medir_mama(vertices, signo), sufijo)
    for o in objetos:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(SALIDA), export_format="GLB", use_selection=True,
                              export_yup=True)
    print(f"[OK] Mamas generadas en {SALIDA}")


if __name__ == "__main__":
    main()
