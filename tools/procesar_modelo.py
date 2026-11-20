"""
procesar_modelo.py — Preparación de modelos anatómicos para Godot (ejecutar con Blender sin interfaz).

Toma un .blend o .fbx (por ejemplo, de Z-Anatomy o Mixamo), conserva solo los objetos /
colecciones indicados en un archivo de mapeo JSON, aplica transformaciones, reduce polígonos
con Decimate, renombra los objetos según la convención del proyecto (Corazon, PulmonIzq, ...)
y exporta un .glb por sistema (Piel.glb, Oseo.glb, Circulatorio.glb, ...).

Uso:
    # Con un .blend (se abre directamente):
    blender -b assets_fuente/z-anatomy/Z-Anatomy.blend --python tools/procesar_modelo.py -- \
        --mapeo tools/mapeo_ejemplo.json

    # Con un .fbx (Blender arranca vacío y el script lo importa):
    blender -b --factory-startup --python tools/procesar_modelo.py -- \
        --entrada assets_fuente/mixamo/personaje.fbx --mapeo tools/mapeo_mixamo.json

    # Solo listar nombres de objetos y colecciones (para armar el mapeo):
    blender -b archivo.blend --python tools/procesar_modelo.py -- --listar

Argumentos (después de "--"):
    --entrada RUTA       .blend o .fbx de entrada. Si se omite, se usa el .blend abierto con "-b".
    --mapeo RUTA         JSON con sistemas -> {NombreDestino: [nombres fuente]}.
    --salida DIR         Carpeta de salida (por defecto: models/ del proyecto).
    --max-tris N         Máximo de triángulos por objeto (sobrescribe el valor del JSON).
    --sistemas A,B       Exportar solo estos sistemas (por defecto: todos los del JSON).
    --escala F           Factor de escala uniforme extra (por defecto: el del JSON o 1.0).
    --sin-origen         No mover el origen de cada objeto al centro de su geometría.
    --listar             Solo imprime colecciones y objetos de malla con sus triángulos.
    --simular            Procesa y reporta, pero no escribe ningún .glb.

Formato del JSON de mapeo (ver tools/mapeo_ejemplo.json):
    {
      "max_triangulos": 15000,
      "escala": 1.0,
      "sistemas": {
        "Circulatorio": {
          "Corazon": ["Heart"],                      <- nombre exacto de objeto
          "Aorta":   ["coleccion:Aorta"],            <- todas las mallas de una colección
          "Venas":   ["*vein*"]                      <- comodines estilo fnmatch (sin mayúsculas)
        }
      }
    }
    Si varios objetos fuente coinciden con un mismo destino, se unen (Join) en un solo objeto.
"""

import fnmatch
import json
import os
import re
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

TIPOS_GEOMETRIA = ("MESH", "CURVE")   # Las curvas con grosor (vasos, esófago...) se convierten a malla
EXCLUIR = None                        # Expresión regular de nombres a ignorar (del JSON: "excluir_regex")

# Raíz del proyecto Godot = carpeta padre de tools/
RAIZ_PROYECTO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ---------------------------------------------------------------------------
# Argumentos
# ---------------------------------------------------------------------------

def leer_argumentos():
    """Lee los argumentos que vienen después de '--' en la línea de comandos de Blender."""
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


# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------

def contar_triangulos(obj):
    """Triángulos de la malla evaluada (incluye modificadores aún no aplicados)."""
    if obj.type != "MESH":
        return 0
    dg = bpy.context.evaluated_depsgraph_get()
    malla = obj.evaluated_get(dg).to_mesh()
    tris = sum(len(poligono.vertices) - 2 for poligono in malla.polygons)
    obj.evaluated_get(dg).to_mesh_clear()
    return tris


