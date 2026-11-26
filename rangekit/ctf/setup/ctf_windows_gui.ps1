# ctf_windows_gui.ps1 - install the GUI side of a CTF toolchain on the Windows host.
#
# The Linux toolchain (ctf_setup.sh) runs in a VM or WSL2; GUI tools work better
# on the host: Ghidra, Burp Suite, Wireshark, a hex editor, dnSpyEx and CyberChef.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File rangekit\ctf\setup\ctf_windows_gui.ps1 -DryRun
#   powershell -NoProfile -ExecutionPolicy Bypass -File rangekit\ctf\setup\ctf_windows_gui.ps1
#
# winget packages are checked with "winget show" first; an id winget does not
# know is reported and skipped. Ghidra, dnSpyEx and CyberChef come from the
# latest GitHub release and are unpacked under -Dest. Rerunning skips what exists.
# ASCII ONLY.

[CmdletBinding()]
param(
    [string]$Dest = "$env:USERPROFILE\ctf-tools",
    [switch]$DryRun,
    [switch]$SkipWinget,
    [switch]$SkipReleases
)

$ErrorActionPreference = 'Continue'
$failed = New-Object System.Collections.Generic.List[string]

function Show-Step([string]$Message) { Write-Host ''; Write-Host ('=== ' + $Message + ' ===') }

$wingetPackages = [ordered]@{
    'Git.Git'                          = 'git'
    'Python.Python.3.12'               = 'Python 3.12'
    'EclipseAdoptium.Temurin.21.JDK'   = 'Java 21 (Ghidra needs it)'
    'PortSwigger.BurpSuite.Community'  = 'Burp Suite Community'
    'WiresharkFoundation.Wireshark'    = 'Wireshark'
    '7zip.7zip'                        = '7-Zip'
    'MHNexus.HxD'                      = 'HxD hex editor'
    'Microsoft.VisualStudioCode'       = 'VS Code'
}

# repo, asset name pattern, folder under $Dest
$releases = @(
    @('NationalSecurityAgency/ghidra', '^ghidra_.*_PUBLIC_.*\.zip$', 'ghidra'),
    @('dnSpyEx/dnSpy', '^dnSpy-net-win64\.zip$', 'dnSpyEx'),
    @('gchq/CyberChef', '^CyberChef_.*\.zip$', 'CyberChef')
)

# Tools a player may already have, installed some other way: use those, never a second copy.
$searchRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA, (Join-Path $env:LOCALAPPDATA 'Programs'),
    $env:USERPROFILE, (Join-Path $env:USERPROFILE 'Downloads'), (Join-Path $env:USERPROFILE 'Desktop'), 'C:\Tools', $Dest) |
    Where-Object { $_ -and (Test-Path $_) }
