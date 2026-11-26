# START HERE

New challenge: `.\new-challenge.ps1 <category> <name>` (PowerShell in this folder) creates
`<category>\<name>\` with `notes.md` and the category template, then opens it.
Every category folder starts with `_cheatsheet.md` (and `_*.py` templates where they exist).

| Category | First move | Main tools | Template |
|---|---|---|---|
| [reverse](reverse/_cheatsheet.md) | `file`, `strings`, `ltrace` | Ghidra, dnSpyEx (.NET), gdb + pwndbg, z3 | - |
| [web](web/_cheatsheet.md) | read source and JS, `ffuf`, Burp proxy | Burp Suite, sqlmap, ffuf, flask-unsign | `_web_session.py` |
| [pwn](pwn/_cheatsheet.md) | `checksec`, find the offset with `cyclic` | pwntools, gdb + pwndbg, ROPgadget, one_gadget | `_pwn_exploit.py` |
| [crypto](crypto/_cheatsheet.md) | identify the scheme and the weak parameter | crypto_helpers, z3, SageMath, CyberChef | `_crypto_helpers.py` |
| [misc](misc/_cheatsheet.md) | CyberChef Magic, `file`, `binwalk` | CyberChef, zbarimg, bkcrack, pwntools for services | - |
| [forensic](forensic/_cheatsheet.md) | `file`, `exiftool`, `binwalk -e` | Wireshark/tshark, Volatility 3, zsteg, steghide, foremost | - |
| [scenario](scenario/_cheatsheet.md) | read the story, list the artifacts | as forensic, plus the DFIR parsers in `sec-range-kit\rangekit\dfir` | - |

Stuck for 20 minutes: write what you tried in `notes.md`, tell the team, switch.

## Where things run

- Windows host: Ghidra, dnSpyEx, Burp Suite, Wireshark, HxD, CyberChef (`%USERPROFILE%\ctf-tools`).
- Linux VM / WSL2: everything else, after `source ~/ctf-venv/bin/activate`.
  This folder is `/mnt/c/Users/<you>/Downloads/Sec` from WSL2; copy pwn binaries into the Linux home first.

## With Claude Code

Start it in this folder (`claude`); it reads `CLAUDE.md` and the `ctf-*` skills in `.claude\skills`.
Point it at one challenge folder and ask for a script that prints the flag; run it yourself.
