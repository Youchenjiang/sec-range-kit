# Reverse

## Triage

```bash
file chall ; checksec --file=chall        # arch, stripped?, protections
strings -n 6 chall | grep -iE 'flag|correct|wrong|key|pass'
ltrace ./chall ; strace -f ./chall       # library and system calls (strcmp often leaks the answer)
upx -d chall                             # "UPX!" in strings: unpack first
```

## Static

| Target | Tool |
|---|---|
| ELF / PE native | Ghidra (`ghidraRun`): decompile `main`, rename variables as you go |
| .NET (`file` says Mono/.Net assembly) | dnSpyEx: decompiles to C#, can edit and re-run |
| Java `.jar` / Android `.apk` | `jadx-gui` / unzip + `jd-gui` |
| Python `.pyc` / PyInstaller exe | `pyinstxtractor.py` then `pycdc` / `decompyle3` |
| Quick look | `r2 -A chall` then `afl`, `pdf @ main`, `iz` (strings) |

## Dynamic (gdb + pwndbg)

```text
gdb ./chall
b *main+123     r     ni / si     x/32gx $rsp     x/s $rdi     finish     set $rax=0
```

## Common shapes

- Input checked byte by byte against a transformed constant: invert the transform in Python, or let z3 solve it:

```python
from z3 import BitVec, Solver, sat
flag = [BitVec(f"c{i}", 8) for i in range(32)]
s = Solver()
for c in flag: s.add(c >= 0x20, c < 0x7f)
# s.add(...) one constraint per check you read in the decompiler
if s.check() == sat: print(bytes(s.model()[c].as_long() for c in flag))
```

- XOR with a repeating key, ROT/Caesar, base64 with a custom alphabet: copy the table out of the binary.
- Anti-debug (`ptrace(PTRACE_TRACEME)`, `IsDebuggerPresent`): patch the jump in Ghidra or `set $rax=0` after the call.
- angr when the path is long but the check is pure computation (install it in the venv only when needed: `pip install angr`).
