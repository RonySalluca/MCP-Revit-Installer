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

- Ejecuta un diagnostico antes de instalar.
- Requiere al menos un cliente MCP/LLM detectado: Claude, Codex o Antigravity.
- Permite instalar clientes MCP/LLM con `winget`.
- Muestra un menu simple.
- Permite elegir versiones de Revit: 2023, 2024, 2025, 2026 y 2027.
- Permite instalar en todas las versiones reales detectadas.
- Permite escribir versiones manualmente, por ejemplo `2024,2025,2026`, solo con confirmacion explicita.
- No considera carpetas `Addins\<version>` ni claves de registro residuales como prueba suficiente de Revit instalado.
- Revit solo cuenta como detectado si encuentra un `Revit.exe` real.
- Claude, Codex y Antigravity solo cuentan como detectados si hay app instalada o ejecutable real; configs viejas no cuentan como instalacion.
- Descarga el `install.ps1` oficial.
- Ejecuta el instalador oficial por cada version elegida.
- Repara la configuracion de Claude/MCP sin borrar otros MCPs ni preferencias.
- Si la entrada Revit MCP ya existe, no la modifica.
- Detecta la ruta clasica de Claude y tambien la ruta MSIX/WindowsApps.
- Configura Antigravity/Gemini en `.gemini\config\mcp_config.json` y, si existe, tambien en `.gemini\antigravity\mcp_config.json`.
- Configura Codex en `.codex\config.toml` agregando `[mcp_servers.revit-ludattilo]` solo si falta.
- No crea archivos de configuracion de clientes si Claude, Antigravity o Codex no existen.
- Al instalar en varias versiones, configura los clientes apuntando a una version MCP verificada.

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

1. Ejecuta el script.
2. Elige `Diagnostico y recomendacion`.
3. Si no hay cliente MCP/LLM, instala Claude, Codex o Antigravity desde el menu.
4. Abre el cliente instalado al menos una vez para que cree sus archivos de configuracion.
5. Vuelve a ejecutar el script.
6. Cierra Revit.
7. Elige `Instalar/Reparar Revit MCP`.
8. Selecciona las versiones reales de Revit.
9. Elige `Configurar MCP en clientes existentes`.
10. Abre Revit, ve a `Add-Ins` y haz clic en `Revit MCP Switch`.
11. Reinicia tus clientes MCP/LLM.

## Notas

- El script no guarda claves ni credenciales.
- El script descarga los archivos oficiales al directorio temporal de Windows.
- Si el instalador oficial cambia, este wrapper seguira usando la version actual publicada por el repo oficial.

## Creditos

Instalador oficial y plugin Revit MCP:

https://github.com/LuDattilo/revit-mcp-server
