param (
    [string]$Target = ""
)

if ($Target -ne "") {
    Write-Host "Formateando con gdformat (-l 120): $Target" -ForegroundColor Cyan
    gdformat -l 120 $Target
} else {
    Write-Host "Especifica un archivo o carpeta. Ejemplos:" -ForegroundColor Yellow
    Write-Host "  .\tools\format.ps1 scripts/core/effects/triggers/DSR_SearchGoldCombos.gd"
    Write-Host "  .\tools\format.ps1 scripts/ui/hand/"
}

