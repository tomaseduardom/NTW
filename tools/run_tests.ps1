# Corre las pruebas headless de NTW antes de exportar:
#   tools/tests/test_core.tscn          reglas y red sin tablero (mazos, texto, reloj, historial)
#   tools/test_keywords_strength.tscn   palabras clave y Fuerza con cartas reales en el tablero
# Uso:  powershell -File tools/run_tests.ps1 [-Godot "ruta\Godot_v4.6-stable_win64_console.exe"]
# Sale con código 1 si alguna suite falla.
param (
    [string]$Godot = "$env:USERPROFILE\Desktop\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe"
)

$project = Split-Path -Parent $PSScriptRoot
$suites = @("res://tools/tests/test_core.tscn", "res://tools/test_keywords_strength.tscn")
$failed = 0

foreach ($suite in $suites) {
    Write-Host "== $suite" -ForegroundColor Cyan
    $output = & $Godot --headless --path $project $suite 2>&1
    $code = $LASTEXITCODE
    $output | Where-Object { $_ -match "FALLA|esperado|obtenido|casos OK|SCRIPT ERROR" } | ForEach-Object { Write-Host $_ }
    if ($code -ne 0) {
        $failed++
        Write-Host "   -> falló (código $code)" -ForegroundColor Red
    } else {
        Write-Host "   -> OK" -ForegroundColor Green
    }
}

if ($failed -gt 0) {
    Write-Host "$failed suite(s) con fallas" -ForegroundColor Red
    exit 1
}
Write-Host "Todas las suites OK" -ForegroundColor Green
