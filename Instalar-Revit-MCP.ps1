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
$SupportedYears = @("2023", "2024", "2025", "2026", "2027")

function Test-RevitRegistryInstalled {
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

function Write-Title {
    Clear-Host
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Revit MCP - instalador facil" -ForegroundColor Cyan
    Write-Host " Repo oficial: LuDattilo/revit-mcp-server" -ForegroundColor DarkCyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Get-RevitYearInfo {
    $items = @()
    foreach ($year in $SupportedYears) {
        $exe = "C:\Program Files\Autodesk\Revit $year\Revit.exe"
        $addinDir = Join-Path $env:APPDATA "Autodesk\Revit\Addins\$year"
        $pluginDir = Join-Path $addinDir "revit_mcp_plugin"
        $addinFile = Join-Path $addinDir "mcp-servers-for-revit.addin"
        $exeExists = Test-Path $exe
        $registryExists = Test-RevitRegistryInstalled -Year $year

        $items += [PSCustomObject]@{
            Year = $year
            RevitInstalled = $exeExists -or $registryExists
            RevitExe = $exeExists
            RevitRegistry = $registryExists
            AddinsFolder = Test-Path $addinDir
            McpInstalled = (Test-Path $pluginDir) -and (Test-Path $addinFile)
            AddinsPath = $addinDir
        }
    }
    return $items
}

function Show-VersionTable {
    $info = Get-RevitYearInfo
    Write-Host "Versiones disponibles:" -ForegroundColor White
    Write-Host ""
    for ($i = 0; $i -lt $info.Count; $i++) {
        $item = $info[$i]
        $sources = @()
        if ($item.RevitExe) { $sources += "exe" }
        if ($item.RevitRegistry) { $sources += "registro" }
        $detected = if ($item.RevitInstalled) { "Revit detectado (" + ($sources -join "+") + ")" } elseif ($item.AddinsFolder) { "residuo Addins, no cuenta" } else { "no detectado" }
        $mcp = if ($item.McpInstalled) { "MCP instalado" } else { "MCP no instalado" }
        Write-Host ("  [{0}] Revit {1}  -  {2}  -  {3}" -f ($i + 1), $item.Year, $detected, $mcp)
    }
    Write-Host ""
    Write-Host "  [A] Todas las versiones detectadas"
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
        $manual = Read-Host "Escribe versiones separadas por coma (ej: 2024,2025,2026)"
        return @($manual.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -in $SupportedYears } | Select-Object -Unique)
    }

    $selected = @()
    foreach ($part in $choice.Split(",")) {
        $n = 0
        if ([int]::TryParse($part.Trim(), [ref]$n)) {
            if ($n -ge 1 -and $n -le $SupportedYears.Count) {
                $selected += $SupportedYears[$n - 1]
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

    $claudeInstalled = ($claudeConfigPaths.Count -gt 0) -or
        (Test-AppxPackageInstalled -NamePatterns @("*Claude*", "*Anthropic*Claude*")) -or
        (Test-AnyPath -Paths @(
            (Join-Path $env:LOCALAPPDATA "Programs\Claude\Claude.exe"),
            (Join-Path $env:LOCALAPPDATA "AnthropicClaude\Claude.exe"),
            "C:\Program Files\Claude\Claude.exe"
        ))

    $antigravityInstalled = ($antigravityConfigPaths.Count -gt 0) -or
        (Test-AnyPath -Paths @(
            (Join-Path $env:USERPROFILE ".gemini\antigravity"),
            (Join-Path $env:LOCALAPPDATA "Programs\Antigravity\Antigravity.exe"),
            "C:\Program Files\Google\Antigravity\Antigravity.exe",
            "C:\Program Files\Antigravity\Antigravity.exe"
        ))

    $codexInstalled = (Test-Path $codexConfigPath) -or
        (Test-AppxPackageInstalled -NamePatterns @("OpenAI.Codex*")) -or
        (Test-AnyPath -Paths @(
            (Join-Path $env:LOCALAPPDATA "OpenAI\Codex"),
            "C:\Program Files\WindowsApps\OpenAI.Codex_26.527.3686.0_x64__2p2nqsd0c76g0"
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
    foreach ($item in $revitInfo) {
        $sources = @()
        if ($item.RevitExe) { $sources += "exe" }
        if ($item.RevitRegistry) { $sources += "registro" }
        $status = if ($item.RevitInstalled) { "detectado (" + ($sources -join "+") + ")" } elseif ($item.AddinsFolder) { "residuo Addins, no cuenta" } else { "no detectado" }
        $mcp = if ($item.McpInstalled) { "MCP instalado" } else { "MCP no instalado" }
        Write-Host ("  - Revit {0}: {1}; {2}" -f $item.Year, $status, $mcp)
    }

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
    foreach ($year in ($SupportedYears | Sort-Object -Descending)) {
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

function Set-RevitMcpEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Installed
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-Host "Config no existe, no se crea: $ConfigPath" -ForegroundColor Yellow
        return
    }

    $config = $null

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

    $config | ConvertTo-Json -Depth 20 | Set-Content -Path $ConfigPath -Encoding UTF8
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
        Write-Host "Config no existe, no se crea: $ConfigPath" -ForegroundColor Yellow
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
    $config | ConvertTo-Json -Depth 20 | Set-Content -Path $ConfigPath -Encoding UTF8
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
        Write-Host "Antigravity/Gemini no detectado. No se crea configuracion." -ForegroundColor Yellow
        return
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

    $pattern = "(?ms)^\\[mcp_servers\\.revit-ludattilo\\]\\r?\\n.*?(?=^\\[|\\z)"
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
        Write-Host "Claude no detectado. No se crea configuracion." -ForegroundColor Yellow
        return
    }

    foreach ($configPath in $configPaths) {
        Set-RevitMcpEntry -ConfigPath $configPath -Installed $Installed
    }

    Write-Host "Claude configurado para Revit $($Installed.Year) en $($configPaths.Count) ubicacion(es)." -ForegroundColor Green
    Write-Host "Node: $($Installed.NodePath)" -ForegroundColor DarkGray
    Write-Host "Server: $($Installed.ServerPath)" -ForegroundColor DarkGray
}

function Repair-ClientConfigs {
    Write-Host ""
    Write-Host "Reparando configuraciones MCP de clientes..." -ForegroundColor Cyan

    $installed = Get-InstalledMcpServer
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

    foreach ($year in $years) {
        Write-Host ""
        Write-Host "Instalando/Reparando Revit $year..." -ForegroundColor Cyan
        & powershell -NoProfile -ExecutionPolicy Bypass -File $InstallerPath -RevitVersion $year -Force
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Revit $year termino con error. Revisa el mensaje anterior." -ForegroundColor Yellow
        }
    }

    Repair-ClientConfigs

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
