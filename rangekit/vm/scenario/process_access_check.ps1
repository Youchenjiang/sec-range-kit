# process_access_check.ps1 - prove whether Sysmon EID 10 (ProcessAccess) sees a handle open.
#
# Many Sysmon configs ship a bare <ProcessAccess onmatch="include"></ProcessAccess>
# with ZERO rules. "include with no rules" logs NOTHING, so a grep for the tag name
# wrongly says EID 10 is on (audit_baseline.ps1 reports such sections as INERT).
#
# This script adds ONE rule scoped to -TargetImage (enabling ProcessAccess for every
# process is one of the noisiest things you can do to Sysmon), reloads Sysmon,
# opens handles to the target with each -Access mask (no memory is read, no dump is
# written) and saves the EID 10 events it produced. Run the same open in a scenario
# (kind process_open) before and after to show the blind spot closing.
#
# Only events whose source is this PowerShell process, whose target is -TargetImage
# and whose time is at or after the probe count as evidence; other EID 10 events in
# the window are reported as unrelated.
#
#   -Revert : reload Sysmon from -BaselineConfig and stop.
#
# Exit codes: 0 probe events found (or revert applied); 1 setup or Sysmon reload
# failed (a failed patch reload is followed by a baseline reload attempt);
# 3 the probe ran but Sysmon recorded none of its handle opens.
#
# ASCII ONLY.

[CmdletBinding()]
param(
    [string]$Process = 'lsass',
    [string]$TargetImage = 'C:\Windows\system32\lsass.exe',
    [int[]]$Access = @(0x1000, 0x1410),
    [string]$SysmonExe = '',
    [string]$ToolRoot = 'C:\Tools\DFIR',
    [string]$BaselineConfig = 'C:\Tools\DFIR\out\baseline\sysmonconfig.baseline.xml',
    [string]$OutDir = 'C:\Tools\DFIR\out\process_access',
    [switch]$Revert
)

$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$log = Join-Path $OutDir 'process_access_log.txt'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $utf8)
function L([string]$m) { [IO.File]::AppendAllText($log, $m + "`r`n", $utf8) }

if (-not $SysmonExe) {
    $found = Get-ChildItem $ToolRoot -Filter 'Sysmon64.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $SysmonExe = $found.FullName }
}
if (-not $SysmonExe -or -not (Test-Path $SysmonExe)) { L ('ERROR: Sysmon64.exe not found under ' + $ToolRoot); Write-Host 'ERROR Sysmon64.exe not found'; exit 1 }
if (-not (Test-Path $BaselineConfig)) { L ('ERROR: baseline config missing: ' + $BaselineConfig + ' (run audit_baseline.ps1 first)'); Write-Host 'ERROR baseline config missing'; exit 1 }

# Returns $true only when Sysmon accepted the configuration (exit code 0).
function Invoke-SysmonConfig([string]$Config) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $rc = & $SysmonExe -c $Config 2>&1 | Out-String
    $code = $LASTEXITCODE
    $sw.Stop()
    L ('  Sysmon64 -c exit=' + $code + ' elapsed=' + [math]::Round($sw.Elapsed.TotalSeconds, 1) + 's config=' + $Config)
    foreach ($line in ($rc -split "`n")) { if ($line.Trim()) { L ('  | ' + $line.Trim()) } }
    foreach ($s in (Get-Service -Name 'Sysmon*' -ErrorAction SilentlyContinue)) { L ('  service ' + $s.Name + ' = ' + $s.Status) }
    return ($code -eq 0)
}

function Stop-WithError([string]$Message) {
    L ('ERROR: ' + $Message)
    Write-Host ('ERROR ' + $Message + ' -> ' + $log)
    exit 1
}

