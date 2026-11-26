# audit_baseline.ps1 - turn on the Windows telemetry a known-answer exercise depends on.
#
# A stock Windows 10/11 install does NOT write several events DFIR exercises rely on:
#   - 4688 (process creation)      : "Process Creation" audit subcategory not configured
#   - 4698 (scheduled task created): "Other Object Access Events" not configured
#   - 4776 (NTLM credential check) : "Credential Validation" not configured
#   - 4104 (PS script block)       : ScriptBlockLogging policy absent
#   - TaskScheduler/Operational    : channel disabled
# This script enables them, enlarges the main logs, backs up the Sysmon config and
# reports which Sysmon sections are inert (include + 0 rules => nothing is logged).
#
# Revert the audit policy with:  auditpol /restore /file:<OutDir>\auditpol_backup.csv
#
# Usage (from the host, via the vmrun wrapper):
#   put  rangekit/vm/collect/audit_baseline.ps1  C:\Windows\Temp\audit_baseline.ps1
#   exec powershell -NoProfile -ExecutionPolicy Bypass -File C:\Windows\Temp\audit_baseline.ps1 -OutDir C:\Tools\DFIR\out\baseline
#
# ASCII ONLY. PowerShell 5.1 parses a BOM-less .ps1 in the ANSI code page (for
# example CP950), so non-ASCII literals would be corrupted.

[CmdletBinding()]
param(
    [string]$OutDir = 'C:\Tools\DFIR\out\baseline',
    [string]$SysmonConfig = 'C:\Tools\DFIR\sysmonconfig.xml',
    [int]$SecurityLogMB = 100,
    [int]$SystemLogMB = 64,
    [int]$SysmonLogMB = 128,
    [int]$PowerShellLogMB = 64
)

$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$log = Join-Path $OutDir 'baseline_log.txt'
$utf8 = New-Object System.Text.UTF8Encoding($false)
function L([string]$m) { [IO.File]::AppendAllText($log, $m + "`r`n", $utf8) }
[IO.File]::WriteAllText($log, '', $utf8)

