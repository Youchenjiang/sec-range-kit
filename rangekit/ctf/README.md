# rangekit.ctf

Jeopardy CTF kit: install the toolchain, then solve with the cheat sheets and templates.
Categories: Reverse, Web, Pwn, Crypto, Misc, Forensic.

## Before the event

Work through [CHECKLIST.zh-TW.md](CHECKLIST.zh-TW.md) on every laptop (network adapter, accounts that
must not need a phone, toolchain, snapshot, roles).

## Solving folder on the event laptop

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File rangekit\ctf\setup\ctf_workspace.ps1 -Workspace C:\Users\<you>\Downloads\Sec
```

```text
Sec\
├── START.md            one table: category -> folder, first move, tools, template
├── new-challenge.ps1   .\new-challenge.ps1 pwn babyrop  ->  pwn\babyrop\ with notes.md + template
├── CLAUDE.md           the layout and rules, for Claude Code
├── .claude\skills\     the ctf-* skills, loaded by Claude Code started in Sec\
├── cheatsheets\        every sheet, starting with 00-triage.md
├── reverse\ web\ pwn\ crypto\ misc\ forensic\ scenario\
│                       each with _cheatsheet.md, and _*.py templates for web, pwn, crypto
└── sec-range-kit\      the kit itself
```

Rerunning refreshes the kit, skills, START.md, the helper, sheets and templates; challenge folders
and an existing `CLAUDE.md` are never overwritten. `-Branch` picks another branch of the kit;
`-DryRun` previews. Each challenge's `notes.md` uses one format (Given / Tried / Found / Next,
status, flag) so a teammate or Claude Code can take over.

The repository's own `skills/` folder is not loaded by Claude Code automatically: it looks in
`.claude/skills/` under the folder it was started in and under your user profile.

## Install

| Where | Command |
|---|---|
| Ubuntu / Debian / Kali, in a VM or WSL2 | `bash rangekit/ctf/setup/ctf_setup.sh --with-wordlists --with-pwndbg` |
| Some categories only | `bash rangekit/ctf/setup/ctf_setup.sh --only pwn,crypto` |
| Preview | `bash rangekit/ctf/setup/ctf_setup.sh --dry-run` |
| Windows host (GUI tools) | `powershell -NoProfile -ExecutionPolicy Bypass -File rangekit\ctf\setup\ctf_windows_gui.ps1` |

- Linux: apt packages one by one (a name the distribution lacks is skipped and listed at the end), Python
  tools in `~/ctf-venv` (`source ~/ctf-venv/bin/activate`), Ruby gems with `--user-install`, git checkouts
  in `~/ctf-tools`. Rerunning skips what is installed; exit 3 means something did not install.
- Windows: Git, Python, Java 21, Burp Suite Community, Wireshark, 7-Zip, HxD and VS Code via winget;
  Ghidra, dnSpyEx and CyberChef (offline HTML) from their latest GitHub release into `%USERPROFILE%\ctf-tools`.

## During the event

| Need | File |
|---|---|
| First five minutes on any challenge | [cheatsheets/00-triage.md](cheatsheets/00-triage.md) |
| Category sheets | [reverse](cheatsheets/reverse.md), [pwn](cheatsheets/pwn.md), [crypto](cheatsheets/crypto.md), [web](cheatsheets/web.md), [forensic](cheatsheets/forensic.md), [misc](cheatsheets/misc.md) |
| pwntools exploit skeleton (local / GDB / REMOTE) | [templates/pwn_exploit.py](templates/pwn_exploit.py) |
| RSA, XOR, CRT and root helpers (stdlib only, self-test) | [templates/crypto_helpers.py](templates/crypto_helpers.py) |
| requests session with Burp switch and flag finder | [templates/web_session.py](templates/web_session.py) |

With Claude Code, the `ctf-*` skills in `skills/` cover each category's techniques; point it at the
challenge folder and ask for a script that prints the flag, then run and check it yourself.

Forensic challenges can also use the DFIR parsers in `rangekit/dfir/` and the Windows collectors in
`rangekit/vm/collect/`.
