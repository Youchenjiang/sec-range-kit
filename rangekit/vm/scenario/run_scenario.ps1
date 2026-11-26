# run_scenario.ps1 - run a known-answer scenario in the guest, or remove what it created.
#
# The scenario file (JSON, see scenario.example.json and rangekit/vm/scenario.py)
# lists steps; each step has a kind this script implements, the names it uses and
# the events it is expected to produce. Every kind is BENIGN and REVERSIBLE: it
# exists only to make specific telemetry appear (calc.exe is referenced in command
# lines but never executed, no existing file is touched, Defender stays on).
#
#   run      : remove what an earlier run of this scenario left (owned.json), refuse
#              to start if any artifact the scenario names already exists, then run
#              every step and write ground_truth.csv (one row per step: UTC/local
#              start and end, expected events, observed output), sim_log.txt and
#              window.txt to -OutDir.
#   -Cleanup : remove the artifacts this scenario created (owned.json), newest first,
#              then verify every artifact it names is gone (cleanup_log.txt); exit 1
#              if anything is left or cannot be checked. -Force also removes
#              same-named artifacts the scenario did not create. Telemetry settings
#              made by audit_baseline.ps1 / process_access_check.ps1 are NOT reverted.
#
# Ownership: owned.json in -OutDir records each step that created something, so a
# name collision with existing guest state is refused, never deleted.
#
# Secrets: a local_user step takes its password from the environment variable in
# params.password_env (set it in the guest before the run), or a random one, and
# creates the account with New-LocalUser so the password never appears on a command
# line (process-creation telemetry records command lines). failed_logons uses random
# wrong passwords in process. No password is written to any output.
#
# Every native call goes through Invoke-Native: stdin is closed (a prompt gets EOF
# instead of hanging the vmrun session) and each call has a hard timeout.
#
# Validate the file on the host first:  python -m rangekit.vm.scenario validate <file>
# ASCII ONLY (PowerShell 5.1 reads a BOM-less .ps1 in the ANSI code page).

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Scenario,
    [string]$OutDir = 'C:\Tools\DFIR\out\scenario',
    [switch]$Cleanup,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$log = Join-Path $OutDir $(if ($Cleanup) { 'cleanup_log.txt' } else { 'sim_log.txt' })
[IO.File]::WriteAllText($log, '', $utf8)
function L([string]$m) { [IO.File]::AppendAllText($log, $m + "`r`n", $utf8) }
function Q([string]$s) { '"' + ($s -replace '"', '""') + '"' }

# ---------------------------------------------------------------------------
# scenario file (the host validator is the full check; this guards the guest)
# ---------------------------------------------------------------------------
$spec = Get-Content -Path $Scenario -Raw -Encoding UTF8 | ConvertFrom-Json
$stage = if ($spec.stage_dir) { [string]$spec.stage_dir } else { 'C:\Windows\Temp' }
$safe = '^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$'
foreach ($s in $spec.steps) {
    foreach ($prop in $s.params.PSObject.Properties) {
        if ($prop.Name -in @('task', 'service', 'value', 'user', 'filter', 'consumer', 'process', 'blob_file', 'out_file', 'file', 'staged_file') -and
            [string]$prop.Value -notmatch $safe) {
            throw ('step ' + $s.id + ': params.' + $prop.Name + ' is not a safe name; run python -m rangekit.vm.scenario validate')
        }
    }
}
function StagePath([string]$name) { Join-Path $stage $name }

