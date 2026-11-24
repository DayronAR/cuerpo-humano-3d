import fnmatch
import json
import math
import os
import re
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

TIPOS_GEOMETRIA = ("MESH", "CURVE")
EXCLUIR = None
RESOLUCION_CURVAS = 0
BRAZOS = None


def centro_original(o):
    return sum((o.matrix_world @ Vector(c) for c in o.bound_box), Vector()) / 8


def ajuste_de(f, base):
    if f.get("sin_ajuste"):
        return Matrix.Identity(4)
    if BRAZOS:
        c = centro_original(f)
        if abs(c.x) > BRAZOS.get("x_min", 0.19) and c.z > BRAZOS.get("z_min", 0.6):
            signo = 1.0 if c.x > 0 else -1.0
            px, py, pz = BRAZOS["pivote"]
            pivote = Vector((px * signo, py, pz))
            rot = Matrix.Rotation(math.radians(-BRAZOS["angulo"] * signo), 4, "Y")
            return base @ Matrix.Translation(pivote) @ rot @ Matrix.Translation(-pivote)
    return base


def importar_glb_ubicado(definicion):
    antes = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(definicion["archivo"]))
    nuevos = [o for o in bpy.data.objects if o not in antes]
    t = definicion.get("transformacion", {})
    m = Matrix.Translation(Vector(t.get("desplazamiento", [0, 0, 0]))) @ Matrix.Scale(t.get("escala", 1.0), 4)
    for o in nuevos:
        if o.parent is None:
            o.matrix_world = m @ o.matrix_world
    bpy.context.view_layer.update()
    destino = bpy.data.collections.get("Importados") or bpy.data.collections.new("Importados")
    if destino.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(destino)
    for o in nuevos:
        o["sin_ajuste"] = True
        for c in list(o.users_collection):
            c.objects.unlink(o)
        destino.objects.link(o)
    print(f"[OK] Importado {definicion['archivo']} ({len([o for o in nuevos if o.type == 'MESH'])} mallas)")


def mezclar(base, cambios):
    resultado = dict(base)
    for k, v in cambios.items():
        if v is None:
            resultado.pop(k, None)
        elif isinstance(v, dict) and isinstance(resultado.get(k), dict) and not k.startswith("_"):
            resultado[k] = mezclar(resultado[k], v)
        else:
            resultado[k] = v
    return resultado

RAIZ_PROYECTO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def leer_argumentos():
    import argparse

    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser(prog="procesar_modelo.py", add_help=True)
    p.add_argument("--entrada", default=None)
    p.add_argument("--mapeo", default=None)
    p.add_argument("--salida", default=os.path.join(RAIZ_PROYECTO, "models"))
    p.add_argument("--max-tris", type=int, default=None)
    p.add_argument("--sistemas", default=None)
    p.add_argument("--escala", type=float, default=None)
    p.add_argument("--sin-origen", action="store_true")
    p.add_argument("--listar", action="store_true")
    p.add_argument("--simular", action="store_true")
    return p.parse_args(argv)


def contar_triangulos(obj):
    if obj.type != "MESH":
        return 0
    dg = bpy.context.evaluated_depsgraph_get()
    malla = obj.evaluated_get(dg).to_mesh()
    tris = sum(len(poligono.vertices) - 2 for poligono in malla.polygons)
    obj.evaluated_get(dg).to_mesh_clear()
    return tris


def contexto_objeto(obj, seleccion=None):
    seleccion = seleccion if seleccion is not None else [obj]
    return bpy.context.temp_override(
        object=obj,
        active_object=obj,
        selected_objects=seleccion,
        selected_editable_objects=seleccion,
    )


def deseleccionar_todo():
    for o in bpy.context.view_layer.objects:
        o.select_set(False)


def importar_entrada(ruta):
    ruta = os.path.abspath(ruta)
    ext = os.path.splitext(ruta)[1].lower()
    if ext == ".blend":
        bpy.ops.wm.open_mainfile(filepath=ruta)
    elif ext == ".fbx":
        bpy.ops.wm.read_factory_settings(use_empty=True)
        if hasattr(bpy.ops.import_scene, "fbx"):
            bpy.ops.import_scene.fbx(filepath=ruta)
        else:
            bpy.ops.wm.fbx_import(filepath=ruta)
    else:
        raise SystemExit(f"[ERROR] Formato no soportado: {ext} (usa .blend o .fbx)")
    print(f"[OK] Entrada cargada: {ruta}")


def es_geometria(o):
    return o.type in TIPOS_GEOMETRIA and not (EXCLUIR and EXCLUIR.search(o.name))


def mallas_de_coleccion(nombre):
    col = bpy.data.collections.get(nombre)
    if col is None:
        return []
    return [o for o in col.all_objects if es_geometria(o)]


def buscar_fuentes(patrones):
    encontrados = []
    for patron in patrones:
        if patron.lower().startswith("coleccion:"):
            encontrados += mallas_de_coleccion(patron.split(":", 1)[1])
        elif any(c in patron for c in "*?["):
            encontrados += [o for o in bpy.data.objects
                            if es_geometria(o) and fnmatch.fnmatchcase(o.name.lower(), patron.lower())]
        else:
            o = bpy.data.objects.get(patron)
            if o is not None and es_geometria(o):
                encontrados.append(o)
            elif o is None:
                encontrados += mallas_de_coleccion(patron)
    vistos, unicos = set(), []
    for o in encontrados:
        if o.name not in vistos:
            vistos.add(o.name)
            unicos.append(o)
    return unicos


