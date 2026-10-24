<#
.SYNOPSIS
    Copia el cache local de cartas a data/cards.json para que viaje dentro
    del ejecutable exportado (res://data/cards.json).

.DESCRIPTION
    2026-10-12: el juego cargaba las cartas del cache de CADA PC
    (%APPDATA%\Godot\app_userdata\NTW\card_cache\cards.json), así
    que el Anfitrión y el Remoto podían tener catálogos distintos (p.ej. uno
    con Drácula y el otro sin) y cada jugador tenía que sincronizar por su
    cuenta. Con data/cards.json en el proyecto, CardDatabase.load_cards_from_
    bundled() lo carga primero y el zip ya trae las cartas. sync_cards.ps1
    llama a este script al terminar.

.EXAMPLE
    .\bundle_cards.ps1
#>
$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$cacheFile = Join-Path $env:APPDATA "Godot\app_userdata\NTW\card_cache\cards.json"
$bundleFile = Join-Path (Split-Path -Parent $here) "data\cards.json"

if (-not (Test-Path $cacheFile)) {
    Write-Error "No se encontro el cache local del juego en: $cacheFile"
    exit 1
}

# Se valida que sea un JSON con una lista de cartas antes de copiarlo.
$text = [System.IO.File]::ReadAllText($cacheFile, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
$cards = $text | ConvertFrom-Json
if ($null -eq $cards -or $cards.Count -lt 100) {
    Write-Error "El cache no parece valido (cartas: $($cards.Count)). No se toco data\cards.json."
    exit 1
}

# Sin BOM: load_cards_from_bundled() usa JSON.parse_string() sobre el texto crudo.
[System.IO.File]::WriteAllText($bundleFile, $text, (New-Object System.Text.UTF8Encoding $false))
Write-Host "data\cards.json actualizado: $($cards.Count) cartas."