# ---------------------------------------------------------------------------
# native runner: stdin closed + hard timeout + no pipe deadlock
# ---------------------------------------------------------------------------
function Invoke-Native {
    param([string]$Exe, [string[]]$Argv, [int]$TimeoutSec = 30)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = (($Argv | ForEach-Object {
                if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
            }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.WorkingDirectory = "$env:SystemRoot\System32"
    try { $p = [Diagnostics.Process]::Start($psi) } catch { return ('<START-FAILED: ' + $_.Exception.Message + '>') }
    $p.StandardInput.Close()
    $ot = $p.StandardOutput.ReadToEndAsync()
    $et = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch { Write-Verbose ("process already exited: " + $_.Exception.Message) }
        return ('<TIMEOUT after ' + $TimeoutSec + 's, process killed> ' + $ot.Result + $et.Result)
    }
    return (((($ot.Result + ' ' + $et.Result) -replace '\s+', ' ').Trim()) + ' [exit=' + $p.ExitCode + ']')
}

Add-Type -ErrorAction SilentlyContinue -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RangeKitNt {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool LogonUser(string user, string domain, string password,
        int logonType, int logonProvider, out IntPtr token);
}
'@

function New-RandomSecret([int]$Length = 12) {
    # net user prompts (and hangs) for passwords longer than 14 characters.
    $sets = @('ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '.-_')
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $bytes = New-Object byte[] $Length
    $rng.GetBytes($bytes)
    $chars = for ($i = 0; $i -lt $Length; $i++) { $set = $sets[$i % $sets.Count]; $set[$bytes[$i] % $set.Length] }
    -join $chars
}

$runKey = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run'

# ---------------------------------------------------------------------------
# kinds: Run makes the artifact, Clean removes it, Gone verifies the removal.
# Gone returns $true (absent) or $false (present) and THROWS when it cannot tell,
# so a failed or timed-out query is never reported as a clean removal.
# ---------------------------------------------------------------------------
$runKeyPath = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run'
$Kinds = @{
    scheduled_task = @{
        # Created DISABLED: Task Scheduler still logs the registration (4698, TaskScheduler/106)
        # but the command can never fire, even if cleanup does not run before the trigger time.
        Run   = {
            param($p)
            (Invoke-Native 'schtasks.exe' @('/create', '/tn', $p.task, '/tr', $p.command, '/sc', 'once', '/st', '23:59', '/f')) +
            ' | disable: ' + (Invoke-Native 'schtasks.exe' @('/change', '/tn', $p.task, '/disable'))
        }
        Clean = { param($p) Invoke-Native 'schtasks.exe' @('/delete', '/tn', $p.task, '/f') 20 }
        Gone  = { param($p) -not (Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskName -eq $p.task }) }
    }
    service = @{
        Run   = { param($p) Invoke-Native 'sc.exe' @('create', $p.service, 'binPath=', $p.command, 'start=', 'demand') }
        Clean = { param($p) Invoke-Native 'sc.exe' @('delete', $p.service) 20 }
        Gone  = { param($p) -not (Get-Service -ErrorAction Stop | Where-Object { $_.Name -eq $p.service }) }
    }
    run_key = @{
        Run   = { param($p) Invoke-Native 'reg.exe' @('add', $runKey, '/v', $p.value, '/t', 'REG_SZ', '/d', $p.data, '/f') }
        Clean = { param($p) Invoke-Native 'reg.exe' @('delete', $runKey, '/v', $p.value, '/f') 20 }
        Gone  = { param($p) (Get-Item -Path $runKeyPath -ErrorAction Stop).GetValueNames() -notcontains $p.value }
    }
    local_user = @{
        # New-LocalUser takes a SecureString in process: no net.exe command line, so the
        # password never reaches Sysmon EID 1 or Security 4688. The account still logs 4720.
        Run   = {
            param($p)
            $secret = $null
            if ($p.password_env) { $secret = [Environment]::GetEnvironmentVariable([string]$p.password_env) }
            $source = 'env ' + $p.password_env
            if (-not $secret) { $secret = New-RandomSecret; $source = 'random' }
            $secure = ConvertTo-SecureString -String $secret -AsPlainText -Force
            $secret = $null
            $u = New-LocalUser -Name $p.user -Password $secure -Description 'rangekit scenario account' -ErrorAction Stop
            'created ' + $u.Name + ' (password: ' + $source + ')'
        }
        Clean = { param($p) Remove-LocalUser -Name $p.user -ErrorAction Stop; 'removed' }
        Gone  = { param($p) -not (Get-LocalUser -ErrorAction Stop | Where-Object { $_.Name -eq $p.user }) }
    }
    group_add = @{
        Run = { param($p) Invoke-Native 'net.exe' @('localgroup', $p.group, $p.user, '/add') }
    }
    failed_logons = @{
        Run = {
            param($p)
            $o = @()
            foreach ($u in $p.users) {
                for ($i = 0; $i -lt [int]$p.attempts_per_user; $i++) {
                    $tok = [IntPtr]::Zero
                    # LOGON32_LOGON_NETWORK (3): LogonType 3, like an SMB brute-force attempt
                    $ok = [RangeKitNt]::LogonUser([string]$u, '.', ('x' + [guid]::NewGuid().ToString('N')), 3, 0, [ref]$tok)
                    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
                    if ($ok -and ($tok -ne [IntPtr]::Zero)) { [void][RangeKitNt]::CloseHandle($tok) }
                    $o += ([string]$u + ' ok=' + $ok + ' Win32Err=' + $err)
                }
            }
            $o -join ' | '
        }
    }
    encoded_powershell = @{
        Run = {
            param($p)
            $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('Write-Output "' + $p.marker + '"; $env:COMPUTERNAME'))
            'b64len=' + $b64.Length + ' :: ' + (Invoke-Native "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @('-NoProfile', '-EncodedCommand', $b64))
        }
    }
    certutil_decode = @{
        Run = {
            param($p)
            $b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("Write-Output '" + $p.marker + "'"))
            # 64-character lines, as certutil -encode writes them
            $lines = for ($i = 0; $i -lt $b64.Length; $i += 64) { $b64.Substring($i, [Math]::Min(64, $b64.Length - $i)) }
            Set-Content -Path (StagePath $p.blob_file) -Value $lines -Encoding ASCII
            Invoke-Native 'certutil.exe' @('-f', '-decode', (StagePath $p.blob_file), (StagePath $p.out_file))
        }
    }
    ads = @{
        Run = {
            param($p)
            Set-Content -Path (StagePath $p.file) -Stream $p.stream -Value $p.data -Encoding ASCII
            'streams=' + ((Get-Item (StagePath $p.file) -Stream * | Select-Object -ExpandProperty Stream) -join ' / ')
        }
    }
    lolbin_egress = @{
        Run = {
            param($p)
            Copy-Item $p.source (StagePath $p.staged_file) -Force
            Invoke-Native (StagePath $p.staged_file) @('-s', '-o', 'NUL', '-m', '10', $p.url) 25
        }
    }
    discovery = @{
        Run = {
            param($p)
            $o = @()
            $o += 'whoami:' + (Invoke-Native 'whoami.exe' @('/all') 20)
            $o += 'netuser:' + (Invoke-Native 'net.exe' @('user') 20)
            $o += 'netlg:' + (Invoke-Native 'net.exe' @('localgroup', 'Administrators') 20)
            $o += 'ipconfig:' + (Invoke-Native 'ipconfig.exe' @('/all') 20)
            $o += 'tasklist:' + (Invoke-Native 'tasklist.exe' @() 20)
            $o -join ' | '
        }
    }
    eicar = @{
        Run = {
            param($p)
            # assembled at run time so this script is never itself a complete signature
            $e1 = 'X5O!P%@AP[4\PZX54(P^)7CC)7}$'
            $e2 = 'EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*'
            Set-Content -Path (StagePath $p.file) -Value ($e1 + $e2) -Encoding ASCII -NoNewline
            Start-Sleep -Seconds 6
            'file_still_present=' + (Test-Path (StagePath $p.file))
        }
    }
    process_open = @{
        Run = {
            param($p)
            $proc = Get-Process -Name $p.process -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $proc) { return ($p.process + ' not running') }
            $o = @($p.process + '_pid=' + $proc.Id)
            foreach ($mask in $p.access) {
                $h = [RangeKitNt]::OpenProcess([uint32]$mask, $false, $proc.Id)
                $ok = ($h -ne [IntPtr]::Zero)
                if ($ok) { [void][RangeKitNt]::CloseHandle($h) }
                $o += ('open_0x' + ([int]$mask).ToString('X4') + '=' + $ok)
                Start-Sleep -Milliseconds 400
            }
            $o -join ' '
        }
    }
    wmi_subscription = @{
        Run = {
            param($p)
            $f = New-CimInstance -Namespace root\subscription -ClassName __EventFilter -Property @{
                Name = [string]$p.filter; EventNamespace = 'root\cimv2'; QueryLanguage = 'WQL'
                Query = "SELECT * FROM __InstanceModificationEvent WITHIN 60 WHERE TargetInstance ISA 'Win32_PerfFormattedData_PerfOS_System'"
            }
            $c = New-CimInstance -Namespace root\subscription -ClassName CommandLineEventConsumer -Property @{
                Name = [string]$p.consumer; CommandLineTemplate = [string]$p.command
            }
            $b = New-CimInstance -Namespace root\subscription -ClassName __FilterToConsumerBinding -Property @{ Filter = [ref]$f; Consumer = [ref]$c }
            'filter=' + $f.Name + ' consumer=' + $c.Name + ' binding=' + $b.CimClass.CimClassName
        }
        Clean = {
            param($p)
            Get-CimInstance -Namespace root\subscription -ClassName __FilterToConsumerBinding -ErrorAction SilentlyContinue |
                Where-Object { $_.Filter.Name -eq $p.filter -or $_.Consumer.Name -eq $p.consumer } | Remove-CimInstance
            Get-CimInstance -Namespace root\subscription -ClassName CommandLineEventConsumer -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq $p.consumer } | Remove-CimInstance
            Get-CimInstance -Namespace root\subscription -ClassName __EventFilter -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq $p.filter } | Remove-CimInstance
            'removed'
        }
        Gone = {
            param($p)
            -not (Get-CimInstance -Namespace root\subscription -ClassName __EventFilter -ErrorAction Stop | Where-Object { $_.Name -eq $p.filter }) -and
            -not (Get-CimInstance -Namespace root\subscription -ClassName CommandLineEventConsumer -ErrorAction Stop | Where-Object { $_.Name -eq $p.consumer })
        }
    }
}

