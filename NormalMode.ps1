# Normal Mode Boot - with confirmation
# Removes Safe Mode flag and reboots normally

Write-Host ""
Write-Host "=== Boot in Normal Mode ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will:" -ForegroundColor Yellow
Write-Host "  1. Remove Safe Mode setting" -ForegroundColor White
Write-Host "  2. Immediately restart your PC" -ForegroundColor White
Write-Host ""
Write-Host "[Enter] = Proceed | [ESC] = Cancel" -ForegroundColor Yellow

do {
    $key = [Console]::ReadKey($true).Key
    if ($key -eq "Escape") {
        Write-Host "Cancelled." -ForegroundColor Red
        Start-Sleep 1
        exit
    }
} while ($key -ne "Enter")

Write-Host ""
Write-Host "Removing Safe Mode and rebooting..." -ForegroundColor Green
bcdedit /deletevalue "{current}" safeboot
shutdown /r /t 0 /f
