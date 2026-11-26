# START HERE

New challenge: `.\new-challenge.ps1 <category> <name>` (PowerShell in this folder) creates
`<category>\<name>\` with `notes.md` and the category template, then opens it.
Every category folder starts with `_cheatsheet.md` (and `_*.py` templates where they exist).

| Category | First move | Main tools | Template |
|---|---|---|---|
| [reverse](reverse/_cheatsheet.md) | `file`, `strings`, `ltrace` | Ghidra/IDA, dnSpyEx (.NET), jadx (APK), pyinstxtractor + pycdc (Python exe), gdb + pwndbg, z3 | - |
| [web](web/_cheatsheet.md) | read source and JS, `ffuf`, Burp proxy | Burp Suite, sqlmap, ffuf, flask-unsign, jwt_tool, git-dumper | `_web_session.py` |
| [pwn](pwn/_cheatsheet.md) | `checksec`, find the offset with `cyclic` | pwntools, gdb + pwndbg, ROPgadget, one_gadget, libc-database | `_pwn_exploit.py` |
| [crypto](crypto/_cheatsheet.md) | identify the scheme and the weak parameter | crypto_helpers, z3, SageMath, CyberChef | `_crypto_helpers.py` |
| [misc](misc/_cheatsheet.md) | CyberChef Magic, `file`, `binwalk` | CyberChef, zbarimg, bkcrack, pwntools for services | - |
| [forensic](forensic/_cheatsheet.md) | `file`, `exiftool`, `binwalk -e` | Wireshark/tshark, Volatility 3, zsteg, steghide + stegseek, foremost | - |
| [scenario](scenario/_cheatsheet.md) | read the story, list the artifacts | as forensic, plus the DFIR parsers in `sec-range-kit\rangekit\dfir` | - |

Stuck for 20 minutes: write what you tried in `notes.md`, tell the team, switch.

## Where each tool runs (one rule, no duplicates)

| Tool | Runs on | How a person uses it | How Claude Code uses it |
|---|---|---|---|
| IDA Pro | Windows host (the installed copy) | GUI | IDA MCP (`ida-pro-mcp`), when the plugin is running in IDA |
| Burp Suite | Windows host (the installed copy) | GUI, proxy 127.0.0.1:8080 | Burp MCP at `http://127.0.0.1:9876/mcp` (asks before sending requests) |
| Ghidra, dnSpyEx, jadx-gui, Wireshark, HxD, CyberChef | Windows host | GUI | not directly: paste the result, or use the Kali CLI equivalent |
| pwntools, gdb/pwndbg, checksec, ROPgadget, binwalk, volatility, tshark, sqlmap, hashcat, z3, bkcrack, pycdc, stegseek, ... | Kali (WSL2 first, VM as backup) | `.\kali.ps1 <command>` | `.\kali.ps1 <command>` from the challenge folder |
| Python helpers in this folder (`*_helpers.py`, templates) | Kali | `.\kali.ps1 python3 x.py` | same |

- Do not use Kali's copies of Ghidra or Burp; the host has them.
- `kali.ps1` runs in the Linux path of the current folder with `~/ctf-venv` active. `-Vm` uses the Kali VM over SSH
  (set `CTF_KALI_SSH=user@host` and `CTF_KALI_SHARE=<workspace path in the VM>`).
- Script tools are cloned in `~/ctf-tools` (`python3 ~/ctf-tools/jwt_tool/jwt_tool.py`, `~/ctf-tools/pyinstxtractor/pyinstxtractor.py`,
  `~/ctf-tools/libc-database/find`); pycdc and bkcrack are in `~/.local/bin`.
- pwn binaries: copy into the Kali home before running (`/mnt/c` has no exec bits and is slow).

## With Claude Code

Start it in this folder (`claude`); it reads `CLAUDE.md`, the `ctf-*` skills in `.claude\skills` and the MCP servers in `.mcp.json`
(approve them on first use; `claude mcp list` shows what is connected).
Point it at one challenge folder and ask for a script that prints the flag; run it yourself.