def listar_escena():
    print("\n=== COLECCIONES ===")
    for col in bpy.data.collections:
        print(f"  {col.name}  ({len([o for o in col.all_objects if o.type == 'MESH'])} mallas)")
    print("\n=== OBJETOS DE MALLA (triángulos) ===")
    for o in sorted(bpy.data.objects, key=lambda x: x.name):
        if o.type == "MESH":
            print(f"  {o.name:<50} {contar_triangulos(o):>9}")


def preparar_organo(destino, fuentes, max_tris, escala, desplazamiento, centrar_origen, remallado=0.0,
                    soldar=0.0004, simetria=False):
    escena = bpy.context.scene
    for f in fuentes:
        if f.type == "CURVE" and RESOLUCION_CURVAS:
            f.data.resolution_u = min(f.data.resolution_u, RESOLUCION_CURVAS)
            f.data.bevel_resolution = max(1, min(f.data.bevel_resolution, 2))
        f.hide_viewport = False
        if f.name not in bpy.context.view_layer.objects:
            escena.collection.objects.link(f)
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()

    ajuste = Matrix.Translation(Vector(desplazamiento)) @ Matrix.Scale(escala, 4)
    bm = bmesh.new()
    for f in fuentes:
        evaluado = f.evaluated_get(dg)
        malla = bpy.data.meshes.new_from_object(evaluado, preserve_all_data_layers=False, depsgraph=dg)
        malla.transform(ajuste_de(f, ajuste) @ f.matrix_world)
        bm.from_mesh(malla)
        bpy.data.meshes.remove(malla)
    if simetria:
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=0.0001,
                               plane_co=(0, 0, 0), plane_no=(1, 0, 0), clear_outer=True)
        if simetria in (True, "completa"):
            reflejo = bmesh.ops.duplicate(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:])
            verts_reflejo = [e for e in reflejo["geom"] if isinstance(e, bmesh.types.BMVert)]
            bmesh.ops.scale(bm, vec=(-1, 1, 1), verts=verts_reflejo)
            caras_reflejo = [e for e in reflejo["geom"] if isinstance(e, bmesh.types.BMFace)]
            bmesh.ops.reverse_faces(bm, faces=caras_reflejo)
        elif simetria == "izquierda":
            bmesh.ops.scale(bm, vec=(-1, 1, 1), verts=bm.verts[:])
            bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=soldar)
    vistas = set()
    repetidas = []
    for cara in bm.faces:
        clave = tuple(sorted(v.index for v in cara.verts))
        if clave in vistas:
            repetidas.append(cara)
        else:
            vistas.add(clave)
    if repetidas:
        bmesh.ops.delete(bm, geom=repetidas, context="FACES_ONLY")
    malla = bpy.data.meshes.new(destino + "_malla")
    bm.to_mesh(malla)
    bm.free()
    for poligono in malla.polygons:
        poligono.material_index = 0
    malla.materials.clear()

    anterior = bpy.data.objects.get(destino)
    if anterior is not None:
        anterior.name = destino + "_original"
    obj = bpy.data.objects.new(destino, malla)
    escena.collection.objects.link(obj)
    tris_antes = sum(len(p.vertices) - 2 for p in malla.polygons)

    if remallado > 0.0:
        aplicar_modificador(obj, "REMESH", lambda m: (setattr(m, "mode", "VOXEL"), setattr(m, "voxel_size", remallado),
                                                      setattr(m, "adaptivity", 0.0)))

    tris_actuales = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if max_tris and tris_actuales > max_tris:
        mod = obj.modifiers.new(name="Decimate", type="DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = max(0.001, max_tris / tris_actuales)
        mod.use_collapse_triangulate = True
        dg = bpy.context.evaluated_depsgraph_get()
        dg.update()
        reducida = bpy.data.meshes.new_from_object(obj.evaluated_get(dg), depsgraph=dg)
        obj.modifiers.remove(mod)
        vieja = obj.data
        obj.data = reducida
        reducida.name = destino + "_malla"
        bpy.data.meshes.remove(vieja)

    obj.data.shade_smooth()
    if centrar_origen and len(obj.data.vertices) > 0:
        mn = Vector((min(v.co[i] for v in obj.data.vertices) for i in range(3)))
        mx = Vector((max(v.co[i] for v in obj.data.vertices) for i in range(3)))
        centro = (mn + mx) / 2
        obj.data.transform(Matrix.Translation(-centro))
        obj.location = centro
    return obj, tris_antes


def aplicar_modificador(obj, tipo, configurar):
    mod = obj.modifiers.new(name=tipo, type=tipo)
    configurar(mod)
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    nueva = bpy.data.meshes.new_from_object(obj.evaluated_get(dg), depsgraph=dg)
    obj.modifiers.remove(mod)
    vieja = obj.data
    obj.data = nueva
    nueva.name = vieja.name
    bpy.data.meshes.remove(vieja)


def exportar_glb(objetos, ruta):
    deseleccionar_todo()
    for o in objetos:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objetos[0]

    disponibles = {p.identifier for p in bpy.ops.export_scene.gltf.get_rna_type().properties}
    opciones = {
        "filepath": ruta,
        "export_format": "GLB",
        "use_selection": True,
        "export_apply": True,
        "export_yup": True,
        "export_animations": False,
        "export_cameras": False,
        "export_lights": False,
    }
    opciones = {k: v for k, v in opciones.items() if k in disponibles}
    bpy.ops.export_scene.gltf(**opciones)


LADO = re.compile(r"\.([lr])$")
LADO_GUION = re.compile(r"_([LR])$")


def separar_lado(nombre):
    m = LADO.search(nombre)
    if m:
        return nombre[:m.start()], m.group(1)
    if nombre.startswith("VH_F_") or nombre.startswith("VH_M_"):
        base = nombre[5:]
        m = LADO_GUION.search(base)
        lado = m.group(1).lower() if m else ""
        base = base[:m.start()] if m else base
        return base.replace("_", " "), lado
    return nombre, ""


def id_valido(texto):
    limpio = re.sub(r"[^A-Za-z0-9]+", "_", texto).strip("_")
    return limpio or "Parte"


class Terminologia:

    def __init__(self, ruta, excepciones):
        self.tabla = {}
        self.excepciones = {k.lower(): v for k, v in excepciones.items()}
        if ruta and os.path.exists(ruta):
            for linea in open(ruta, encoding="utf-8-sig"):
                campos = linea.strip().strip('"').split(";")
                if len(campos) > 4 and campos[4].strip():
                    self.tabla.setdefault(campos[1].strip().lower(), campos[4].strip())
        self.sin_traduccion = set()

    def espanol(self, ingles):
        clave = ingles.strip().lower()
        if clave in self.excepciones:
            return self.excepciones[clave]
        for variante in (clave, clave + " muscle", clave + " bone", re.sub(r" muscle$", "", clave)):
            if variante in self.tabla:
                texto = self.tabla[variante]
                return texto[0].upper() + texto[1:]
        self.sin_traduccion.add(ingles)
        return ingles


def agrupar_partes(fuentes, modo):
    grupos = {}
    for f in fuentes:
        base, lado = separar_lado(f.name)
        if modo == "bilateral":
            clave, lado_parte = id_valido(base), ""
        else:
            clave = id_valido(base) + {"l": "_Izq", "r": "_Der"}.get(lado, "")
            lado_parte = lado
        grupos.setdefault(clave, [base, lado_parte, []])[2].append(f)
    return grupos


def construir_organo_con_partes(destino, partes, max_tris, min_tris_parte, escala, desplazamiento, soldar,
                                sin_reducir=None):
    tris_fuente = {}
    for clave, p in partes.items():
        tris_fuente[clave] = max(1, sum(contar_triangulos(f) if f.type == "MESH" else 500 for f in p["fuentes"]))
    total = sum(tris_fuente.values())
    objetos = []
    for clave, p in partes.items():
        limite = max(min_tris_parte, int(max_tris * tris_fuente[clave] / total))
        if sin_reducir and sin_reducir.search(clave):
            limite = 0
        obj, _ = preparar_organo(f"{destino}__{clave}", p["fuentes"], limite, escala, desplazamiento, True,
                                 soldar=soldar, simetria=p.get("simetria", False))
        if len(obj.data.polygons) == 0:
            bpy.data.objects.remove(obj, do_unlink=True)
            continue
        objetos.append((clave, obj))
    if not objetos:
        return None, []
    mn = Vector((min(o.location[i] for _, o in objetos) for i in range(3)))
    mx = Vector((max(o.location[i] for _, o in objetos) for i in range(3)))
    anterior = bpy.data.objects.get(destino)
    if anterior is not None:
        anterior.name = destino + "_original"
    vacio = bpy.data.objects.new(destino, None)
    bpy.context.scene.collection.objects.link(vacio)
    vacio.location = (mn + mx) / 2
    bpy.context.view_layer.update()
    for _, o in objetos:
        mundo = o.matrix_world.copy()
        o.parent = vacio
        o.matrix_world = mundo
    return vacio, objetos


def taubin(malla, iteraciones, lam=0.5, mu=-0.53):
    import numpy as np
    n = len(malla.vertices)
    co = np.empty(n * 3)
    malla.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)
    aristas = np.empty(len(malla.edges) * 2, dtype=np.int64)
    malla.edges.foreach_get("vertices", aristas)
    aristas = aristas.reshape(-1, 2)
    grado = np.bincount(aristas.ravel(), minlength=n).astype(float)
    grado[grado == 0] = 1
    for _ in range(iteraciones):
        for factor in (lam, mu):
            suma = np.zeros((n, 3))
            np.add.at(suma, aristas[:, 0], co[aristas[:, 1]])
            np.add.at(suma, aristas[:, 1], co[aristas[:, 0]])
            co = co + factor * (suma / grado[:, None] - co)
    malla.vertices.foreach_set("co", co.ravel())
    malla.update()