L '=== audit baseline ==='
L ('local : ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss K'))
L ('utc   : ' + (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') + 'Z')
L ('tz    : ' + [TimeZoneInfo]::Local.Id)

# ---------- 1  audit policy: backup + raw CSV dump ----------
L ''
L '--- 1 audit policy snapshot ---'
$backup = Join-Path $OutDir 'auditpol_backup.csv'
& auditpol.exe /backup /file:$backup 2>&1 | ForEach-Object { L ('  ' + $_) }
L ('  auditpol /backup exit=' + $LASTEXITCODE)
if (Test-Path $backup) { L ('  snapshot file: auditpol_backup.csv (' + (Get-Item $backup).Length + ' bytes)') }
# /r gives CSV; subcategory names come out in the OS language but the
# Subcategory GUID column is always ASCII, so we key on GUIDs.
$csvBefore = & auditpol.exe /get /category:* /r 2>&1
[IO.File]::WriteAllLines((Join-Path $OutDir 'auditpol_before.csv'), $csvBefore, $utf8)
L ('  auditpol_before.csv lines=' + @($csvBefore).Count)

$guids = [ordered]@{
    'Process Creation'             = '{0CCE922B-69AE-11D9-BED3-505054503030}'
    'Other Object Access Events'   = '{0CCE9227-69AE-11D9-BED3-505054503030}'
    'Credential Validation'        = '{0CCE923F-69AE-11D9-BED3-505054503030}'
    'Logon'                        = '{0CCE9215-69AE-11D9-BED3-505054503030}'
    'Special Logon'                = '{0CCE921B-69AE-11D9-BED3-505054503030}'
    'User Account Management'      = '{0CCE9235-69AE-11D9-BED3-505054503030}'
    'Security System Extension'    = '{0CCE9211-69AE-11D9-BED3-505054503030}'
    'Audit Policy Change'          = '{0CCE922F-69AE-11D9-BED3-505054503030}'
}
L ''
L '--- 1b BEFORE: setting per GUID ---'
foreach ($k in $guids.Keys) {
    $hit = $csvBefore | Where-Object { $_ -like ('*' + $guids[$k] + '*') } | Select-Object -First 1
    L ('  ' + $k.PadRight(28) + ' => ' + $hit)
}

# ---------- 2  enable the three audit subcategories ----------
L ''
L '--- 2 enabling audit subcategories (by GUID, locale independent) ---'
$enable = @(
    @{ name = 'Process Creation';           why = 'Security 4688 -> process tree can be rebuilt from Security.evtx' },
    @{ name = 'Other Object Access Events'; why = 'Security 4698/4699 -> scheduled task object access' },
    @{ name = 'Credential Validation';      why = 'Security 4776 -> NTLM credential check, pairs with 4625' }
)
foreach ($e in $enable) {
    & auditpol.exe /set /subcategory:$($guids[$e.name]) /success:enable /failure:enable 2>&1 | Out-Null
    L ('  enabled ' + $e.name.PadRight(28) + ' exit=' + $LASTEXITCODE + '  (' + $e.why + ')')
}

# ---------- 3  4688 command line ----------
L ''
L '--- 3 4688 command line capture ---'
$auditKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit'
New-Item -Path $auditKey -Force | Out-Null
New-ItemProperty -Path $auditKey -Name 'ProcessCreationIncludeCmdLine_Enabled' -Value 1 -PropertyType DWord -Force | Out-Null
L ('  ProcessCreationIncludeCmdLine_Enabled = ' + (Get-ItemProperty -Path $auditKey -Name ProcessCreationIncludeCmdLine_Enabled).ProcessCreationIncludeCmdLine_Enabled)
L '  NOTE: without this, 4688 fires but CommandLine is a single dash.'

# ---------- 4  PowerShell script block logging ----------
L ''
L '--- 4 PowerShell script block logging (EID 4104) ---'
$psKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
New-Item -Path $psKey -Force | Out-Null
New-ItemProperty -Path $psKey -Name 'EnableScriptBlockLogging' -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $psKey -Name 'EnableScriptBlockInvocationLogging' -Value 1 -PropertyType DWord -Force | Out-Null
L ('  EnableScriptBlockLogging = ' + (Get-ItemProperty -Path $psKey -Name EnableScriptBlockLogging).EnableScriptBlockLogging)
L '  NOTE: 4104 is what recovers the plaintext of -EncodedCommand.'

# ---------- 5  log sizes + disabled channels ----------
L ''
L '--- 5 log sizes and channels ---'
$sizes = [ordered]@{
    'Security'                                  = $SecurityLogMB
    'System'                                    = $SystemLogMB
    'Microsoft-Windows-Sysmon/Operational'      = $SysmonLogMB
    'Microsoft-Windows-PowerShell/Operational'  = $PowerShellLogMB
}
foreach ($n in $sizes.Keys) {
    $bytes = [int64]$sizes[$n] * 1MB
    & wevtutil.exe sl $n /ms:$bytes 2>&1 | Out-Null
    $gl = (& wevtutil.exe gl $n 2>&1 | Select-String -Pattern 'maxSize' | Select-Object -First 1)
    L ('  ' + $n.PadRight(42) + ' ' + ("$gl".Trim()))
}
$tsChan = 'Microsoft-Windows-TaskScheduler/Operational'
& wevtutil.exe sl $tsChan /e:true 2>&1 | Out-Null
$tsState = (& wevtutil.exe gl $tsChan 2>&1 | Select-String -Pattern 'enabled:' | Select-Object -First 1)
L ('  enabled channel ' + $tsChan + ' -> ' + ("$tsState".Trim()))

# ---------- 6  sysmon config backup + effectiveness probe ----------
L ''
L '--- 6 sysmon config (tag present != rule present) ---'
if (Test-Path $SysmonConfig) {
    Copy-Item $SysmonConfig (Join-Path $OutDir 'sysmonconfig.baseline.xml') -Force
    L ('  baseline copy: sysmonconfig.baseline.xml (' + (Get-Item $SysmonConfig).Length + ' bytes)')
    $raw = Get-Content $SysmonConfig -Raw
    foreach ($sec in @('ProcessAccess', 'FileCreate', 'RegistryEvent', 'FileCreateStreamHash', 'DnsQuery', 'WmiEvent', 'CreateRemoteThread')) {
        $m = [regex]::Match($raw, '(?s)<' + $sec + ' ([^>]*?)>(.*?)</' + $sec + '>')
        if (-not $m.Success) { L ('  ' + $sec.PadRight(22) + ' : section missing'); continue }
        $attr = $m.Groups[1].Value.Trim()
        $rules = ([regex]::Matches($m.Groups[2].Value, '<(TargetImage|TargetObject|TargetFilename|Image|EventType|Query)\b')).Count
        $verdict = if ($attr -match 'include' -and $rules -eq 0) { 'INERT (include + 0 rules => nothing logged)' } else { 'effective' }
        L ('  ' + $sec.PadRight(22) + ' : ' + $attr.PadRight(22) + ' rules=' + $rules.ToString().PadLeft(3) + '  ' + $verdict)
    }
} else { L ('  sysmon config NOT FOUND: ' + $SysmonConfig) }
foreach ($s in (Get-Service -Name 'Sysmon*' -ErrorAction SilentlyContinue)) { L ('  service ' + $s.Name + ' = ' + $s.Status) }

# ---------- 7  after snapshot ----------
L ''
L '--- 7 AFTER: setting per GUID ---'
$csvAfter = & auditpol.exe /get /category:* /r 2>&1
[IO.File]::WriteAllLines((Join-Path $OutDir 'auditpol_after.csv'), $csvAfter, $utf8)
foreach ($k in $guids.Keys) {
    $hit = $csvAfter | Where-Object { $_ -like ('*' + $guids[$k] + '*') } | Select-Object -First 1
    $setting = ''
    if ($hit) { $setting = ($hit -split ',' | Select-Object -Last 3) -join '|' }
    L ('  ' + $k.PadRight(28) + ' => ' + $setting)
}

L ''
L 'DONE audit_baseline'
Write-Host ('DONE audit_baseline -> read ' + $log)
