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
$FixUrl = "$RepoRaw/fix-mcp.ps1"
$InstallerPath = Join-Path $env:TEMP "install-revit-mcp-official.ps1"
$FixPath = Join-Path $env:TEMP "fix-revit-mcp-official.ps1"
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
    Write-Host "Descargando scripts oficiales..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -Headers @{ "User-Agent" = "revit-mcp-menu-installer" }
    Invoke-WebRequest -Uri $FixUrl -OutFile $FixPath -Headers @{ "User-Agent" = "revit-mcp-menu-installer" }
    Write-Host "OK: scripts descargados en TEMP." -ForegroundColor Green
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

    Write-Host ""
    Write-Host "Ejecutando reparacion de configuracion MCP/Claude..." -ForegroundColor Cyan
    & powershell -NoProfile -ExecutionPolicy Bypass -File $FixPath

    Write-Host ""
    Write-Host "Listo. Abre Revit, pulsa 'Revit MCP Switch', y reinicia Claude Desktop completo." -ForegroundColor Green
    Pause
}

function Fix-Only {
    Download-OfficialScripts
    Write-Host ""
    Write-Host "Ejecutando fix-mcp oficial..." -ForegroundColor Cyan
    & powershell -NoProfile -ExecutionPolicy Bypass -File $FixPath
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
    Write-Host "  [2] Solo reparar configuracion MCP/Claude"
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