def desplegar(malla, rondas=8):
    bm = bmesh.new()
    bm.from_mesh(malla)
    for ronda in range(rondas):
        bm.normal_update()
        malas = []
        for f in bm.faces:
            vecinas = [g for e in f.edges for g in e.link_faces if g is not f]
            if not vecinas:
                continue
            media = sum((g.normal * g.calc_area() for g in vecinas), Vector()).normalized()
            if f.normal.dot(media) < 0.3 or f.calc_area() < 1e-9:
                malas.append(f)
        if ronda == 0 or not malas:
            print(f"  caras plegadas: {len(malas)} (ronda {ronda + 1})")
        if not malas:
            break
        zona = {v for f in malas for v in f.verts}
        zona |= {w for v in list(zona) for e in v.link_edges for w in e.verts}
        for _ in range(6):
            nuevas = {}
            for v in zona:
                vecinos = [e.other_vert(v) for e in v.link_edges]
                if vecinos and not v.is_boundary:
                    nuevas[v] = v.co.lerp(sum((w.co for w in vecinos), Vector()) / len(vecinos), 0.6)
            for v, co in nuevas.items():
                v.co = co
    bm.to_mesh(malla)
    bm.free()


def alisar_linea_media(malla, mundo):
    bm = bmesh.new()
    bm.from_mesh(malla)
    bm.verts.ensure_lookup_table()
    peso = {}
    for v in bm.verts:
        p = mundo @ v.co
        if p.y > -0.03:
            continue
        lado = 1.0 - min(1.0, max(0.0, (abs(p.x) - 0.02) / 0.025))
        alto = min(1.0, max(0.0, (p.z - 1.07) / 0.03)) * min(1.0, max(0.0, (1.40 - p.z) / 0.03))
        if lado * alto > 0.0:
            peso[v] = lado * alto
    for _ in range(25):
        nuevas = {}
        for v, w in peso.items():
            vec = [e.other_vert(v) for e in v.link_edges]
            if vec:
                nuevas[v] = v.co.lerp(sum((u.co for u in vec), Vector()) / len(vec), 0.5 * w)
        for v, co in nuevas.items():
            v.co = co
    print(f"  línea media del tórax alisada ({len(peso)} vértices)")
    bm.to_mesh(malla)
    bm.free()


