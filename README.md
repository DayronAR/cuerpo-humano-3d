# Cuerpo Humano 3D Interactivo

Atlas 3D interactivo del cuerpo humano con simulaciones fisiológicas simples (correr, fumar, comer).
Aplicación de escritorio 100 % offline hecha con **Godot 4.7.2 (GDScript)**.

> Simulación educativa con valores aproximados.

---

## 1. Requisitos de desarrollo (macOS, Apple Silicon)

| Herramienta | Versión usada | Instalación |
|---|---|---|
| macOS | 27.2.1 (arm64) | — |
| Xcode Command Line Tools | ya instaladas | `xcode-select --install` |
| Homebrew | 7.0.13 | https://brew.sh |
| git | 2.56.1 (Homebrew) | `brew install git` |
| Godot (estándar, **no** .NET) | 4.7.2.stable | `brew install --cask godot` |
| Plantillas de exportación | 4.7.2.stable | ver abajo |
| Blender | 5.3.0 | `brew install --cask blender` (o instalador oficial) |

Comandos en la terminal (zsh):

- `godot` → `/opt/homebrew/bin/godot` (enlace creado por Homebrew). `~/.zprofile` ejecuta
  `brew shellenv` para que `/opt/homebrew/bin` vaya primero en el PATH.
- `blender` → `~/.local/bin/blender`, un script envoltorio que ejecuta
  `/Applications/Blender.app/Contents/MacOS/Blender`. **No usar un enlace simbólico**: Blender
  busca su Python y sus recursos a partir de la ruta con la que se invoca, y con un symlink falla
  con `No module named 'encodings'`.

Plantillas de exportación: `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`
(descargadas de `Godot_v4.7.2-stable_export_templates.tpz` del release oficial en GitHub y
verificadas con SHA-512). Deben coincidir **exactamente** con la versión del editor.

## 2. Cómo correr el proyecto

```bash
godot -e --path .      # abrir el editor
godot --path .         # ejecutar el juego directamente
```

Validación sin interfaz (se usa antes de cerrar cada fase):

```bash
godot --headless --path . --import                                   # reimporta recursos
godot --headless --path . --quit-after 10                            # carga la escena principal y sale
godot --headless --path . --script res://tools/validar_cuerpo.gd     # convención de nombres vs JSON
```

Regenerar el cuerpo de prueba (si se cambia `tools/generar_cuerpo_prueba.gd`):

```bash
godot --headless --path . --script res://tools/generar_cuerpo_prueba.gd
```

## 3. Renderer: Mobile

Se usa el renderer **Mobile** (`rendering/renderer/rendering_method="mobile"`) porque:

- La sustentación es en laptops de gama media con Windows, normalmente con GPU integrada
  (Intel UHD/Iris, AMD Vega). Mobile hace un solo pase de render y usa menos ancho de banda que
  Forward+, que está pensado para GPU dedicadas (clustered lighting, SDFGI, SSR, volumetría…).
- La escena tiene pocas luces y no necesita GI ni efectos de pantalla avanzados: lo que sí
  necesitamos (transparencia, shaders propios, partículas GPU, SubViewport) Mobile lo soporta.
- `rendering/rendering_device/fallback_to_opengl3=true`: si el equipo no tiene Vulkan/D3D12
  usable, Godot cae automáticamente al renderer Compatibility (OpenGL 3.3) en lugar de cerrarse.
- En esta Mac, Mobile corre sobre Metal.

## 4. Exportar a .exe y .app

Presets en `export_presets.cfg`:

| Preset | Salida | Uso |
|---|---|---|
| Windows Desktop | `builds/windows/CuerpoHumano3D.exe` (x86_64, PCK incrustado) | entrega y sustentación |
| macOS | `builds/macos/CuerpoHumano3D.app` (universal) | pruebas en esta Mac |

```bash
mkdir -p builds/windows builds/macos
godot --headless --path . --export-release "Windows Desktop" builds/windows/CuerpoHumano3D.exe
godot --headless --path . --export-release "macOS" builds/macos/CuerpoHumano3D.app
```

Ambos presets incluyen `data/*.json` en el filtro de recursos no importados, para que los JSON
viajen dentro del .pck.

### Limitaciones de exportar a Windows desde macOS

- **Firma de código**: el .exe sale sin firmar. Firmarlo desde macOS requiere `osslsigncode` y un
  certificado Authenticode (de pago). Sin firma, Windows SmartScreen puede mostrar
  "Windows protegió su PC" → *Más información* → *Ejecutar de todas formas*. Para la
  sustentación conviene probar el .exe antes en la misma laptop.
