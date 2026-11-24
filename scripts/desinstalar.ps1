try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERRO: Execute como ADMINISTRADOR." -ForegroundColor Red
    exit 1
}

foreach ($tName in @("InfraWatchDashboard", "InfraWatchAgente")) {
    try {
        Stop-ScheduledTask -TaskName $tName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $tName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "[OK] Tarefa '$tName' removida." -ForegroundColor Green
    } catch { }
}

Remove-NetFirewallRule -DisplayName "InfraWatch - Dashboard Local*" -ErrorAction SilentlyContinue
Write-Host "[OK] Regra de firewall removida." -ForegroundColor Green
Write-Host "Desinstalação concluída." -ForegroundColor Cyan
