#Requires -Version 5.1
<#
.SYNOPSIS
    Menu installer/repair wrapper for LuDattilo/revit-mcp-server.

.DESCRIPTION
    This script does not bundle or modify the official installer.
    It downloads the latest official install.ps1 / fix-mcp.ps1 from:
    https://github.com/LuDattilo/revit-mcp-server

    Use it when the official installer does not detect all Revit versions.
    It lets you select one or more Revit versions, creates the Addins folder
    if needed, then calls the official installer with -RevitVersion.
#>

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoRaw = "https://raw.githubusercontent.com/LuDattilo/revit-mcp-server/main/scripts"
$InstallerUrl = "$RepoRaw/install.ps1"
$InstallerPath = Join-Path $env:TEMP "install-revit-mcp-official.ps1"
$SupportedYears = @("2023", "2024", "2025", "2026", "2027")

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

        $items += [PSCustomObject]@{
            Year = $year
            RevitInstalled = Test-Path $exe
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
        $detected = if ($item.RevitInstalled) { "Revit detectado" } elseif ($item.AddinsFolder) { "solo carpeta Addins" } else { "no detectado" }
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
        $years = @($info | Where-Object { $_.RevitInstalled -or $_.AddinsFolder } | ForEach-Object { $_.Year })
        if ($years.Count -eq 0) {
            Write-Host "No se detecto ninguna version. Usa M para elegir manualmente." -ForegroundColor Yellow
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

    $standardDir = Join-Path $env:APPDATA "Claude"
    $paths += (Join-Path $standardDir "claude_desktop_config.json")

    $packageRoot = Join-Path $env:LOCALAPPDATA "Packages"
    if (Test-Path $packageRoot) {
        $packageDirs = Get-ChildItem $packageRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "Claude_*" -or $_.Name -like "AnthropicClaude_*" -or $_.Name -like "Anthropic.Claude_*" }

        foreach ($pkg in $packageDirs) {
            $paths += (Join-Path $pkg.FullName "LocalCache\Roaming\Claude\claude_desktop_config.json")
        }
    }

    $existing = @($paths | Where-Object { Test-Path $_ } | Select-Object -Unique)
    if ($existing.Count -gt 0) {
        return $existing
    }

    return @((Join-Path $standardDir "claude_desktop_config.json"))
}

function Set-RevitMcpEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Installed
    )

    $configDir = Split-Path $ConfigPath -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    }

    $config = $null

    if (Test-Path $ConfigPath) {
        try {
            $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        } catch {
            $backupPath = "$ConfigPath.invalid-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item $ConfigPath $backupPath -Force
            Write-Host "El JSON anterior era invalido. Backup: $backupPath" -ForegroundColor Yellow
            $config = [PSCustomObject]@{}
        }
    } else {
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

    $configDir = Split-Path $ConfigPath -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    }

    if (Test-Path $ConfigPath) {
        try {
            $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        } catch {
            $backupPath = "$ConfigPath.invalid-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item $ConfigPath $backupPath -Force
            Write-Host "El JSON anterior era invalido. Backup: $backupPath" -ForegroundColor Yellow
            $config = [PSCustomObject]@{}
        }
    } else {
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
    if ($existing.Count -gt 0) {
        return $existing
    }

    return @($paths[0])
}

function Repair-AntigravityConfig {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Installed
    )

    Write-Host ""
    Write-Host "Reparando configuracion MCP/Antigravity..." -ForegroundColor Cyan
    $paths = @(Get-AntigravityConfigPaths)
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

    $configDir = Split-Path $ConfigPath -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    }

    $content = ""
    if (Test-Path $ConfigPath) {
        $content = Get-Content $ConfigPath -Raw
    }

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
        $addinDir = Join-Path $env:APPDATA "Autodesk\Revit\Addins\$year"
        New-Item -ItemType Directory -Force -Path $addinDir | Out-Null

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
    Write-Host "  [1] Instalar/Reparar Revit MCP en versiones elegidas"
    Write-Host "  [2] Solo reparar configuracion MCP de Claude/Antigravity/Codex"
    Write-Host "  [3] Desinstalar Revit MCP de versiones elegidas"
    Write-Host "  [4] Ver estado detectado"
    Write-Host "  [0] Salir"
    Write-Host ""

    $action = (Read-Host "Opcion").Trim()
    switch ($action) {
        "1" { Install-SelectedYears }
        "2" { Fix-Only }
        "3" { Uninstall-SelectedYears }
        "4" { Write-Title; Get-RevitYearInfo | Format-Table -AutoSize; Pause }
        "0" { exit 0 }
        default { Write-Host "Opcion no valida." -ForegroundColor Yellow; Pause }
    }
}
