param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "config.json"),
    [string]$EndpointUrlOverride = "",
    [switch]$RunOnce,
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not (Test-Path $ConfigPath)) {
    Write-Error "Arquivo de configuração não encontrado: $ConfigPath"
    exit 1
}

$config = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$endpointUrl = if ($EndpointUrlOverride) { $EndpointUrlOverride } else { $config.endpointUrl }
$apiKey = if ($config.apiKey) { [string]$config.apiKey } else { "" }
if (-not $DryRun -and ([string]::IsNullOrWhiteSpace($apiKey) -or $apiKey -eq "CHANGE_ME_ON_INSTALL")) {
    Write-Error "Chave 'apiKey' não configurada em $ConfigPath. Execute scripts\instalar.ps1 ou defina uma chave segura."
    exit 1
}
$intervalSeconds = if ($config.intervalSeconds -and $config.intervalSeconds -ge 2) { [int]$config.intervalSeconds } else { 5 }

# Coletor nativo de CPU via kernel32.dll (GetSystemTimes) - independe de WMI e idioma do Windows
try {
    if (-not ([System.Management.Automation.PSTypeName]'InfraWatchCpuNative').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Threading;

public static class InfraWatchCpuNative
{
    [StructLayout(LayoutKind.Sequential)]
    private struct FILETIME { public uint dwLowDateTime; public uint dwHighDateTime; }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetSystemTimes(out FILETIME idle, out FILETIME kernel, out FILETIME user);

    private static ulong ToUInt64(FILETIME ft)
    {
        return ((ulong)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
    }

    private static ulong _prevIdle = 0;
    private static ulong _prevKernel = 0;
    private static ulong _prevUser = 0;
    private static bool _hasPrev = false;

    public static double GetCpuPercent()
    {
        FILETIME i, k, u;
        if (!GetSystemTimes(out i, out k, out u)) return -1;
        ulong idle = ToUInt64(i);
        ulong kernel = ToUInt64(k);
        ulong user = ToUInt64(u);

        if (!_hasPrev)
        {
            _prevIdle = idle; _prevKernel = kernel; _prevUser = user; _hasPrev = true;
            Thread.Sleep(350);
            if (!GetSystemTimes(out i, out k, out u)) return -1;
            idle = ToUInt64(i); kernel = ToUInt64(k); user = ToUInt64(u);
        }

        ulong dIdle = idle >= _prevIdle ? idle - _prevIdle : 0;
        ulong dKernel = kernel >= _prevKernel ? kernel - _prevKernel : 0;
        ulong dUser = user >= _prevUser ? user - _prevUser : 0;

        _prevIdle = idle; _prevKernel = kernel; _prevUser = user;

        ulong dTotal = dKernel + dUser;
        if (dTotal == 0) return 0;
        double busy = ((double)(dTotal - dIdle) / (double)dTotal) * 100.0;
        if (busy < 0) busy = 0;
        if (busy > 100) busy = 100;
        return Math.Round(busy, 1);
    }
}

public static class InfraWatchSessionNative
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WTS_SESSION_INFO
    {
        public int SessionID;
        public string pWinStationName;
        public int State;
    }

    [DllImport("wtsapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool WTSEnumerateSessions(IntPtr hServer, int Reserved, int Version, out IntPtr ppSessionInfo, out int pCount);

    [DllImport("wtsapi32.dll")]
    private static extern void WTSFreeMemory(IntPtr pMemory);

    [DllImport("wtsapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool WTSQuerySessionInformation(IntPtr hServer, int sessionId, int wtsInfoClass, out IntPtr ppBuffer, out int pBytesReturned);

    private static string QueryString(int sessionId, int infoClass)
    {
        IntPtr buffer;
        int bytes;
        if (WTSQuerySessionInformation(IntPtr.Zero, sessionId, infoClass, out buffer, out bytes) && buffer != IntPtr.Zero)
        {
            try { return Marshal.PtrToStringUni(buffer) ?? ""; }
            finally { WTSFreeMemory(buffer); }
        }
        return "";
    }

    public static System.Collections.Generic.List<System.Collections.Generic.Dictionary<string, object>> GetSessions()
    {
        var result = new System.Collections.Generic.List<System.Collections.Generic.Dictionary<string, object>>();
        IntPtr ppSessionInfo = IntPtr.Zero;
        int count = 0;

        if (!WTSEnumerateSessions(IntPtr.Zero, 0, 1, out ppSessionInfo, out count) || ppSessionInfo == IntPtr.Zero)
            return result;

        try
        {
            int dataSize = Marshal.SizeOf(typeof(WTS_SESSION_INFO));
            for (int i = 0; i < count; i++)
            {
                IntPtr current = new IntPtr(ppSessionInfo.ToInt64() + (i * dataSize));
                WTS_SESSION_INFO si = (WTS_SESSION_INFO)Marshal.PtrToStructure(current, typeof(WTS_SESSION_INFO));
                if (si.SessionID == 0) continue;

                string user = QueryString(si.SessionID, 5).Trim();
                if (string.IsNullOrEmpty(user)) continue;

                string domain = QueryString(si.SessionID, 7).Trim();
                string client = QueryString(si.SessionID, 10).Trim();
                string winStation = (si.pWinStationName ?? "").Trim();

                bool isActive = (si.State == 0 || si.State == 1);
                string stateText = si.State == 0 ? "Ativo" : (si.State == 1 ? "Conectado" : (si.State == 4 ? "Desconectado" : "Sessao"));
                bool isRdp = winStation.StartsWith("RDP", StringComparison.OrdinalIgnoreCase) || !string.IsNullOrEmpty(client);
                string source = isRdp ? (string.IsNullOrEmpty(client) ? "RDP" : "RDP (" + client + ")") : "Console";

                var item = new System.Collections.Generic.Dictionary<string, object>
                {
                    { "username", user },
                    { "domain", domain },
                    { "sessionName", string.IsNullOrEmpty(winStation) ? ("sessao-" + si.SessionID) : winStation },
                    { "state", stateText },
                    { "isActive", isActive },
                    { "idleTime", "-" },
                    { "logonTime", "Logado (ID " + si.SessionID + ")" },
                    { "source", source }
                };
                result.Add(item);
            }
        }
        finally
        {
            WTSFreeMemory(ppSessionInfo);
        }

        return result;
    }
}
"@ -ErrorAction Stop
    }
} catch { }

# Cache de informações de hardware que não mudam durante a execução
$cpuStatic = $null
$osStatic = $null
$csStatic = $null
try { $cpuStatic = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1 } catch { }
try { $osStatic = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop | Select-Object -First 1 } catch { }
try { $csStatic = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop | Select-Object -First 1 } catch { }

$regCpu = Get-ItemProperty -Path "HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0" -ErrorAction SilentlyContinue

$hostname = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } elseif ($csStatic) { $csStatic.Name } else { "WINDOWS-SERVER" }
$cpuName = if ($cpuStatic -and $cpuStatic.Name) {
    ($cpuStatic.Name -replace "\s+", " ").Trim()
} elseif ($regCpu -and $regCpu.ProcessorNameString) {
    ($regCpu.ProcessorNameString -replace "\s+", " ").Trim()
} else {
    "Processador Windows"
}
$cpuCores = if ($cpuStatic -and $cpuStatic.NumberOfCores) { [int]$cpuStatic.NumberOfCores } else { 0 }
$cpuLogical = if ($cpuStatic -and $cpuStatic.NumberOfLogicalProcessors) { [int]$cpuStatic.NumberOfLogicalProcessors } else { [Environment]::ProcessorCount }
$cpuMaxClock = if ($cpuStatic -and $cpuStatic.MaxClockSpeed) {
    [int]$cpuStatic.MaxClockSpeed
} elseif ($regCpu -and $regCpu.'~MHz') {
    [int]$regCpu.'~MHz'
} else {
    0
}

$script:PrevRxBytes = $null
$script:PrevTxBytes = $null
$script:PrevNetTime = $null
$script:BackupScanAt = $null
$script:BackupScanCache = $null

function Get-CpuUsagePercent {
    # 1. Método nativo via kernel32.dll (GetSystemTimes) - mais rápido e confiável no Windows 10
    try {
        if (([System.Management.Automation.PSTypeName]'InfraWatchCpuNative').Type) {
            $nativeCpu = [InfraWatchCpuNative]::GetCpuPercent()
            if ($nativeCpu -ge 0) {
                return [Math]::Min([double]100, [Math]::Max([double]0, [Math]::Round([double]$nativeCpu, 1)))
            }
        }
    } catch { }

    # 2. Fallback WMI/CIM caso Add-Type esteja restrito
    try {
        $procs = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
        $loads = @($procs | Where-Object { $null -ne $_.LoadPercentage } | ForEach-Object { [double]$_.LoadPercentage })
        if ($loads.Count -gt 0) {
            $avg = ($loads | Measure-Object -Average).Average
            return [Math]::Min([double]100, [Math]::Max([double]0, [Math]::Round([double]$avg, 1)))
        }
    } catch { }

    try {
        $perf = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop | Select-Object -First 1
        if ($null -ne $perf -and $null -ne $perf.PercentProcessorTime) {
            return [Math]::Min([double]100, [Math]::Max([double]0, [Math]::Round([double]$perf.PercentProcessorTime, 1)))
        }
    } catch { }

    return 0
}

function Get-MemoryMetrics {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop | Select-Object -First 1
        $totalBytes = [double]$os.TotalVisibleMemorySize * 1024.0
        $freeBytes = [double]$os.FreePhysicalMemory * 1024.0
        $usedBytes = [Math]::Max([double]0, $totalBytes - $freeBytes)
        $pct = if ($totalBytes -gt 0) { [Math]::Round(($usedBytes / $totalBytes) * 100.0, 1) } else { 0 }

        return @{
            totalBytes   = [long]$totalBytes
            usedBytes    = [long]$usedBytes
            freeBytes    = [long]$freeBytes
            usagePercent = $pct
        }
    } catch {
        try {
            Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
            $ci = New-Object Microsoft.VisualBasic.Devices.ComputerInfo
            $totalBytes = [double]$ci.TotalPhysicalMemory
            $freeBytes = [double]$ci.AvailablePhysicalMemory
            $usedBytes = [Math]::Max([double]0, $totalBytes - $freeBytes)
            $pct = if ($totalBytes -gt 0) { [Math]::Round(($usedBytes / $totalBytes) * 100.0, 1) } else { 0 }

            return @{
                totalBytes   = [long]$totalBytes
                usedBytes    = [long]$usedBytes
                freeBytes    = [long]$freeBytes
                usagePercent = $pct
            }
        } catch {
            return @{ totalBytes = 0; usedBytes = 0; freeBytes = 0; usagePercent = 0 }
        }
    }
}

function Get-DiskMetrics {
    $list = New-Object System.Collections.ArrayList
    try {
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop
        foreach ($d in $disks) {
            $size = if ($d.Size) { [double]$d.Size } else { [double]0 }
            $free = if ($d.FreeSpace) { [double]$d.FreeSpace } else { [double]0 }
            $used = [Math]::Max([double]0, $size - $free)
            $pct = if ($size -gt 0) { [Math]::Round(($used / $size) * 100.0, 1) } else { 0 }

            [void]$list.Add(@{
                drive        = $d.DeviceID
                label        = if ($d.VolumeName) { $d.VolumeName } else { "Disco Local" }
                fileSystem   = if ($d.FileSystem) { $d.FileSystem } else { "NTFS" }
                totalBytes   = [long]$size
                usedBytes    = [long]$used
                freeBytes    = [long]$free
                usagePercent = $pct
            })
        }
    } catch {
        try {
            foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
                if ($d.DriveType -ne [System.IO.DriveType]::Fixed -or -not $d.IsReady) { continue }
                $size = [double]$d.TotalSize
                $free = [double]$d.AvailableFreeSpace
                $used = [Math]::Max([double]0, $size - $free)
                $pct = if ($size -gt 0) { [Math]::Round(($used / $size) * 100.0, 1) } else { 0 }

                [void]$list.Add(@{
                    drive        = $d.Name.TrimEnd('\')
                    label        = if ($d.VolumeLabel) { $d.VolumeLabel } else { "Disco Local" }
                    fileSystem   = if ($d.DriveFormat) { $d.DriveFormat } else { "NTFS" }
                    totalBytes   = [long]$size
                    usedBytes    = [long]$used
                    freeBytes    = [long]$free
                    usagePercent = $pct
                })
            }
        } catch { }
    }
    return ,$list.ToArray()
}

function Get-NetworkMetrics {
    $adaptersList = New-Object System.Collections.ArrayList
    $primaryIp = ""
    $primaryGateway = ""
    $bestScore = -1

    try {
        $netConfigs = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction Stop
        $netAdapters = @{}
        Get-CimInstance -ClassName Win32_NetworkAdapter -ErrorAction SilentlyContinue | ForEach-Object {
            $netAdapters[$_.Index] = $_
        }

        foreach ($cfg in $netConfigs) {
            $ipv4 = ($cfg.IPAddress | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' -and $_ -notlike '169.254.*' } | Select-Object -First 1)
            if (-not $ipv4) { continue }

            $gw = if ($cfg.DefaultIPGateway) { ($cfg.DefaultIPGateway | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' } | Select-Object -First 1) } else { "" }
            $adapterObj = $netAdapters[$cfg.Index]
            $name = if ($adapterObj -and $adapterObj.NetConnectionID) { $adapterObj.NetConnectionID } else { $cfg.Description }
            $speedText = ""
            if ($adapterObj -and $adapterObj.Speed -and [double]$adapterObj.Speed -gt 0) {
                $spd = [double]$adapterObj.Speed
                if ($spd -ge 1000000000) {
                    $speedText = "$([Math]::Round($spd / 1000000000, 1)) Gbps"
                } else {
                    $speedText = "$([Math]::Round($spd / 1000000, 0)) Mbps"
                }
            }

            $score = 0
            if ($gw) { $score += 100 }
            if ($ipv4 -match '^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)') { $score += 50 }
            if ("$name $($cfg.Description)" -notmatch 'Radmin|VPN|Virtual|Hyper-V|VMware|VirtualBox|Loopback|Hamachi|Tailscale|ZeroTier') { $score += 30 }

            if ($score -gt $bestScore) {
                $bestScore = $score
                $primaryIp = $ipv4
                $primaryGateway = $gw
            }

            [void]$adaptersList.Add(@{
                name        = $name
                description = $cfg.Description
                ip          = $ipv4
                gateway     = if ($gw) { $gw } else { "-" }
                linkSpeed   = if ($speedText) { $speedText } else { "-" }
                status      = "Up"
                mac         = if ($cfg.MACAddress) { $cfg.MACAddress } else { "-" }
            })
        }
    } catch { }

    $totalRx = [double]0
    $totalTx = [double]0
    try {
        $stats = Get-NetAdapterStatistics -ErrorAction Stop
        foreach ($s in $stats) {
            $totalRx += [double]$s.ReceivedBytes
            $totalTx += [double]$s.SentBytes
        }
    } catch {
        try {
            $rawIf = Get-CimInstance -ClassName Win32_PerfRawData_Tcpip_NetworkInterface -ErrorAction Stop
            foreach ($r in $rawIf) {
                $totalRx += [double]$r.BytesReceivedPersec
                $totalTx += [double]$r.BytesSentPersec
            }
        } catch { }
    }

    $now = Get-Date
    $downloadBps = [double]0
    $uploadBps = [double]0

    if ($null -ne $script:PrevNetTime -and $null -ne $script:PrevRxBytes) {
        $elapsed = ($now - $script:PrevNetTime).TotalSeconds
        if ($elapsed -gt 0.2) {
            $rxDelta = $totalRx - $script:PrevRxBytes
            $txDelta = $totalTx - $script:PrevTxBytes
            if ($rxDelta -ge 0) { $downloadBps = [Math]::Round($rxDelta / $elapsed, 1) }
            if ($txDelta -ge 0) { $uploadBps = [Math]::Round($txDelta / $elapsed, 1) }
        }
    }

    $script:PrevRxBytes = $totalRx
    $script:PrevTxBytes = $totalTx
    $script:PrevNetTime = $now

    return @{
        primaryIp      = $primaryIp
        primaryGateway = $primaryGateway
        downloadBps    = $downloadBps
        uploadBps      = $uploadBps
        totalRxBytes   = [long]$totalRx
        totalTxBytes   = [long]$totalTx
        adapters       = @($adaptersList.ToArray())
    }
}

function Get-ShareMetrics {
    $list = New-Object System.Collections.ArrayList
    $usedSmbCmdlet = $false

    try {
        $shares = Get-SmbShare -ErrorAction Stop
        $usedSmbCmdlet = $true
        foreach ($s in $shares) {
            $isSys = ($s.Special -eq $true) -or ($s.Name -like '*$')
            [void]$list.Add(@{
                name         = $s.Name
                path         = if ($s.Path) { $s.Path } else { "-" }
                description  = if ($s.Description) { $s.Description } else { "" }
                isSystem     = [bool]$isSys
                currentUsers = if ($null -ne $s.CurrentUsers) { [int]$s.CurrentUsers } else { 0 }
            })
        }
    } catch { }

    if (-not $usedSmbCmdlet) {
        try {
            $wmiShares = Get-CimInstance -ClassName Win32_Share -ErrorAction Stop
            foreach ($s in $wmiShares) {
                $isSys = ($s.Name -like '*$') -or ($s.Type -ge 2147483648)
                [void]$list.Add(@{
                    name         = $s.Name
                    path         = if ($s.Path) { $s.Path } else { "-" }
                    description  = if ($s.Description) { $s.Description } else { "" }
                    isSystem     = [bool]$isSys
                    currentUsers = 0
                })
            }
        } catch { }
    }

    return ,$list.ToArray()
}

function Get-UserMetrics {
    $accountsList = New-Object System.Collections.ArrayList
    $activeList = New-Object System.Collections.ArrayList
    $smbList = New-Object System.Collections.ArrayList
    $activeUserNames = @{}

    # 1. Sessões interativas / RDP via API nativa Win32 (wtsapi32.dll - funciona em qualquer idioma/Windows 10)
    try {
        if (([System.Management.Automation.PSTypeName]'InfraWatchSessionNative').Type) {
            $wtsSessions = [InfraWatchSessionNative]::GetSessions()
            foreach ($s in $wtsSessions) {
                $uName = [string]$s["username"]
                if (-not $uName) { continue }
                if ([bool]$s["isActive"]) {
                    $activeUserNames[$uName.ToLowerInvariant()] = $true
                }
                [void]$activeList.Add(@{
                    username    = $uName
                    sessionName = [string]$s["sessionName"]
                    state       = [string]$s["state"]
                    isActive    = [bool]$s["isActive"]
                    idleTime    = [string]$s["idleTime"]
                    logonTime   = [string]$s["logonTime"]
                    source      = [string]$s["source"]
                })
            }
        }
    } catch { }

    # Fallback 1: Processos explorer.exe (cada usuário logado no desktop possui seu próprio explorer.exe)
    if ($activeList.Count -eq 0) {
        try {
            $seenOwners = @{}
            $explorers = Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop
            foreach ($exp in $explorers) {
                $owner = Invoke-CimMethod -InputObject $exp -MethodName GetOwner -ErrorAction SilentlyContinue
                if ($owner -and $owner.User) {
                    $uKey = $owner.User.ToLowerInvariant()
                    if (-not $seenOwners.ContainsKey($uKey)) {
                        $seenOwners[$uKey] = $true
                        $activeUserNames[$uKey] = $true
                        [void]$activeList.Add(@{
                            username    = $owner.User
                            sessionName = "sessao-$($exp.SessionId)"
                            state       = "Ativo"
                            isActive    = $true
                            idleTime    = "-"
                            logonTime   = if ($exp.CreationDate) { $exp.CreationDate.ToString("dd/MM/yyyy HH:mm") } else { "Ativo" }
                            source      = "Desktop"
                        })
                    }
                }
            }
        } catch { }
    }

    # Fallback 2: quser (com suporte a PT-BR e EN-US)
    if ($activeList.Count -eq 0) {
        try {
            $quserOutput = & quser 2>$null
            if ($quserOutput) {
                $lines = $quserOutput | Select-Object -Skip 1
                foreach ($line in $lines) {
                    $trimmed = $line.Trim()
                    if (-not $trimmed) { continue }
                    if ($trimmed -match '^>?(\S+)\s+(?:(\S+)\s+)?(\d+)\s+(\S+)\s+(\S+)\s+(.+)$') {
                        $uName = $Matches[1]
                        $sessName = if ($Matches[2]) { $Matches[2] } else { "desconectada" }
                        $rawState = $Matches[4]
                        $idle = $Matches[5]
                        $logon = $Matches[6].Trim()

                        $isActiveState = ($rawState -match '^(Ativ|Active)')
                        $friendlyState = if ($isActiveState) { "Ativo" } elseif ($rawState -match '^(Desc|Disc)') { "Desconectado" } else { $rawState }

                        if ($isActiveState) {
                            $activeUserNames[$uName.ToLowerInvariant()] = $true
                        }

                        [void]$activeList.Add(@{
                            username    = $uName
                            sessionName = $sessName
                            state       = $friendlyState
                            isActive    = $isActiveState
                            idleTime    = $idle
                            logonTime   = $logon
                            source      = if ($sessName -like "rdp*") { "RDP" } else { "Console" }
                        })
                    }
                }
            }
        } catch { }
    }

    # Fallback 3: Win32_ComputerSystem.UserName
    if ($activeList.Count -eq 0) {
        try {
            $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop | Select-Object -First 1
            if ($cs -and $cs.UserName) {
                $shortName = ($cs.UserName -split '\\')[-1]
                $activeUserNames[$shortName.ToLowerInvariant()] = $true
                [void]$activeList.Add(@{
                    username    = $shortName
                    sessionName = "console"
                    state       = "Ativo"
                    isActive    = $true
                    idleTime    = "-"
                    logonTime   = "Sessão atual"
                    source      = "Console"
                })
            }
        } catch { }
    }

    # 2. Sessões de rede SMB (usuários acessando pastas compartilhadas pela rede)
    $gotSmb = $false
    try {
        $smbSessions = Get-SmbSession -ErrorAction Stop
        $gotSmb = $true
        foreach ($sess in $smbSessions) {
            $uRaw = if ($sess.ClientUserName) { $sess.ClientUserName } else { "Convidado" }
            $shortU = ($uRaw -split '\\')[-1]
            if ($shortU) { $activeUserNames[$shortU.ToLowerInvariant()] = $true }

            [void]$smbList.Add(@{
                username         = $uRaw
                clientIp         = if ($sess.ClientComputerName) { $sess.ClientComputerName } else { "-" }
                numOpens         = if ($null -ne $sess.NumOpens) { [int]$sess.NumOpens } else { 0 }
                secondsConnected = if ($null -ne $sess.SecondsExists) { [int]$sess.SecondsExists } else { 0 }
            })
        }
    } catch { }

    if (-not $gotSmb) {
        try {
            $netSess = & net session 2>$null
            foreach ($line in $netSess) {
                if ($line -match '^\\\\(\S+)\s+(\S+)\s+.*?\s+(\d+)\s+\d+:\d+:\d+') {
                    $cIp = $Matches[1]
                    $cUser = $Matches[2]
                    $cOpens = [int]$Matches[3]
                    $activeUserNames[$cUser.ToLowerInvariant()] = $true
                    [void]$smbList.Add(@{
                        username         = $cUser
                        clientIp         = $cIp
                        numOpens         = $cOpens
                        secondsConnected = 0
                    })
                }
            }
        } catch { }
    }

    # 3. Contas locais cadastradas no Windows
    $usedLocalUser = $false
    try {
        $localUsers = Get-LocalUser -ErrorAction Stop
        $usedLocalUser = $true
        foreach ($u in $localUsers) {
            $isNowActive = $activeUserNames.ContainsKey($u.Name.ToLowerInvariant())
            [void]$accountsList.Add(@{
                name        = $u.Name
                fullName    = if ($u.FullName) { $u.FullName } else { "" }
                description = if ($u.Description) { $u.Description } else { "" }
                enabled     = [bool]$u.Enabled
                lastLogon   = if ($u.LastLogon) { $u.LastLogon.ToString("o") } else { $null }
                isActive    = [bool]$isNowActive
            })
        }
    } catch { }

    if (-not $usedLocalUser) {
        try {
            $wmiUsers = Get-CimInstance -ClassName Win32_UserAccount -Filter "LocalAccount=True" -ErrorAction Stop
            foreach ($u in $wmiUsers) {
                $isNowActive = $activeUserNames.ContainsKey($u.Name.ToLowerInvariant())
                [void]$accountsList.Add(@{
                    name        = $u.Name
                    fullName    = if ($u.FullName) { $u.FullName } else { "" }
                    description = if ($u.Description) { $u.Description } else { "" }
                    enabled     = (-not [bool]$u.Disabled)
                    lastLogon   = $null
                    isActive    = [bool]$isNowActive
                })
            }
        } catch { }
    }

    $enabledCount = (@($accountsList | Where-Object { $_.enabled -eq $true })).Count
    $activeInteractiveCount = (@($activeList | Where-Object { $_.isActive -eq $true })).Count

    return @{
        totalAccounts       = $accountsList.Count
        enabledAccounts     = [int]$enabledCount
        activeSessionsCount = [int]$activeInteractiveCount
        smbSessionsCount    = $smbList.Count
        accounts            = @($accountsList.ToArray())
        activeSessions      = @($activeList.ToArray())
        smbSessions         = @($smbList.ToArray())
    }
}

function Get-TopProcesses {
    $list = New-Object System.Collections.ArrayList
    try {
        $procs = Get-Process -ErrorAction SilentlyContinue |
            Sort-Object -Property WorkingSet64 -Descending |
            Select-Object -First 6
        foreach ($p in $procs) {
            [void]$list.Add(@{
                name        = $p.ProcessName
                pid         = [int]$p.Id
                memoryBytes = [long]$p.WorkingSet64
                cpuSeconds  = if ($null -ne $p.CPU) { [Math]::Round([double]$p.CPU, 1) } else { 0 }
            })
        }
    } catch { }
    return ,$list.ToArray()
}

function Get-CustomExtras {
    # Seção extensível: adicione novos módulos aqui no futuro (ex: temperatura, backup, banco de dados)
    # e a dashboard exibirá automaticamente!
    $extras = New-Object System.Collections.ArrayList

    # 1. Serviços monitorados do Windows
    if ($config.watchedServices) {
        foreach ($svcCfg in $config.watchedServices) {
            try {
                $svc = Get-Service -Name $svcCfg.name -ErrorAction Stop
                $running = ($svc.Status -eq "Running")
                [void]$extras.Add(@{
                    id     = "svc-$($svcCfg.name)"
                    title  = $svcCfg.label
                    value  = if ($running) { "Em execu$([char]0x00E7)$([char]0x00E3)o" } else { $svc.Status.ToString() }
                    status = if ($running) { "ok" } else { "warn" }
                    detail = "Servi$([char]0x00E7)o Windows: $($svcCfg.name)"
                })
            } catch {
                [void]$extras.Add(@{
                    id     = "svc-$($svcCfg.name)"
                    title  = $svcCfg.label
                    value  = "N$([char]0x00E3)o encontrado"
                    status = "neutral"
                    detail = "Servi$([char]0x00E7)o Windows: $($svcCfg.name)"
                })
            }
        }
    }

    # 2. Latência até o Gateway local
    if ($config.gatewayToPing) {
        try {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $reply = $ping.Send($config.gatewayToPing, 800)
            if ($reply.Status -eq "Success") {
                [void]$extras.Add(@{
                    id     = "ping-gateway"
                    title  = "Ping Gateway"
                    value  = "$($reply.RoundtripTime) ms"
                    status = if ($reply.RoundtripTime -lt 50) { "ok" } else { "warn" }
                    detail = "Destino: $($config.gatewayToPing)"
                })
            } else {
                [void]$extras.Add(@{
                    id     = "ping-gateway"
                    title  = "Ping Gateway"
                    value  = "Sem resposta"
                    status = "error"
                    detail = "Destino: $($config.gatewayToPing)"
                })
            }
        } catch { }
    }

    return ,$extras.ToArray()
}

function Read-LogHeadTail {
    param([string]$FilePath)
    try {
        $fi = New-Object System.IO.FileInfo($FilePath)
        if (-not $fi.Exists -or $fi.Length -eq 0) { return "" }

        $fs = [System.IO.File]::Open($FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $maxFull = 65536
            if ($fi.Length -le $maxFull) {
                $buf = New-Object byte[] $fi.Length
                $read = $fs.Read($buf, 0, $buf.Length)
                return [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
            }

            $headLen = 16384
            $tailLen = 16384
            $headBuf = New-Object byte[] $headLen
            $headRead = $fs.Read($headBuf, 0, $headLen)

            $fs.Seek(-$tailLen, [System.IO.SeekOrigin]::End) | Out-Null
            $tailBuf = New-Object byte[] $tailLen
            $tailRead = $fs.Read($tailBuf, 0, $tailLen)

            return ([System.Text.Encoding]::UTF8.GetString($headBuf, 0, $headRead) + "`n" + [System.Text.Encoding]::UTF8.GetString($tailBuf, 0, $tailRead))
        } finally {
            $fs.Dispose()
        }
    } catch {
        return ""
    }
}

function Parse-FreeFileSyncLog {
    param([System.IO.FileInfo]$File)

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
    $jobName = ($baseName -replace '\s+\d{4}-\d{2}-\d{2}[\s_]+\d{6}(?:\.\d+)?$', '').Trim()
    if (-not $jobName) { $jobName = $baseName }

    $raw = Read-LogHeadTail -FilePath $File.FullName
    $text = $raw
    if ($File.Extension -match 'html?') {
        $text = $text -replace '<style[\s\S]*?</style>', ' '
        $text = $text -replace '<script[\s\S]*?</script>', ' '
        $text = $text -replace '<[^>]+>', ' '
        try { $text = [System.Net.WebUtility]::HtmlDecode($text) } catch { }
    }
    $text = ($text -replace '\s+', ' ').Trim()

    $runStatus = "ok"
    $resultText = "Conclu$([char]0x00ED)do"

    if ($text -match '(?i)(Completed with errors|Conclu[i\u00ED]d[oa] com erros|Fatal Error|Erro fatal|Cannot find the following folders|N[a\u00E3]o [e\u00E9] poss[i\u00ED]vel encontrar)') {
        $runStatus = "error"
        $resultText = "Com erros"
    } elseif ($text -match '(?i)(Stopped|Interrompid[oa]|Cancelled|Cancelad[oa])') {
        $runStatus = "error"
        $resultText = "Interrompido"
    } elseif ($text -match '(?i)(Completed with warnings|Conclu[i\u00ED]d[oa] com avisos)') {
        $runStatus = "warn"
        $resultText = "Com avisos"
    } elseif ($text -match '(?i)(Nothing to synchronize|Nada para sincronizar)') {
        $runStatus = "ok"
        $resultText = "Sem altera$([char]0x00E7)$([char]0x00F5)es"
    } elseif ($text -match '(?i)(Completed successfully|Conclu[i\u00ED]d[oa] com [e\u00EA]xito|Synchronization completed|Sincroniza[c\u00E7][a\u00E3]o conclu[i\u00ED]da)') {
        $runStatus = "ok"
        $resultText = "Sucesso"
    }

    $parts = New-Object System.Collections.ArrayList
    if ($text -match '(?i)(?:Itens processados|Items processed)\s*:\s*([0-9\.,]+\s*(?:\([^)]+\))?)') {
        [void]$parts.Add("Itens: $($Matches[1].Trim())")
    }
    if ($text -match '(?i)(?:Tempo total|Total time)\s*:\s*([0-9:]+)') {
        [void]$parts.Add("Dura$([char]0x00E7)$([char]0x00E3)o: $($Matches[1].Trim())")
    }
    $summary = if ($parts.Count -gt 0) { ($parts.ToArray() -join " $([char]0x00B7) ") } else { "Log: $($File.Name)" }

    return @{
        timeUtc   = $File.LastWriteTimeUtc
        timeIso   = $File.LastWriteTimeUtc.ToString("o")
        name      = $jobName
        status    = $runStatus
        result    = $resultText
        summary   = $summary
        fileName  = $File.Name
        filePath  = $File.FullName
    }
}

function Get-BackupMetrics {
    $bCfg = $config.backup
    $label = if ($bCfg -and $bCfg.label) { [string]$bCfg.label } else { "FreeFileSync $([char]0x2192) OneDrive" }
    $warnHours = if ($bCfg -and $bCfg.warnAfterHours -and [double]$bCfg.warnAfterHours -gt 0) { [double]$bCfg.warnAfterHours } else { 24 }
    $critHours = if ($bCfg -and $bCfg.criticalAfterHours -and [double]$bCfg.criticalAfterHours -gt 0) { [double]$bCfg.criticalAfterHours } else { 48 }

    # Verificação instantânea de processos em execução (rápida, executada a cada ciclo)
    $syncRunning = $false
    $realTimeSyncRunning = $false
    $oneDriveRunning = $false
    try {
        $procs = Get-Process -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            if ($p.ProcessName -match '^FreeFileSync') { $syncRunning = $true }
            elseif ($p.ProcessName -match '^RealTimeSync') { $realTimeSyncRunning = $true }
            elseif ($p.ProcessName -match '^OneDrive') { $oneDriveRunning = $true }
        }
    } catch { }

    # Varredura de disco/logs/tarefas com cache de 30s para não sobrecarregar o servidor
    $nowUtc = (Get-Date).ToUniversalTime()
    $needScan = ($null -eq $script:BackupScanCache) -or ($null -eq $script:BackupScanAt) -or (($nowUtc - $script:BackupScanAt).TotalSeconds -ge 30)

    if ($needScan) {
        $logDirs = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
        $destDirs = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

        # 1. Caminhos configurados manualmente no config.json
        if ($bCfg -and $bCfg.logPaths) {
            foreach ($lp in $bCfg.logPaths) {
                if ($lp -and (Test-Path -LiteralPath $lp)) { [void]$logDirs.Add($lp) }
            }
        }
        if ($bCfg -and $bCfg.destinationPaths) {
            foreach ($dp in $bCfg.destinationPaths) {
                if ($dp -and (Test-Path -LiteralPath $dp)) { [void]$destDirs.Add($dp) }
            }
        }

        # 2. Descoberta automática das pastas padrão do FreeFileSync e OneDrive em todos os perfis de usuário
        $userProfiles = New-Object System.Collections.ArrayList
        try {
            Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Name -notin @("Public", "Default", "Default User", "All Users")) {
                    [void]$userProfiles.Add($_.FullName)
                }
            }
        } catch { }
        [void]$userProfiles.Add("C:\Windows\System32\config\systemprofile")

        $lastRunGuiBest = $null

        foreach ($prof in $userProfiles) {
            $ffsRoaming = Join-Path $prof "AppData\Roaming\FreeFileSync"
            $ffsLocal   = Join-Path $prof "AppData\Local\FreeFileSync"
            foreach ($candLog in @(
                (Join-Path $ffsRoaming "Logs"),
                (Join-Path $ffsLocal "Logs"),
                (Join-Path $prof "Documents\FreeFileSync\Logs")
            )) {
                if (Test-Path -LiteralPath $candLog) { [void]$logDirs.Add($candLog) }
            }

            # Lê pasta de log customizada em GlobalSettings.xml se existir
            $globalXml = Join-Path $ffsRoaming "GlobalSettings.xml"
            if (Test-Path -LiteralPath $globalXml) {
                try {
                    [xml]$gx = Get-Content -LiteralPath $globalXml -Raw -Encoding UTF8 -ErrorAction Stop
                    $logNodes = $gx.SelectNodes("//DefaultLogFolder | //LogFolder")
                    if ($logNodes) {
                        foreach ($ln in $logNodes) {
                            $customLog = ($ln.InnerText).Trim()
                            if ($customLog -and (Test-Path -LiteralPath $customLog)) {
                                [void]$logDirs.Add($customLog)
                            }
                        }
                    }
                } catch { }
            }

            # Verifica LastRun.ffs_gui (atualizado pelo FreeFileSync e contém pastas configuradas)
            $lastRunGui = Join-Path $ffsRoaming "LastRun.ffs_gui"
            if (Test-Path -LiteralPath $lastRunGui) {
                try {
                    $fiGui = Get-Item -LiteralPath $lastRunGui -ErrorAction Stop
                    if ($null -eq $lastRunGuiBest -or $fiGui.LastWriteTimeUtc -gt $lastRunGuiBest.LastWriteTimeUtc) {
                        $lastRunGuiBest = $fiGui
                    }
                    [xml]$lrgXml = Get-Content -LiteralPath $lastRunGui -Raw -Encoding UTF8 -ErrorAction Stop
                    $folderNodes = $lrgXml.SelectNodes("//Left | //Right")
                    if ($folderNodes) {
                        foreach ($fn in $folderNodes) {
                            $pVal = ($fn.InnerText).Trim()
                            if ($pVal -and ($pVal -match '(?i)OneDrive|Backup') -and (Test-Path -LiteralPath $pVal)) {
                                [void]$destDirs.Add($pVal)
                            }
                        }
                    }
                } catch { }
            }

            # Pastas OneDrive do perfil
            try {
                Get-ChildItem -Path $prof -Directory -Filter "OneDrive*" -ErrorAction SilentlyContinue | ForEach-Object {
                    [void]$destDirs.Add($_.FullName)
                }
            } catch { }
        }

        if (Test-Path -LiteralPath "C:\ProgramData\FreeFileSync\Logs") {
            [void]$logDirs.Add("C:\ProgramData\FreeFileSync\Logs")
        }

        # 3. Coleta os logs mais recentes do FreeFileSync (.html e .log)
        $logFiles = New-Object System.Collections.ArrayList
        foreach ($ld in $logDirs) {
            try {
                $found = Get-ChildItem -LiteralPath $ld -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Extension -match '^\.(html?|log)$' } |
                    Sort-Object -Property LastWriteTimeUtc -Descending |
                    Select-Object -First 8
                foreach ($f in $found) { [void]$logFiles.Add($f) }
            } catch { }
        }

        $topLogs = @($logFiles | Sort-Object -Property LastWriteTimeUtc -Descending | Select-Object -First 5)
        $parsedRuns = New-Object System.Collections.ArrayList
        foreach ($lf in $topLogs) {
            [void]$parsedRuns.Add((Parse-FreeFileSyncLog -File $lf))
        }

        # 4. Procura sync.ffs_db nas pastas OneDrive / destino (atualizado exatamente ao concluir uma sincronização)
        $bestFfsDb = $null
        $detectedDestPath = ""
        foreach ($dd in $destDirs) {
            if (-not $detectedDestPath) { $detectedDestPath = $dd }
            try {
                $dbs = Get-ChildItem -LiteralPath $dd -Filter "sync.ffs_db" -File -Force -Recurse -Depth 2 -ErrorAction SilentlyContinue
                foreach ($db in $dbs) {
                    if ($null -eq $bestFfsDb -or $db.LastWriteTimeUtc -gt $bestFfsDb.LastWriteTimeUtc) {
                        $bestFfsDb = $db
                        $detectedDestPath = $db.DirectoryName
                    }
                }
            } catch { }
        }

        # Se o usuário configurou destinationPaths explicitamente e não há sync.ffs_db, olha o arquivo mais recente
        $bestDestFile = $null
        if ($null -eq $bestFfsDb -and $bCfg -and $bCfg.destinationPaths) {
            foreach ($dp in $bCfg.destinationPaths) {
                if (-not $dp -or -not (Test-Path -LiteralPath $dp)) { continue }
                try {
                    $newest = Get-ChildItem -LiteralPath $dp -File -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                        Sort-Object -Property LastWriteTimeUtc -Descending |
                        Select-Object -First 1
                    if ($newest -and ($null -eq $bestDestFile -or $newest.LastWriteTimeUtc -gt $bestDestFile.LastWriteTimeUtc)) {
                        $bestDestFile = $newest
                        $detectedDestPath = $dp
                    }
                } catch { }
            }
        }

        # 5. Verifica Tarefas Agendadas do Windows relacionadas a FreeFileSync / Backup / OneDrive
        $bestTask = $null
        $nextScheduledIso = $null
        $taskKeywords = if ($bCfg -and $bCfg.taskNameContains -and $bCfg.taskNameContains.Count -gt 0) {
            @($bCfg.taskNameContains)
        } else {
            @("FreeFileSync", "FileSync", "RealTimeSync", "Backup", "OneDrive")
        }
        $kwRegex = ($taskKeywords | ForEach-Object { [regex]::Escape([string]$_) }) -join "|"

        try {
            $tasks = Get-ScheduledTask -ErrorAction Stop | Where-Object {
                $_.TaskPath -notlike "\Microsoft\Windows\*" -and $_.TaskName -notlike "InfraWatch*"
            }
            foreach ($t in $tasks) {
                $actText = ""
                try {
                    $actText = (($t.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join " ")
                } catch { }

                $matchesTask = ($t.TaskName -match $kwRegex) -or ($actText -match '(?i)FreeFileSync|RealTimeSync|\.ffs_batch')
                if (-not $matchesTask) { continue }

                try {
                    $info = Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Stop
                    if ($info.NextRunTime -and $info.NextRunTime.Year -gt 2000) {
                        $nIso = $info.NextRunTime.ToUniversalTime().ToString("o")
                        if (-not $nextScheduledIso) { $nextScheduledIso = $nIso }
                    }
                    if ($info.LastRunTime -and $info.LastRunTime.Year -gt 2000) {
                        $lrUtc = $info.LastRunTime.ToUniversalTime()
                        if ($null -eq $bestTask -or $lrUtc -gt $bestTask.timeUtc) {
                            $okCode = ($info.LastTaskResult -eq 0 -or $info.LastTaskResult -eq 1 -or $info.LastTaskResult -eq 267009)
                            $bestTask = @{
                                timeUtc = $lrUtc
                                timeIso = $lrUtc.ToString("o")
                                name    = $t.TaskName
                                status  = if ($okCode) { "ok" } else { "error" }
                                result  = if ($info.LastTaskResult -eq 0) { "Sucesso" } elseif ($info.LastTaskResult -eq 1) { "Com avisos (c$([char]0x00F3)digo 1)" } else { "C$([char]0x00F3)digo $($info.LastTaskResult)" }
                                detail  = "Tarefa agendada: $($t.TaskName)"
                            }
                        }
                    }
                } catch { }
            }
        } catch { }

        # 6. Seleciona a fonte mais recente e rica
        $chosenTimeUtc = $null
        $chosenRunStatus = "unknown"
        $chosenResult = "N$([char]0x00E3)o encontrado"
        $chosenSource = "N$([char]0x00E3)o detectado"
        $chosenJobName = ""
        $chosenDetail = ""
        $chosenLogFile = ""

        if ($parsedRuns.Count -gt 0) {
            $latestLog = $parsedRuns[0]
            $chosenTimeUtc = $latestLog.timeUtc
            $chosenRunStatus = $latestLog.status
            $chosenResult = $latestLog.result
            $chosenSource = "Logs do FreeFileSync"
            $chosenJobName = $latestLog.name
            $chosenDetail = $latestLog.summary
            $chosenLogFile = $latestLog.fileName
        }

        if ($null -ne $bestFfsDb -and ($null -eq $chosenTimeUtc -or $bestFfsDb.LastWriteTimeUtc -gt $chosenTimeUtc.AddMinutes(2))) {
            $chosenTimeUtc = $bestFfsDb.LastWriteTimeUtc
            $chosenRunStatus = "ok"
            $chosenResult = "Sincronizado"
            $chosenSource = "Banco FreeFileSync (sync.ffs_db)"
            $chosenJobName = Split-Path -Leaf $bestFfsDb.DirectoryName
            $chosenDetail = "Arquivo sync.ffs_db atualizado no destino OneDrive"
        }

        if ($null -ne $bestTask -and ($null -eq $chosenTimeUtc -or $bestTask.timeUtc -gt $chosenTimeUtc.AddMinutes(2))) {
            $chosenTimeUtc = $bestTask.timeUtc
            $chosenRunStatus = $bestTask.status
            $chosenResult = $bestTask.result
            $chosenSource = "Tarefa Agendada (Windows)"
            $chosenJobName = $bestTask.name
            $chosenDetail = $bestTask.detail
        }

        if ($null -eq $chosenTimeUtc -and $null -ne $lastRunGuiBest) {
            $chosenTimeUtc = $lastRunGuiBest.LastWriteTimeUtc
            $chosenRunStatus = "ok"
            $chosenResult = "Executado (GUI)"
            $chosenSource = "FreeFileSync (LastRun.ffs_gui)"
            $chosenJobName = "FreeFileSync"
            $chosenDetail = "$([char]0x00DA)ltima execu$([char]0x00E7)$([char]0x00E3)o registrada pelo aplicativo FreeFileSync"
        }

        if ($null -eq $chosenTimeUtc -and $null -ne $bestDestFile) {
            $chosenTimeUtc = $bestDestFile.LastWriteTimeUtc
            $chosenRunStatus = "ok"
            $chosenResult = "Arquivo atualizado"
            $chosenSource = "Pasta de destino configurada"
            $chosenJobName = $bestDestFile.Name
            $chosenDetail = "$([char]0x00DA)ltimo arquivo alterado em $detectedDestPath"
        }

        $recentList = New-Object System.Collections.ArrayList
        foreach ($pr in $parsedRuns) {
            [void]$recentList.Add(@{
                time    = $pr.timeIso
                name    = $pr.name
                status  = $pr.status
                result  = $pr.result
                summary = $pr.summary
            })
        }

        $script:BackupScanCache = @{
            timeUtc         = $chosenTimeUtc
            runStatus       = $chosenRunStatus
            result          = $chosenResult
            source          = $chosenSource
            jobName         = $chosenJobName
            detail          = $chosenDetail
            logFile         = $chosenLogFile
            destinationPath = $detectedDestPath
            nextScheduledAt = $nextScheduledIso
            recentRuns      = @($recentList.ToArray())
        }
        $script:BackupScanAt = $nowUtc
    }

    $cached = $script:BackupScanCache
    $lastBackupIso = $null
    $ageSec = $null
    $finalStatus = "unknown"
    $statusLabel = "N$([char]0x00E3)o detectado"

    if ($null -ne $cached.timeUtc) {
        $lastBackupIso = $cached.timeUtc.ToString("o")
        $ageSec = [long][Math]::Max([double]0, ($nowUtc - $cached.timeUtc).TotalSeconds)
        $ageHours = $ageSec / 3600.0

        if ($cached.runStatus -eq "error") {
            $finalStatus = "error"
            $statusLabel = "Falha no $([char]0x00FA)ltimo backup"
        } elseif ($ageHours -ge $critHours) {
            $finalStatus = "error"
            $statusLabel = "Atrasado (>$([int]$critHours)h)"
        } elseif ($ageHours -ge $warnHours) {
            $finalStatus = "warn"
            $statusLabel = "Aten$([char]0x00E7)$([char]0x00E3)o (>$([int]$warnHours)h)"
        } elseif ($cached.runStatus -eq "warn") {
            $finalStatus = "warn"
            $statusLabel = "Conclu$([char]0x00ED)do com avisos"
        } else {
            $finalStatus = "ok"
            $statusLabel = "Em dia"
        }
    }

    if ($syncRunning) {
        $finalStatus = "running"
        $statusLabel = "Sincronizando agora"
    }

    return @{
        label               = $label
        status              = $finalStatus
        statusLabel         = $statusLabel
        lastBackupAt        = $lastBackupIso
        ageSeconds          = $ageSec
        result              = $cached.result
        source              = $cached.source
        jobName             = $cached.jobName
        detail              = $cached.detail
        logFile             = $cached.logFile
        destinationPath     = $cached.destinationPath
        nextScheduledAt     = $cached.nextScheduledAt
        oneDriveRunning     = [bool]$oneDriveRunning
        syncRunning         = [bool]$syncRunning
        realTimeSyncRunning = [bool]$realTimeSyncRunning
        warnAfterHours      = [int]$warnHours
        criticalAfterHours  = [int]$critHours
        recentRuns          = $cached.recentRuns
    }
}

function Collect-Payload {
    $net = Get-NetworkMetrics
    $uptimeSec = 0
    $lastBootIso = $null
    if ($osStatic -and $osStatic.LastBootUpTime) {
        $lastBootIso = $osStatic.LastBootUpTime.ToString("o")
        $uptimeSec = [long][Math]::Max([double]0, ((Get-Date) - $osStatic.LastBootUpTime).TotalSeconds)
    }

    return @{
        serverId     = if ($config.serverId) { $config.serverId } else { $hostname.ToLowerInvariant() }
        hostname     = $hostname
        label        = if ($config.serverLabel) { $config.serverLabel } else { "Servidor $hostname" }
        ip           = if ($net.primaryIp) { $net.primaryIp } else { "-" }
        gateway      = if ($net.primaryGateway) { $net.primaryGateway } else { "-" }
        timestamp    = (Get-Date).ToUniversalTime().ToString("o")
        os           = @{
            caption       = if ($osStatic) { $osStatic.Caption } else { "Windows" }
            version       = if ($osStatic) { $osStatic.Version } else { "-" }
            architecture  = if ($osStatic) { $osStatic.OSArchitecture } else { "64-bit" }
            lastBoot      = $lastBootIso
            uptimeSeconds = $uptimeSec
        }
        cpu          = @{
            name              = $cpuName
            usagePercent      = Get-CpuUsagePercent
            cores             = $cpuCores
            logicalProcessors = $cpuLogical
            clockMhz          = $cpuMaxClock
        }
        memory       = Get-MemoryMetrics
        disks        = Get-DiskMetrics
        network      = @{
            downloadBps  = $net.downloadBps
            uploadBps    = $net.uploadBps
            totalRxBytes = $net.totalRxBytes
            totalTxBytes = $net.totalTxBytes
            adapters     = $net.adapters
        }
        shares       = Get-ShareMetrics
        users        = Get-UserMetrics
        topProcesses = Get-TopProcesses
        extras       = Get-CustomExtras
        backup       = Get-BackupMetrics
    }
}

if (-not $DryRun) {
    Write-Host ""
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "  InfraWatch - Agente de Coleta Windows" -ForegroundColor White
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "  Host coletado : $hostname" -ForegroundColor Green
    Write-Host "  Destino API   : $endpointUrl" -ForegroundColor Yellow
    Write-Host "  Intervalo     : a cada $intervalSeconds segundos" -ForegroundColor Gray
    Write-Host "--------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "  Pressione Ctrl+C para encerrar o agente." -ForegroundColor Gray
    Write-Host ""
}

while ($true) {
    $startTick = Get-Date
    try {
        $payload = Collect-Payload
        $json = $payload | ConvertTo-Json -Depth 6 -Compress

        if ($DryRun) {
            Write-Output $json
            break
        }

        $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

        $headers = @{
            "x-api-key" = $apiKey
        }

        $resp = Invoke-RestMethod -Uri $endpointUrl -Method Post -Headers $headers -Body $utf8Bytes -ContentType "application/json; charset=utf-8" -TimeoutSec 8
        Write-Host ("[{0}] Enviado OK | Host: {1} ({2}) | CPU: {3}% | RAM: {4}% | Shares: {5} | Ativos: {6}" -f `
            (Get-Date -Format "HH:mm:ss"),
            $payload.hostname,
            $payload.ip,
            $payload.cpu.usagePercent,
            $payload.memory.usagePercent,
            $payload.shares.Count,
            ($payload.users.activeSessionsCount + $payload.users.smbSessionsCount)) -ForegroundColor Green
    } catch {
        Write-Host ("[{0}] Falha ao enviar para {1}: {2}" -f (Get-Date -Format "HH:mm:ss"), $endpointUrl, $_.Exception.Message) -ForegroundColor Red
    }

    if ($RunOnce) { break }

    $spent = ((Get-Date) - $startTick).TotalMilliseconds
    $sleepMs = [Math]::Max(500, ($intervalSeconds * 1000) - [int]$spent)
    Start-Sleep -Milliseconds $sleepMs
}