def contexto_objeto(obj, seleccion=None):
    """Contexto mínimo para ejecutar operadores sobre un objeto en modo sin interfaz."""
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
    """Abre un .blend o importa un .fbx en una escena vacía."""
    ruta = os.path.abspath(ruta)
    ext = os.path.splitext(ruta)[1].lower()
    if ext == ".blend":
        bpy.ops.wm.open_mainfile(filepath=ruta)
    elif ext == ".fbx":
        bpy.ops.wm.read_factory_settings(use_empty=True)
        if hasattr(bpy.ops.import_scene, "fbx"):
            bpy.ops.import_scene.fbx(filepath=ruta)
        else:  # Importador nuevo de Blender 4.5+
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
    """Resuelve una lista de patrones (nombre exacto, 'coleccion:X' o comodín) a objetos de malla."""
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
                # Si no es objeto, se intenta como colección con ese nombre.
                encontrados += mallas_de_coleccion(patron)
    # Quitar duplicados conservando el orden
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


# ---------------------------------------------------------------------------
# Procesamiento de un órgano
# ---------------------------------------------------------------------------

def preparar_organo(destino, fuentes, max_tris, escala, desplazamiento, centrar_origen, remallado=0.0,
                    soldar=0.0004, simetria=False):
    """Une las fuentes en un objeto nuevo, decima y renombra. Devuelve (obj, tris_antes).

    No usa operadores de Blender (fallan con objetos ocultos o fuera de la capa de vista):
    toma la malla EVALUADA de cada fuente (con modificadores y el grosor de las curvas ya
    aplicados), la lleva a coordenadas de mundo y la agrega a un bmesh común. El archivo
    fuente nunca se modifica en disco.
    """
    escena = bpy.context.scene
    for f in fuentes:
        # Asegurar que la fuente se evalúe (la plantilla de Z-Anatomy oculta muchos objetos)
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
        malla.transform(ajuste @ f.matrix_world)
        bm.from_mesh(malla)
        bpy.data.meshes.remove(malla)
    # Soldar vértices coincidentes: elimina las costuras entre piezas vecinas (p. ej. las
    # regiones de la piel) y ayuda a que el Decimate no abra grietas
    if simetria:
        # Simetría: conservar solo el lado derecho del paciente (x <= 0), cortado exactamente en
        # la línea media, y completarlo con su reflejo. Elimina las diferencias entre lados.
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=0.0001,
                               plane_co=(0, 0, 0), plane_no=(1, 0, 0), clear_outer=True)
        reflejo = bmesh.ops.duplicate(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:])
        verts_reflejo = [e for e in reflejo["geom"] if isinstance(e, bmesh.types.BMVert)]
        bmesh.ops.scale(bm, vec=(-1, 1, 1), verts=verts_reflejo)
        caras_reflejo = [e for e in reflejo["geom"] if isinstance(e, bmesh.types.BMFace)]
        bmesh.ops.reverse_faces(bm, faces=caras_reflejo)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=soldar)
    # Caras repetidas (piezas superpuestas que quedaron con los mismos vértices tras soldar)
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

    # Remallado por vóxeles (opcional): convierte piezas solapadas en UNA superficie continua.
    # Útil para la piel de Z-Anatomy, que viene dividida en regiones con costuras.
    if remallado > 0.0:
        aplicar_modificador(obj, "REMESH", lambda m: (setattr(m, "mode", "VOXEL"), setattr(m, "voxel_size", remallado),
                                                      setattr(m, "adaptivity", 0.0)))

    # Reducción de polígonos: modificador Decimate y malla evaluada (sin operadores)
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
    # Origen en el centro de la geometría: necesario para el latido, la respiración y las capas
    if centrar_origen and len(obj.data.vertices) > 0:
        mn = Vector((min(v.co[i] for v in obj.data.vertices) for i in range(3)))
        mx = Vector((max(v.co[i] for v in obj.data.vertices) for i in range(3)))
        centro = (mn + mx) / 2
        obj.data.transform(Matrix.Translation(-centro))
        obj.location = centro
    return obj, tris_antes


