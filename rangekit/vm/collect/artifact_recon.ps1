# artifact_recon.ps1 - read-only survey of the execution-artifact sources on the guest.
#
# Know EXACTLY which artifacts exist and are enabled BEFORE generating activity,
# so "the artifact was empty" is never confused with "we looked in the wrong place".
#
# Artifact families probed:
#   1. Prefetch        (execution count / first / last run)
#   2. Amcache         (SHA-1 of executed files)
#   3. Shimcache       (AppCompatCache, execution presence)
#   4. USBSTOR         (device serials / first install)
#   5. UserAssist      (ROT13 GUI launch paths)
#   6. ConsentStore    (mic / camera usage windows)
# plus the EZ Tools needed to parse them and a Prefetch baseline for -BaselineExes.
#
# Under a non-interactive vmrun session HKCU may resolve to HKU\.DEFAULT; if the
# HKCU sections look empty, run user_hive_probe.ps1.
#
# ASCII ONLY.

[CmdletBinding()]
param(
    [string]$ToolRoot = 'C:\Tools\DFIR',
    [string]$EZToolsDir = 'C:\Tools\DFIR\EZTools',
    [string[]]$BaselineExes = @('notepad.exe', 'calc.exe', 'cmd.exe', 'powershell.exe', 'mspaint.exe', 'write.exe', 'charmap.exe')
)

$ErrorActionPreference = 'Continue'
function Show-Message([string]$m) { Write-Host $m }

