param(
    [int]$TestPort = 18095
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$passed = 0
$failed = 0

function Assert-Check {
    param(
        [string]$Name,
        [bool]$Condition,
        [string]$Detail = ""
    )
    if ($Condition) {
        $script:passed++
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    } else {
        $script:failed++
        Write-Host "  [FAIL] $Name $Detail" -ForegroundColor Red
    }
}

function Invoke-HttpRaw {
    param(
        [string]$Method,
        [string]$Url,
        [hashtable]$Headers = @{},
        [string]$Body = ""
    )
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.Method = $Method
    $req.Timeout = 5000
    foreach ($k in $Headers.Keys) {
        $req.Headers[$k] = $Headers[$k]
    }
    if ($Body) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
        $req.ContentType = "application/json; charset=utf-8"
        $req.ContentLength = $bytes.Length
        $st = $req.GetRequestStream()
        $st.Write($bytes, 0, $bytes.Length)
        $st.Close()
    }
    try {
        $resp = $req.GetResponse()
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $text = $sr.ReadToEnd()
        $sr.Close()
        $code = [int]$resp.StatusCode
        $resp.Close()
        return @{ StatusCode = $code; Body = $text }
    } catch [System.Net.WebException] {
        if ($_.Exception.Response) {
            $resp = $_.Exception.Response
            $sr = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
            $text = $sr.ReadToEnd()
            $sr.Close()
            $code = [int]$resp.StatusCode
            $resp.Close()
            return @{ StatusCode = $code; Body = $text }
        }
        throw
    }
}

Write-Host ""
Write-Host "=== InfraWatch — Suite de Verificacao ===" -ForegroundColor Cyan

# 1. Validacao sintatica dos scripts PowerShell
$psFiles = @(
    "agent\server-agent.ps1",
    "server\local-server.ps1",
    "scripts\instalar.ps1",
    "scripts\desinstalar.ps1"
)
foreach ($rel in $psFiles) {
    $full = Join-Path $ProjectRoot $rel
    $errs = $null
    [System.Management.Automation.Language.Parser]::ParseFile($full, [ref]$null, [ref]$errs) | Out-Null
    Assert-Check "Sintaxe PowerShell: $rel" ($errs.Count -eq 0) "($($errs.Count) erros)"
}

# 2. Validacao JSON
foreach ($rel in @("agent\config.example.json", "public\manifest.json")) {
    $full = Join-Path $ProjectRoot $rel
    $okJson = $false
    try {
        Get-Content -Path $full -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
        $okJson = $true
    } catch { }
    Assert-Check "JSON valido: $rel" $okJson
}

# 3. Teste do agente em modo -DryRun
$prevEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$dryOut = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectRoot "agent\server-agent.ps1") `
    -ConfigPath (Join-Path $ProjectRoot "agent\config.example.json") -DryRun 2>$null
$ErrorActionPreference = $prevEap
$dryJson = $null
try {
    $dryJson = ($dryOut -join "`n") | ConvertFrom-Json
} catch { }
Assert-Check "Agente -DryRun retorna JSON valido" ($null -ne $dryJson)
Assert-Check "Agente -DryRun contem cpu, memory, disks e network" (
    $null -ne $dryJson -and $null -ne $dryJson.cpu -and $null -ne $dryJson.memory -and $null -ne $dryJson.network
)

# 4. Testes da API HTTP local
$testApiKey = "test-api-key-1234567890"
$testBackupToken = "test-backup-token-0987654321"
$backupFile = Join-Path $ProjectRoot "data\backup-history.json"
$hadBackupFile = Test-Path $backupFile
$backupBak = $null
if ($hadBackupFile) {
    $backupBak = [System.IO.File]::ReadAllBytes($backupFile)
}

$serverProc = Start-Process -FilePath "powershell.exe" -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", (Join-Path $ProjectRoot "server\local-server.ps1"),
    "-Port", $TestPort,
    "-ApiKey", $testApiKey,
    "-BackupToken", $testBackupToken,
    "-OfflineThresholdSeconds", "20"
) -PassThru -WindowStyle Hidden

