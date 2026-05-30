#Requires -Version 5.1
<#
.SYNOPSIS
    Menu installer/repair wrapper for LuDattilo/revit-mcp-server.

.DESCRIPTION
    This script does not bundle or modify the official installer.
    It downloads the latest official install.ps1 from:
    https://github.com/LuDattilo/revit-mcp-server

    Use it when the official installer does not detect all Revit versions.
    It lets you select one or more verified Revit versions, then calls the
    official installer with -RevitVersion.
#>

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoRaw = "https://raw.githubusercontent.com/LuDattilo/revit-mcp-server/main/scripts"
$InstallerUrl = "$RepoRaw/install.ps1"
$InstallerPath = Join-Path $env:TEMP "install-revit-mcp-official.ps1"
$InstallerSupportedYears = @("2023", "2024", "2025", "2026", "2027")

function Get-DetectedRevitYears {
    $years = @()

    foreach ($root in @("C:\Program Files\Autodesk", "C:\Program Files (x86)\Autodesk")) {
        if (Test-Path $root) {
            $years += Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^Revit\s+(\d{4})$' } |
                ForEach-Object { $Matches[1] }
        }
    }

    foreach ($root in @(
        "HKLM:\SOFTWARE\Autodesk\Revit",
        "HKLM:\SOFTWARE\WOW6432Node\Autodesk\Revit",
        "HKCU:\SOFTWARE\Autodesk\Revit"
    )) {
        if (Test-Path $root) {
            $years += Get-ChildItem $root -ErrorAction SilentlyContinue |
                Where-Object { $_.PSChildName -match '(\d{4})$' } |
                ForEach-Object { $Matches[1] }
        }
    }

    $addinsRoot = Join-Path $env:APPDATA "Autodesk\Revit\Addins"
    if (Test-Path $addinsRoot) {
        $years += Get-ChildItem $addinsRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{4}$' } |
            ForEach-Object { $_.Name }
    }

    $years = @($years | Where-Object { $_ -match '^\d{4}$' } | Sort-Object -Unique)

    if ($years.Count -eq 0) {
        return $InstallerSupportedYears
    }

    return $years
}

function Get-RevitExePaths {
    param([string]$Year)

    $paths = @("C:\Program Files\Autodesk\Revit $Year\Revit.exe")
    $regPaths = @(
        "HKLM:\SOFTWARE\Autodesk\Revit\Autodesk Revit $Year",
        "HKLM:\SOFTWARE\WOW6432Node\Autodesk\Revit\Autodesk Revit $Year",
        "HKCU:\SOFTWARE\Autodesk\Revit\Autodesk Revit $Year"
    )

    foreach ($path in $regPaths) {
        if (Test-Path $path) {
            try {
                $props = Get-ItemProperty $path -ErrorAction SilentlyContinue
                foreach ($name in @("InstallLocation", "InstallationLocation", "InstallDir")) {
                    $location = $props.$name
                    if ($location) {
                        $paths += (Join-Path $location "Revit.exe")
                    }
                }
            } catch {}
        }
    }

    return @($paths | Where-Object { Test-Path $_ } | Select-Object -Unique)
}

function Test-RevitRegistryResidue {
    param([string]$Year)

    $regPaths = @(
        "HKLM:\SOFTWARE\Autodesk\Revit\Autodesk Revit $Year",
        "HKLM:\SOFTWARE\WOW6432Node\Autodesk\Revit\Autodesk Revit $Year",
        "HKCU:\SOFTWARE\Autodesk\Revit\Autodesk Revit $Year"
    )

    foreach ($path in $regPaths) {
        if (Test-Path $path) {
            return $true
        }
    }

    return $false
}

