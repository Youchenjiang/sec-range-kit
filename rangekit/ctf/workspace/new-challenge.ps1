# new-challenge.ps1 - start a challenge: folder, notes and the category template.
#
#   .\new-challenge.ps1 pwn babyrop
#   .\new-challenge.ps1 web login-panel -NoOpen
#
# Creates <category>\<name>\ next to this script with notes.md (the shared
# hand-over format), a copy of the category template and
# Writeups\<category>_<name>.md from writeup-template.md, then opens the folder.
# An existing challenge folder is reused; its files are never overwritten.
# ASCII ONLY.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('reverse', 'web', 'pwn', 'crypto', 'misc', 'forensic', 'scenario')]
    [string]$Category,
    [Parameter(Mandatory = $true, Position = 1)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')]
    [string]$Name,
    [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$dir = Join-Path (Join-Path $root $Category) $Name
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$notes = Join-Path $dir 'notes.md'
if (-not (Test-Path $notes)) {
    $now = Get-Date -Format 'HH:mm'
    $text = @(
        ('# ' + $Category + ' / ' + $Name),
        '',
        ('- owner: ' + $env:USERNAME + '    started: ' + $now),
        '- status: open        (open / stuck / solved)',
        '- flag: ',
        '',
        '## Given',
        '- files / URL / host:port: ',
        '- description hint: ',
        '',
        '## Tried',
        '- ',
        '',
        '## Found',
        '- ',
        '',
        '## Next',
        '- '
    )
    [IO.File]::WriteAllLines($notes, $text, (New-Object System.Text.UTF8Encoding($false)))
}

# write-up skeleton, named <category>_<name>.md; the event name is this folder's name
$tplWriteup = Join-Path $root 'writeup-template.md'
$writeup = Join-Path (Join-Path $root 'Writeups') ($Category + '_' + $Name + '.md')
if ((Test-Path $tplWriteup) -and -not (Test-Path $writeup)) {
    New-Item -ItemType Directory -Force -Path (Split-Path $writeup) | Out-Null
    $body = [IO.File]::ReadAllText($tplWriteup, [Text.Encoding]::UTF8)
    $body = $body.Replace('{{NAME}}', $Name).Replace('{{CATEGORY}}', $Category).Replace('{{EVENT}}', (Split-Path $root -Leaf)).Replace('{{OWNER}}', $env:USERNAME)
    [IO.File]::WriteAllText($writeup, $body, (New-Object System.Text.UTF8Encoding($false)))
}

# category template: "_<file>.py" in the category folder -> "<file>.py" in the challenge
foreach ($tpl in (Get-ChildItem (Join-Path $root $Category) -File -Filter '_*.py' -ErrorAction SilentlyContinue)) {
    $target = Join-Path $dir ($tpl.Name.Substring(1))
    if (-not (Test-Path $target)) { Copy-Item $tpl.FullName $target }
}

Write-Host ('ready: ' + $dir)
if (Test-Path $writeup) { Write-Host ('write-up: ' + $writeup) }
Write-Host ('cheat sheet: ' + (Join-Path (Join-Path $root $Category) '_cheatsheet.md'))
if (-not $NoOpen) { Invoke-Item $dir }
