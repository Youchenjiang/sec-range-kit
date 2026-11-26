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
#   -Revert : reload Sysmon from -BaselineConfig and stop.
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

function Invoke-SysmonConfig([string]$Config) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $rc = & $SysmonExe -c $Config 2>&1 | Out-String
    $sw.Stop()
    L ('  Sysmon64 -c exit=' + $LASTEXITCODE + ' elapsed=' + [math]::Round($sw.Elapsed.TotalSeconds, 1) + 's config=' + $Config)
    foreach ($line in ($rc -split "`n")) { if ($line.Trim()) { L ('  | ' + $line.Trim()) } }
    foreach ($s in (Get-Service -Name 'Sysmon*' -ErrorAction SilentlyContinue)) { L ('  service ' + $s.Name + ' = ' + $s.Status) }
}

$t0 = Get-Date
L '=== ProcessAccess (EID 10) check ==='
L ('local ' + $t0.ToString('yyyy-MM-dd HH:mm:ss K') + ' | utc ' + $t0.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') + 'Z')

if ($Revert) {
    L ''
    L '--- revert: reload the baseline config ---'
    Invoke-SysmonConfig $BaselineConfig
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
Invoke-SysmonConfig $patchedPath
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
L '--- 4. Sysmon EID 10 events since the reload ---'
$ev10 = @()
try {
    $ev10 = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Sysmon/Operational'; Id = 10; StartTime = $t0.AddMinutes(-1) } -ErrorAction Stop
} catch { L ('  query: ' + $_.Exception.Message) }
L ('  EID 10 events: ' + @($ev10).Count)
$lines = @(
    'Sysmon EID 10 (ProcessAccess) evidence'
    ('probe_utc   = ' + $mark.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss.fff') + 'Z')
    ('probe       = ' + $detail)
    ('config      = ' + $patchedPath + ' (include rules = ' + $ruleCount + ')')
    ('count       = ' + @($ev10).Count)
    ''
)
foreach ($e in $ev10) {
    $xml = [xml]$e.ToXml()
    $lines += '-----------------------------------------------------------'
    $lines += 'TimeCreated(utc) = ' + $e.TimeCreated.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss.fff') + 'Z'
    foreach ($d in $xml.Event.EventData.Data) { $lines += ('  ' + $d.Name.PadRight(22) + ' = ' + $d.'#text') }
}
[IO.File]::WriteAllLines((Join-Path $OutDir 'eid10.txt'), $lines, $utf8)

L ''
L ('DONE process_access_check events=' + @($ev10).Count + ' (revert with -Revert)')
Write-Host ('DONE process_access_check events=' + @($ev10).Count + ' -> ' + $log)