foreach ($s in $spec.steps) {
    if (-not $Kinds.ContainsKey([string]$s.kind)) { throw ('step ' + $s.id + ': unknown kind ' + $s.kind) }
}

function Get-StagedFiles($p) {
    foreach ($key in @('blob_file', 'out_file', 'file', 'staged_file')) {
        if ($p.PSObject.Properties.Name -contains $key) { StagePath ([string]$p.$key) }
    }
}

function Remove-StepArtifacts($s) {
    $k = $Kinds[[string]$s.kind]
    if ($k.Clean) {
        $res = try { (& $k.Clean $s.params 2>&1 | Out-String).Trim() } catch { 'error: ' + $_.Exception.Message }
        L ('  [' + $s.id + '] ' + ([string]$s.kind).PadRight(18) + ' clean -> ' + $res)
    }
    foreach ($f in (Get-StagedFiles $s.params)) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
}

function Test-StepCreates($s) { [bool]$Kinds[[string]$s.kind].Clean -or @(Get-StagedFiles $s.params).Count -gt 0 }

# ---- ownership record: which steps of this scenario created something ----
$ownedFile = Join-Path $OutDir ('owned_' + $spec.name + '.json')
function Get-OwnedIds {
    if (-not (Test-Path -LiteralPath $ownedFile)) { return @() }
    @((Get-Content -LiteralPath $ownedFile -Raw | ConvertFrom-Json))
}
function Save-OwnedIds([string[]]$Ids) {
    [IO.File]::WriteAllText($ownedFile, (ConvertTo-Json -InputObject @($Ids) -Compress), $utf8)
}

