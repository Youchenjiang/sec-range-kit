# telemetry_recon.ps1 - read-only survey of what the guest can actually log.
#
# Run it BEFORE designing a known-answer simulation: it shows the current
# identity, the Sysmon service and config (which event types are really enabled),
# the advanced audit policy, Defender state (check before an EICAR test), log
# sizes and time basis, the Sysmon EID mix over the lookback window, and the
# existing local accounts (so simulated accounts do not collide).
# Nothing is changed on the guest.
#
# ASCII ONLY: the guest console code page (for example CP950) corrupts other text
# once stdout is redirected to a file.

[CmdletBinding()]
param(
    [string]$ToolRoot = 'C:\Tools\DFIR',
    [string]$SysmonConfig = 'C:\Tools\DFIR\sysmonconfig.xml',
    [int]$LookbackHours = 24
)

$ErrorActionPreference = 'Continue'
function Show-Message([string]$m) { Write-Host $m }

Show-Message '=== 1. identity and token ==='
Show-Message ("whoami      : " + (whoami))
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
Show-Message ("IsAdmin     : " + $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
Show-Message ("Identity    : " + $id.Name)

Show-Message ''
Show-Message '=== 2. Sysmon service and config ==='
$svc = Get-Service -Name 'Sysmon*' -ErrorAction SilentlyContinue
if ($svc) {
    foreach ($s in $svc) { Show-Message ("service     : " + $s.Name + " = " + $s.Status) }
} else { Show-Message 'service     : NOT FOUND' }

$sysmonExe = Get-ChildItem $ToolRoot -Filter 'Sysmon64.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($sysmonExe) { Show-Message ("exe         : " + $sysmonExe.FullName) }

if (Test-Path $SysmonConfig) {
    $raw = Get-Content $SysmonConfig -Raw
    Show-Message ("cfg size    : " + $raw.Length + " bytes")
    # ProcessAccess is Sysmon EID 10; it is off unless the config enables it.
    $hasPA = $raw -match '<ProcessAccess'
    Show-Message ("cfg ProcessAccess(EID10) : " + $hasPA)
    if ($hasPA) {
        foreach ($x in [regex]::Matches($raw, '(?s)<ProcessAccess.*?</ProcessAccess>')) {
            Show-Message ('  PA-block len = ' + $x.Value.Length)
            foreach ($line in ($x.Value -split "`n")) {
                $t = $line.Trim()
                if ($t -match 'TargetImage|Include|onmatch|<ProcessAccess|</ProcessAccess') { Show-Message ('    ' + $t) }
            }
        }
    }
    foreach ($k in @('FileCreate', 'RegistryEvent', 'NetworkConnect', 'CreateRemoteThread', 'ImageLoad')) {
        Show-Message ("cfg has <$k> : " + ($raw -match ("<" + $k)))
    }
    # RegistryEvent onmatch direction matters: include logs only listed keys, exclude is the reverse.
    $re = [regex]::Match($raw, '(?s)<RegistryEvent.*?</RegistryEvent>')
    if ($re.Success) { Show-Message ('  RegEvt onmatch = ' + (([regex]::Match($re.Value, 'onmatch="(\w+)"')).Groups[1].Value)) }
} else { Show-Message "cfg         : NOT FOUND ($SysmonConfig)" }

Show-Message ''
Show-Message '=== 3. advanced audit policy (which Security EIDs get written) ==='
foreach ($line in (& auditpol.exe /get /category:* 2>&1)) { Show-Message $line }

Show-Message ''
Show-Message '=== 4. Windows Defender state ==='
try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    Show-Message ("RealTimeProtection : " + $mp.RealTimeProtectionEnabled)
    Show-Message ("AntivirusEnabled   : " + $mp.AntivirusEnabled)
    Show-Message ("BehaviorMonitor    : " + $mp.BehaviorMonitorEnabled)
    Show-Message ("TamperProtection   : " + $mp.IsTamperProtected)
} catch { Show-Message ("Get-MpComputerStatus failed: " + $_.Exception.Message) }
try {
    $pref = Get-MpPreference -ErrorAction Stop
    Show-Message ("ExclusionPath count: " + @($pref.ExclusionPath).Count)
    foreach ($p in @($pref.ExclusionPath)) { if ($p) { Show-Message ("  excl: " + $p) } }
    Show-Message ("DisableRealtimeMon : " + $pref.DisableRealtimeMonitoring)
} catch { Show-Message ("Get-MpPreference failed: " + $_.Exception.Message) }

Show-Message ''
Show-Message '=== 5. log sizes and time basis ==='
$now = Get-Date
Show-Message ("LocalNow  : " + $now.ToString('yyyy-MM-dd HH:mm:ss K'))
Show-Message ("UtcNow    : " + $now.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') + 'Z')
Show-Message ("TimeZone  : " + [TimeZoneInfo]::Local.Id + " (offset " + [TimeZoneInfo]::Local.BaseUtcOffset + ")")
foreach ($ln in @('Security', 'System', 'Application', 'Microsoft-Windows-Sysmon/Operational', 'Microsoft-Windows-PowerShell/Operational', 'Microsoft-Windows-TaskScheduler/Operational')) {
    try {
        $ev = Get-WinEvent -ListLog $ln -ErrorAction Stop
        Show-Message ("log : " + $ln.PadRight(46) + " count=" + $ev.RecordCount + " max=" + [math]::Round($ev.MaximumSizeInBytes / 1MB, 1) + "MB enabled=" + $ev.IsEnabled)
    } catch { Show-Message ("log : " + $ln.PadRight(46) + " (unavailable)") }
}

Show-Message ''
Show-Message ('=== 6. Sysmon EID mix over the last ' + $LookbackHours + 'h ===')
try {
    $events = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Sysmon/Operational'; StartTime = (Get-Date).AddHours(-$LookbackHours) } -ErrorAction Stop
    $events | Group-Object Id | Sort-Object { [int]$_.Name } | ForEach-Object {
        Show-Message ("EID " + $_.Name.PadRight(4) + " x " + $_.Count)
    }
} catch { Show-Message ('Sysmon log query failed: ' + $_.Exception.Message) }

Show-Message ''
Show-Message '=== 7. local accounts (avoid collisions with simulated ones) ==='
& net user 2>&1 | ForEach-Object { Show-Message $_ }

Show-Message ''
Show-Message 'DONE telemetry_recon'
