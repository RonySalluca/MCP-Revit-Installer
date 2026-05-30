# Revit MCP Easy Installer

Instalador con menu para instalar o reparar **Revit MCP** en una o varias versiones de Autodesk Revit.

Este repo no reemplaza el instalador oficial. Solo descarga y ejecuta los scripts oficiales de:

https://github.com/LuDattilo/revit-mcp-server

## Instalacion rapida

Cuando este repo este publicado en GitHub, usa esta linea en PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=\"$env:TEMP\Instalar-Revit-MCP.ps1\"; irm https://raw.githubusercontent.com/TU_USUARIO/revit-mcp-easy-installer/main/Instalar-Revit-MCP.ps1 -OutFile $p; & $p"
```

Cambia `TU_USUARIO` por tu usuario de GitHub.

## Que hace

- Muestra un menu simple.
- Permite elegir versiones de Revit: 2023, 2024, 2025, 2026 y 2027.
- Permite instalar en todas las versiones detectadas.
- Permite escribir versiones manualmente, por ejemplo `2024,2025,2026`.
- Crea la carpeta `Addins\<version>` antes de ejecutar el instalador, para evitar fallos de deteccion.
- Descarga el `install.ps1` oficial.
- Descarga el `fix-mcp.ps1` oficial.
- Ejecuta el instalador oficial por cada version elegida.
- Al final ejecuta el fix oficial para reparar la configuracion de Claude/MCP.

## Uso local

Si ya tienes el archivo descargado:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Instalar-Revit-MCP.ps1"
```

## Requisitos

- Windows 10/11
- PowerShell 5.1 o superior
- Autodesk Revit 2023-2027
- Conexion a internet
- Claude Desktop si quieres usar Revit MCP desde Claude

## Flujo recomendado

1. Cierra Revit.
2. Ejecuta el script.
3. Elige `Instalar/Reparar`.
4. Selecciona las versiones de Revit.
5. Abre Revit.
6. Ve a `Add-Ins`.
7. Haz clic en `Revit MCP Switch`.
8. Reinicia Claude Desktop completamente.

## Notas

- El script no guarda claves ni credenciales.
- El script descarga los archivos oficiales al directorio temporal de Windows.
- Si el instalador oficial cambia, este wrapper seguira usando la version actual publicada por el repo oficial.

## Creditos

Instalador oficial y plugin Revit MCP:

https://github.com/LuDattilo/revit-mcp-server