def separar_brazos(malla, mundo, arbol, etiquetas):
    es_brazo = lambda e: any(k in e.lower() for k in ("brazo", "codo", "mano"))
    bm = bmesh.new()
    bm.from_mesh(malla)
    bm.faces.ensure_lookup_table()
    brazo = {}
    for f in bm.faces:
        brazo[f] = es_brazo(etiquetas[arbol.find(mundo @ f.calc_center_median())[1]])
    contacto = set()
    for f in bm.faces:
        if (mundo @ f.calc_center_median()).z > 1.28:
            continue
        for e in f.edges:
            for g in e.link_faces:
                if g is not f and brazo[g] != brazo[f]:
                    contacto.add(f)
    zona = set(contacto)
    for _ in range(3):
        zona |= {g for f in list(zona) for e in f.edges for g in e.link_faces}
    if zona:
        bmesh.ops.delete(bm, geom=list(zona), context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bordes = [e for e in bm.edges if e.is_boundary]
        nuevas = bmesh.ops.holes_fill(bm, edges=bordes, sides=200)["faces"]
        bmesh.ops.triangulate(bm, faces=nuevas)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        bm.normal_update()
        if sum(f.calc_area() * f.normal.dot(f.calc_center_median()) for f in bm.faces) < 0:
            bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    print(f"  brazos separados del tronco: {len(contacto)} caras de contacto, "
          f"{sum(1 for e in bm.edges if e.is_boundary)} aristas de borde")
    bm.to_mesh(malla)
    bm.free()
    malla.shade_smooth()


def cerrar_huecos(malla):
    bm = bmesh.new()
    bm.from_mesh(malla)
    antes = sum(1 for e in bm.edges if e.is_boundary)
    parches = set()
    for _ in range(3):
        bmesh.ops.remove_doubles(bm, verts=[v for v in bm.verts if v.is_boundary], dist=0.002)
        raras = {f for e in bm.edges if len(e.link_faces) > 2 for f in e.link_faces}
        if raras:
            bmesh.ops.delete(bm, geom=list(raras), context="FACES")
        sueltos = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=sueltos, context="VERTS")
        bordes = [e for e in bm.edges if e.is_boundary]
        if not bordes:
            break
        nuevas = bmesh.ops.holes_fill(bm, edges=bordes, sides=300)["faces"]
        parches |= set(bmesh.ops.triangulate(bm, faces=nuevas)["faces"]) | set(nuevas)
    parches = [f for f in parches if f.is_valid]
    if parches:
        for _ in range(2):
            caras = set(parches)
            res = bmesh.ops.poke(bm, faces=list(caras))
            parches = res["faces"]
        zona = {v for f in parches for v in f.verts}
        for _ in range(2):
            zona |= {w for v in list(zona) for e in v.link_edges for w in e.verts}
        fijos = {v for v in zona if any(w not in zona for e in v.link_edges for w in e.verts)}
        for _ in range(40):
            nuevas_pos = {}
            for v in zona - fijos:
                vec = [e.other_vert(v) for e in v.link_edges]
                nuevas_pos[v] = v.co.lerp(sum((w.co for w in vec), Vector()) / len(vec), 0.7)
            for v, co in nuevas_pos.items():
                v.co = co
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()
    if sum(f.calc_area() * f.normal.dot(f.calc_center_median()) for f in bm.faces) < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    print(f"  huecos: {antes} aristas de borde -> {sum(1 for e in bm.edges if e.is_boundary)}")
    bm.to_mesh(malla)
    bm.free()


def solo_exterior(obj):
    from mathutils.bvhtree import BVHTree
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.normal_update()
    arbol = BVHTree.FromBMesh(bm)

    def direcciones(n):
        t = n.orthogonal().normalized()
        b = n.cross(t)
        res = [n]
        for k in range(8):
            ang = k * math.tau / 8
            res.append((n * 0.6 + (t * math.cos(ang) + b * math.sin(ang)) * 0.8).normalized())
        return res

    lejos = []
    for f in bm.faces:
        c = f.calc_center_median()
        sale = False
        for d in direcciones(f.normal):
            if arbol.ray_cast(c + d * 2e-4, d, 3.0)[0] is None:
                sale = True
                break
        if not sale:
            lejos.append(f)
    print(f"  remallado: {len(lejos)} de {len(bm.faces)} caras son de la capa interior")
    bmesh.ops.delete(bm, geom=lejos, context="FACES")
    bordes = [e for e in bm.edges if e.is_boundary]
    bmesh.ops.holes_fill(bm, edges=bordes, sides=1500)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bm.verts.ensure_lookup_table()
    visto = set()
    piezas = []
    for v in bm.verts:
        if v.index in visto:
            continue
        pila, pieza = [v], []
        visto.add(v.index)
        while pila:
            a = pila.pop()
            pieza.append(a)
            for e in a.link_edges:
                b = e.other_vert(a)
                if b.index not in visto:
                    visto.add(b.index)
                    pila.append(b)
        piezas.append(pieza)
    piezas.sort(key=len, reverse=True)
    sobran = [v for pieza in piezas[1:] for v in pieza if len(pieza) < 2000]
    bmesh.ops.delete(bm, geom=sobran, context="VERTS")
    abiertos = sum(1 for e in bm.edges if e.is_boundary)
    print(f"  remallado: {len(piezas)} piezas, {abiertos} aristas de borde restantes")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()
    if sum(f.calc_area() * f.normal.dot(f.calc_center_median()) for f in bm.faces) < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    bm.to_mesh(obj.data)
    bm.free()


