# evtx_export.ps1 - export the key event channels and run three parsers over the same set.
#
# All three tools (EvtxECmd, Hayabusa, Chainsaw) read the SAME directory of
# exported .evtx files so their outputs are directly comparable. Timings and exit
# codes are logged because "the tool worked" should be backed by numbers.
# An EID census over the last -WindowMinutes is written to eid_census.csv.
#
# Tool paths default to the layout of rangekit/vm/setup/vm_setup_dfir.ps1; an
# empty -Hayabusa means "the newest hayabusa-*.exe under <ToolRoot>\hayabusa".
# Use -SkipTools to export and count only.
#
# ASCII ONLY.

[CmdletBinding()]
param(
    [string]$OutDir = 'C:\Tools\DFIR\out\evtx',
    [int]$WindowMinutes = 30,
    [string]$ToolRoot = 'C:\Tools\DFIR',
    [string]$EvtxECmd = 'C:\Tools\DFIR\EZTools\net9\EvtxeCmd\EvtxECmd.exe',
    [string]$Hayabusa = '',
    [string]$Chainsaw = 'C:\Tools\DFIR\chainsaw\chainsaw.exe',
    [string]$SigmaRules = 'C:\Tools\DFIR\sigma-rules',
    [string]$ChainsawMapping = 'C:\Tools\DFIR\chainsaw\mappings\sigma-event-logs-all.yml',
    [switch]$SkipTools
)

$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$log = Join-Path $OutDir 'export_log.txt'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($log, '', $utf8)
function L([string]$m) { [IO.File]::AppendAllText($log, $m + "`r`n", $utf8) }

$evtxDir = Join-Path $OutDir 'evtx'
$toolDir = Join-Path $OutDir 'toolout'
Remove-Item $evtxDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $toolDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $evtxDir | Out-Null
New-Item -ItemType Directory -Force -Path $toolDir | Out-Null