- **Icono y metadatos del .exe**: desde Godot 4.2 el exportador modifica el icono y la
  información de versión del .exe por sí mismo (sin `rcedit` ni Wine), con
  `application/modify_resources=true`. Hay que asignar un `.ico` en el preset
  (`application/icon`) cuando tengamos el definitivo.
- **Antivirus**: algunos antivirus marcan ejecutables sin firmar recién creados. Si pasa,
  entregar el .exe dentro de un .zip y/o agregarlo como excepción en la máquina de la sustentación.
- **No se puede probar el .exe en esta Mac** (Apple Silicon no ejecuta binarios x86 de Windows
  sin una VM). Hay que probarlo en una PC con Windows.
- macOS: el .app se firma *ad-hoc* (suficiente para esta Mac). En otra Mac, Gatekeeper lo
  bloqueará por no estar notarizado: clic derecho → *Abrir*, o
  `xattr -dr com.apple.quarantine CuerpoHumano3D.app`.

## 5. Estructura del proyecto

```
res://
├── scenes/            escenas (.tscn): main, body_viewer, ui/
├── scripts/           scripts GDScript
├── data/              JSON: sistemas, órganos, cámara, escenarios (nunca datos en los scripts)
├── models/            .glb exportados con tools/procesar_modelo.py
├── shaders/           shaders propios
└── tools/             herramientas fuera del juego (Blender, generador y validador); excluidas del export
assets_fuente/         (NO versionado) modelos de origen pesados
├── z-anatomy/         archivos de Z-Anatomy (.blend)
└── mixamo/            personaje y animaciones de Mixamo (.fbx)
builds/                (NO versionado) ejecutables exportados
```

`assets_fuente/` y `builds/` están en `.gitignore`: cada integrante descarga los modelos fuente
por su cuenta (requieren cuenta/navegador).

## 6. Arquitectura

### Principios

1. **Datos fuera del código**: todo lo que es contenido (sistemas, fichas de órganos, vistas de
   cámara, luego escenarios) vive en `res://data/*.json`. Los scripts solo saben *leerlo*.
2. **Un único punto de acceso a los datos**: el autoload `Datos` (`scripts/datos.gd`) carga los
   JSON al arrancar. Ningún otro script abre archivos.
3. **Componentes que no se conocen entre sí**: cada escena tiene su script y se comunica por
   **señales**. La escena principal (`main`) es la única que conecta unas con otras.
4. **Convención de nombres** como contrato entre el 3D y los datos (ver abajo).

### Escenas y scripts

```
Main (Node)                         scenes/main.tscn · scripts/main.gd
├── BodyViewer (Node3D)             scenes/body_viewer.tscn · scripts/body_viewer.gd
│   ├── Entorno, LuzPrincipal, LuzRelleno, Plataforma
│   ├── Cuerpo  ← instancia de scenes/cuerpo_prueba.tscn (luego, del cuerpo con .glb)
│   ├── Camara (Camera3D)           scripts/camara_orbital.gd
│   └── GestorCapas (Node)          scripts/gestor_capas.gd
└── UI (CanvasLayer)
    ├── Aviso, Ayuda (Label)
    ├── BarraSistemas               scenes/ui/barra_sistemas.tscn · scripts/ui/barra_sistemas.gd
    ├── PanelFicha                  scenes/ui/panel_ficha.tscn · scripts/ui/panel_ficha.gd
    └── BarraVistas                 scenes/ui/barra_vistas.tscn · scripts/ui/barra_vistas.gd
Autoload: Datos                     scripts/datos.gd
```

| Componente | Responsabilidad | Señales que emite |
|---|---|---|
| `Datos` | Carga y expone `sistemas.json`, `organos.json`, `camara.json` | — |
| `CamaraOrbital` | Girar, zoom, desplazar (mouse y trackpad), vistas rápidas con Tween | `transicion_terminada` |
| `BodyViewer` | Indexa el cuerpo, crea colisiones, detecta clics, resalta el órgano, muestra sistemas y encuadra | `organo_seleccionado(id, sistema)`, `seleccion_limpiada`, `sistema_mostrado(id)` |
| `GestorCapas` | Retira/restaura capas una por una con animación interrumpible; modo fantasma | `capa_retirada(id)`, `capa_restaurada(id)`, `secuencia_terminada` |
| `BarraSistemas` | Lista de sistemas desde JSON, "Cuerpo completo", interruptor de modo fantasma | `sistema_solicitado(id)`, `modo_fantasma_cambiado(activo)` |
| `PanelFicha` | Muestra la ficha que recibe | `cerrado` |
| `BarraVistas` | Crea un botón por vista definida en JSON | `vista_solicitada(id)` |
| `Main` | Conecta las señales anteriores | — |

Flujo de una selección:

