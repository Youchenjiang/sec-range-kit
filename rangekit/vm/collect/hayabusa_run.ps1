# hayabusa_run.ps1 - repair a Hayabusa install and run its timeline pass.
#
# A minimal Hayabusa install holds only the exe, encoded_rules.yml and
# rules_config_files.txt. At runtime it also needs rules/config/*.txt
# (generic_abbreviations.txt, eventkey_alias.txt, ...) relative to its WORKING
# DIRECTORY; without them dfir-timeline exits 1 with
# "Cannot open file. [file:rules/config/generic_abbreviations.txt]".
# `update-rules` fetches the full rules tree, config included (needs network).
#
# Two details that matter:
#   - the child's WorkingDirectory is the Hayabusa folder, because -r (rules) and
#     -c (rules config) default to ./rules resolved against the CWD, not the exe.
#   - stdin is closed for every child: update-rules and the scan both have
#     interactive paths, and a blocked read on stdin hangs a vmrun session.
#
# ASCII ONLY.

[CmdletBinding()]
param(
    [string]$HayabusaDir = 'C:\Tools\DFIR\hayabusa',
    [string]$EvtxDir = 'C:\Tools\DFIR\out\evtx\evtx',
    [string]$OutCsv = 'C:\Tools\DFIR\out\evtx\toolout\hayabusa.csv',
    [string]$LogFile = '',
    [switch]$SkipUpdate,
    [int]$UpdateTimeoutSec = 300,
    [int]$ScanTimeoutSec = 480
)

$ErrorActionPreference = 'Continue'
$hbExe = Get-ChildItem $HayabusaDir -Filter 'hayabusa-*.exe' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
if (-not $hbExe) { Write-Host ('Hayabusa exe NOT FOUND under ' + $HayabusaDir); exit 1 }
$HB = $hbExe.FullName
New-Item -ItemType Directory -Force -Path (Split-Path $OutCsv -Parent) | Out-Null
if (-not $LogFile) { $LogFile = Join-Path (Split-Path $OutCsv -Parent) 'hayabusa_log.txt' }
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($LogFile, '', $utf8)
function L([string]$m) { [IO.File]::AppendAllText($LogFile, $m + "`r`n", $utf8) }

function Invoke-Hayabusa([string]$ArgLine, [int]$TimeoutSec) {
    # The parameter must NOT be called $Args: that is PowerShell's automatic
    # argument array, and the child would receive an empty command line.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $HB
    $psi.Arguments = $ArgLine
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.WorkingDirectory = $HayabusaDir
    $p = [Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $ot = $p.StandardOutput.ReadToEndAsync()
    $et = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch { Write-Verbose ("process already exited: " + $_.Exception.Message) }
        return @{ exit = -1; text = '<TIMEOUT>' }
    }
    return @{ exit = $p.ExitCode; text = ($ot.Result + "`n" + $et.Result) }
}

function Write-Result($r, $sw) {
    L ('  exit=' + $r.exit + ' elapsed=' + [math]::Round($sw.Elapsed.TotalSeconds, 1) + 's')
    foreach ($line in ($r.text -split "`n")) { if ($line.Trim()) { L ('  | ' + $line.Trim()) } }
}

L '=== Hayabusa repair + run ==='
L ('local ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss K'))
L ('exe   ' + $HB)

# ---- 1. what is installed ----
L ''
L '--- 1. current install state ---'
foreach ($f in (Get-ChildItem $HayabusaDir -Force | Select-Object -First 30)) {
    L ('  ' + $f.Name.PadRight(34) + $(if ($f.PSIsContainer) { '<DIR>' } else { [math]::Round($f.Length / 1KB, 1).ToString() + ' KB' }))
}
$cfgDir = Join-Path $HayabusaDir 'rules\config'
L ('  rules\config exists : ' + (Test-Path $cfgDir))

# ---- 2. update-rules ----
if (-not $SkipUpdate) {
    L ''
    L '--- 2. update-rules (downloads the rules tree incl. config) ---'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $r = Invoke-Hayabusa 'update-rules' $UpdateTimeoutSec
    $sw.Stop()
    Write-Result $r $sw
    L ('  rules\config exists now : ' + (Test-Path $cfgDir))
    if (Test-Path $cfgDir) {
        $cfg = Get-ChildItem $cfgDir -File
        L ('  rules\config files      : ' + $cfg.Count)
    }
}

# ---- 3. dfir-timeline ----
L ''
L '--- 3. dfir-timeline over the evtx set ---'
Remove-Item $OutCsv -Force -ErrorAction SilentlyContinue
$sw = [Diagnostics.Stopwatch]::StartNew()
$r = Invoke-Hayabusa ('dfir-timeline -d "' + $EvtxDir + '" -o "' + $OutCsv + '" -w -K -N -U -C') $ScanTimeoutSec
$sw.Stop()
Write-Result $r $sw
if (Test-Path $OutCsv) {
    $rows = [math]::Max(0, (Get-Content $OutCsv | Measure-Object -Line).Lines - 1)
    L ('  output ' + (Split-Path $OutCsv -Leaf) + ' rows=' + $rows + ' size=' + [math]::Round((Get-Item $OutCsv).Length / 1KB, 1) + ' KB')
} else { L '  output MISSING' }

L ''
L 'DONE hayabusa_run'
Write-Host ('DONE hayabusa_run -> ' + $LogFile)
if (-not (Test-Path $OutCsv)) { exit 1 }