$nowL = Get-Date
L '=== evtx export ==='
L ('collect_local = ' + $nowL.ToString('yyyy-MM-dd HH:mm:ss K'))
L ('collect_utc   = ' + $nowL.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') + 'Z')

# ---------- 1. export channels ----------
L ''
L '--- 1. wevtutil epl per channel ---'
$channels = [ordered]@{
    'Security'                                       = 'Security.evtx'
    'System'                                         = 'System.evtx'
    'Microsoft-Windows-Sysmon/Operational'           = 'Sysmon.evtx'
    'Microsoft-Windows-PowerShell/Operational'       = 'PowerShell-Operational.evtx'
    'Microsoft-Windows-Windows Defender/Operational' = 'Defender-Operational.evtx'
    'Microsoft-Windows-TaskScheduler/Operational'    = 'TaskScheduler-Operational.evtx'
}
foreach ($channel in $channels.Keys) {
    $file = $channels[$channel]
    $dst = Join-Path $evtxDir $file
    & wevtutil.exe epl $channel $dst 2>&1 | Out-Null
    if (Test-Path $dst) {
        $mb = [math]::Round((Get-Item $dst).Length / 1MB, 2)
        L ('  OK    ' + $channel.PadRight(46) + ' -> ' + $file.PadRight(34) + ' ' + $mb + ' MB')
    } else {
        L ('  FAIL  ' + $channel + ' (channel missing or not readable)')
    }
}

# ---------- 2. event-id census in the window ----------
L ''
L ('--- 2. EID census for the last ' + $WindowMinutes + ' minutes ---')
$winStart = $nowL.AddMinutes(-$WindowMinutes)
$census = @()
foreach ($ch in @($channels.Keys | Where-Object { $_ -ne 'System' })) {
    try {
        $ev = Get-WinEvent -FilterHashtable @{ LogName = $ch; StartTime = $winStart } -ErrorAction Stop
    } catch { L ('  ' + $ch.PadRight(46) + ' (no events / unavailable)'); continue }
    L ('  ' + $ch + '  total=' + @($ev).Count)
    foreach ($g in ($ev | Group-Object Id | Sort-Object { [int]$_.Name })) {
        L ('         EID ' + $g.Name.PadRight(6) + ' x ' + $g.Count)
        $census += [pscustomobject]@{ Channel = $ch; EID = [int]$g.Name; Count = $g.Count }
    }
}
$census | Export-Csv -Path (Join-Path $OutDir 'eid_census.csv') -NoTypeInformation -Encoding UTF8

function Invoke-Timed([string]$Name, [scriptblock]$Body) {
    L ''
    L ('--- ' + $Name + ' ---')
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $text = & $Body 2>&1 | Out-String
    $sw.Stop()
    L ('  exit=' + $LASTEXITCODE + ' elapsed=' + [math]::Round($sw.Elapsed.TotalSeconds, 1) + 's')
    foreach ($line in ($text -split "`n")) { if ($line.Trim()) { L ('  | ' + $line.Trim()) } }
}

function Write-OutputStat([string]$File) {
    $f = Join-Path $toolDir $File
    if (-not (Test-Path $f)) { L ('  output ' + $File + ' MISSING'); return }
    $kb = [math]::Round((Get-Item $f).Length / 1KB, 1)
    if ($File -like '*.csv') {
        $rows = [math]::Max(0, (Get-Content $f | Measure-Object -Line).Lines - 1)
        L ('  output ' + $File + ' rows=' + $rows + ' size=' + $kb + ' KB')
    } else {
        $hits = ([regex]::Matches((Get-Content $f -Raw), '"tag"')).Count
        L ('  output ' + $File + ' size=' + $kb + ' KB  tag_markers=' + $hits)
    }
}

if (-not $SkipTools) {
    if (-not $Hayabusa) {
        $hb = Get-ChildItem (Join-Path $ToolRoot 'hayabusa') -Filter 'hayabusa-*.exe' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($hb) { $Hayabusa = $hb.FullName }
    }

    # ---------- 3. EvtxECmd ----------
    if (Test-Path $EvtxECmd) {
        Invoke-Timed '3. EvtxECmd' { & $EvtxECmd -d $evtxDir --csv $toolDir --csvf evtxecmd.csv }
        Write-OutputStat 'evtxecmd.csv'
    } else { L ''; L ('--- 3. EvtxECmd NOT FOUND: ' + $EvtxECmd) }

    # ---------- 4. Hayabusa ----------
    # Hayabusa resolves ./rules against the working directory; see hayabusa_run.ps1
    # when rules/config is missing.
    if ($Hayabusa -and (Test-Path $Hayabusa)) {
        Push-Location (Split-Path $Hayabusa -Parent)
        Invoke-Timed '4. Hayabusa dfir-timeline' { & $Hayabusa dfir-timeline -d $evtxDir -o (Join-Path $toolDir 'hayabusa.csv') -w -K -N -U -C }
        Pop-Location
        Write-OutputStat 'hayabusa.csv'
    } else { L ''; L '--- 4. Hayabusa NOT FOUND ---' }

    # ---------- 5. Chainsaw ----------
    if (Test-Path $Chainsaw) {
        Invoke-Timed '5. Chainsaw hunt with Sigma' { & $Chainsaw hunt -s $SigmaRules -m $ChainsawMapping -o (Join-Path $toolDir 'chainsaw.json') --json $evtxDir }
        Write-OutputStat 'chainsaw.json'
    } else { L ''; L ('--- 5. Chainsaw NOT FOUND: ' + $Chainsaw) }
}

# ---------- 6. inventory ----------
L ''
L '--- 6. produced files ---'
foreach ($d in @($evtxDir, $toolDir, $OutDir)) {
    L ('  [' + (Split-Path $d -Leaf) + ']')
    Get-ChildItem $d -File | Sort-Object Name | ForEach-Object { L ('    ' + $_.Name.PadRight(38) + ' ' + [math]::Round($_.Length / 1KB, 1) + ' KB') }
}

L ''
L 'DONE evtx_export'
Write-Host ('DONE evtx_export -> read ' + $log)
