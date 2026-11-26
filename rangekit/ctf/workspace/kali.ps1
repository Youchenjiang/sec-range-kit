# kali.ps1 - run one Linux command in Kali, from the current challenge folder.
#
#   .\kali.ps1 file chall                         # WSL2 Kali (default)
#   .\kali.ps1 "checksec --file=chall && python3 exploit.py"
#   .\kali.ps1 -Vm "binwalk -e x.bin"             # Kali VM over SSH instead
#
# The one way Claude Code and teammates reach the Linux tools, so every call sees
# the same environment: the command runs in bash with ~/ctf-venv activated, in the
# Linux path of the current Windows folder (WSL: /mnt/c/...; VM: the same relative
# path under $KaliShare). Exit code is the command's own.
#
# Settings, also readable from environment variables:
#   -Distro   / CTF_KALI_DISTRO   WSL distribution name (default kali-linux)
#   -SshHost  / CTF_KALI_SSH      user@host of the Kali VM, for -Vm
#   -Share    / CTF_KALI_SHARE    path in the VM where this workspace is mounted, for -Vm
# ASCII ONLY.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Command,
    [switch]$Vm,
    [string]$Distro = $(if ($env:CTF_KALI_DISTRO) { $env:CTF_KALI_DISTRO } else { 'kali-linux' }),
    [string]$SshHost = $env:CTF_KALI_SSH,
    [string]$Share = $env:CTF_KALI_SHARE
)

$ErrorActionPreference = 'Stop'
$line = $Command -join ' '
$here = (Get-Location).ProviderPath
$prelude = 'if [ -f ~/ctf-venv/bin/activate ]; then . ~/ctf-venv/bin/activate; fi; export PATH="$PATH:$(gem env user_gemhome 2>/dev/null)/bin"'

if ($Vm) {
    if (-not $SshHost) { throw 'set -SshHost user@host (or CTF_KALI_SSH) for the Kali VM' }
    $workspace = $PSScriptRoot
    $cd = '~'
    if ($Share -and $here.StartsWith($workspace, [StringComparison]::OrdinalIgnoreCase)) {
        $rel = $here.Substring($workspace.Length).TrimStart('\').Replace('\', '/')
        $cd = ($Share.TrimEnd('/') + '/' + $rel).TrimEnd('/')
    }
    $remote = "cd '" + $cd.Replace("'", "'\''") + "' && " + $prelude + '; ' + $line
    & ssh $SshHost $remote
    exit $LASTEXITCODE
}

if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) { throw 'wsl not found: install WSL2 or use -Vm' }
$known = (& wsl -l -q 2>$null | Out-String) -replace "`0", ''
if ($known -notmatch ('(?m)^\s*' + [regex]::Escape($Distro) + '\s*$')) {
    throw ('WSL distribution "' + $Distro + '" not found; installed: ' + (($known -split '\s+' | Where-Object { $_ }) -join ', ') + '. Use -Distro or -Vm.')
}
# --cd takes the Windows path; WSL maps it to /mnt/<drive>/...
& wsl -d $Distro --cd $here -- bash -lc ($prelude + '; ' + $line)
exit $LASTEXITCODE