# State of every artifact one step names: GONE, PRESENT or UNKNOWN (the check failed).
function Get-StepArtifactStates($s) {
    $states = @()
    $k = $Kinds[[string]$s.kind]
    if ($k.Gone) {
        $state = try { if ([bool](& $k.Gone $s.params)) { 'GONE' } else { 'PRESENT' } } catch { 'UNKNOWN' }
        $states += , @([string]$s.kind, $state)
    }
    foreach ($f in (Get-StagedFiles $s.params)) {
        $states += , @(('file ' + $f), $(if (Test-Path -LiteralPath $f) { 'PRESENT' } else { 'GONE' }))
    }
    , $states
}

# Logs each artifact of the given steps; returns how many are not confirmed gone.
function Measure-Leftovers($Steps) {
    $left = 0
    foreach ($s in $Steps) {
        foreach ($a in (Get-StepArtifactStates $s)) {
            $mark = switch ($a[1]) { 'GONE' { 'GONE' } 'PRESENT' { 'STILL PRESENT <<<' } default { 'CHECK FAILED <<<' } }
            L ('  [' + $s.id + '] ' + $a[0].PadRight(40) + ' : ' + $mark)
            if ($a[1] -ne 'GONE') { $left++ }
        }
    }
    return $left
}

function Remove-Steps($Steps) {
    $ordered = @($Steps)
    [array]::Reverse($ordered)
    foreach ($s in $ordered) { Remove-StepArtifacts $s }
}

if ($Cleanup) {
    $owned = Get-OwnedIds
    $targets = @($spec.steps | Where-Object { $Force -or ($owned -contains [string]$_.id) })
    L ('=== cleanup: ' + $spec.name + ' (' + $(if ($Force) { 'forced: every named artifact' } else { 'steps recorded in ' + $ownedFile }) + ') ===')
    L ('local ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss K'))
    Remove-Steps $targets
    L ''
    L '--- verification (every line should say GONE) ---'
    $left = Measure-Leftovers $targets
    if ($left -eq 0) { Save-OwnedIds @() }
    L ''
    L ('DONE cleanup steps=' + $targets.Count + ' left=' + $left)
    Write-Host ('DONE cleanup steps=' + $targets.Count + ' left=' + $left + ' -> read ' + $log)
    if ($left -gt 0) { exit 1 }
    exit 0
}

# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------
L ('=== scenario: ' + $spec.name + ' ===')
L ''
L '--- prologue: remove what an earlier run of this scenario created ---'
$owned = @(Get-OwnedIds)
Remove-Steps @($spec.steps | Where-Object { $owned -contains [string]$_.id })
L ''
L '--- collision check: every artifact this scenario names must be absent ---'
if ((Measure-Leftovers @($spec.steps | Where-Object { Test-StepCreates $_ })) -gt 0) {
    L ''
    L 'REFUSED: an artifact above exists but was not created by this scenario (or could not be checked).'
    L 'Rename it in the scenario, or remove it yourself; -Cleanup -Force removes same-named artifacts.'
    Write-Host ('REFUSED: name collision with existing guest state -> read ' + $log)
    exit 2
}
Save-OwnedIds @()
Start-Sleep -Seconds 2

$gt = Join-Path $OutDir 'ground_truth.csv'
[IO.File]::WriteAllText($gt, "seq,step,technique,name,start_utc,start_local,end_utc,end_local,expect_sysmon,expect_security,expect_other,observed_output`r`n", $utf8)
$t0l = Get-Date
L ''
L '=== simulation window opens ==='
L ('start_local : ' + $t0l.ToString('yyyy-MM-dd HH:mm:ss.fff K'))
L ('start_utc   : ' + $t0l.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss.fff') + 'Z')

$seq = 0
foreach ($s in $spec.steps) {
    $seq++
    $sl = Get-Date
    L ''
    L ('--- [' + $s.id + '] (' + $s.technique + ') ' + $s.name)
    Write-Host ('STEP ' + ([string]$s.id).PadRight(4) + ' (' + $s.technique + ') ' + $s.name)
    # recorded BEFORE the step runs, so a step that fails halfway is still cleaned up
    if (Test-StepCreates $s) { $owned = @(Get-OwnedIds) + [string]$s.id; Save-OwnedIds $owned }
    $note = try { (& $Kinds[[string]$s.kind].Run $s.params 2>&1 | Out-String) } catch { 'THREW: ' + $_.Exception.Message }
    Start-Sleep -Milliseconds 800
    $el = Get-Date
    $note = (($note -replace '\s+', ' ').Trim())
    if ($note.Length -gt 400) { $note = $note.Substring(0, 400) }
    $exp = $s.expect
    L ('    expected: SYSMON[' + $exp.sysmon + '] SECURITY[' + $exp.security + '] OTHER[' + $exp.other + ']')
    L ('    observed: ' + $note)
    $row = @($seq, $s.id, $s.technique, $s.name,
        $sl.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss.fff'), $sl.ToString('yyyy-MM-dd HH:mm:ss.fff'),
        $el.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss.fff'), $el.ToString('yyyy-MM-dd HH:mm:ss.fff'),
        $exp.sysmon, $exp.security, $exp.other, $note) | ForEach-Object { Q ([string]$_) }
    [IO.File]::AppendAllText($gt, ($row -join ',') + "`r`n", $utf8)
}

$t1l = Get-Date
$win = @(
    ('scenario    = ' + $spec.name)
    ('start_local = ' + $t0l.ToString('yyyy-MM-dd HH:mm:ss.fff K'))
    ('start_utc   = ' + $t0l.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss.fff') + 'Z')
    ('end_local   = ' + $t1l.ToString('yyyy-MM-dd HH:mm:ss.fff K'))
    ('end_utc     = ' + $t1l.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss.fff') + 'Z')
    ('steps       = ' + $seq)
    ('local tz    = ' + [TimeZoneInfo]::Local.Id)
    'NOTE        = the prologue reset before start_utc also generates events; treat them as setup noise'
)
[IO.File]::WriteAllLines((Join-Path $OutDir 'window.txt'), $win, $utf8)
L ''
L ('DONE scenario steps=' + $seq + ' elapsed=' + [math]::Round(($t1l - $t0l).TotalSeconds, 1) + 's')
Write-Host ('DONE scenario steps=' + $seq + ' -> ' + $gt)