def aplicar_modificador(obj, tipo, configurar):
    """Aplica un modificador tomando la malla evaluada (sin operadores de Blender)."""
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
    """Exporta solo los objetos dados a un .glb (eje Y hacia arriba, como usa Godot)."""
    deseleccionar_todo()
    for o in objetos:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objetos[0]

    # Se filtran opciones según las que existan en esta versión de Blender
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


# ---------------------------------------------------------------------------
# Programa principal
# ---------------------------------------------------------------------------

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

    max_tris = args.max_tris if args.max_tris is not None else int(mapeo.get("max_triangulos", 15000))
    escala = args.escala if args.escala is not None else float(mapeo.get("escala", 1.0))
    desplazamiento = mapeo.get("desplazamiento", [0.0, 0.0, 0.0])
    global EXCLUIR
    if mapeo.get("excluir_regex"):
        EXCLUIR = re.compile(mapeo["excluir_regex"])
    sistemas = mapeo.get("sistemas", {})
    if args.sistemas:
        pedidos = [s.strip() for s in args.sistemas.split(",")]
        sistemas = {k: v for k, v in sistemas.items() if k in pedidos}

    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    os.makedirs(args.salida, exist_ok=True)
    reporte = []      # (sistema, destino, fuentes, antes, despues)
    faltantes = []    # (sistema, destino, patrones)

    for sistema, organos in sistemas.items():
        procesados = []
        for destino, definicion in organos.items():
            if destino.startswith("_"):
                continue   # Comentarios
            # Formatos: lista de patrones, o {"fuentes": [...], "max_triangulos": N}
            limite = max_tris
            remallado = 0.0
            soldar = 0.0004
            simetria = False
            patrones = definicion
            if isinstance(definicion, dict):
                patrones = definicion.get("fuentes", [])
                limite = int(definicion.get("max_triangulos", max_tris))
                remallado = float(definicion.get("remallado_voxel", 0.0))
                soldar = float(definicion.get("soldar", 0.0004))
                simetria = bool(definicion.get("simetria", False))
            fuentes = buscar_fuentes(patrones if isinstance(patrones, list) else [patrones])
            if not fuentes:
                faltantes.append((sistema, destino, patrones))
                continue
            obj, antes = preparar_organo(destino, fuentes, limite, escala, desplazamiento, not args.sin_origen, remallado, soldar, simetria)
            procesados.append(obj)
            reporte.append((sistema, destino, len(fuentes), antes, contar_triangulos(obj)))

        if not procesados:
            print(f"[AVISO] El sistema {sistema} no tiene objetos; no se exporta.")
            continue

        # Altura del sistema (ayuda a comprobar la escala: un cuerpo adulto mide ~1.7 m)
        zs = [(o.matrix_world @ v.co).z for o in procesados for v in o.data.vertices] or [0.0]
        print(f"[INFO] {sistema}: altura {max(zs) - min(zs):.3f} m (Z de {min(zs):.3f} a {max(zs):.3f})")

        ruta = os.path.join(args.salida, f"{sistema}.glb")
        if args.simular:
            print(f"[SIMULAR] Se exportaría {ruta}")
        else:
            exportar_glb(procesados, ruta)
            print(f"[OK] Exportado {ruta}")

    # ----- Reporte final -----
    print("\n" + "=" * 78)
    print(f"REPORTE DE TRIÁNGULOS (máximo por objeto: {max_tris})")
    print("=" * 78)
    print(f"{'Sistema':<14}{'Objeto':<24}{'Fuentes':>8}{'Antes':>14}{'Después':>14}")
    print("-" * 78)
    total = 0
    for sistema, destino, n, antes, despues in reporte:
        print(f"{sistema:<14}{destino:<24}{n:>8}{antes:>14,}{despues:>14,}")
        total += despues
    print("-" * 78)
    print(f"{'TOTAL':<46}{total:>32,}")
    if faltantes:
        print("\n[AVISO] Destinos sin coincidencias (revisa los nombres con --listar):")
        for sistema, destino, patrones in faltantes:
            print(f"  {sistema}/{destino}: {patrones}")


if __name__ == "__main__":
    main()
