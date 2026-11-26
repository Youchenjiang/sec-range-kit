# artifact_parse.ps1 - turn captured execution artifacts into CSVs with the EZ tool chain.
#
# Expected input layout under -BaseDir (override any piece with its parameter):
#   snapshot\*.pf, snapshot\Amcache.hve   copied Prefetch files and Amcache hive
#   hives\<SystemHive>, hives\<NtUserHive> copies of SYSTEM and a user's NTUSER.DAT
# Output: <BaseDir>\toolout\*.csv and analyze_log.txt; exit 1 when any tool fails.
#
# Three hard-won rules baked in here:
#   1. RECmd picks the hive TYPE from the hive header's EMBEDDED base name
#      ("ntuser.dat" -> NtUser, "SYSTEM" -> System). A hive made by `reg save` to a
#      custom file name keeps a non-standard embedded name and is typed "Other", so
#      EVERY batch rule is silently skipped. We rewrite the 64-byte name field at
#      base-block offset 0x30 (on the copy, never on a live hive).
#   2. RECmd batch (.reb) files MUST use LF line endings. With CRLF the YAML parser
#      keeps a trailing \r inside KeyPath, so the regex can never match.
#   3. AmcacheParser aborts on a dirty hive unless --nl true is given.
#
# ASCII ONLY.

[CmdletBinding()]
param(
    [string]$BaseDir = 'C:\Tools\DFIR\out\artifacts',
    [string]$SnapshotDir = '',
    [string]$HivesDir = '',
    [string]$SystemHive = 'SYSTEM_copy.hive',
    [string]$NtUserHive = 'NTUSER_copy.hive',
    [string]$EZDir = 'C:\Tools\DFIR\EZTools\net9',
    [switch]$NoPatchHiveNames
)

$ErrorActionPreference = 'Continue'
if (-not $SnapshotDir) { $SnapshotDir = Join-Path $BaseDir 'snapshot' }
if (-not $HivesDir) { $HivesDir = Join-Path $BaseDir 'hives' }
$systemPath = Join-Path $HivesDir $SystemHive
$ntuserPath = Join-Path $HivesDir $NtUserHive
$out   = Join-Path $BaseDir 'toolout'
$batch = Join-Path $BaseDir 'batch'
Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $batch -Recurse -Force -ErrorAction SilentlyContinue
foreach ($d in @($out, $batch)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
$log = Join-Path $out 'analyze_log.txt'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $utf8)
function L([string]$m) { [IO.File]::AppendAllText($log, $m + "`r`n", $utf8) }
$script:failures = 0

function Set-HiveBaseName([string]$Path, [string]$Name) {
    if (-not (Test-Path $Path)) { L ('  hive MISSING: ' + $Path); $script:failures++; return }
    $b = [IO.File]::ReadAllBytes($Path)
    for ($i = 0; $i -lt 64; $i++) { $b[0x30 + $i] = 0 }
    $nb = [Text.Encoding]::Unicode.GetBytes($Name)
    [Array]::Copy($nb, 0, $b, 0x30, $nb.Length)
    [IO.File]::WriteAllBytes($Path, $b)
    L ('  base name patched -> ' + $Name + '  (' + $Path + ')')
}

# RECmd batch with LF endings (NOT CRLF)
function Write-RebLf([string]$Path, [string]$Desc, [string]$HiveType, [string]$Category, [string]$KeyPath) {
    $content = @(
        "Description: $Desc",
        'Author: rangekit',
        'Version: 1',
        ('Id: ' + [guid]::NewGuid().ToString()),
        'Keys:',
        '    -',
        ('        Description: ' + $Desc),
        ('        HiveType: ' + $HiveType),
        ('        Category: ' + $Category),
        ('        KeyPath: ' + $KeyPath),
        '        Recursive: True',   # capital T: YamlDotNet is case-sensitive on bools
        '        Comment:'
    ) -join "`n"
    [IO.File]::WriteAllText($Path, $content + "`n", $utf8)
}