def partir_en_objetos(destino, completa, asignacion, normales, arbol_vertices):
    m = completa.data
    mundo = completa.matrix_world
    objetos = []
    for clave, caras in asignacion.items():
        bm = bmesh.new()
        bm.from_mesh(m)
        bm.faces.ensure_lookup_table()
        conservar = set(caras)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in conservar], context="FACES")
        bmesh.ops.transform(bm, matrix=mundo, verts=bm.verts[:])
        nueva = bpy.data.meshes.new(f"{destino}__{clave}_malla")
        bm.to_mesh(nueva)
        bm.free()
        nueva.normals_split_custom_set_from_vertices(
            [normales[arbol_vertices.find(v.co)[1]] for v in nueva.vertices])
        obj = bpy.data.objects.new(f"{destino}__{clave}", nueva)
        bpy.context.scene.collection.objects.link(obj)
        mn = Vector((min(v.co[i] for v in nueva.vertices) for i in range(3)))
        mx = Vector((max(v.co[i] for v in nueva.vertices) for i in range(3)))
        centro = (mn + mx) / 2
        nueva.transform(Matrix.Translation(-centro))
        obj.location = centro
        objetos.append((clave, obj))
    bpy.data.objects.remove(completa, do_unlink=True)

    anterior = bpy.data.objects.get(destino)
    if anterior is not None:
        anterior.name = destino + "_original"
    vacio = bpy.data.objects.new(destino, None)
    bpy.context.scene.collection.objects.link(vacio)
    mn = Vector((min(o.location[i] for _, o in objetos) for i in range(3)))
    mx = Vector((max(o.location[i] for _, o in objetos) for i in range(3)))
    vacio.location = (mn + mx) / 2
    bpy.context.view_layer.update()
    for _, o in objetos:
        mundo_o = o.matrix_world.copy()
        o.parent = vacio
        o.matrix_world = mundo_o
    return vacio, objetos


def dividir_por_regiones(destino, fuentes, regiones, max_tris, escala, desplazamiento, soldar, cerrar=False,
                         ejes="xz"):
    from mathutils.kdtree import KDTree
    from mathutils.bvhtree import BVHTree
    completa, _ = preparar_organo(destino + "__completa", fuentes, max_tris, escala, desplazamiento, False,
                                  soldar=soldar)
    if cerrar:
        cerrar_huecos(completa.data)
        completa.data.shade_smooth()
    m = completa.data
    mundo = completa.matrix_world
    ajuste = Matrix.Translation(Vector(desplazamiento)) @ Matrix.Scale(escala, 4)
    vertices = [mundo @ v.co for v in m.vertices]
    minimo = Vector((min(v[i] for v in vertices) for i in range(3)))
    maximo = Vector((max(v[i] for v in vertices) for i in range(3)))
    tamano = maximo - minimo

    def malla_mundo(nombre):
        obj = bpy.data.objects.get(nombre)
        if obj is None:
            print(f"[AVISO] {destino}: no existe {nombre}")
            return None
        dg = bpy.context.evaluated_depsgraph_get()
        malla = bpy.data.meshes.new_from_object(obj.evaluated_get(dg), depsgraph=dg)
        malla.transform(ajuste_de(obj, ajuste) @ obj.matrix_world)
        return malla

    def arbol_de(nombre):
        malla = malla_mundo(nombre)
        if malla is None:
            return None
        bm = bmesh.new()
        bm.from_mesh(malla)
        arbol_o = BVHTree.FromBMesh(bm)
        bm.free()
        bpy.data.meshes.remove(malla)
        return arbol_o

    def marca_a_punto(marca):
        if marca.startswith("rel:"):
            f = [float(x) for x in marca[4:].split(",")]
            return Vector((minimo.x + tamano.x * f[0], minimo.y + tamano.y * f[1], minimo.z + tamano.z * f[2]))
        if marca.startswith("centro:"):
            malla = malla_mundo(marca[7:])
            if malla is None:
                return None
            c = sum((v.co for v in malla.vertices), Vector()) / max(1, len(malla.vertices))
            bpy.data.meshes.remove(malla)
            return c
        if marca.startswith("junto:"):
            arbol_o = arbol_de(marca[6:])
            if arbol_o is None:
                return None
            return min(vertices, key=lambda v: (arbol_o.find_nearest(v)[3] or 1e9))
        obj = bpy.data.objects.get(marca)
        if obj is None:
            print(f"[AVISO] {destino}: no existe la marca {marca}")
            return None
        return ajuste_de(obj, ajuste) @ obj.matrix_world.translation

    def proyectar(v):
        return Vector((v.x if "x" in ejes else 0.0, v.y if "y" in ejes else 0.0, v.z if "z" in ejes else 0.0))

    puntos, etiquetas, radios, franjas, pertenencias = [], [], [], [], []
    for clave, r in regiones.items():
        for nombre in r.get("en", []):
            arbol_o = arbol_de(nombre)
            if arbol_o is not None:
                pertenencias.append((clave, arbol_o))
        if r.get("rango_z"):
            franjas.append((clave, minimo.z + tamano.z * r["rango_z"][0], minimo.z + tamano.z * r["rango_z"][1]))
        for marca in r.get("marcas", []):
            punto = marca_a_punto(marca)
            if punto is None:
                continue
            if r.get("radio"):
                radios.append([clave, punto, float(r["radio"])])
            else:
                puntos.append(proyectar(punto))
                etiquetas.append(clave)
    arbol = KDTree(max(1, len(puntos)))
    for k, pt in enumerate(puntos):
        arbol.insert(pt, k)
    arbol.balance()
    normales = [v.normal.copy() for v in m.vertices]
    arbol_vertices = KDTree(len(m.vertices))
    for v in m.vertices:
        arbol_vertices.insert(mundo @ v.co, v.index)
    arbol_vertices.balance()
    asignacion = {}
    for poligono in m.polygons:
        c = mundo @ poligono.center
        clave = next((k for k, a in pertenencias if (a.find_nearest(c)[3] or 1.0) < 0.001), None)
        if clave is None:
            clave = next((k for k, z0, z1 in franjas if z0 <= c.z <= z1), None)
        if clave is None:
            clave = next((rad[0] for rad in radios if (c - rad[1]).length < rad[2]), None)
        if clave is None and puntos:
            _, k, _ = arbol.find(proyectar(c))
            clave = etiquetas[k]
        if clave is None:
            clave = next(iter(regiones))
        asignacion.setdefault(clave, []).append(poligono.index)
    print(f"  {destino}: " + ", ".join(f"{c} {len(v)} caras" for c, v in asignacion.items()))
    return partir_en_objetos(destino, completa, asignacion, normales, arbol_vertices)


