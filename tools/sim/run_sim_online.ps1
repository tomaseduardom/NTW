# Partidas en línea simuladas (tools/sim/sim_match.gd, modos host y remote): levanta el relay local,
# corre Anfitrión y Remoto en dos procesos headless y compara en cada checkpoint lo que el Remoto ve
# contra el estado del Anfitrión. Resumen en <Salida>/resumen.md.
# Uso:  powershell -File tools/sim/run_sim_online.ps1 [-Partidas 5] [-Semilla 1] [-Puerto 8091]
#       [-Salida carpeta] [-Godot "ruta\Godot_v4.6-stable_win64_console.exe"]
param (
    [int]$Partidas = 5,
    [int]$Semilla = 1,
    [int]$Puerto = 8091,
    [string]$Salida = "",
    [string]$Godot = "$env:USERPROFILE\Desktop\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe"
)

$project = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ($Salida -eq "") { $Salida = Join-Path $env:TEMP "wtn-sim-online" }
New-Item -ItemType Directory -Force $Salida | Out-Null
Get-ChildItem $Salida | Where-Object { $_.Name -match "^(host|remoto|codigo)-" } | Remove-Item -Force

$env:PORT = "$Puerto"
$env:TRUST_PROXY = "0"
$relay = Start-Process -FilePath "node" -ArgumentList "server.js" -WorkingDirectory (Join-Path $project "relay-server") `
    -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $Salida "relay.txt") -RedirectStandardError (Join-Path $Salida "relay-err.txt")
Start-Sleep -Seconds 2
$url = "ws://localhost:$Puerto"
$timeoutS = 1200

try {
    for ($s = $Semilla; $s -lt $Semilla + $Partidas; $s++) {
        $code = Join-Path $Salida "codigo-$s.txt"
        $procs = @()
        foreach ($m in @("host", "remote")) {
            $tag = if ($m -eq "host") { "host" } else { "remoto" }
            $json = Join-Path $Salida "$tag-$s.json"
            $log = Join-Path $Salida "$tag-$s.log"
            $procs += Start-Process -FilePath $Godot -PassThru -WindowStyle Hidden `
                -ArgumentList "--headless", "--path", "`"$project`"", "res://tools/sim/sim_match.tscn", "--", $m, "`"$json`"", "$s", "`"$code`"", $url `
                -RedirectStandardOutput $log -RedirectStandardError "$log.err"
        }
        Write-Host "Partida en línea $s iniciada"
        $start = Get-Date
        while (@($procs | Where-Object { -not $_.HasExited }).Count -gt 0) {
            Start-Sleep -Milliseconds 500
            if (((Get-Date) - $start).TotalSeconds -gt $timeoutS) {
                $procs | Where-Object { -not $_.HasExited } | ForEach-Object { Stop-Process -Id $_.Id -Force }
                Write-Host "Partida $s cortada por tiempo" -ForegroundColor Yellow
            }
        }
        Write-Host "Partida en línea $s terminada"
    }
} finally {
    Stop-Process -Id $relay.Id -Force -ErrorAction SilentlyContinue
}

& (Join-Path $PSScriptRoot "summarize_sim.ps1") -Carpeta $Salida