function Invoke-Tool([string]$Name, [string]$Exe, [string[]]$ArgList, [string]$CsvFile) {
    L ''
    L ('--- ' + $Name + ' ---')
    if (-not (Test-Path $Exe)) { L ('  tool NOT FOUND: ' + $Exe); $script:failures++; return }
    L ('  cmd: ' + $Exe + ' ' + ($ArgList -join ' '))
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $res = & $Exe @ArgList 2>&1 | Out-String
    $sw.Stop()
    L ('  exit=' + $LASTEXITCODE + ' elapsed=' + [math]::Round($sw.Elapsed.TotalSeconds, 1) + 's')
    if ($LASTEXITCODE -ne 0) { $script:failures++ }
    foreach ($line in ($res -split "`n")) { if ($line.Trim()) { L ('  | ' + $line.Trim()) } }
    if ($CsvFile) {
        $f = Join-Path $out $CsvFile
        if (Test-Path $f) {
            $rows = [math]::Max(0, ((Get-Content $f | Measure-Object -Line).Lines - 1))
            L ('  output ' + $CsvFile + ' rows=' + $rows + ' size=' + [math]::Round((Get-Item $f).Length / 1KB, 1) + ' KB')
        } else { L ('  output ' + $CsvFile + ' MISSING'); $script:failures++ }
    }
}

L ('=== artifact parse  UTC=' + [DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss') + 'Z ===')

# 0. make the hive copies self-identifying
if (-not $NoPatchHiveNames) {
    Set-HiveBaseName $systemPath 'SYSTEM'
    Set-HiveBaseName $ntuserPath 'NTUSER.DAT'
}

# 1. batch files (LF). KeyPath uses SINGLE backslashes; doubled ones never match.
Write-RebLf (Join-Path $batch 'usbstor.reb')      'USBSTOR devices'    'System' 'USB'        'CurrentControlSet\Enum\USBSTOR'
Write-RebLf (Join-Path $batch 'userassist.reb')   'UserAssist counts'  'NtUser' 'UserAssist' 'Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist'
Write-RebLf (Join-Path $batch 'consentstore.reb') 'ConsentStore usage' 'NtUser' 'Consent'    'Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'

# 2. Prefetch
Invoke-Tool 'PECmd' "$EZDir\PECmd.exe" @('-q', '-d', $SnapshotDir, '--csv', $out, '--csvf', 'prefetch.csv') 'prefetch.csv'

# 3. Amcache
Invoke-Tool 'AmcacheParser' "$EZDir\AmcacheParser.exe" @('-f', (Join-Path $SnapshotDir 'Amcache.hve'), '-i', '--nl', 'true', '--csv', $out, '--csvf', 'amcache.csv') 'amcache_UnassociatedFileEntries.csv'

# 4. Shimcache
Invoke-Tool 'AppCompatCacheParser' "$EZDir\AppCompatCacheParser.exe" @('-f', $systemPath, '--csv', $out, '--csvf', 'shimcache.csv') 'shimcache.csv'

# 5-7. RECmd batches
$recmd = "$EZDir\RECmd\RECmd.exe"
Invoke-Tool 'RECmd-USBSTOR' $recmd @('-f', $systemPath, '--bn', (Join-Path $batch 'usbstor.reb'), '--csv', $out, '--csvf', 'usbstor.csv', '--nl', 'true') 'usbstor.csv'
Invoke-Tool 'RECmd-UserAssist' $recmd @('-f', $ntuserPath, '--bn', (Join-Path $batch 'userassist.reb'), '--csv', $out, '--csvf', 'userassist_raw.csv', '--nl', 'true') 'userassist_raw.csv'
Invoke-Tool 'RECmd-ConsentStore' $recmd @('-f', $ntuserPath, '--bn', (Join-Path $batch 'consentstore.reb'), '--csv', $out, '--csvf', 'consentstore_raw.csv', '--nl', 'true') 'consentstore_raw.csv'

L ''
L '--- produced files ---'
Get-ChildItem $out | Sort-Object Name | ForEach-Object { L ('  ' + $_.Name.PadRight(34) + ' ' + [math]::Round($_.Length / 1KB, 1) + ' KB') }

L ''
L ('DONE artifact_parse failures=' + $script:failures)
Write-Host ('DONE artifact_parse failures=' + $script:failures + ' -> read ' + $log)
if ($script:failures -gt 0) { exit 1 }
