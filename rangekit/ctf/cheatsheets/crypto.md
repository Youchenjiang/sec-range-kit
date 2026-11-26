# Crypto

Helpers: `rangekit/ctf/templates/crypto_helpers.py` (copy it next to the challenge, `from crypto_helpers import *`).

## Recognise the encoding first

| Looks like | Try |
|---|---|
| `[A-Za-z0-9+/]+={0,2}` | base64 (`base64 -d`), then check `file` on the result |
| only `0-9a-f`, even length | hex (`xxd -r -p`) |
| `[A-Z2-7]+=*` | base32 |
| letters only, word lengths kept | Caesar / ROT13 / Vigenere (CyberChef "Magic") |
| `.-` and spaces | Morse |

CyberChef's **Magic** operation auto-detects stacked encodings.

## RSA: given n, e, c

| Clue | Attack (crypto_helpers) |
|---|---|
| e = 3 and small m | `rsa_small_e(c, 3)` |
| same m, e recipients | `rsa_hastad(cs, ns, e)` |
| same n, two e | `rsa_common_modulus(c1, c2, e1, e2, n)` |
| several n | `shared_prime(n1, n2)` (gcd) |
| p, q close | `fermat_factor(n)` |
| huge e | `wiener(e, n)` gives d |
| n small (< 256 bit) | factor it: factordb.com, or `sympy.factorint(n)` |
| p known / leaked bits | Coppersmith (SageMath `small_roots`) |

Then `rsa_decrypt(c, p, q, e)` and `i2b(m)`.

## Symmetric

- **AES-ECB**: identical 16-byte blocks repeat; byte-at-a-time oracle when you control a prefix.
- **AES-CBC**: bit-flip the previous ciphertext block to change plaintext; padding oracle if errors differ.
- **CTR / stream with a reused nonce**: `c1 xor c2 = p1 xor p2`; crib-drag with a known word.
- **XOR**: `single_byte_xor_candidates(data)`; a repeating key's length shows in Hamming distances; known prefix (`flag{`) gives key bytes directly.

## Hashes

```bash
hashcat -m 0 hash.txt /usr/share/wordlists/rockyou.txt     # 0 md5, 100 sha1, 1400 sha256, 3200 bcrypt
john --wordlist=rockyou.txt hash.txt ; john --show hash.txt
```

- Length extension (MD5/SHA1/SHA256 `H(secret || msg)`): `hashpump` / `hlextend`.

## Solvers

- Linear relations / bit tricks: z3 (`from z3 import *`).
- Lattices, elliptic curves, polynomial rings: SageMath (`docker run -it sagemath/sagemath` when it is not installed).
