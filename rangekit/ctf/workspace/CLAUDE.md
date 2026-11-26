# CTF solving workspace

Jeopardy CTF in progress. Categories: reverse, web, pwn, crypto, misc, forensic, scenario.
This file is refreshed by ctf_workspace.ps1; put local notes in `CLAUDE.local.md` instead.

## Layout

- `START.md`: category -> folder, first move, tools, template, and where each tool runs.
- One folder per challenge: `<category>\<challenge-name>\`, created by `.\new-challenge.ps1 <category> <name>`.
  Keep the original download untouched; work on copies.
- Keep `notes.md` in the challenge folder current (Given / Tried / Found / Next, status, flag) so a teammate can take over.
- Each category folder has `_cheatsheet.md` (kit sheet plus the matching ctf skill's quick start and when-to-pivot),
  and web / pwn / crypto have a `_*.py` template. All sheets: `cheatsheets\` (start with `00-triage.md`).
- CTF skills: `.claude\skills\ctf-*`. The full kit: the path in the last section of `START.md`.
- `Writeups\<category>_<name>.md` is each challenge's write-up skeleton (`new-challenge.ps1` creates it).

## Where tools run (follow this; do not install duplicates)

- Linux command-line tools (pwntools, gdb, checksec, binwalk, volatility, tshark, sqlmap, hashcat, z3, Python scripts):
  run them in Kali through `.\kali.ps1 <command>` from the challenge folder. It uses the Linux path of the current
  folder and activates `~/ctf-venv`. Do not call `wsl` or `ssh` directly.
- pwn binaries: copy into the Kali home before running them (`/mnt/c` has no exec bits).
- IDA Pro and Burp Suite are the copies installed on this Windows host. Use them through their MCP servers
  (`ida-pro-mcp`, `burp`) when connected; never install Kali's copies.
- Ghidra, Wireshark, HxD, CyberChef are host GUI tools: ask the user to open them and paste results when needed.

## Rules

- Prefer a script that prints the flag; show the flag and how it was obtained. The user submits flags.
- When a challenge is solved, fill in its write-up at once: the commands actually run, the full solve script,
  evidence paths, the flag. Organizers may require write-ups and disqualify teams that cannot show their work.
- Only interact with the challenge targets. No scanning or attacks against anything else, including the event platform.
- Burp MCP asks before sending requests; do not ask the user to switch that approval off.