function Get-RevitMcpInstallStatus {
    param([string]$Year)

    $addinDir = Join-Path $env:APPDATA "Autodesk\Revit\Addins\$Year"
    $pluginDir = Join-Path $addinDir "revit_mcp_plugin"
    $addinFile = Join-Path $addinDir "mcp-servers-for-revit.addin"
    $serverRoot = Join-Path $pluginDir "Commands\RevitMCPCommandSet\server"
    $nodePath = Join-Path $serverRoot "runtime\node.exe"
    $serverPath = Join-Path $serverRoot "build\index.js"
    $commandDll = Join-Path $pluginDir "Commands\RevitMCPCommandSet\$Year\RevitMCPCommandSet.dll"

    $hasAny = (Test-Path $addinDir) -or (Test-Path $pluginDir) -or (Test-Path $addinFile) -or (Test-Path $nodePath) -or (Test-Path $serverPath) -or (Test-Path $commandDll)
    $complete = (Test-Path $addinFile) -and (Test-Path $pluginDir) -and (Test-Path $nodePath) -and (Test-Path $serverPath) -and (Test-Path $commandDll)

    if ($complete) { return "MCP OK" }
    if ($hasAny) { return "MCP incompleto/residuo" }
    return "Sin MCP"
}

function Write-Title {
    Clear-Host
    Write-Host ""
    Write-Host "  ______   ______   _____" -ForegroundColor Red
    Write-Host " |  ____| /  ____| |  __ \" -ForegroundColor Red
    Write-Host " | |__   |  |      | |  | |" -ForegroundColor Red
    Write-Host " |  __|  |  |      | |  | |" -ForegroundColor DarkRed
    Write-Host " | |____ |  |____  | |__| |" -ForegroundColor DarkRed
    Write-Host " |______| \______| |_____/" -ForegroundColor DarkRed
    Write-Host ""
    Write-Host "        MCP Revit Installer" -ForegroundColor Cyan
    Write-Host "        Escuela de Construccion Digital" -ForegroundColor DarkCyan
    Write-Host "        Repo oficial base: LuDattilo/revit-mcp-server" -ForegroundColor DarkGray
    Write-Host "============================================================" -ForegroundColor DarkGray
    Write-Host ""
}

function Get-RevitYearInfo {
    $items = @()
    foreach ($year in (Get-DetectedRevitYears)) {
        $exe = "C:\Program Files\Autodesk\Revit $year\Revit.exe"
        $addinDir = Join-Path $env:APPDATA "Autodesk\Revit\Addins\$year"
        $pluginDir = Join-Path $addinDir "revit_mcp_plugin"
        $addinFile = Join-Path $addinDir "mcp-servers-for-revit.addin"
        $exePaths = @(Get-RevitExePaths -Year $year)
        $exeExists = $exePaths.Count -gt 0
        $registryResidue = Test-RevitRegistryResidue -Year $year
        $mcpStatus = Get-RevitMcpInstallStatus -Year $year

        $items += [PSCustomObject]@{
            Year = $year
            RevitInstalled = $exeExists
            RevitExe = $exeExists
            RevitRegistry = $registryResidue
            RevitExePath = if ($exeExists) { $exePaths -join "; " } else { "" }
            AddinsFolder = Test-Path $addinDir
            McpInstalled = $mcpStatus -eq "MCP OK"
            McpStatus = $mcpStatus
            AddinsPath = $addinDir
            SupportedByInstaller = $year -in $InstallerSupportedYears
            Installable = $exeExists -and ($year -in $InstallerSupportedYears)
        }
    }
    return $items
}

function Write-RevitTable {
    param([object[]]$Info)

    Write-Host ("  {0,-4} {1,-8} {2,-24} {3,-24} {4,-12} {5}" -f "Op", "Version", "Revit", "MCP", "Soporte", "Accion")
    Write-Host ("  {0,-4} {1,-8} {2,-24} {3,-24} {4,-12} {5}" -f "--", "-------", "-----", "---", "-------", "------") -ForegroundColor DarkGray

    for ($i = 0; $i -lt $Info.Count; $i++) {
        $item = $Info[$i]
        $op = "[$($i + 1)]"
        $revit = if ($item.RevitInstalled) {
            "REAL: Revit.exe"
        } elseif ($item.RevitRegistry -or $item.AddinsFolder -or $item.McpStatus -ne "Sin MCP") {
            "Residuo, no instalable"
        } else {
            "No detectado"
        }
        $support = if ($item.SupportedByInstaller) { "Soportado" } else { "No soportado" }
        $action = if ($item.Installable) {
            "Se puede instalar/reparar"
        } elseif ($item.RevitInstalled -and -not $item.SupportedByInstaller) {
            "Revit real, sin ZIP oficial"
        } elseif ($item.McpStatus -ne "Sin MCP") {
            "Limpiar/ignorar residuo"
        } else {
            "No usar"
        }
        $color = if ($item.Installable) { "Green" } elseif ($item.RevitInstalled -and -not $item.SupportedByInstaller) { "Magenta" } elseif ($item.McpStatus -ne "Sin MCP" -or $item.AddinsFolder -or $item.RevitRegistry) { "Yellow" } else { "DarkGray" }
        Write-Host ("  {0,-4} {1,-8} {2,-24} {3,-24} {4,-12} {5}" -f $op, $item.Year, $revit, $item.McpStatus, $support, $action) -ForegroundColor $color
    }
}

