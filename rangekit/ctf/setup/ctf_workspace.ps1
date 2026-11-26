# ctf_workspace.ps1 - prepare a solving folder on the event laptop.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File ctf_workspace.ps1 -Workspace C:\Users\me\Downloads\Sec
#
# Run it from a sec-range-kit checkout, or let it clone one. It creates:
#   <Workspace>\sec-range-kit\              the kit (cloned, or fast-forwarded when present);
#                                           -Kit <path> keeps it elsewhere, e.g. one kit shared
#                                           by several event folders (Sec\tools\sec-range-kit)
#   <Workspace>\.claude\skills\ctf-*\       the CTF skills, so Claude Code started in <Workspace> loads them
#   <Workspace>\START.md                    one table: category -> folder, first move, tools, template
#   <Workspace>\new-challenge.ps1           .\new-challenge.ps1 pwn babyrop -> folder + notes.md + template
#                                           + Writeups\pwn_babyrop.md (from writeup-template.md)
#   <Workspace>\Writeups\                   one write-up per challenge (never overwritten)
#   <Workspace>\kali.ps1                    .\kali.ps1 <command> -> runs it in Kali (WSL2, or -Vm over SSH)
#   <Workspace>\CLAUDE.md                   layout and tool rules for Claude Code (kit-managed)
#   <Workspace>\.mcp.json                   Burp MCP for Claude Code (written once, then left alone)
#   <Workspace>\MCP_SETUP.zh-TW.md          how to connect the IDA Pro and Burp MCP servers
#   <Workspace>\cheatsheets\                every sheet, including 00-triage.md
#   <Workspace>\<category>\_cheatsheet.md   the category's sheet plus the matching ctf skill's quick start
#   <Workspace>\<category>\_*.py            the category's solve template (web, pwn, crypto)
# Categories: reverse web pwn crypto misc forensic scenario.
# Rerunning refreshes everything the kit manages; challenge folders, .mcp.json and
# CLAUDE.local.md (put your own notes for Claude Code there) are never overwritten.
# ASCII ONLY.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Workspace,
    [string]$RepoUrl = 'https://github.com/Youchenjiang/sec-range-kit.git',
    [string]$Branch = 'main',
    [string]$Kit,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
function Invoke-Step([string]$Label, [scriptblock]$Body) {
    if ($DryRun) { Write-Host ('[dry-run] ' + $Label); return }
    Write-Host $Label
    & $Body
}