```
clic → BodyViewer (rayo físico → órgano) ──organo_seleccionado──▶ Main
Main → Datos.ficha_organo(id) → PanelFicha.mostrar(ficha)
PanelFicha ──cerrado──▶ BodyViewer.limpiar_seleccion() ──seleccion_limpiada──▶ PanelFicha.ocultar()
```

Flujo al elegir un sistema:

```
BarraSistemas ──sistema_solicitado("Circulatorio")──▶ Main → BodyViewer.mostrar_sistema()
BodyViewer → GestorCapas.retirar_solo(Datos.cubierto_por(id))   + Camara.encuadrar(caja del sistema)
GestorCapas ──capa_retirada("Piel")──▶ BodyViewer: desactiva colisiones de esa capa (y deselecciona)
BodyViewer ──sistema_mostrado(id)──▶ BarraSistemas.marcar(id)
```

### Capas (Fase 2)

Definidas en `data/sistemas.json`:

- `orden_capas`: todos los sistemas de **afuera hacia adentro** (Piel > Muscular > Oseo > …).
- `cubierto_por` (en cada sistema): las capas que hay que retirar para verlo.
- `animacion_capas`: duración, pausa entre capas, desplazamiento, escala final, transparencia del
  modo fantasma y margen de encuadre.

Algoritmo de `GestorCapas.retirar_solo(capas_objetivo)`:

1. **Restaurar** las capas retiradas que ya no están en el objetivo, de **adentro hacia afuera**.
2. **Retirar** las del objetivo que aún no lo están, de **afuera hacia adentro**.
3. Cada capa se anima completa antes de la siguiente (una por una).

Así, al pasar de Circulatorio (retira Piel, Muscular, Oseo) a Óseo (retira Piel, Muscular) solo
se restaura el Óseo. Cada capa guarda un `progreso` de 0 (en su sitio) a 1 (retirada) que anima
un `Tween`; una función traduce el progreso a posición (se aleja del eje del cuerpo), escala
(se encoge alrededor de su centro) y transparencia. Si el usuario cambia de sistema a mitad de
una secuencia, la anterior se abandona (contador de generación) y la nueva continúa desde el
progreso en que quedó cada capa.

- **Transparencia**: al empezar a desvanecerse, cada superficie recibe una *copia* de su material
  con `TRANSPARENCY_ALPHA_DEPTH_PRE_PASS`; al restaurarse vuelve el material original opaco.
  (Se probó `GeometryInstance3D.transparency`, pero no tuvo efecto visible con este renderer.)
- **Modo fantasma**: un valor de mezcla 0–1 animado: con 1 las capas retiradas no se mueven ni
  encogen y quedan al 18 % de opacidad.
- Las capas retiradas (también en modo fantasma) **no se pueden seleccionar**: sus colisiones
  pasan a `collision_layer = 0`, y así el clic llega a los órganos internos.

### Convención del cuerpo (obligatoria)

```
Cuerpo (Node3D)
└── <Sistema> (Node3D)   Piel, Muscular, Oseo, Circulatorio, Respiratorio, Digestivo, Nervioso
    └── <Organo>         MeshInstance3D, o Node3D con varias MeshInstance3D (partes)
```

- El nombre del **sistema** debe coincidir con un `id` de `data/sistemas.json`.
- El nombre del **órgano** debe ser una clave de `data/organos.json` y ser único en todo el cuerpo.
- El sistema de un órgano se deduce de su nodo padre (no se repite en el JSON).
- Ejes: Y hacia arriba, el cuerpo mira hacia **+Z**, pies en y = 0, ~1,75 m de altura.
  El lado **izquierdo del paciente** está en **+X** (sufijo `Izq`).

Detalles de implementación:

- **Selección**: `BodyViewer` crea en tiempo de ejecución un `StaticBody3D` con forma *trimesh*
  por cada malla. Así no hay que preparar colisiones a mano ni en las primitivas ni en los .glb.
  Un clic solo cuenta si el puntero se movió menos de 6 px entre presionar y soltar (si no, fue
  un arrastre de cámara).
- **Resaltado**: se usa `material_overlay` con `shaders/resaltado.gdshader` (brillo Fresnel que
  pulsa). Es una capa encima del material original: no modifica los materiales del modelo.
- **Cámara**: la entrada modifica un estado *deseado* (yaw, pitch, distancia, objetivo) y la
  cámara lo sigue con suavizado exponencial, lo que da movimiento fluido con trackpad. Las
  vistas rápidas animan ese estado con un `Tween` (el yaw toma el camino más corto).
- **Cuerpo de prueba**: `scenes/cuerpo_prueba.tscn` lo genera `tools/generar_cuerpo_prueba.gd`
  (no editarlo a mano; cambiar el generador y volver a ejecutarlo).

### Controles