function Show-VersionTable {
    $info = Get-RevitYearInfo
    Write-Host "Versiones disponibles:" -ForegroundColor White
    Write-Host ""
    Write-RevitTable -Info $info
    Write-Host ""
    Write-Host "  [A] Todas las versiones con Revit.exe real y soporte oficial"
    Write-Host "  [M] Elegir manualmente por anios (ej: 2024,2026)"
    Write-Host ""
}

function Read-SelectedYears {
    Show-VersionTable
    $choice = (Read-Host "Elige numeros, A, o M").Trim()
    $info = Get-RevitYearInfo

    if ($choice -match "^[aA]$") {
        $years = @($info | Where-Object { $_.RevitInstalled } | ForEach-Object { $_.Year })
        if ($years.Count -eq 0) {
            Write-Host "No se detecto ninguna version real de Revit. Usa M solo si estas seguro." -ForegroundColor Yellow
            return @()
        }
        return $years
    }

    if ($choice -match "^[mM]$") {
        Write-Host "Modo manual puede instalar en versiones no detectadas. Usalo solo si sabes que Revit existe." -ForegroundColor Yellow
        $confirm = Read-Host "Escribe SI para continuar con seleccion manual"
        if ($confirm -ne "SI") {
            return @()
        }
        $manual = Read-Host "Escribe versiones separadas por coma (ej: 2024,2025,2026)"
        return @($manual.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d{4}$' } | Select-Object -Unique)
    }

    $selected = @()
    foreach ($part in $choice.Split(",")) {
        $n = 0
        if ([int]::TryParse($part.Trim(), [ref]$n)) {
            if ($n -ge 1 -and $n -le $info.Count) {
                $item = $info[$n - 1]
                if ($item.Installable) {
                    $selected += $item.Year
                } elseif ($item.RevitInstalled -and -not $item.SupportedByInstaller) {
                    Write-Host "Revit $($item.Year) existe, pero el instalador oficial no publica ZIP para esa version. Se omite." -ForegroundColor Magenta
                } else {
                    Write-Host "Revit $($item.Year) no esta detectado como instalacion real instalable. Se omite." -ForegroundColor Yellow
                }
            }
        }
    }
    return @($selected | Select-Object -Unique)
}

function Download-OfficialScripts {
    Write-Host ""
    Write-Host "Descargando instalador oficial..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -Headers @{ "User-Agent" = "revit-mcp-menu-installer" }
    Write-Host "OK: instalador descargado en TEMP." -ForegroundColor Green
}

function Test-AppxPackageInstalled {
    param([string[]]$NamePatterns)

    try {
        $packages = @(Get-AppxPackage -ErrorAction SilentlyContinue)
        foreach ($pattern in $NamePatterns) {
            if ($packages | Where-Object { $_.Name -like $pattern -or $_.PackageFullName -like $pattern }) {
                return $true
            }
        }
    } catch {}

    return $false
}

function Test-UninstallEntryInstalled {
    param([string[]]$NamePatterns)

    $roots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        foreach ($entry in Get-ChildItem $root -ErrorAction SilentlyContinue) {
            try {
                $props = Get-ItemProperty $entry.PSPath -ErrorAction SilentlyContinue
                foreach ($pattern in $NamePatterns) {
                    if ($props.DisplayName -like $pattern) {
                        return $true
                    }
                }
            } catch {}
        }
    }

    return $false
}

function Test-AnyPath {
    param([string[]]$Paths)

    foreach ($path in $Paths) {
        if (Test-Path $path) {
            return $true
        }
    }

    return $false
}

