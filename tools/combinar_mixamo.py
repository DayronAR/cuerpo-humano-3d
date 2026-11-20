"""
combinar_mixamo.py — Une un personaje de Mixamo y sus animaciones en un solo .glb para Godot.

Uso (Blender sin interfaz, desde la raíz del proyecto):
    blender -b --factory-startup --python tools/combinar_mixamo.py -- \
        --carpeta assets_fuente/mixamo --salida models/mixamo/Personaje.glb

Espera en la carpeta:
    personaje.fbx            personaje "With Skin" (T-pose)
    idle.fbx, caminar.fbx, trotar.fbx, correr.fbx, cansado.fbx   animaciones "Without Skin"
Si falta alguna animación se avisa y se omite (el personaje usará otra en su lugar).

Cada animación se renombra (Idle, Walking, Jogging, Running, Breathing) para que coincida con
data/visuales.json → personaje.animaciones, y se exportan todas las acciones en el .glb.
"""

import argparse
import os
import sys

import bpy

ANIMACIONES = {
    "idle.fbx": "Idle",
    "caminar.fbx": "Walking",
    "trotar.fbx": "Jogging",
    "correr.fbx": "Running",
    "cansado.fbx": "Breathing",
}


def argumentos():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--carpeta", default="assets_fuente/mixamo")
    p.add_argument("--salida", default="models/mixamo/Personaje.glb")
    return p.parse_args(argv)


def importar_fbx(ruta):
    antes = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=ruta, automatic_bone_orientation=False)
    return [o for o in bpy.data.objects if o not in antes]


def main():
    args = argumentos()
    bpy.ops.wm.read_factory_settings(use_empty=True)

    objetos = importar_fbx(os.path.abspath(os.path.join(args.carpeta, "personaje.fbx")))
    armadura = next(o for o in objetos if o.type == "ARMATURE")
    armadura.name = "Personaje"
    # La pose de descanso del personaje no es una animación útil
    if armadura.animation_data and armadura.animation_data.action:
        accion_tpose = armadura.animation_data.action
        armadura.animation_data.action = None
        bpy.data.actions.remove(accion_tpose)
    armadura.animation_data_create()

    for archivo, nombre in ANIMACIONES.items():
        ruta = os.path.abspath(os.path.join(args.carpeta, archivo))
        if not os.path.exists(ruta):
            print(f"[AVISO] Falta {archivo}: la animación '{nombre}' no se incluirá")
            continue
        nuevos = importar_fbx(ruta)
        temporal = next(o for o in nuevos if o.type == "ARMATURE")
        accion = temporal.animation_data.action
        accion.name = nombre
        accion.use_fake_user = True
        # Una pista NLA por animación: el exportador glTF crea una animación por pista
        pista = armadura.animation_data.nla_tracks.new()
        pista.name = nombre
        pista.strips.new(nombre, int(accion.frame_range[0]), accion)
        for o in nuevos:
            bpy.data.objects.remove(o, do_unlink=True)
        print(f"[OK] {archivo} -> {nombre} ({int(accion.frame_range[1] - accion.frame_range[0])} cuadros)")

    salida = os.path.abspath(args.salida)
    os.makedirs(os.path.dirname(salida), exist_ok=True)
    opciones = {
        "filepath": salida,
        "export_format": "GLB",
        "export_animations": True,
        "export_animation_mode": "NLA_TRACKS",
        "export_yup": True,
        "export_apply": False,
        "export_cameras": False,
        "export_lights": False,
    }
    disponibles = {p.identifier for p in bpy.ops.export_scene.gltf.get_rna_type().properties}
    bpy.ops.export_scene.gltf(**{k: v for k, v in opciones.items() if k in disponibles})
    print(f"[OK] Exportado {salida}")


if __name__ == "__main__":
    main()