| Acción | Mouse | Trackpad de Mac |
|---|---|---|
| Seleccionar | clic izquierdo | clic |
| Girar | arrastrar con clic izquierdo | clic y arrastrar |
| Zoom | rueda | pellizco, o ⌘ + dos dedos |
| Desplazar | arrastrar con clic derecho/central, o Mayús + clic izquierdo | dos dedos |

Si el desplazamiento con dos dedos va al revés, cambiar `invertir_gesto_desplazamiento` en
`data/camara.json`.

## 7. Herramienta de modelos: `tools/procesar_modelo.py`

Script de Blender que se ejecuta sin interfaz y convierte los modelos fuente en un `.glb` por
sistema, con los nombres de nodo que espera el proyecto.

Qué hace, en orden, para cada órgano del mapeo:

1. Busca los objetos fuente (nombre exacto, `coleccion:Nombre` o comodín como `*lung*`).
2. Los copia, les quita el padre conservando la posición, convierte modificadores a malla y
   aplica transformaciones (ubicación, rotación, escala).
3. Si hay varios objetos fuente, los une en uno solo.
4. Aplica la escala extra (si se pidió) y un **Decimate** (Collapse) hasta el máximo de
   triángulos por objeto.
5. Pone el origen en el centro de la geometría (necesario para el latido del corazón, la
   respiración de los pulmones, etc.).
6. Renombra el objeto con el nombre del proyecto (`Corazon`, `PulmonIzq`, …).
7. Exporta todos los órganos del sistema a `models/<Sistema>.glb` (eje Y arriba).
8. Imprime un reporte de triángulos antes/después por objeto, la altura de cada sistema (para
   verificar la escala) y los destinos que no encontraron coincidencias.

### Uso

```bash
# 1) Ver los nombres de colecciones y objetos del archivo fuente
blender -b assets_fuente/z-anatomy/Z-Anatomy.blend --python tools/procesar_modelo.py -- --listar

# 2) Copiar tools/mapeo_ejemplo.json, ajustar los nombres fuente y probar sin escribir archivos
blender -b assets_fuente/z-anatomy/Z-Anatomy.blend --python tools/procesar_modelo.py -- \
    --mapeo tools/mapeo_zanatomy.json --simular

# 3) Exportar (todos los sistemas o solo algunos)
blender -b assets_fuente/z-anatomy/Z-Anatomy.blend --python tools/procesar_modelo.py -- \
    --mapeo tools/mapeo_zanatomy.json --max-tris 12000 --sistemas Circulatorio,Respiratorio

# Con un .fbx (Mixamo): Blender arranca vacío e importa el archivo
blender -b --factory-startup --python tools/procesar_modelo.py -- \
    --entrada assets_fuente/mixamo/personaje.fbx --listar
```

| Argumento | Descripción |
|---|---|
| `--entrada RUTA` | `.blend` o `.fbx`. Si se omite, usa el `.blend` abierto con `-b`. |
| `--mapeo RUTA` | JSON de mapeo (formato abajo). |
| `--salida DIR` | Carpeta de salida (por defecto `models/`). |
| `--max-tris N` | Máximo de triángulos por objeto (sobrescribe el JSON). |
| `--sistemas A,B` | Exporta solo esos sistemas. |
| `--escala F` | Escala uniforme extra. |
| `--sin-origen` | No centrar el origen de cada objeto. |
| `--listar` | Solo lista colecciones y mallas con sus triángulos. |
| `--simular` | Procesa y reporta sin escribir `.glb`. |

Formato del mapeo:

```json
{
  "max_triangulos": 15000,
  "escala": 1.0,
  "sistemas": {
    "Circulatorio": { "Corazon": ["Heart"] },
    "Respiratorio": { "PulmonIzq": ["Left lung"], "PulmonDer": ["Right lung"] },
    "Nervioso":     { "Cerebro": ["coleccion:Brain"] }
  }
}
```

Los nombres fuente de `tools/mapeo_ejemplo.json` son orientativos: confírmalos con `--listar`.
El script no modifica el archivo fuente (no guarda el `.blend`).

## 8. Dónde colocar los modelos externos

Estos recursos requieren cuenta o navegador, así que se descargan a mano:

- **Z-Anatomy** (modelos anatómicos, licencia CC BY-SA 4.0 — hay que citarlo en los créditos):
  colocar el `.blend` en `assets_fuente/z-anatomy/`.
- **Mixamo** (personaje y animaciones, requiere cuenta Adobe): descargar en formato FBX
  (*FBX Binary*, personaje *With Skin*; las animaciones de caminar/correr/respirar cansado
  pueden ir *Without Skin* y *In Place*) y colocarlas en `assets_fuente/mixamo/`.

## 9. Guía para reemplazar primitivas por modelos .glb

_Se completa en la Fase 4._