$now = Get-Date
Show-Message '=== 0. identity / time basis ==='
Show-Message ("whoami     : " + (whoami))
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
Show-Message ("IsAdmin    : " + $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
Show-Message ("LocalNow   : " + $now.ToString('yyyy-MM-dd HH:mm:ss K'))
Show-Message ("UtcNow     : " + $now.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') + 'Z')
Show-Message ("TimeZone   : " + [TimeZoneInfo]::Local.Id + " (offset " + [TimeZoneInfo]::Local.BaseUtcOffset + ")")

Show-Message ''
Show-Message '=== 1. Prefetch ==='
$pp = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'
try {
    $v = Get-ItemProperty -Path $pp -ErrorAction Stop
    Show-Message ("EnablePrefetcher : " + $v.EnablePrefetcher + "  (0=off 1=app 2=boot 3=both)")
    Show-Message ("EnableSuperfetch : " + $v.EnableSuperfetch)
} catch { Show-Message ("PrefetchParameters read failed: " + $_.Exception.Message) }
$pfDir = "$env:SystemRoot\Prefetch"
if (Test-Path $pfDir) {
    $pfs = Get-ChildItem $pfDir -Filter '*.pf' -ErrorAction SilentlyContinue
    Show-Message ("prefetch dir     : $pfDir (.pf count = " + @($pfs).Count + ")")
    Show-Message '  newest 10:'
    $pfs | Sort-Object LastWriteTime -Descending | Select-Object -First 10 | ForEach-Object {
        Show-Message ('    ' + $_.Name.PadRight(40) + ' ' + $_.LastWriteTimeUtc.ToString('yyyy-MM-dd HH:mm:ss') + 'Z')
    }
    Show-Message ("  Layout.ini      : " + (Test-Path (Join-Path $pfDir 'Layout.ini')))
    Show-Message ("  ReadyBoot       : " + (Test-Path (Join-Path $pfDir 'ReadyBoot')))
} else { Show-Message ("prefetch dir     : MISSING ($pfDir)") }
$sysmain = Get-Service -Name 'SysMain' -ErrorAction SilentlyContinue
if ($sysmain) { Show-Message ("SysMain service  : " + $sysmain.Status + " / " + $sysmain.StartType) } else { Show-Message 'SysMain service  : NOT FOUND' }

Show-Message ''
Show-Message '=== 2. Amcache ==='
$am = "$env:SystemRoot\AppCompat\Programs"
foreach ($p in @("$am\Amcache.hve", "$am\Amcache.hve.LOG1", "$am\Amcache.hve.LOG2", "$am\RecentFileCache.bcf")) {
    if (Test-Path $p) {
        Show-Message ('  EXISTS ' + $p + '  ' + [math]::Round((Get-Item $p).Length / 1MB, 2) + ' MB  ' + (Get-Item $p).LastWriteTimeUtc.ToString('yyyy-MM-dd HH:mm:ss') + 'Z')
    } else { Show-Message ('  MISSING ' + $p) }
}

Show-Message ''
Show-Message '=== 3. Shimcache (AppCompatCache) ==='
$systemLive = "$env:SystemRoot\System32\config\SYSTEM"
if (Test-Path $systemLive) { Show-Message ('  SYSTEM hive: ' + [math]::Round((Get-Item $systemLive).Length / 1MB, 2) + ' MB  ' + (Get-Item $systemLive).LastWriteTimeUtc.ToString('yyyy-MM-dd HH:mm:ss') + 'Z') }
try {
    $item = Get-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\AppCompatCache' -ErrorAction Stop
    Show-Message ('  AppCompatCache value size = ' + $item.GetValue('AppCompatCache').Length + ' bytes')
} catch { Show-Message ('  AppCompatCache registry read: ' + $_.Exception.Message) }

Show-Message ''
Show-Message '=== 4. USBSTOR ==='
$usb = 'HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR'
if (Test-Path $usb) {
    $devs = Get-ChildItem $usb -ErrorAction SilentlyContinue
    Show-Message ('  USBSTOR device types = ' + @($devs).Count)
    foreach ($d in $devs) {
        foreach ($i in (Get-ChildItem $d.PSPath -ErrorAction SilentlyContinue)) { Show-Message ('    ' + $i.PSChildName) }
    }
} else { Show-Message '  USBSTOR key MISSING' }
$setupapi = "$env:SystemRoot\inf\setupapi.dev.log"
if (Test-Path $setupapi) { Show-Message ('  setupapi.dev.log : ' + [math]::Round((Get-Item $setupapi).Length / 1KB, 1) + ' KB') } else { Show-Message '  setupapi.dev.log : MISSING' }
$mp2 = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2'
if (Test-Path $mp2) { Show-Message ('  MountPoints2 entries = ' + @(Get-ChildItem $mp2 -ErrorAction SilentlyContinue).Count) } else { Show-Message '  MountPoints2 : MISSING' }

Show-Message ''
Show-Message '=== 5. UserAssist ==='
$ua = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist'
if (Test-Path $ua) {
    $guids = Get-ChildItem $ua -ErrorAction SilentlyContinue
    Show-Message ('  UserAssist GUID subkeys = ' + @($guids).Count)
    foreach ($g in $guids) {
        $cnt = Get-Item (Join-Path $g.PSPath 'Count') -ErrorAction SilentlyContinue
        if ($cnt) { Show-Message ('    ' + $g.PSChildName + '  Count values = ' + @($cnt.GetValueNames()).Count) }
    }
} else { Show-Message '  UserAssist : MISSING' }

Show-Message ''
Show-Message '=== 6. ConsentStore (mic / camera) ==='
$csRoot = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'
foreach ($cap in @('microphone', 'webcam')) {
    $p = Join-Path $csRoot $cap
    if (Test-Path $p) {
        Show-Message ('  ' + $cap + ' : subkeys = ' + @(Get-ChildItem $p -Recurse -ErrorAction SilentlyContinue).Count)
    } else { Show-Message ('  ' + $cap + ' : MISSING') }
}
$csNonPkg = Join-Path $csRoot 'microphone\NonPackaged'
if (Test-Path $csNonPkg) { Show-Message ('  microphone\NonPackaged apps = ' + @(Get-ChildItem $csNonPkg -ErrorAction SilentlyContinue).Count) }

Show-Message ''
Show-Message '=== 7. EZ Tools presence ==='
foreach ($t in @('PECmd.exe', 'AmcacheParser.exe', 'AppCompatCacheParser.exe', 'RECmd.exe', 'MFTECmd.exe', 'SBECmd.exe')) {
    $f = Get-ChildItem $EZToolsDir -Filter $t -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { Show-Message ('  OK   ' + $t.PadRight(28) + $f.FullName) } else { Show-Message ('  MISS ' + $t) }
}
$rebs = Get-ChildItem $ToolRoot -Filter '*.reb' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 5
Show-Message ('  RECmd batch files found: ' + @($rebs).Count)
foreach ($b in $rebs) { Show-Message ('    ' + $b.FullName) }

Show-Message ''
Show-Message '=== 8. Prefetch baseline for known programs (diff after the exercise) ==='
foreach ($exe in $BaselineExes) {
    $found = Get-ChildItem $pfDir -Filter ($exe.Split('.')[0].ToUpper() + '.EXE-*') -ErrorAction SilentlyContinue
    Show-Message ('  ' + $exe.PadRight(16) + ' prefetch present = ' + @($found).Count)
}

Show-Message ''
Show-Message 'DONE artifact_recon'
