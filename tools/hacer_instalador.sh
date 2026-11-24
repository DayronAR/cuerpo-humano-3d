#!/bin/sh
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
"$GODOT" --headless --path . --export-release "Windows Desktop"
cd instalador
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 makensis -V2 instalador.nsi
ls -la ../builds/windows/Instalar_CuerpoHumano3D.exe