def dividir_superficie(destino, partes, max_tris, escala, desplazamiento, soldar, superficie=None, alisado=0,
                       subdividir=False, remallar=0.0, alisado_remallado=0):
    from mathutils.kdtree import KDTree
    todas = []
    for p in partes.values():
        for f in p["fuentes"]:
            if f not in todas:
                todas.append(f)
    if superficie:
        completa, _ = preparar_organo(destino + "__completa", superficie, max_tris, escala, desplazamiento, False,
                                      soldar=soldar)
    else:
        completa, _ = preparar_organo(destino + "__completa", todas, max_tris * 40 if remallar else max_tris, escala,
                                      desplazamiento, False, soldar=soldar, simetria=True)
    if remallar:
        aplicar_modificador(completa, "REMESH", lambda m: (setattr(m, "mode", "VOXEL"),
                                                           setattr(m, "voxel_size", remallar),
                                                           setattr(m, "adaptivity", 0.0)))
        solo_exterior(completa)
        if alisado_remallado:
            taubin(completa.data, alisado_remallado)
        tris = sum(len(p.vertices) - 2 for p in completa.data.polygons)
        print(f"  remallado ({remallar * 1000:.1f} mm): {tris} triángulos")
        if tris > max_tris:
            aplicar_modificador(completa, "DECIMATE", lambda m: (setattr(m, "ratio", max_tris / tris),
                                                                 setattr(m, "use_collapse_triangulate", True)))
    if subdividir:
        aplicar_modificador(completa, "SUBSURF", lambda m: (setattr(m, "levels", 1), setattr(m, "render_levels", 1)))
        tris = sum(len(p.vertices) - 2 for p in completa.data.polygons)
        if tris > max_tris:
            aplicar_modificador(completa, "DECIMATE", lambda m: (setattr(m, "ratio", max_tris / tris),
                                                                 setattr(m, "use_collapse_triangulate", True)))
    if alisado:
        taubin(completa.data, alisado)
        completa.data.shade_smooth()
    if remallar or subdividir:
        desplegar(completa.data)
    if remallar:
        cerrar_huecos(completa.data)
        alisar_linea_media(completa.data, completa.matrix_world)
        completa.data.shade_smooth()
    dg = bpy.context.evaluated_depsgraph_get()
    ajuste = Matrix.Translation(Vector(desplazamiento)) @ Matrix.Scale(escala, 4)
    puntos, etiquetas = [], []
    for clave, p in partes.items():
        for f in p["fuentes"]:
            malla = bpy.data.meshes.new_from_object(f.evaluated_get(dg), depsgraph=dg)
            malla.transform(ajuste_de(f, ajuste) @ f.matrix_world)
            for poligono in malla.polygons:
                c = poligono.center.copy()
                if c.x > 0.0005:
                    continue
                espejo = Vector((-c.x, c.y, c.z))
                if p.get("simetria") == "derecha":
                    puntos.append(c)
                elif p.get("simetria") == "izquierda":
                    puntos.append(espejo)
                else:
                    puntos.extend([c, espejo])
                    etiquetas.append(clave)
                etiquetas.append(clave)
            bpy.data.meshes.remove(malla)
    arbol = KDTree(len(puntos))
    for i, pt in enumerate(puntos):
        arbol.insert(pt, i)
    arbol.balance()

    m = completa.data
    mundo = completa.matrix_world
    if remallar:
        separar_brazos(m, mundo, arbol, etiquetas)
    normales = [v.normal.copy() for v in m.vertices]
    arbol_vertices = KDTree(len(m.vertices))
    for v in m.vertices:
        arbol_vertices.insert(mundo @ v.co, v.index)
    arbol_vertices.balance()
    asignacion = {}
    for poligono in m.polygons:
        _, i, _ = arbol.find(mundo @ poligono.center)
        asignacion.setdefault(etiquetas[i], []).append(poligono.index)

    return partir_en_objetos(destino, completa, asignacion, normales, arbol_vertices)