$Workspace = [IO.Path]::GetFullPath($Workspace)
$kit = if ($Kit) { [IO.Path]::GetFullPath($Kit) } else { Join-Path $Workspace 'sec-range-kit' }

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
Invoke-Step 'copy START.md, CLAUDE.md, MCP_SETUP.zh-TW.md, writeup-template.md, new-challenge.ps1 and kali.ps1' {
    foreach ($f in @('START.md', 'CLAUDE.md', 'MCP_SETUP.zh-TW.md', 'writeup-template.md', 'new-challenge.ps1', 'kali.ps1')) {
        Copy-Item (Join-Path $ctf ('workspace\' + $f)) $Workspace -Force
    }
    # where the kit lives, for the people and the Claude Code session in this folder
    $kitNote = "`r`n## The kit`r`n`r`n``" + $kit + "`` (all cheat sheets, setup scripts, the ``rangekit\dfir`` parsers).`r`n"
    [IO.File]::AppendAllText((Join-Path $Workspace 'START.md'), $kitNote, (New-Object System.Text.UTF8Encoding($false)))
    New-Item -ItemType Directory -Force -Path (Join-Path $Workspace 'Writeups') | Out-Null
}

# Project-scoped MCP servers for Claude Code started in the workspace. Burp's server is
# local and asks before every request; IDA's comes from the ida-pro-mcp Claude plugin
# (see MCP_SETUP.zh-TW.md). An existing .mcp.json is left alone.
$mcpJson = Join-Path $Workspace '.mcp.json'
if (-not (Test-Path $mcpJson)) {
    Invoke-Step ('write ' + $mcpJson) {
        $mcp = '{' + "`n" + '  "mcpServers": {' + "`n" + '    "burp": { "type": "http", "url": "http://127.0.0.1:9876/mcp" }' + "`n" + '  }' + "`n" + '}' + "`n"
        [IO.File]::WriteAllText($mcpJson, $mcp, (New-Object System.Text.UTF8Encoding($false)))
    }
}

# Sections of a ctf-* SKILL.md worth having next to the challenges: how to start, and when to change course.
$skillSections = '^## (Quick Start Commands|Quick Wins|First-Pass Workflow|Problem-Solving Workflow|When to Pivot)'

# The start-here and when-to-pivot sections of one skill, plus its bundled scripts, as markdown.
function Get-SkillDigest([string]$Skill) {
    $skillDir = Join-Path (Join-Path $kit 'skills') $Skill
    $entry = Join-Path $skillDir 'SKILL.md'
    if (-not (Test-Path $entry)) { return '' }
    $out = New-Object System.Collections.Generic.List[string]
    $out.Add('---')
    $out.Add('')
    $out.Add('# From the ' + $Skill + ' skill')
    $out.Add('')
    $out.Add('Extracted from `.claude\skills\' + $Skill + '\SKILL.md` (third-party, licence and source in `sec-range-kit\skills\SOURCES.json`). The full skill and its reference pages are in that folder.')
    $out.Add('')
    $keep = $false
    $inFence = $false
    foreach ($line in [IO.File]::ReadAllLines($entry)) {
        if ($line -match '^```') { $inFence = -not $inFence }
        if (-not $inFence -and $line -match '^## ') { $keep = $line -match $skillSections }
        if ($keep) { $out.Add($line) }
    }
    $scripts = Join-Path $skillDir 'scripts'
    if (Test-Path $scripts) {
        $out.Add('')
        $out.Add('## Ready-made scripts in this skill')
        $out.Add('')
        foreach ($s in (Get-ChildItem $scripts -File | Sort-Object Name)) { $out.Add('- `.claude\skills\' + $Skill + '\scripts\' + $s.Name + '`') }
    }
    return ($out -join "`r`n")
}

# category -> sheets (concatenated into _cheatsheet.md), template (copied as _<name>.py), skill digests
$layout = [ordered]@{
    reverse  = @(@('reverse.md'), $null, @('ctf-reverse'))
    web      = @(@('web.md'), 'web_session.py', @('ctf-web'))
    pwn      = @(@('pwn.md'), 'pwn_exploit.py', @('ctf-pwn'))
    crypto   = @(@('crypto.md'), 'crypto_helpers.py', @('ctf-crypto'))
    misc     = @(@('misc.md'), $null, @('ctf-misc'))
    forensic = @(@('forensic.md'), $null, @('ctf-forensics'))
    scenario = @(@('00-triage.md', 'forensic.md'), $null, @('ctf-forensics', 'ctf-osint'))
}
foreach ($c in $layout.Keys) {
    $dir = Join-Path $Workspace $c
    Invoke-Step ('prepare ' + $dir) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $parts = @(foreach ($sheet in $layout[$c][0]) { [IO.File]::ReadAllText((Join-Path $sheets $sheet)) })
        $parts += @(foreach ($skill in $layout[$c][2]) { Get-SkillDigest $skill })
        [IO.File]::WriteAllText((Join-Path $dir '_cheatsheet.md'), ($parts -join "`r`n`r`n"), (New-Object System.Text.UTF8Encoding($false)))
        $tpl = $layout[$c][1]
        if ($tpl) { Copy-Item (Join-Path $ctf ('templates\' + $tpl)) (Join-Path $dir ('_' + $tpl)) -Force }
    }
}

Write-Host ''
Write-Host ('workspace ready: ' + $Workspace + '  (open START.md)')
Write-Host ('start Claude Code there:  cd "' + $Workspace + '"; claude')
