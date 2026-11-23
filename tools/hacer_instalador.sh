#!/bin/sh
# Exporta la versión de Windows con Godot y arma el instalador (NSIS) en un solo paso.
#   sh tools/hacer_instalador.sh
# Requiere Godot 4.7 y makensis (macOS: brew install makensis).
# Resultado: builds/windows/Instalar_CuerpoHumano3D.exe
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
"$GODOT" --headless --path . --export-release "Windows Desktop"
cd instalador
# makensis necesita un entorno UTF-8 para leer los acentos del script
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 makensis -V2 instalador.nsi
ls -la ../builds/windows/Instalar_CuerpoHumano3D.exe
