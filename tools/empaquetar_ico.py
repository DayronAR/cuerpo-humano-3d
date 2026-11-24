import os
import struct

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TAMANOS = [16, 24, 32, 48, 64, 128, 256]

imagenes = []
for t in TAMANOS:
    with open(os.path.join(RAIZ, "ui", "iconos", f"icono_{t}.png"), "rb") as f:
        imagenes.append((t, f.read()))

cabecera = struct.pack("<HHH", 0, 1, len(imagenes))
directorio = b""
datos = b""
desplazamiento = 6 + 16 * len(imagenes)
for t, png in imagenes:
    lado = 0 if t >= 256 else t
    directorio += struct.pack("<BBBBHHII", lado, lado, 0, 0, 1, 32, len(png), desplazamiento + len(datos))
    datos += png

salida = os.path.join(RAIZ, "ui", "icono.ico")
with open(salida, "wb") as f:
    f.write(cabecera + directorio + datos)
print("ICO generado:", salida)
