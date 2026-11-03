# Resumen de una carpeta de partidas simuladas (run_sim.ps1 / run_sim_online.ps1): resultados,
# invariantes rotas, trabas, desincronizaciones y errores de script, en <carpeta>/resumen.md.
param ([Parameter(Mandatory = $true)][string]$Carpeta)

$results = @()
$errors = @{}
$ghosts = @{}
foreach ($log in Get-ChildItem $Carpeta -Filter "*.log") {
    $name = $log.BaseName
    $json = Join-Path $Carpeta "$name.json"
    $r = $null
    if (Test-Path $json) { $r = Get-Content $json -Raw -Encoding UTF8 | ConvertFrom-Json }
    $results += [pscustomobject]@{ Nombre = $name; R = $r }
    $lines = @(Get-Content $log.FullName -Encoding UTF8)
    if (Test-Path "$($log.FullName).err") { $lines += @(Get-Content "$($log.FullName).err" -Encoding UTF8) }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "Carta fantasma borrada: (.+) \(") {
            $g = $Matches[1]
            if (-not $ghosts.ContainsKey($g)) { $ghosts[$g] = 0 }
            $ghosts[$g]++
        }
        if ($lines[$i] -match "^(SCRIPT )?ERROR: (.+)$" -and $lines[$i] -notmatch "BUG: Unreferenced|leaked at exit|PagedAllocator|ObjectDB") {
            $where = ""
            if ($i + 1 -lt $lines.Count -and $lines[$i + 1] -match "^\s+at: (.+)$") { $where = $Matches[1] }
            $key = "$($lines[$i].Trim()) | $where"
            if (-not $errors.ContainsKey($key)) { $errors[$key] = @{ Veces = 0; Partidas = @{} } }
            $errors[$key].Veces++
            $errors[$key].Partidas[$name] = $true
        }
    }
}

$md = @("# Partidas simuladas — $(Get-Date -Format 'yyyy-MM-dd HH:mm')", "")
$md += "| Partida | Mazos | Fin | Ganador | Turnos | Invariantes | Trabas | Desync | s |"
$md += "|---|---|---|---|---|---|---|---|---|"
foreach ($x in $results | Sort-Object Nombre) {
    $r = $x.R
    if (-not $r) { $md += "| $($x.Nombre) | ? | **sin resultado (colgada o caída)** | | | | | | |"; continue }
    $ds = if ($r.PSObject.Properties["desync"]) { "$(@($r.desync).Count) ($($r.checks_ok)/$($r.checks) checks OK)" } else { "" }
    $md += "| $($x.Nombre) | $($r.mazos -join ' vs ') | $($r.fin) | $($r.ganador) | $($r.turnos) | $(@($r.invariantes).Count) | $(@($r.trabas).Count) | $ds | $([math]::Round($r.segundos_reales)) |"
}

$md += "", "## Invariantes rotas", ""
$inv = @{}
foreach ($x in $results) {
    if (-not $x.R) { continue }
    foreach ($v in @($x.R.invariantes)) {
        if (-not $v) { continue }
        $k = "[$($v.tipo)] $($v.detalle -replace '\d+', 'N')"
        if (-not $inv.ContainsKey($k)) { $inv[$k] = @() }
        $inv[$k] += "$($x.Nombre) (turno $($v.turno), $($v.fase)): $($v.detalle)"
    }
}
if ($inv.Count -eq 0) { $md += "Ninguna." }
foreach ($k in $inv.Keys | Sort-Object) {
    $md += "- **$k** — $($inv[$k].Count) vez/veces"
    foreach ($e in $inv[$k] | Select-Object -First 3) { $md += "  - $e" }
}

$md += "", "## Trabas", ""
$any = $false
foreach ($x in $results) {
    if (-not $x.R) { continue }
    foreach ($t in @($x.R.trabas)) {
        if (-not $t) { continue }
        $any = $true
        $md += "- $($x.Nombre): turno $($t.turno), J$($t.activo), $($t.fase) — prioridad=$($t.prioridad)/J$($t.prioridad_de), pila=$($t.pila)/$($t.pila_acciones), resolviendo=$($t.resolviendo), eligiendo=$($t.eligiendo), selección=$($t.seleccion_abierta) · driver: $($t.paso_driver) · log: $($t.ultimo_log)"
    }
}
if (-not $any) { $md += "Ninguna." }

$md += "", "## Desincronización Anfitrión → Remoto", ""
$ds = @{}
foreach ($x in $results) {
    if (-not $x.R -or -not $x.R.PSObject.Properties["desync"]) { continue }
    foreach ($d in @($x.R.desync)) {
        if (-not $d) { continue }
        $k = $d.campo
        if (-not $ds.ContainsKey($k)) { $ds[$k] = @() }
        $ds[$k] += "$($x.Nombre) (turno $($d.turno), $($d.fase)) $($d.carta): Anfitrión=$($d.anfitrion) · Remoto=$($d.remoto) · $($d.veces) checks"
    }
}
if ($ds.Count -eq 0) { $md += "Ninguna (o no hubo partidas en línea)." }
foreach ($k in $ds.Keys | Sort-Object) {
    $md += "- **$k** — $($ds[$k].Count) caso(s)"
    foreach ($e in $ds[$k] | Select-Object -First 4) { $md += "  - $e" }
}

$md += "", "## Cartas fantasma que borró el Remoto (salieron sin remove_card)", ""
if ($ghosts.Count -eq 0) { $md += "Ninguna." }
foreach ($g in $ghosts.Keys | Sort-Object { - $ghosts[$_] }) { $md += "- $g ($($ghosts[$g])×)" }

$md += "", "## Errores de script", ""
if ($errors.Count -eq 0) { $md += "Ninguno." }
foreach ($k in $errors.Keys | Sort-Object { - $errors[$_].Veces }) {
    $md += "- ($($errors[$k].Veces)× en $($errors[$k].Partidas.Count) partida(s)) ``$k``"
}

$out = Join-Path $Carpeta "resumen.md"
$md | Out-File -FilePath $out -Encoding utf8
Write-Host "Resumen: $out"