try {
    $baseUrl = "http://127.0.0.1:$TestPort"
    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        try {
            $h = Invoke-HttpRaw -Method "GET" -Url "$baseUrl/api/health"
            if ($h.StatusCode -eq 200) { $ready = $true; break }
        } catch {
            Start-Sleep -Milliseconds 500
        }
    }
    Assert-Check "Servidor HTTP local sobe na porta $TestPort" $ready

    if ($ready) {
        $rIndex = Invoke-HttpRaw -Method "GET" -Url "$baseUrl/"
        Assert-Check "GET / serve index.html com InfraWatch" ($rIndex.StatusCode -eq 200 -and $rIndex.Body -match "InfraWatch")

        $rTrav = Invoke-HttpRaw -Method "GET" -Url "$baseUrl/../agent/config.example.json"
        Assert-Check "Protecao contra path traversal (404)" ($rTrav.StatusCode -eq 404)

        $rNoKey = Invoke-HttpRaw -Method "POST" -Url "$baseUrl/api/metrics" -Body '{"hostname":"TEST"}'
        Assert-Check "POST /api/metrics sem x-api-key retorna 401" ($rNoKey.StatusCode -eq 401)

        $rBadKey = Invoke-HttpRaw -Method "POST" -Url "$baseUrl/api/metrics" -Headers @{ "x-api-key" = "errada" } -Body '{"hostname":"TEST"}'
        Assert-Check "POST /api/metrics com x-api-key invalida retorna 401" ($rBadKey.StatusCode -eq 401)

        $payload = '{"hostname":"SRV-TEST","ip":"192.168.1.50","cpu":{"usagePercent":22.5},"memory":{"usagePercent":48.0},"network":{"downloadBps":1000,"uploadBps":500}}'
        $rOkPost = Invoke-HttpRaw -Method "POST" -Url "$baseUrl/api/metrics" -Headers @{ "x-api-key" = $testApiKey } -Body $payload
        Assert-Check "POST /api/metrics autenticado retorna 200" ($rOkPost.StatusCode -eq 200)

        $rMetrics = Invoke-HttpRaw -Method "GET" -Url "$baseUrl/api/metrics"
        $mObj = $rMetrics.Body | ConvertFrom-Json
        Assert-Check "GET /api/metrics reflete status online apos heartbeat" ($rMetrics.StatusCode -eq 200 -and $mObj.status -eq "online")

        $rBadBackupAuth = Invoke-HttpRaw -Method "POST" -Url "$baseUrl/api/backup" -Headers @{ "Authorization" = "Bearer invalido" } -Body '{"tarefa":"T1","status":"sucesso"}'
        Assert-Check "POST /api/backup com Bearer invalido retorna 401" ($rBadBackupAuth.StatusCode -eq 401)

        $rBadBackupBody = Invoke-HttpRaw -Method "POST" -Url "$baseUrl/api/backup" -Headers @{ "Authorization" = "Bearer $testBackupToken" } -Body '{"tarefa":"T1","status":"invalido"}'
        Assert-Check "POST /api/backup com status invalido retorna 400" ($rBadBackupBody.StatusCode -eq 400)

        $rOkBackup = Invoke-HttpRaw -Method "POST" -Url "$baseUrl/api/backup" -Headers @{ "Authorization" = "Bearer $testBackupToken" } -Body '{"tarefa":"Backup_Teste","agendamento":"Diario","status":"sucesso","codigo":0,"maquina":"SRV-TEST"}'
        Assert-Check "POST /api/backup valido retorna 201" ($rOkBackup.StatusCode -eq 201)

        $rGetBackup = Invoke-HttpRaw -Method "GET" -Url "$baseUrl/api/backup"
        $bObj = $rGetBackup.Body | ConvertFrom-Json
        Assert-Check "GET /api/backup retorna registro persistido" ($rGetBackup.StatusCode -eq 200 -and $bObj.hasRecords -eq $true -and $bObj.lastBackup.tarefa -eq "Backup_Teste")
    }
} finally {
    if ($serverProc -and -not $serverProc.HasExited) {
        try { Stop-Process -Id $serverProc.Id -Force -ErrorAction SilentlyContinue } catch { }
    }
    if ($hadBackupFile -and $null -ne $backupBak) {
        [System.IO.File]::WriteAllBytes($backupFile, $backupBak)
    } elseif (Test-Path $backupFile) {
        Remove-Item -Force $backupFile -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "Resultado: $passed passaram, $failed falharam." -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
if ($failed -gt 0) { exit 1 }