function Get-ClientStatus {
    $claudeConfigPaths = @(Get-ClaudeConfigPaths)
    $antigravityConfigPaths = @(Get-AntigravityConfigPaths)
    $codexConfigPath = Join-Path $env:USERPROFILE ".codex\config.toml"

    $claudeInstalled =
        (Test-AppxPackageInstalled -NamePatterns @("*Claude*", "*Anthropic*Claude*")) -or
        (Test-UninstallEntryInstalled -NamePatterns @("Claude", "Claude *", "Anthropic Claude*")) -or
        (Test-AnyPath -Paths @(
            (Join-Path $env:LOCALAPPDATA "Programs\Claude\Claude.exe"),
            (Join-Path $env:LOCALAPPDATA "AnthropicClaude\Claude.exe"),
            "C:\Program Files\Claude\Claude.exe",
            "C:\Program Files\Anthropic\Claude\Claude.exe"
        ))

    $antigravityInstalled =
        (Test-UninstallEntryInstalled -NamePatterns @("Antigravity", "Google Antigravity*", "Antigravity IDE*")) -or
        (Test-AnyPath -Paths @(
            (Join-Path $env:LOCALAPPDATA "Programs\Antigravity\Antigravity.exe"),
            "C:\Program Files\Google\Antigravity\Antigravity.exe",
            "C:\Program Files\Antigravity\Antigravity.exe"
        ))

    $codexInstalled =
        (Test-AppxPackageInstalled -NamePatterns @("OpenAI.Codex*")) -or
        (Test-UninstallEntryInstalled -NamePatterns @("Codex", "OpenAI Codex*")) -or
        (Test-AnyPath -Paths @(
            (Join-Path $env:LOCALAPPDATA "OpenAI\Codex\Codex.exe"),
            (Join-Path $env:LOCALAPPDATA "Programs\Codex\Codex.exe"),
            "C:\Program Files\Codex\Codex.exe"
        ))

    return @(
        [PSCustomObject]@{
            Name = "Claude"
            Installed = [bool]$claudeInstalled
            ConfigFound = $claudeConfigPaths.Count -gt 0
            ConfigPath = if ($claudeConfigPaths.Count -gt 0) { $claudeConfigPaths -join "; " } else { "" }
            WingetId = "Anthropic.Claude"
            WingetSource = "winget"
        },
        [PSCustomObject]@{
            Name = "Antigravity"
            Installed = [bool]$antigravityInstalled
            ConfigFound = $antigravityConfigPaths.Count -gt 0
            ConfigPath = if ($antigravityConfigPaths.Count -gt 0) { $antigravityConfigPaths -join "; " } else { "" }
            WingetId = "Google.Antigravity"
            WingetSource = "winget"
        },
        [PSCustomObject]@{
            Name = "Codex"
            Installed = [bool]$codexInstalled
            ConfigFound = Test-Path $codexConfigPath
            ConfigPath = if (Test-Path $codexConfigPath) { $codexConfigPath } else { "" }
            WingetId = "9PLM9XGG6VKS"
            WingetSource = "msstore"
        }
    )
}

function Test-AnyMcpClientInstalled {
    return [bool](@(Get-ClientStatus | Where-Object { $_.Installed }).Count -gt 0)
}

