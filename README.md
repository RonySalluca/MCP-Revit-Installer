# Revit MCP Easy Installer

Instalador con menu para instalar o reparar **Revit MCP** en una o varias versiones de Autodesk Revit.

Este repo no reemplaza el instalador oficial. Solo descarga y ejecuta los scripts oficiales de:

https://github.com/LuDattilo/revit-mcp-server

## Instalacion rapida

Cuando este repo este publicado en GitHub, usa esta linea en PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/RonySalluca/MCP-Revit-Installer/main/Instalar-Revit-MCP.ps1 | iex"
```

Si ya estas dentro de PowerShell, tambien puedes usar la version corta:

```powershell
irm https://raw.githubusercontent.com/RonySalluca/MCP-Revit-Installer/main/Instalar-Revit-MCP.ps1 | iex
```

## Que hace

- Muestra un menu simple.
- Permite elegir versiones de Revit: 2023, 2024, 2025, 2026 y 2027.
- Permite instalar en todas las versiones reales detectadas.
- Permite escribir versiones manualmente, por ejemplo `2024,2025,2026`.
- No considera carpetas `Addins\<version>` como prueba de Revit instalado, porque pueden ser residuos.
- Descarga el `install.ps1` oficial.
- Ejecuta el instalador oficial por cada version elegida.
- Repara la configuracion de Claude/MCP sin borrar otros MCPs ni preferencias.
- Si la entrada Revit MCP ya existe, no la modifica.
- Detecta la ruta clasica de Claude y tambien la ruta MSIX/WindowsApps.
- Configura Antigravity/Gemini en `.gemini\config\mcp_config.json` y, si existe, tambien en `.gemini\antigravity\mcp_config.json`.
- Configura Codex en `.codex\config.toml` agregando `[mcp_servers.revit-ludattilo]` solo si falta.
- No crea archivos de configuracion de clientes si Claude, Antigravity o Codex no existen.

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
