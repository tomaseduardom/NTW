# Partidas simuladas contra el bot (tools/sim/sim_match.gd, modo offline): una partida por proceso,
# en paralelo, y un resumen en Markdown con invariantes rotas, trabas y errores de script.
# Uso:  powershell -File tools/sim/run_sim.ps1 [-Partidas 20] [-Paralelo 4] [-Semilla 1] [-Salida sim-offline]
#       [-Godot "ruta\Godot_v4.6-stable_win64_console.exe"]
param (
    [int]$Partidas = 20,
    [int]$Paralelo = 4,
    [int]$Semilla = 1,
    [string]$Salida = "",
    [string]$Godot = "$env:USERPROFILE\Desktop\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe"
)

$project = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ($Salida -eq "") { $Salida = Join-Path $env:TEMP "wtn-sim-offline" }
New-Item -ItemType Directory -Force $Salida | Out-Null
Get-ChildItem $Salida -Filter "partida-*" | Remove-Item -Force

$timeoutS = 900
$pending = @($Semilla..($Semilla + $Partidas - 1))
$running = @()
while ($pending.Count -gt 0 -or $running.Count -gt 0) {
    while ($running.Count -lt $Paralelo -and $pending.Count -gt 0) {
        $s = $pending[0]
        $pending = @($pending | Select-Object -Skip 1)
        $json = Join-Path $Salida "partida-$s.json"
        $log = Join-Path $Salida "partida-$s.log"
        $p = Start-Process -FilePath $Godot -PassThru -WindowStyle Hidden `
            -ArgumentList "--headless", "--path", "`"$project`"", "res://tools/sim/sim_match.tscn", "--", "offline", "`"$json`"", "$s" `
            -RedirectStandardOutput $log -RedirectStandardError "$log.err"
        $running += [pscustomobject]@{ Proc = $p; Seed = $s; Start = Get-Date }
        Write-Host "Partida $s iniciada"
    }
    Start-Sleep -Milliseconds 500
    foreach ($r in @($running)) {
        if ($r.Proc.HasExited) {
            $running = @($running | Where-Object { $_ -ne $r })
            Write-Host "Partida $($r.Seed) terminada"
        } elseif (((Get-Date) - $r.Start).TotalSeconds -gt $timeoutS) {
            Stop-Process -Id $r.Proc.Id -Force
            $running = @($running | Where-Object { $_ -ne $r })
            Write-Host "Partida $($r.Seed) cortada por tiempo" -ForegroundColor Yellow
        }
    }
}

& (Join-Path $PSScriptRoot "summarize_sim.ps1") -Carpeta $Salida
