param (
    [string]$Target = ""
)

if ($Target -ne "") {
    Write-Host "Ejecutando gdlint en: $Target" -ForegroundColor Cyan
    gdlint $Target
} else {
    Write-Host "Ejecutando gdlint en todos los scripts/..." -ForegroundColor Cyan
    gdlint scripts/
}