function Show-Diagnostics {
    Write-Title

    Write-Host "Revit:" -ForegroundColor White
    $revitInfo = @(Get-RevitYearInfo)
    Write-RevitTable -Info $revitInfo

    Write-Host ""
    Write-Host "Clientes MCP:" -ForegroundColor White
    $clients = @(Get-ClientStatus)
    foreach ($client in $clients) {
        $installed = if ($client.Installed) { "instalado/detectado" } else { "no detectado" }
        $config = if ($client.ConfigFound) { "config encontrada" } else { "sin config existente" }
        Write-Host ("  - {0}: {1}; {2}" -f $client.Name, $installed, $config)
        if ($client.ConfigFound) {
            Write-Host ("      {0}" -f $client.ConfigPath) -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    Write-Host "Recomendacion:" -ForegroundColor White
    if (-not ($revitInfo | Where-Object { $_.RevitInstalled })) {
        Write-Host "  - Instala Revit primero. No uses residuos Addins como prueba de instalacion." -ForegroundColor Yellow
    }

    if (-not ($clients | Where-Object { $_.Installed })) {
        Write-Host "  - Instala al menos un cliente MCP/LLM antes de instalar Revit MCP." -ForegroundColor Yellow
        Write-Host "  - Si no sabes cual elegir: Claude para uso general, Codex para trabajo tecnico, Antigravity si usas Gemini/Google." -ForegroundColor DarkYellow
    } elseif ($clients | Where-Object { $_.Installed -and -not $_.ConfigFound }) {
        Write-Host "  - Abre los clientes instalados una vez para que creen su configuracion; luego vuelve a correr este script." -ForegroundColor Yellow
    } else {
        Write-Host "  - Ya puedes instalar/Reparar Revit MCP y luego configurar los clientes existentes." -ForegroundColor Green
    }
}

function Read-SelectedClients {
    $clients = @(Get-ClientStatus)
    Write-Host "Clientes disponibles para instalar con winget:" -ForegroundColor White
    Write-Host ""
    for ($i = 0; $i -lt $clients.Count; $i++) {
        $client = $clients[$i]
        $status = if ($client.Installed) { "detectado" } else { "no detectado" }
        Write-Host ("  [{0}] {1}  -  {2}" -f ($i + 1), $client.Name, $status)
    }
    Write-Host ""
    Write-Host "  [A] Todos los no detectados"
    Write-Host ""

    $choice = (Read-Host "Elige numeros o A").Trim()
    if ($choice -match "^[aA]$") {
        return @($clients | Where-Object { -not $_.Installed })
    }

    $selected = @()
    foreach ($part in $choice.Split(",")) {
        $n = 0
        if ([int]::TryParse($part.Trim(), [ref]$n)) {
            if ($n -ge 1 -and $n -le $clients.Count) {
                $selected += $clients[$n - 1]
            }
        }
    }

    return @($selected | Sort-Object Name -Unique)
}

function Install-McpClients {
    Write-Title
    $selected = @(Read-SelectedClients)
    if ($selected.Count -eq 0) {
        Write-Host "No elegiste clientes para instalar." -ForegroundColor Yellow
        Pause
        return
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "winget no esta disponible en esta maquina. Instala App Installer desde Microsoft Store." -ForegroundColor Red
        Pause
        return
    }

    foreach ($client in $selected) {
        if ($client.Installed) {
            Write-Host "$($client.Name) ya parece estar instalado. Se omite." -ForegroundColor Yellow
            continue
        }

        Write-Host ""
        Write-Host "Instalando $($client.Name)..." -ForegroundColor Cyan
        & winget install --id $client.WingetId --source $client.WingetSource --accept-source-agreements --accept-package-agreements
    }

    Write-Host ""
    Write-Host "Abre cada cliente instalado al menos una vez para que cree sus archivos de configuracion." -ForegroundColor Yellow
    Write-Host "Luego vuelve a correr este script y usa la opcion de configurar MCP." -ForegroundColor Yellow
    Pause
}

function Get-InstalledMcpServer {
    param([string[]]$Years = $InstallerSupportedYears)

    foreach ($year in ($Years | Sort-Object -Descending)) {
        $serverRoot = Join-Path $env:APPDATA "Autodesk\Revit\Addins\$year\revit_mcp_plugin\Commands\RevitMCPCommandSet\server"
        $nodePath = Join-Path $serverRoot "runtime\node.exe"
        $serverPath = Join-Path $serverRoot "build\index.js"
        if ((Test-Path $nodePath) -and (Test-Path $serverPath)) {
            return [PSCustomObject]@{
                Year = $year
                NodePath = $nodePath
                ServerPath = $serverPath
            }
        }
    }
    return $null
}

function Get-ClaudeConfigPaths {
    $paths = @()

    $standardPath = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
    if (Test-Path $standardPath) {
        $paths += $standardPath
    }

    $packageRoot = Join-Path $env:LOCALAPPDATA "Packages"
    if (Test-Path $packageRoot) {
        $packageDirs = Get-ChildItem $packageRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "Claude_*" -or $_.Name -like "AnthropicClaude_*" -or $_.Name -like "Anthropic.Claude_*" }

        foreach ($pkg in $packageDirs) {
            $candidate = Join-Path $pkg.FullName "LocalCache\Roaming\Claude\claude_desktop_config.json"
            if (Test-Path $candidate) {
                $paths += $candidate
            }
        }
    }

    return @($paths | Select-Object -Unique)
}

function Format-Json {
    param([string]$json)
    $indent = 0
    $result = ""
    $inString = $false
    for ($i = 0; $i -lt $json.Length; $i++) {
        $c = $json[$i]
        if ($c -eq '"') {
            $bsCount = 0
            $j = $i - 1
            while ($j -ge 0 -and $json[$j] -eq '\') {
                $bsCount++
                $j--
            }
            if ($bsCount % 2 -eq 0) {
                $inString = -not $inString
            }
        }
        if (-not $inString) {
            if ($c -eq '{' -or $c -eq '[') {
                $indent += 2
                $result += $c + "`r`n" + (" " * $indent)
            } elseif ($c -eq '}' -or $c -eq ']') {
                $indent -= 2
                $result += "`r`n" + (" " * $indent) + $c
            } elseif ($c -eq ',') {
                $result += $c + "`r`n" + (" " * $indent)
            } elseif ($c -eq ':') {
                $result += ": "
            } elseif ([char]::IsWhiteSpace($c)) {
            } else {
                $result += $c
            }
        } else {
            $result += $c
        }
    }
    return $result
}

function Set-RevitMcpEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Installed
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-Host "Config no existe, no se modifica: $ConfigPath" -ForegroundColor Yellow
        return
    }

    try {
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    } catch {
        $backupPath = "$ConfigPath.invalid-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $ConfigPath $backupPath -Force
        Write-Host "JSON invalido, no se modifica. Backup: $backupPath" -ForegroundColor Yellow
        return
    }

    if (-not $config) {
        $config = [PSCustomObject]@{}
    }

    if (-not $config.mcpServers) {
        $config | Add-Member -NotePropertyName "mcpServers" -NotePropertyValue ([PSCustomObject]@{}) -Force
    }

    if ($config.mcpServers.PSObject.Properties["revit-mcp"]) {
        Write-Host "Ya existe revit-mcp, no se modifica: $ConfigPath" -ForegroundColor Yellow
        return
    }

    if (Test-Path $ConfigPath) {
        $backupPath = "$ConfigPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $ConfigPath $backupPath -Force
        Write-Host "Backup: $backupPath" -ForegroundColor DarkGray
    }

    $entry = [PSCustomObject]@{
        command = $Installed.NodePath
        args = @($Installed.ServerPath)
    }

    # Preserve every existing MCP server and every top-level Claude setting.
    # Only add revit-mcp when it is missing.
    $config.mcpServers | Add-Member -NotePropertyName "revit-mcp" -NotePropertyValue $entry

    $rawJson = $config | ConvertTo-Json -Depth 20 -Compress
    $formattedJson = Format-Json -json $rawJson
    Set-Content -Path $ConfigPath -Value $formattedJson -Encoding UTF8
    Get-Content $ConfigPath -Raw | ConvertFrom-Json | Out-Null
    Write-Host "OK: $ConfigPath" -ForegroundColor Green
}

