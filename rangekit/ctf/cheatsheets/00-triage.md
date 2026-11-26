# First five minutes on any challenge

1. Read the description twice; note the flag format, any hint, any port.
2. Make a folder per challenge: `mkdir -p ~/ctf/<category>-<name> && cd $_`, keep the original download untouched.
3. Identify every file:

```bash
file *            # what it really is, regardless of the extension
strings -n 6 x | less ; strings -el x | less    # ASCII, then UTF-16LE strings
grep -aoE '[A-Za-z0-9_]{2,16}\{[^}]{3,100}\}' -r .   # flag-shaped strings anywhere
exiftool x ; binwalk x ; xxd x | head            # metadata, embedded files, magic bytes
```

4. Pick the category sheet: [reverse](reverse.md), [pwn](pwn.md), [crypto](crypto.md), [web](web.md), [forensic](forensic.md), [misc](misc.md).
5. Stuck for 20 minutes? Write what you tried in the challenge notes and hand it over or switch.

## Asking Claude Code

- Give it the challenge folder and the exact goal: "find the flag in ./chall; notes in notes.md".
- The `ctf-*` skills in `skills/` hold per-category techniques (ctf-pwn, ctf-crypto, ctf-web, ctf-reverse, ctf-forensics, ctf-misc, ctf-osint).
- Ask for a script that prints the flag, then run it yourself and check the output.