$t0 = Get-Date
L '=== ProcessAccess (EID 10) check ==='
L ('local ' + $t0.ToString('yyyy-MM-dd HH:mm:ss K') + ' | utc ' + $t0.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') + 'Z')

if ($Revert) {
    L ''
    L '--- revert: reload the baseline config ---'
    if (-not (Invoke-SysmonConfig $BaselineConfig)) { Stop-WithError 'Sysmon rejected the baseline config; the patched config may still be active' }
    L 'DONE revert'
    Write-Host ('DONE revert -> ' + $log)
    exit 0
}

# ---- 1. patched config: exact string insert, no regex escaping traps ----
L ''
L '--- 1. add one ProcessAccess rule for the target ---'
$patchedPath = Join-Path $OutDir 'sysmonconfig.process_access.xml'
$raw = [IO.File]::ReadAllText($BaselineConfig)
$needle = '<ProcessAccess onmatch="include">'
$i = $raw.IndexOf($needle)
if ($i -lt 0) { L 'ERROR: <ProcessAccess onmatch="include"> block not found in the baseline config'; Write-Host 'ERROR block not found'; exit 1 }
$rule = '<TargetImage condition="is">' + [Security.SecurityElement]::Escape($TargetImage) + '</TargetImage>'
$insert = $needle + "`r`n`t`t`t" + $rule + ' <!--rangekit: EID 10 scoped to one target-->' + "`r`n`t`t"
$patched = $raw.Substring(0, $i) + $insert + $raw.Substring($i + $needle.Length)
[IO.File]::WriteAllText($patchedPath, $patched, $utf8)
$block = [regex]::Match($patched, '(?s)<ProcessAccess onmatch="include">(.*?)</ProcessAccess>')
$ruleCount = ([regex]::Matches($block.Groups[1].Value, '<TargetImage')).Count
L ('  include rule count now = ' + $ruleCount + '  (baseline bytes ' + $raw.Length + ', patched ' + $patched.Length + ')')

# ---- 2. reload Sysmon ----
L ''
L '--- 2. reload Sysmon with the patched config ---'
if (-not (Invoke-SysmonConfig $patchedPath)) {
    L '  patch rejected; reloading the baseline config so Sysmon is left in a known state'
    $restored = Invoke-SysmonConfig $BaselineConfig
    Stop-WithError ('Sysmon rejected the patched config; probe not run; baseline reload ' + $(if ($restored) { 'succeeded' } else { 'FAILED' }))
}
Start-Sleep -Seconds 2

# ---- 3. open handles to the target ----
L ''
L '--- 3. open handles to the target ---'
Add-Type -ErrorAction SilentlyContinue -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RangeKitAccess {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);
}
'@
$mark = Get-Date
$proc = Get-Process -Name $Process -ErrorAction SilentlyContinue | Select-Object -First 1
$detail = $Process + ' not running'
if ($proc) {
    $parts = @($Process + '_pid=' + $proc.Id)
    foreach ($mask in $Access) {
        $h = [RangeKitAccess]::OpenProcess([uint32]$mask, $false, $proc.Id)
        $ok = ($h -ne [IntPtr]::Zero)
        if ($ok) { [void][RangeKitAccess]::CloseHandle($h) }
        $parts += ('open_0x' + $mask.ToString('X4') + '=' + $ok)
        Start-Sleep -Milliseconds 400
    }
    $detail = $parts -join ' '
}
L ('  probe_utc   : ' + $mark.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss.fff') + 'Z')
L ('  probe_local : ' + $mark.ToString('yyyy-MM-dd HH:mm:ss.fff K'))
L ('  result      : ' + $detail)
Start-Sleep -Seconds 4

# ---- 4. EID 10 evidence ----
L ''
L '--- 4. Sysmon EID 10 events from this probe ---'
$window = @()
try {
    $window = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Sysmon/Operational'; Id = 10; StartTime = $mark.AddSeconds(-1) } -ErrorAction Stop)
} catch { L ('  query: ' + $_.Exception.Message) }
$probeEvents = @()
foreach ($e in $window) {
    $data = @{}
    foreach ($d in ([xml]$e.ToXml()).Event.EventData.Data) { $data[$d.Name] = [string]$d.'#text' }
    # this process opened the handles; the target must be the image the rule names
    if ($data['SourceProcessId'] -eq [string]$PID -and $data['TargetImage'] -eq $TargetImage) { $probeEvents += , @($e, $data) }
}
$unrelated = $window.Count - $probeEvents.Count
L ('  EID 10 since the probe: ' + $window.Count + ' (from this probe: ' + $probeEvents.Count + ', unrelated: ' + $unrelated + ')')
$lines = @(
    'Sysmon EID 10 (ProcessAccess) evidence for one probe'
    ('probe_utc   = ' + $mark.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss.fff') + 'Z')
    ('probe       = ' + $detail + ' source_pid=' + $PID)
    ('config      = ' + $patchedPath + ' (include rules = ' + $ruleCount + ')')
    ('matched     = ' + $probeEvents.Count + ' (source pid ' + $PID + ', target ' + $TargetImage + ')')
    ('unrelated   = ' + $unrelated + ' other EID 10 events in the same window, not listed')
    ''
)
foreach ($pair in $probeEvents) {
    $lines += '-----------------------------------------------------------'
    $lines += 'TimeCreated(utc) = ' + $pair[0].TimeCreated.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss.fff') + 'Z'
    foreach ($name in ($pair[1].Keys | Sort-Object)) { $lines += ('  ' + $name.PadRight(22) + ' = ' + $pair[1][$name]) }
}
[IO.File]::WriteAllLines((Join-Path $OutDir 'eid10.txt'), $lines, $utf8)

L ''
L ('DONE process_access_check matched=' + $probeEvents.Count + ' unrelated=' + $unrelated + ' (revert with -Revert)')
Write-Host ('DONE process_access_check matched=' + $probeEvents.Count + ' -> ' + $log)
if ($probeEvents.Count -eq 0) { exit 3 }