function Set-JsonMcpEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Installed
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-Host "Config no existe, no se modifica: $ConfigPath" -ForegroundColor Yellow
        return
    }

    try {
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    } catch {
        $backupPath = "$ConfigPath.invalid-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $ConfigPath $backupPath -Force
        Write-Host "JSON invalido, no se modifica. Backup: $backupPath" -ForegroundColor Yellow
        return
    }

    if (-not $config) {
        $config = [PSCustomObject]@{}
    }

    if (-not $config.mcpServers) {
        $config | Add-Member -NotePropertyName "mcpServers" -NotePropertyValue ([PSCustomObject]@{}) -Force
    }

    if ($config.mcpServers.PSObject.Properties[$ServerName]) {
        Write-Host "Ya existe $ServerName, no se modifica: $ConfigPath" -ForegroundColor Yellow
        return
    }

    if (Test-Path $ConfigPath) {
        $backupPath = "$ConfigPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $ConfigPath $backupPath -Force
        Write-Host "Backup: $backupPath" -ForegroundColor DarkGray
    }

    $entry = [PSCustomObject]@{
        command = $Installed.NodePath
        args = @($Installed.ServerPath)
        env = [PSCustomObject]@{}
    }

    $config.mcpServers | Add-Member -NotePropertyName $ServerName -NotePropertyValue $entry
    $rawJson = $config | ConvertTo-Json -Depth 20 -Compress
    $formattedJson = Format-Json -json $rawJson
    Set-Content -Path $ConfigPath -Value $formattedJson -Encoding UTF8
    Get-Content $ConfigPath -Raw | ConvertFrom-Json | Out-Null
    Write-Host "OK: $ConfigPath" -ForegroundColor Green
}

