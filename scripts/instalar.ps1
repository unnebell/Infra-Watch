param(
    [int]$PreferredPort = 80
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# Verifica permissão de Administrador
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERRO: Execute este instalador como ADMINISTRADOR no servidor." -ForegroundColor Red
    exit 1
}

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ServerScript = Join-Path $ProjectRoot "server\local-server.ps1"
$AgentScript = Join-Path $ProjectRoot "agent\server-agent.ps1"
$ConfigPath = Join-Path $ProjectRoot "agent\config.json"
$ConfigExamplePath = Join-Path $ProjectRoot "agent\config.example.json"

if (-not (Test-Path $ServerScript) -or -not (Test-Path $AgentScript)) {
    Write-Host "ERRO: Execute este arquivo dentro da pasta completa do projeto (com 'server', 'agent' e 'public')." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $ConfigPath)) {
    if (Test-Path $ConfigExamplePath) {
        Copy-Item -Path $ConfigExamplePath -Destination $ConfigPath -Force
        Write-Host "[OK] agent\config.json criado a partir de agent\config.example.json." -ForegroundColor Green
    } else {
        Write-Host "ERRO: Arquivo agent\config.json (ou config.example.json) não encontrado." -ForegroundColor Red
        exit 1
    }
}

function New-RandomHexToken {
    param([int]$Bytes = 32)
    $buf = New-Object byte[] $Bytes
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($buf) } finally { $rng.Dispose() }
    return ([System.BitConverter]::ToString($buf) -replace '-', '').ToLowerInvariant()
}

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  InfraWatch - Instalador Completo (100% Local)" -ForegroundColor White
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Para tarefas antigas se já existirem (para liberar a porta antes de testar)
foreach ($tName in @("InfraWatchDashboard", "InfraWatchAgente")) {
    try {
        $existing = Get-ScheduledTask -TaskName $tName -ErrorAction SilentlyContinue
        if ($existing) {
            Stop-ScheduledTask -TaskName $tName -ErrorAction SilentlyContinue
        }
    } catch { }
}
Start-Sleep -Milliseconds 600

# 2. Escolhe porta 80 (acesso limpo sem porta) ou fallback para 3000 se porta 80 estiver ocupada
$chosenPort = $PreferredPort
try {
    $testListener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $PreferredPort)
    $testListener.Start()
    $testListener.Stop()
    Write-Host "[OK] Porta $PreferredPort livre! A dashboard funcionará sem precisar digitar porta no navegador." -ForegroundColor Green
} catch {
    $chosenPort = 3000
    Write-Host "[AVISO] A porta $PreferredPort já está em uso por outro programa. Usando a porta 3000." -ForegroundColor Yellow
}

# 3. Atualiza agent\config.json (endpoint local e geração de chaves únicas se estiverem com valor padrão)
$cfg = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$cfg.endpointUrl = "http://127.0.0.1:$chosenPort/api/metrics"
$placeholders = @("", "CHANGE_ME_ON_INSTALL", "server-monitor-local-key")
if (-not $cfg.apiKey -or $placeholders -contains [string]$cfg.apiKey) {
    $cfg.apiKey = New-RandomHexToken -Bytes 32
    Write-Host "[OK] Nova chave apiKey gerada automaticamente em agent\config.json." -ForegroundColor Green
}
if ($cfg.backup -and (-not $cfg.backup.apiToken -or $placeholders -contains [string]$cfg.backup.apiToken)) {
    $cfg.backup.apiToken = New-RandomHexToken -Bytes 32
    Write-Host "[OK] Novo token de backup gerado automaticamente em agent\config.json." -ForegroundColor Green
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($ConfigPath, ($cfg | ConvertTo-Json -Depth 5), $utf8NoBom)
Write-Host "[OK] agent\config.json atualizado para: $($cfg.endpointUrl)" -ForegroundColor Green

# 4. Cria regra de Firewall para redes privadas locais e VPN
$RuleName = "InfraWatch - Dashboard Local (Porta $chosenPort)"
Remove-NetFirewallRule -DisplayName "InfraWatch - Dashboard Local*" -ErrorAction SilentlyContinue
New-NetFirewallRule `
    -DisplayName $RuleName `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort $chosenPort `
    -RemoteAddress @("LocalSubnet", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "26.0.0.0/8") `
    -Action Allow `
    -Profile Private,Domain,Public `
    -ErrorAction Stop | Out-Null
Write-Host "[OK] Regra de Firewall liberada na porta $chosenPort (Rede Local e VPN)." -ForegroundColor Green

# 5. Registra as duas tarefas agendadas em segundo plano (iniciam junto com o Windows como SYSTEM)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -RestartCount 999 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Days 0)

$dashAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ServerScript`" -Port $chosenPort"
Register-ScheduledTask -TaskName "InfraWatchDashboard" -Action $dashAction -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

$agentAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$AgentScript`""
Register-ScheduledTask -TaskName "InfraWatchAgente" -Action $agentAction -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

Write-Host "[OK] Serviços automáticos 'InfraWatchDashboard' e 'InfraWatchAgente' registrados." -ForegroundColor Green

# 6. Inicia os dois serviços agora mesmo
Start-ScheduledTask -TaskName "InfraWatchDashboard"
Start-Sleep -Seconds 3
Start-ScheduledTask -TaskName "InfraWatchAgente"

$hostLower = ($env:COMPUTERNAME).ToLowerInvariant()
$portSuffix = if ($chosenPort -eq 80) { "" } else { ":$chosenPort" }

$ips = @()
try {
    $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
        Select-Object -ExpandProperty IPAddress
} catch { }

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Green
Write-Host "  INSTALAÇÃO CONCLUÍDA COM SUCESSO!" -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Green
Write-Host "  A Dashboard e o Agente agora rodam invisíveis em segundo plano" -ForegroundColor White
Write-Host "  e iniciam automaticamente sempre que o servidor ligar." -ForegroundColor White
Write-Host ""
Write-Host "  Acesse de qualquer dispositivo da rede por:" -ForegroundColor Cyan
Write-Host "    -> http://${hostLower}${portSuffix}" -ForegroundColor Yellow
foreach ($ip in $ips) {
    Write-Host "    -> http://${ip}${portSuffix}" -ForegroundColor Yellow
}
Write-Host ""