function Find-Existing([string]$Pattern, [string]$Leaf) {
    foreach ($root in $searchRoots) {
        $hit = Get-ChildItem $root -Directory -Filter $Pattern -ErrorAction SilentlyContinue |
            Where-Object { -not $Leaf -or (Get-ChildItem $_.FullName -Recurse -Depth 2 -Filter $Leaf -ErrorAction SilentlyContinue | Select-Object -First 1) } |
            Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}
Show-Step 'already installed (used as is)'
$existing = @{
    'IDA Pro' = Find-Existing 'IDA*' 'ida*.exe'
    'Ghidra'  = $(if (Get-Command ghidraRun -ErrorAction SilentlyContinue) { (Get-Command ghidraRun).Source } else { Find-Existing 'ghidra*' 'ghidraRun.bat' })
    'Burp'    = Find-Existing 'BurpSuite*' 'BurpSuite*.exe'
}
foreach ($name in $existing.Keys) {
    Write-Host ('  ' + $name.PadRight(8) + ' ' + $(if ($existing[$name]) { $existing[$name] } else { '(not found)' }))
}
if ($existing['Ghidra']) { $releases = @($releases | Where-Object { $_[2] -ne 'ghidra' }) }
if (-not $existing['IDA Pro']) { Write-Host '  note: IDA Pro is not installed by this script; Ghidra covers decompiling.' }

if (-not $SkipWinget) {
    Show-Step 'winget packages'
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host 'winget not found: install "App Installer" from the Microsoft Store, or use -SkipWinget'
        $failed.Add('winget')
    } else {
        $installed = (& winget list --accept-source-agreements 2>$null | Out-String)
        foreach ($id in $wingetPackages.Keys) {
            $label = $wingetPackages[$id]
            if ($installed -match [regex]::Escape($id)) { Write-Host ('  ok      ' + $label + ' (' + $id + ')'); continue }
            # any Burp edition already present (Professional, or installed outside winget) counts
            if ($id -like 'PortSwigger.BurpSuite.*' -and ($existing['Burp'] -or $installed -match 'PortSwigger\.BurpSuite')) {
                Write-Host ('  ok      Burp Suite already installed; Community not added'); continue
            }
            & winget show --id $id --exact --accept-source-agreements *> $null
            if ($LASTEXITCODE -ne 0) { Write-Host ('  skip    ' + $id + ' is not in the winget catalog'); $failed.Add('winget:' + $id); continue }
            if ($DryRun) { Write-Host ('  [dry-run] winget install --id ' + $id + ' --exact'); continue }
            Write-Host ('  install ' + $label + ' (' + $id + ')')
            & winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements | Out-Null
            if ($LASTEXITCODE -ne 0) { Write-Host ('  FAILED  ' + $id + ' exit=' + $LASTEXITCODE); $failed.Add('winget:' + $id) }
        }
    }
}

if (-not $SkipReleases) {
    Show-Step ('GitHub releases into ' + $Dest)
    if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $Dest | Out-Null }
    foreach ($r in $releases) {
        $target = Join-Path $Dest $r[2]
        if (Test-Path $target) { Write-Host ('  ok      ' + $r[2] + ' (' + $target + ')'); continue }
        try {
            $latest = Invoke-RestMethod -Uri ('https://api.github.com/repos/' + $r[0] + '/releases/latest') -Headers @{ 'User-Agent' = 'rangekit-ctf-setup' } -ErrorAction Stop
            $asset = $latest.assets | Where-Object { $_.name -match $r[1] } | Select-Object -First 1
            if (-not $asset) { throw ('no asset matches ' + $r[1] + ' in ' + $latest.tag_name) }
            if ($DryRun) { Write-Host ('  [dry-run] download ' + $asset.browser_download_url + ' -> ' + $target); continue }
            $zip = Join-Path $env:TEMP $asset.name
            Write-Host ('  download ' + $asset.name + ' (' + $latest.tag_name + ')')
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing -ErrorAction Stop
            Expand-Archive -Path $zip -DestinationPath $target -Force -ErrorAction Stop
            Remove-Item $zip -Force -ErrorAction SilentlyContinue
            Write-Host ('  ok      ' + $r[2] + ' -> ' + $target)
        } catch {
            Write-Host ('  FAILED  ' + $r[0] + ': ' + $_.Exception.Message)
            $failed.Add('release:' + $r[0])
        }
    }
}

Show-Step 'done'
if ($DryRun) { Write-Host 'dry run: nothing was changed' }
if ($existing['Ghidra']) { Write-Host ('Ghidra: use the installed copy at ' + $existing['Ghidra']) }
else { Write-Host ('Ghidra: run ' + (Join-Path $Dest 'ghidra') + '\ghidra_*\ghidraRun.bat (needs the JDK above)') }
if ($existing['IDA Pro']) { Write-Host ('IDA Pro: ' + $existing['IDA Pro'] + '  (MCP setup: MCP_SETUP.zh-TW.md in the solving folder)') }
Write-Host ('CyberChef: open ' + (Join-Path $Dest 'CyberChef') + '\CyberChef_*.html in a browser (works offline)')
if ($failed.Count -gt 0) {
    Write-Host ('not installed (' + $failed.Count + '): ' + ($failed -join ', '))
    exit 3
}
if ($DryRun) { Write-Host 'dry run found every package and release' } else { Write-Host 'everything requested is installed' }