function Get-AntigravityConfigPaths {
    $paths = @(
        (Join-Path $env:USERPROFILE ".gemini\config\mcp_config.json"),
        (Join-Path $env:USERPROFILE ".gemini\antigravity\mcp_config.json")
    )

    $existing = @($paths | Where-Object { Test-Path $_ } | Select-Object -Unique)
    return $existing
}

function Repair-AntigravityConfig {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Installed
    )

    Write-Host ""
    Write-Host "Reparando configuracion MCP/Antigravity..." -ForegroundColor Cyan
    $paths = @(Get-AntigravityConfigPaths)
    if ($paths.Count -eq 0) {
        $defaultPath = Join-Path $env:USERPROFILE ".gemini\config\mcp_config.json"
        $paths = @($defaultPath)
    }

    foreach ($path in $paths) {
        Set-JsonMcpEntry -ConfigPath $path -ServerName "revit-mcp" -Installed $Installed
    }
    Write-Host "Antigravity configurado en $($paths.Count) ubicacion(es)." -ForegroundColor Green
}

function ConvertTo-TomlLiteral {
    param([string]$Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

function Set-CodexMcpEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Installed
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-Host "Codex no detectado o config.toml no existe. No se crea configuracion." -ForegroundColor Yellow
        return
    }

    $content = ""
    $content = Get-Content $ConfigPath -Raw

    $nodeLiteral = ConvertTo-TomlLiteral $Installed.NodePath
    $serverLiteral = ConvertTo-TomlLiteral $Installed.ServerPath
    $block = @"
[mcp_servers.revit-ludattilo]
command = $nodeLiteral
args = [$serverLiteral]
enabled = true
"@

    $pattern = '(?ms)^\[mcp_servers\.revit-ludattilo\]\r?\n.*?(?=^\[|\z)'
    if ($content -match $pattern) {
        Write-Host "Ya existe [mcp_servers.revit-ludattilo], no se modifica: $ConfigPath" -ForegroundColor Yellow
        return
    } else {
        if (Test-Path $ConfigPath) {
            $backupPath = "$ConfigPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item $ConfigPath $backupPath -Force
            Write-Host "Backup: $backupPath" -ForegroundColor DarkGray
        }

        if ($content.Trim().Length -gt 0) {
            $content = $content.TrimEnd() + "`r`n`r`n" + $block.TrimEnd() + "`r`n"
        } else {
            $content = $block.TrimEnd() + "`r`n"
        }
    }

    Set-Content -Path $ConfigPath -Value $content -Encoding UTF8
    Write-Host "OK: $ConfigPath" -ForegroundColor Green
}

function Repair-CodexConfig {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Installed
    )

    Write-Host ""
    Write-Host "Reparando configuracion MCP/Codex..." -ForegroundColor Cyan
    $path = Join-Path $env:USERPROFILE ".codex\config.toml"
    Set-CodexMcpEntry -ConfigPath $path -Installed $Installed
    Write-Host "Codex configurado." -ForegroundColor Green
}

function Repair-ClaudeConfig {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Installed
    )

    Write-Host ""
    Write-Host "Reparando configuracion MCP/Claude..." -ForegroundColor Cyan

    $configPaths = @(Get-ClaudeConfigPaths)
    if ($configPaths.Count -eq 0) {
        $defaultPath = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
        $configPaths = @($defaultPath)
    }

    foreach ($configPath in $configPaths) {
        Set-RevitMcpEntry -ConfigPath $configPath -Installed $Installed
    }

    Write-Host "Claude configurado para Revit $($Installed.Year) en $($configPaths.Count) ubicacion(es)." -ForegroundColor Green
    Write-Host "Node: $($Installed.NodePath)" -ForegroundColor DarkGray
    Write-Host "Server: $($Installed.ServerPath)" -ForegroundColor DarkGray
}

