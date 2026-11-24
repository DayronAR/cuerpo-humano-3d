import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

PIEL = "assets_fuente/hra-femenino/VH_F_Skin_ajustada.glb"
SALIDA = "assets_fuente/hra-femenino/Cabello_generado.glb"
GROSOR = 0.013
GROSOR_BORDE = 0.0015
COLUMNAS = 120
ABERTURA = 95
LARGO_ATRAS = 1.15
LARGO_LADOS = 1.24
PASO = 0.006
SEPARACION = 0.006
FRENTE = 0.055


def suave(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def argumentos():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opciones = {"piel": PIEL, "salida": SALIDA, "prefijo": "VH_F", "corto": False}
    i = 0
    while i < len(args):
        if args[i] == "--corto":
            opciones["corto"] = True
        else:
            opciones[args[i].lstrip("-")] = args[i + 1]
            i += 1
        i += 1
    return opciones


def main():
    global GROSOR, GROSOR_BORDE, FRENTE
    op = argumentos()
    if op["corto"]:
        GROSOR = 0.007
        GROSOR_BORDE = 0.003
        FRENTE = 0.09
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(op["piel"]))
    bm = bmesh.new()
    for o in bpy.data.objects:
        if o.type == "MESH" and ("Epidermis" in o.name or len(bpy.data.objects) < 3 or o.name.startswith("VH_F")):
            malla = o.data.copy()
            malla.transform(o.matrix_world)
            bm.from_mesh(malla)
    piel = next(o for o in bpy.data.objects if o.type == "MESH")
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
        frente = (p.y - cy) / medio
        atras = suave(-0.55, 0.65, frente)
        sienes = 0.032 * min(1.0, abs(p.x) / (ancho * 0.75)) ** 2 * (1.0 - atras)
        return z_top - (FRENTE + 0.12 * atras + sienes)

    def es_oreja(p):
        frente = (p.y - cy) / medio
        return abs(p.x) > ancho * 0.84 and -0.40 < frente < 0.35 and p.z < z_top - 0.078

    cuero_estricto = {v for v in bm.verts if v.co.z > 1.45 and abs(v.co.x) < 0.14
                      and v.co.z > nacimiento(v.co) and not es_oreja(v.co)}
    caras = [f for f in bm.faces if any(v in cuero_estricto for v in f.verts)
             and not any(es_oreja(v.co) for v in f.verts)]
    cuero = {v for f in caras for v in f.verts}

    pelo = bmesh.new()
    mapa = {}
    for v in cuero:
        borde = suave(0.0, 0.035, v.co.z - nacimiento(v.co))
        grosor = GROSOR_BORDE + (GROSOR - GROSOR_BORDE) * borde
        base = v.co.copy()
        if v not in cuero_estricto:
            base.z = max(base.z, nacimiento(base))
        mapa[v] = pelo.verts.new(base + v.normal * grosor)
    for f in caras:
        try:
            pelo.faces.new([mapa[v] for v in f.verts])
        except ValueError:
            pass
    for _ in range(4):
        bmesh.ops.smooth_vert(pelo, verts=pelo.verts[:], factor=0.5, use_axis_x=True, use_axis_y=True,
                              use_axis_z=True)
    for _ in range(60 if op["corto"] else 0):
        nuevas = {}
        for v in pelo.verts:
            if not v.is_boundary:
                continue
            vecinos = [e.other_vert(v) for e in v.link_edges if e.is_boundary]
            if len(vecinos) == 2:
                nuevas[v] = v.co.lerp((vecinos[0].co + vecinos[1].co) / 2, 0.5)
        for v, co in nuevas.items():
            v.co = co
    malla = bpy.data.meshes.new(op["prefijo"] + "_hair_scalp")
    pelo.to_mesh(malla)
    pelo.free()
    capa = bpy.data.objects.new(op["prefijo"] + "_hair_scalp", malla)
    bpy.context.scene.collection.objects.link(capa)
    print(f"  cuero cabelludo: {len(caras)} caras")

    if op["corto"]:
        for o in list(bpy.data.objects):
            if o is not capa:
                bpy.data.objects.remove(o, do_unlink=True)
        capa.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.abspath(op["salida"]), export_format="GLB",
                                  use_selection=True, export_yup=True)
        print(f"[OK] Cabello corto generado en {op['salida']}")
        return

    from mathutils.bvhtree import BVHTree
    arbol = BVHTree.FromBMesh(bm)
    z_ecuador = z_top - 0.035
    centro = Vector((0.0, cy, z_ecuador))
    columnas = []
    for c in range(COLUMNAS):
        theta = math.radians(-ABERTURA + 2 * ABERTURA * c / (COLUMNAS - 1))
        d = Vector((math.sin(theta), math.cos(theta), 0.0))
        golpe, _, _, _ = arbol.ray_cast(centro + d * 0.3, -d, 0.4)
        if golpe is None:
            continue
        mechon = 0.0012 * math.sin(theta * 47.0) + 0.0008 * math.sin(theta * 113.0)
        punto = golpe + d * (GROSOR + 0.003 + mechon)
        z_fin = LARGO_ATRAS + (LARGO_LADOS - LARGO_ATRAS) * abs(math.sin(theta)) ** 2 + 0.006 * math.sin(theta * 9.0)
        columna = [punto.copy()]
        pasos = 0
        siguiendo = True
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
                    siguiendo = False
            else:
                punto.x *= 0.996
                falta = SEPARACION - (punto - cercano).dot(normal)
                if falta > 0:
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

    for o in list(bpy.data.objects):
        if o not in (capa, melena_obj):
            bpy.data.objects.remove(o, do_unlink=True)
    for o in (capa, melena_obj):
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(op["salida"]), export_format="GLB", use_selection=True,
                              export_yup=True)
    print(f"[OK] Cabello generado en {op['salida']}")


if __name__ == "__main__":
    main()
