<#
.SYNOPSIS
    Agrega al cache local del juego las cartas de la API de ShadowForge que
    todavía no están (ediciones nuevas), sin tocar las que ya existen.

.DESCRIPTION
    2026-10-12: complemento de reload_card.ps1 (que actualiza cartas puntuales
    por nombre). Este baja el formato completo y agrega solo las cartas cuyo
    myl_id no está en el cache. Con -Update además reemplaza las que cambiaron
    de texto/coste/fuerza. Antes de escribir deja una copia del cache en
    cards.json.bak. Al final regenera data\cards.json (bundle_cards.ps1) para
    que el próximo zip lleve las cartas nuevas.

.PARAMETER Format
    Formato/temporada a consultar en la API (default "imp" = Imperio).

.PARAMETER Update
    También actualiza las cartas existentes cuyo texto/coste/fuerza cambió.

.PARAMETER DryRun
    Solo informa qué haría, sin escribir el cache.

.EXAMPLE
    .\sync_cards.ps1
    .\sync_cards.ps1 -DryRun
    .\sync_cards.ps1 -Update
#>
param(
    [string]$Format = "imp",
    [switch]$Update,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$credFile = Join-Path $here "shadowforge_credentials.local.ps1"
if (-not (Test-Path $credFile)) {
    Write-Error "Falta $credFile. Copia shadowforge_credentials.example.ps1 con ese nombre y completa usuario/contrasena."
    exit 1
}
. $credFile

$apiBase = "https://iterva.pythonanywhere.com/api/external"
$cacheFile = Join-Path $env:APPDATA "Godot\app_userdata\NTW\card_cache\cards.json"
if (-not (Test-Path $cacheFile)) {
    Write-Error "No se encontro el cache local del juego en: $cacheFile"
    exit 1
}

# Mismo motivo que en reload_card.ps1: PowerShell 5.1 no decodifica bien el
# UTF-8 de la respuesta si el servidor no declara el charset.
function Invoke-Utf8Json {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [string]$Method = "Get",
        [hashtable]$Headers = @{},
        [string]$Body = $null
    )
    $params = @{ Uri = $Uri; Method = $Method; UseBasicParsing = $true; Headers = $Headers }
    if ($Body) {
        $params.Body = $Body
        $params.ContentType = "application/json"
    }
    $resp = Invoke-WebRequest @params
    $text = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
    return $text | ConvertFrom-Json
}

# Constants.CardType (Constants.gd): ORO=0, ALIADO=1, ARMA=2, TALISMAN=3, TOTEM=4
$typeMap = @{
    "oro" = 0; "aliado" = 1; "arma" = 2; "talisman" = 3; "talismán" = 3; "totem" = 4; "tótem" = 4
}
# Constants.Keyword (Constants.gd), en el mismo orden del enum
$keywordMap = [ordered]@{
    "furia" = 0; "imbloqueable" = 1; "indestructible" = 2; "indesterrable" = 3
    "única" = 4; "unica" = 4; "exhumar" = 5; "errante" = 6; "retador" = 7
}

function ConvertTo-CacheCard($m) {
    $abilityText = ""
    if ($m.ability) { $abilityText = $m.ability }
    $lowerAbility = $abilityText.ToLower()
    $keywords = New-Object System.Collections.ArrayList
    foreach ($kw in $keywordMap.Keys) {
        if ($lowerAbility.Contains($kw) -and -not $keywords.Contains($keywordMap[$kw])) {
            [void]$keywords.Add($keywordMap[$kw])
        }
    }
    $typeKey = "aliado"
    if ($m.type) { $typeKey = $m.type.ToString().ToLower() }
    $tipo = 1
    if ($typeMap.ContainsKey($typeKey)) { $tipo = $typeMap[$typeKey] }
    $coste = 0
    if ($null -ne $m.cost -and $m.cost -ne "") { $coste = [int]$m.cost }
    $fuerza = 0
    if ($null -ne $m.damage -and $m.damage -ne "") { $fuerza = [int]$m.damage }
    # El juego espera String en estos campos (ver reload_card.ps1).
    $raza = ""; if ($null -ne $m.race) { $raza = $m.race }
    $edicion = ""; if ($null -ne $m.edition_title) { $edicion = $m.edition_title }
    $frecuencia = ""; if ($null -ne $m.rarity) { $frecuencia = $m.rarity }
    $imagen = ""; if ($null -ne $m.image_url) { $imagen = $m.image_url }
    return [PSCustomObject][ordered]@{
        id          = "$($m.myl_id)"
        uuid        = "$($m.myl_id)"
        nombre      = $m.name
        tipo        = $tipo
        coste       = $coste
        fuerza      = $fuerza
        habilidad   = $abilityText
        raza        = $raza
        edicion     = $edicion
        frecuencia  = $frecuencia
        imagen      = $imagen
        keywords    = @($keywords)
        texto_epico = ""
    }
}

Write-Host "Iniciando sesion en ShadowForge..."
$body = @{ username = $ShadowForgeUser; password = $ShadowForgePass } | ConvertTo-Json
$accessToken = (Invoke-Utf8Json -Uri "$apiBase/token/" -Method Post -Body $body).access

Write-Host "Bajando cartas del formato '$Format'..."
$apiCards = (Invoke-Utf8Json -Uri "$apiBase/cards/$Format/" -Headers @{ Authorization = "Bearer $accessToken" }).cards
Write-Host "  $($apiCards.Count) cartas en la API."

$cache = Get-Content $cacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
$cacheList = [System.Collections.Generic.List[object]]::new()
$indexById = @{}
foreach ($c in $cache) {
    $indexById["$($c.id)"] = $cacheList.Count
    $cacheList.Add($c)
}

$added = @{}
$updated = 0
foreach ($m in $apiCards) {
    $id = "$($m.myl_id)"
    $newCard = ConvertTo-CacheCard $m
    if (-not $indexById.ContainsKey($id)) {
        $indexById[$id] = $cacheList.Count
        $cacheList.Add($newCard)
        $ed = $newCard.edicion
        if (-not $added.ContainsKey($ed)) { $added[$ed] = 0 }
        $added[$ed]++
    } elseif ($Update) {
        $old = $cacheList[$indexById[$id]]
        if ($old.habilidad -ne $newCard.habilidad -or $old.coste -ne $newCard.coste -or $old.fuerza -ne $newCard.fuerza) {
            Write-Host "  Actualizada: $($newCard.nombre) [$id]"
            $cacheList[$indexById[$id]] = $newCard
            $updated++
        }
    }
}

$totalAdded = 0
foreach ($ed in $added.Keys) {
    Write-Host ("  + {0,4}  {1}" -f $added[$ed], $ed)
    $totalAdded += $added[$ed]
}
Write-Host "Nuevas: $totalAdded   Actualizadas: $updated   Total en cache: $($cacheList.Count)"

if ($DryRun) {
    Write-Host "(DryRun: no se escribio nada)"
    exit 0
}
if ($totalAdded -eq 0 -and $updated -eq 0) {
    Write-Host "El cache ya estaba al dia."
    exit 0
}

Copy-Item $cacheFile "$cacheFile.bak" -Force
# Se escribe sin BOM: CardDatabase.load_cards_from_cache() usa JSON.parse_string()
# sobre el texto crudo.
$json = $cacheList | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($cacheFile, $json, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Cache actualizado (copia previa en cards.json.bak):"
Write-Host "  $cacheFile"

# El zip lleva las cartas dentro (res://data/cards.json) — ver bundle_cards.ps1.
& (Join-Path $here "bundle_cards.ps1")