def clasificar_por_region(obj, regiones):
    centro = sum((obj.matrix_world @ Vector(c) for c in obj.bound_box), Vector()) / 8
    x, z = abs(centro.x), centro.z
    for r in regiones:
        if ("z_min" in r and z < r["z_min"]) or ("z_max" in r and z > r["z_max"]):
            continue
        if ("x_min" in r and x < r["x_min"]) or ("x_max" in r and x > r["x_max"]):
            continue
        return r["organo"]
    return regiones[-1]["organo"]


def main():
    args = leer_argumentos()

    if args.entrada:
        importar_entrada(args.entrada)
    elif not bpy.data.filepath:
        raise SystemExit("[ERROR] Indica --entrada o abre un .blend con 'blender -b archivo.blend'.")

    if args.listar:
        listar_escena()
        return

    if not args.mapeo:
        raise SystemExit("[ERROR] Falta --mapeo RUTA.json (usa --listar para ver los nombres disponibles).")

    with open(args.mapeo, encoding="utf-8") as f:
        mapeo = json.load(f)
    if mapeo.get("hereda"):
        with open(mapeo["hereda"], encoding="utf-8") as f:
            mapeo = mezclar(json.load(f), {k: v for k, v in mapeo.items() if k != "hereda"})
    global BRAZOS
    BRAZOS = mapeo.get("brazos")
    for extra in mapeo.get("importar", []):
        importar_glb_ubicado(extra)

    max_tris = args.max_tris if args.max_tris is not None else int(mapeo.get("max_triangulos", 15000))
    min_tris_parte = int(mapeo.get("min_triangulos_parte", 150))
    escala = args.escala if args.escala is not None else float(mapeo.get("escala", 1.0))
    desplazamiento = mapeo.get("desplazamiento", [0.0, 0.0, 0.0])
    global EXCLUIR, RESOLUCION_CURVAS
    RESOLUCION_CURVAS = int(mapeo.get("resolucion_curvas", 0))
    if mapeo.get("excluir_regex"):
        EXCLUIR = re.compile(mapeo["excluir_regex"])
    terminos = Terminologia(mapeo.get("terminologia"), mapeo.get("nombres_es", {}))
    sistemas = mapeo.get("sistemas", {})
    pedidos = [s.strip() for s in args.sistemas.split(",")] if args.sistemas else list(sistemas)

    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    os.makedirs(args.salida, exist_ok=True)
    reporte = []
    faltantes = []
    nombres_partes = {}
    usados = set()

    for organos in sistemas.values():
        for clave, d in organos.items():
            if clave.startswith("_") or clave == "resto":
                continue
            pats = d.get("fuentes", []) if isinstance(d, dict) else d
            usados.update(o.name for o in buscar_fuentes(pats if isinstance(pats, list) else [pats]))
            for g in (d.get("grupos", {}).values() if isinstance(d, dict) else []):
                usados.update(o.name for o in buscar_fuentes(g.get("fuentes", [])))

    for sistema, organos in sistemas.items():
        exportables = []
        organos_def = {k: v for k, v in organos.items() if not k.startswith("_")}
        resto = organos_def.pop("resto", None)

        if resto:
            for d in organos_def.values():
                pats = d.get("fuentes", []) if isinstance(d, dict) else d
                usados.update(o.name for o in buscar_fuentes(pats if isinstance(pats, list) else [pats]))
                for g in (d.get("grupos", {}).values() if isinstance(d, dict) else []):
                    usados.update(o.name for o in buscar_fuentes(g.get("fuentes", [])))
            for regla in (resto if isinstance(resto, list) else [resto]):
                filtro = re.compile(regla["incluir_regex"], re.I) if regla.get("incluir_regex") else None
                restantes = [o for o in mallas_de_coleccion(regla["coleccion"])
                             if o.name not in usados and (filtro is None or filtro.search(o.name))]
                usados.update(o.name for o in restantes)
                if regla.get("descartar"):
                    continue
                por_organo = {}
                for o in restantes:
                    por_organo.setdefault(clasificar_por_region(o, regla["regiones"]), []).append(o)
                for organo, objs in por_organo.items():
                    organos_def[organo] = {"fuentes_objetos": objs, "partes": regla.get("partes"),
                                           "max_triangulos": regla.get("max_triangulos", max_tris)}

        if sistema not in pedidos:
            continue

        for destino, definicion in organos_def.items():
            limite = max_tris
            soldar = 0.00005
            simetria = False
            modo = None
            patrones = definicion
            if isinstance(definicion, dict):
                patrones = definicion.get("fuentes", [])
                limite = int(definicion.get("max_triangulos", max_tris))
                soldar = float(definicion.get("soldar", 0.00005))
                simetria = definicion.get("simetria", False)
                modo = definicion.get("partes")
            fuentes = definicion.get("fuentes_objetos") if isinstance(definicion, dict) and "fuentes_objetos" in definicion \
                else buscar_fuentes(patrones if isinstance(patrones, list) else [patrones])

            if modo == "regiones":
                if not fuentes:
                    faltantes.append((sistema, destino, patrones))
                    continue
                partes = {c: {"nombre": r["nombre"], "lado": "", "nombre_en": r.get("nombre_en", "")}
                          for c, r in definicion["regiones"].items()}
                vacio, objetos = dividir_por_regiones(destino, fuentes, definicion["regiones"], limite, escala,
                                                      desplazamiento, soldar, bool(definicion.get("cerrar")),
                                                      definicion.get("ejes", "xz"))
                exportables.append(vacio)
                exportables.extend(o for _, o in objetos)
                for clave, o in objetos:
                    nombres_partes[o.name] = {"nombre": partes[clave]["nombre"],
                                              "nombre_en": partes[clave]["nombre_en"], "organo": destino}
                reporte.append((sistema, f"{destino} [{len(objetos)} regiones]", len(fuentes), 0,
                                sum(contar_triangulos(o) for _, o in objetos)))
                continue
            if modo == "grupos":
                partes = {}
                for clave, g in definicion["grupos"].items():
                    fg = buscar_fuentes(g["fuentes"])
                    if not fg:
                        faltantes.append((sistema, f"{destino}/{clave}", g["fuentes"]))
                        continue
                    if g.get("lateral"):
                        partes[clave + "Der"] = {"fuentes": fg, "simetria": "derecha", "nombre": g["nombre"], "lado": "r"}
                        partes[clave + "Izq"] = {"fuentes": fg, "simetria": "izquierda", "nombre": g["nombre"], "lado": "l"}
                    else:
                        partes[clave] = {"fuentes": fg, "simetria": "completa", "nombre": g["nombre"], "lado": ""}
                n_fuentes = sum(len(p["fuentes"]) for p in partes.values())
            elif modo in ("individual", "bilateral"):
                if not fuentes:
                    faltantes.append((sistema, destino, patrones))
                    continue
                partes = {}
                for clave, (base, lado, objs) in agrupar_partes(fuentes, modo).items():
                    partes[clave] = {"fuentes": objs, "nombre": terminos.espanol(base), "lado": lado,
                                     "nombre_en": base}
                n_fuentes = len(fuentes)
            else:
                if not fuentes:
                    faltantes.append((sistema, destino, patrones))
                    continue
                obj, antes = preparar_organo(destino, fuentes, limite, escala, desplazamiento, not args.sin_origen,
                                             soldar=soldar, simetria=simetria)
                exportables.append(obj)
                reporte.append((sistema, destino, len(fuentes), antes, contar_triangulos(obj)))
                continue

            if modo == "grupos" and definicion.get("dividir_superficie"):
                superficie = buscar_fuentes(definicion["superficie"]) if definicion.get("superficie") else None
                vacio, objetos = dividir_superficie(destino, partes, limite, escala, desplazamiento, soldar, superficie,
                                                    int(definicion.get("alisado_taubin", 0)),
                                                    bool(definicion.get("subdividir", False)),
                                                    float(definicion.get("remallar_voxel", 0.0)),
                                                    int(definicion.get("alisado_remallado", 0)))
            else:
                sin_reducir = re.compile(definicion["sin_reducir_regex"]) if definicion.get("sin_reducir_regex") else None
                vacio, objetos = construir_organo_con_partes(destino, partes, limite, min_tris_parte, escala,
                                                             desplazamiento, soldar, sin_reducir)
            if vacio is None:
                faltantes.append((sistema, destino, "(sin geometría)"))
                continue
            exportables.append(vacio)
            exportables.extend(o for _, o in objetos)
            for clave, o in objetos:
                p = partes[clave]
                lado = {"l": "izquierdo", "r": "derecho"}.get(p.get("lado", ""), "")
                nombres_partes[o.name] = {"nombre": p["nombre"] + (f" (lado {lado})" if lado else ""),
                                          "nombre_en": p.get("nombre_en", ""), "organo": destino}
            despues = sum(contar_triangulos(o) for _, o in objetos)
            reporte.append((sistema, f"{destino} [{len(objetos)} partes]", n_fuentes, 0, despues))

        mallas = [o for o in exportables if o.type == "MESH"]
        if not mallas:
            print(f"[AVISO] El sistema {sistema} no tiene objetos; no se exporta.")
            continue
        zs = [(o.matrix_world @ v.co).z for o in mallas for v in o.data.vertices] or [0.0]
        print(f"[INFO] {sistema}: altura {max(zs) - min(zs):.3f} m (Z de {min(zs):.3f} a {max(zs):.3f})")

        ruta = os.path.join(args.salida, f"{sistema}.glb")
        if args.simular:
            print(f"[SIMULAR] Se exportaría {ruta}")
        else:
            exportar_glb(exportables, ruta)
            print(f"[OK] Exportado {ruta}")

    if mapeo.get("salida_nombres") and not args.simular:
        ruta_nombres = mapeo["salida_nombres"]
        existentes = {}
        if os.path.exists(ruta_nombres):
            existentes = json.load(open(ruta_nombres, encoding="utf-8")).get("partes", {})
        existentes.update(nombres_partes)
        with open(ruta_nombres, "w", encoding="utf-8") as f:
            json.dump({"_comentario": "Generado por tools/procesar_modelo.py: nombre en español de cada parte "
                       "(id de nodo -> nombre, nombre en inglés y órgano al que pertenece). No editar a mano: "
                       "las excepciones van en tools/mapeo_zanatomy.json -> nombres_es.",
                       "partes": dict(sorted(existentes.items()))}, f, ensure_ascii=False, indent=1)
        print(f"[OK] Nombres de {len(nombres_partes)} partes en {ruta_nombres}")

    print("\n" + "=" * 78)
    print(f"REPORTE DE TRIÁNGULOS (máximo por órgano: {max_tris})")
    print("=" * 78)
    total = 0
    for sistema, destino, n, antes, despues in reporte:
        print(f"{sistema:<14}{destino:<40}{n:>6}{despues:>12,}")
        total += despues
    print("-" * 78)
    print(f"{'TOTAL':<60}{total:>12,}")
    if terminos.sin_traduccion:
        print(f"\n[INFO] {len(terminos.sin_traduccion)} nombres sin traducción (quedan en inglés):")
        print("   " + " | ".join(sorted(terminos.sin_traduccion)[:80]))
    if faltantes:
        print("\n[AVISO] Destinos sin coincidencias (revisa los nombres con --listar):")
        for sistema, destino, patrones in faltantes:
            print(f"  {sistema}/{destino}: {patrones}")


if __name__ == "__main__":
    main()