function Repair-ClientConfigs {
    param([string[]]$Years = $InstallerSupportedYears)

    Write-Host ""
    Write-Host "Reparando configuraciones MCP de clientes..." -ForegroundColor Cyan

    $installed = Get-InstalledMcpServer -Years $Years
    if (-not $installed) {
        Write-Host "No encontre server\\build\\index.js y runtime\\node.exe instalados. Se omite configuracion de clientes." -ForegroundColor Yellow
        return
    }

    Repair-ClaudeConfig -Installed $installed
    Repair-AntigravityConfig -Installed $installed
    Repair-CodexConfig -Installed $installed
}

function Install-SelectedYears {
    if (-not (Test-AnyMcpClientInstalled)) {
        Write-Host "No se detecto ningun cliente MCP/LLM instalado." -ForegroundColor Red
        Write-Host "Primero instala Claude, Codex o Antigravity desde la opcion de clientes." -ForegroundColor Yellow
        Pause
        return
    }

    $years = Read-SelectedYears
    if ($years.Count -eq 0) {
        Write-Host "No elegiste versiones validas." -ForegroundColor Yellow
        Pause
        return
    }

    Download-OfficialScripts

    Write-Host ""
    Write-Host "IMPORTANTE: cierra Revit antes de continuar." -ForegroundColor Yellow
    Read-Host "Presiona Enter cuando Revit este cerrado"

    $installedYears = @()
    foreach ($year in $years) {
        Write-Host ""
        Write-Host "Instalando/Reparando Revit $year..." -ForegroundColor Cyan
        & powershell -NoProfile -ExecutionPolicy Bypass -File $InstallerPath -RevitVersion $year -Force
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Revit $year termino con error. Revisa el mensaje anterior." -ForegroundColor Yellow
        } else {
            $server = Get-InstalledMcpServer -Years @($year)
            if ($server) {
                $installedYears += $year
            } else {
                Write-Host "No encontre el servidor MCP instalado para Revit $year despues del instalador." -ForegroundColor Yellow
            }
        }
    }

    if ($installedYears.Count -gt 0) {
        Repair-ClientConfigs -Years $installedYears
    } else {
        Write-Host "No hay instalaciones MCP verificadas para configurar en clientes." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Listo. Abre Revit, pulsa 'Revit MCP Switch', y reinicia tus clientes MCP." -ForegroundColor Green
    Pause
}

function Fix-Only {
    Repair-ClientConfigs
    Pause
}

function Uninstall-SelectedYears {
    $years = Read-SelectedYears
    if ($years.Count -eq 0) {
        Write-Host "No elegiste versiones validas." -ForegroundColor Yellow
        Pause
        return
    }

    Download-OfficialScripts

    Write-Host ""
    Write-Host "Esto desinstalara Revit MCP solo de las versiones elegidas." -ForegroundColor Yellow
    $ok = Read-Host "Escribe SI para continuar"
    if ($ok -ne "SI") {
        Write-Host "Cancelado." -ForegroundColor Yellow
        Pause
        return
    }

    foreach ($year in $years) {
        Write-Host ""
        Write-Host "Desinstalando de Revit $year..." -ForegroundColor Cyan
        & powershell -NoProfile -ExecutionPolicy Bypass -File $InstallerPath -RevitVersion $year -Uninstall
    }
    Pause
}

while ($true) {
    Write-Title
    Write-Host "Que quieres hacer?" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1] Diagnostico y recomendacion"
    Write-Host "  [2] Instalar clientes MCP/LLM (Claude, Codex, Antigravity)"
    Write-Host "  [3] Instalar/Reparar Revit MCP en versiones elegidas"
    Write-Host "  [4] Configurar MCP en clientes existentes"
    Write-Host "  [5] Desinstalar Revit MCP de versiones elegidas"
    Write-Host "  [0] Salir"
    Write-Host ""

    $action = (Read-Host "Opcion").Trim()
    switch ($action) {
        "1" { Show-Diagnostics; Pause }
        "2" { Install-McpClients }
        "3" { Install-SelectedYears }
        "4" { Fix-Only }
        "5" { Uninstall-SelectedYears }
        "0" { exit 0 }
        default { Write-Host "Opcion no valida." -ForegroundColor Yellow; Pause }
    }
}

