# ctf_workspace.ps1 - prepare a solving folder on the event laptop.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File ctf_workspace.ps1 -Workspace C:\Users\me\Downloads\Sec
#
# Run it from a sec-range-kit checkout, or let it clone one. It creates:
#   <Workspace>\sec-range-kit\              the kit (cloned, or fast-forwarded when present)
#   <Workspace>\.claude\skills\ctf-*\       the CTF skills, so Claude Code started in <Workspace> loads them
#   <Workspace>\START.md                    one table: category -> folder, first move, tools, template
#   <Workspace>\new-challenge.ps1           .\new-challenge.ps1 pwn babyrop -> folder + notes.md + template
#   <Workspace>\CLAUDE.md                   how this folder is laid out, for Claude Code
#   <Workspace>\cheatsheets\                every sheet, including 00-triage.md
#   <Workspace>\<category>\_cheatsheet.md   the category's sheet (scenario: triage + forensic)
#   <Workspace>\<category>\_*.py            the category's solve template (web, pwn, crypto)
# Categories: reverse web pwn crypto misc forensic scenario.
# Rerunning refreshes the kit, skills, START.md, the helper, sheets and templates;
# challenge folders and an existing CLAUDE.md are never overwritten.
# ASCII ONLY.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Workspace,
    [string]$RepoUrl = 'https://github.com/Youchenjiang/sec-range-kit.git',
    [string]$Branch = 'main',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
function Invoke-Step([string]$Label, [scriptblock]$Body) {
    if ($DryRun) { Write-Host ('[dry-run] ' + $Label); return }
    Write-Host $Label
    & $Body
}

$Workspace = [IO.Path]::GetFullPath($Workspace)
$kit = Join-Path $Workspace 'sec-range-kit'

Invoke-Step ('create ' + $Workspace) { New-Item -ItemType Directory -Force -Path $Workspace | Out-Null }

if (Test-Path (Join-Path $kit '.git')) {
    Invoke-Step ('update kit in ' + $kit) {
        & git -C $kit fetch -q origin $Branch
        & git -C $kit checkout -q $Branch
        & git -C $kit pull -q --ff-only origin $Branch
        if ($LASTEXITCODE -ne 0) { throw 'git pull failed; local changes in the kit?' }
    }
} else {
    Invoke-Step ('clone ' + $RepoUrl + ' (' + $Branch + ') into ' + $kit) {
        & git clone -q --branch $Branch $RepoUrl $kit
        if ($LASTEXITCODE -ne 0) { throw 'git clone failed' }
    }
}

# Copy a folder's CONTENTS: Copy-Item of a folder onto an existing one nests it
# (dest\name\name) on every rerun.
function Copy-FolderContent([string]$From, [string]$To) {
    New-Item -ItemType Directory -Force -Path $To | Out-Null
    Copy-Item -Path (Join-Path $From '*') -Destination $To -Recurse -Force
}

$skillsDest = Join-Path $Workspace '.claude\skills'
Invoke-Step ('copy ctf-* skills into ' + $skillsDest) {
    foreach ($skill in (Get-ChildItem (Join-Path $kit 'skills') -Directory -Filter 'ctf-*')) {
        Copy-FolderContent $skill.FullName (Join-Path $skillsDest $skill.Name)
    }
}

$ctf = Join-Path $kit 'rangekit\ctf'
$sheets = Join-Path $ctf 'cheatsheets'
Invoke-Step 'copy cheat sheets' { Copy-FolderContent $sheets (Join-Path $Workspace 'cheatsheets') }
Invoke-Step 'copy START.md and new-challenge.ps1' {
    Copy-Item (Join-Path $ctf 'workspace\START.md') $Workspace -Force
    Copy-Item (Join-Path $ctf 'workspace\new-challenge.ps1') $Workspace -Force
}

# category -> sheets (concatenated into _cheatsheet.md) and template (copied as _<name>.py)
$layout = [ordered]@{
    reverse  = @(@('reverse.md'), $null)
    web      = @(@('web.md'), 'web_session.py')
    pwn      = @(@('pwn.md'), 'pwn_exploit.py')
    crypto   = @(@('crypto.md'), 'crypto_helpers.py')
    misc     = @(@('misc.md'), $null)
    forensic = @(@('forensic.md'), $null)
    scenario = @(@('00-triage.md', 'forensic.md'), $null)
}
foreach ($c in $layout.Keys) {
    $dir = Join-Path $Workspace $c
    Invoke-Step ('prepare ' + $dir) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $parts = foreach ($sheet in $layout[$c][0]) { [IO.File]::ReadAllText((Join-Path $sheets $sheet)) }
        [IO.File]::WriteAllText((Join-Path $dir '_cheatsheet.md'), ($parts -join "`r`n`r`n"), (New-Object System.Text.UTF8Encoding($false)))
        $tpl = $layout[$c][1]
        if ($tpl) { Copy-Item (Join-Path $ctf ('templates\' + $tpl)) (Join-Path $dir ('_' + $tpl)) -Force }
    }
}

$guide = Join-Path $Workspace 'CLAUDE.md'
if (-not (Test-Path $guide)) {
    Invoke-Step ('write ' + $guide) {
        $text = @(
            '# CTF solving workspace',
            '',
            'Jeopardy CTF in progress. Categories: reverse, web, pwn, crypto, misc, forensic, scenario.',
            '',
            '- Start from `START.md`. One folder per challenge: `<category>\<challenge-name>\`, created by `.\new-challenge.ps1 <category> <name>`. Keep the original download untouched; work on copies.',
            '- Keep `notes.md` in the challenge folder current (Given / Tried / Found / Next, status, flag), so a teammate can take over.',
            '- Each category folder has `_cheatsheet.md`, and web / pwn / crypto have a `_*.py` template (copied into the challenge folder without the underscore). All sheets: `cheatsheets\` (start with `00-triage.md`).',
            '- CTF skills are in `.claude\skills\ctf-*`; the full kit is in `sec-range-kit\`.',
            '- Linux tools live in the VM or WSL2 (`source ~/ctf-venv/bin/activate`). From WSL2 this folder is `/mnt/c/...`; copy pwn binaries into the Linux home before running them.',
            '- Prefer a script that prints the flag; show the flag and how it was obtained. Never attack anything outside the challenge targets.'
        )
        [IO.File]::WriteAllLines($guide, $text, (New-Object System.Text.UTF8Encoding($false)))
    }
}

Write-Host ''
Write-Host ('workspace ready: ' + $Workspace + '  (open START.md)')
Write-Host ('start Claude Code there:  cd "' + $Workspace + '"; claude')
