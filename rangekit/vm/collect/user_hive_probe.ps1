# user_hive_probe.ps1 - find WHICH user hive the guest artifacts actually live in.
#
# Under a non-interactive vmrun session, HKCU can resolve to HKU\.DEFAULT instead
# of the logged-on user, which makes UserAssist / ConsentStore look "MISSING" when
# they are not. This probe addresses the user hive by SID explicitly.
# -UserName additionally checks C:\Users\<UserName>\NTUSER.DAT (for example the
# interactive account when vmrun runs as another user); -Sid probes that SID
# instead of the current identity.
#
# ASCII ONLY.

[CmdletBinding()]
param(
    [string]$UserName = '',
    [string]$Sid = ''
)

$ErrorActionPreference = 'Continue'
function Show-Message([string]$m) { Write-Host $m }

Show-Message '=== whoami /user ==='
& whoami.exe /user 2>&1 | ForEach-Object { Show-Message $_ }

Show-Message ''
Show-Message '=== HKU loaded hives ==='
& reg.exe query HKU 2>&1 | ForEach-Object { Show-Message $_ }

Show-Message ''
Show-Message '=== user profile files ==='
$files = @("$env:USERPROFILE\NTUSER.DAT", "$env:USERPROFILE\NTUSER.DAT.LOG1")
if ($UserName) { $files += (Join-Path (Split-Path $env:USERPROFILE -Parent) (Join-Path $UserName 'NTUSER.DAT')) }
foreach ($f in $files) {
    if (Test-Path $f) {
        Show-Message ('  EXISTS ' + $f + '  ' + [math]::Round((Get-Item $f).Length / 1MB, 2) + ' MB  ' + (Get-Item $f).LastWriteTimeUtc.ToString('yyyy-MM-dd HH:mm:ss') + 'Z')
    } else { Show-Message ('  MISSING ' + $f) }
}

if (-not $Sid) { $Sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value }
Show-Message ''
Show-Message ('=== artifacts under HKU\' + $Sid + ' ===')
foreach ($rel in @(
    'Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist',
    'Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone',
    'Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam'
)) {
    # Registry:: provider path; there is no HKU: drive by default.
    $p = "Registry::HKEY_USERS\$Sid\$rel"
    if (Test-Path $p) {
        $subs = @(Get-ChildItem $p -ErrorAction SilentlyContinue)
        Show-Message ('  PRESENT ' + $rel + '  subkeys=' + $subs.Count)
        foreach ($s in $subs) { Show-Message ('      ' + $s.PSChildName) }
    } else { Show-Message ('  ABSENT  ' + $rel) }
}

Show-Message ''
Show-Message '=== HKLM USBSTOR (explicit) ==='
& reg.exe query 'HKLM\SYSTEM\CurrentControlSet\Enum\USBSTOR' 2>&1 | ForEach-Object { Show-Message ('  ' + $_) }

Show-Message ''
Show-Message '=== setupapi.dev.log USB lines (device install history) ==='
$log = "$env:SystemRoot\inf\setupapi.dev.log"
if (Test-Path $log) {
    $lines = Get-Content $log -ErrorAction SilentlyContinue
    Show-Message ('  total lines = ' + @($lines).Count)
    foreach ($h in ($lines | Select-String -Pattern 'USB' -SimpleMatch | Select-Object -First 15)) { Show-Message ('  | ' + $h.Line.Trim()) }
} else { Show-Message '  setupapi.dev.log MISSING' }

Show-Message ''
Show-Message 'DONE user_hive_probe'
