# Misc

## Encodings and esoteric

- CyberChef (offline copy from `ctf_windows_gui.ps1`): **Magic** first, then stack operations.
- Esoteric languages: Brainfuck (`+-<>[].,`), Ook, Whitespace, Piet (image of colour blocks), Malbolge.
- Unicode tricks: zero-width characters (`cat -A`, `python3 -c "print(open('x').read().encode('unicode_escape'))"`), homoglyphs.

## Jails

| Jail | Escape ideas |
|---|---|
| Python `eval`/`exec` with filters | `__import__('os').system('sh')`, `().__class__.__base__.__subclasses__()`, `breakpoint()`, unicode-normalised names (`ｅval`) |
| bash restricted | `vi` / `less` `:!sh`, `$0`, globbing `/???/??t /???/???g*` |

## Interactive services

```python
from pwn import remote
io = remote("host", 1337)
while True:                          # e.g. answer 100 maths questions
    line = io.recvline(timeout=5)
    if not line: break
    print(line)
    # parse, compute, io.sendline(str(answer).encode())
```

## OSINT-flavoured

- Reverse image search (Google Lens, Yandex), EXIF GPS (`exiftool -n -GPS* x.jpg`), Wayback Machine, username search across sites.

## Archives

```bash
7z l x.zip ; zipinfo x.zip              # names, methods (ZipCrypto vs AES)
john: zip2john x.zip > h ; john h --wordlist=rockyou.txt
bkcrack -C x.zip -c known.txt -P known.zip -p known.txt   # ZipCrypto + known plaintext
```
