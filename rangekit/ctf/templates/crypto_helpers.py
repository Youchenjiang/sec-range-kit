#!/usr/bin/env python3
"""Small, dependency-light helpers for common CTF crypto patterns.

Import it next to a challenge (``from crypto_helpers import *``) or run
``python3 crypto_helpers.py`` to self-test. Only the standard library is required;
gmpy2 is used when present for faster integer roots.
"""
from __future__ import annotations

import math
from functools import reduce
from itertools import cycle

try:  # optional speed-up
    import gmpy2
except ImportError:  # pragma: no cover - depends on the environment
    gmpy2 = None


# ---------------------------------------------------------------- bytes / ints
def i2b(n: int) -> bytes:
    return n.to_bytes((n.bit_length() + 7) // 8 or 1, "big")


def b2i(b: bytes) -> int:
    return int.from_bytes(b, "big")


def xor(data: bytes, key: bytes) -> bytes:
    """Repeating-key XOR."""
    return bytes(a ^ b for a, b in zip(data, cycle(key)))


def single_byte_xor_candidates(data: bytes, top: int = 3) -> list[tuple[int, bytes]]:
    """Keys ranked by how printable/English-like the plaintext is."""
    def score(p: bytes) -> int:
        return sum(c in b" etaoinshrdluETAOINSHRDLU" for c in p) * 2 + sum(32 <= c < 127 for c in p)
    ranked = sorted(((k, xor(data, bytes([k]))) for k in range(256)), key=lambda kp: -score(kp[1]))
    return ranked[:top]


# ---------------------------------------------------------------- number theory
def egcd(a: int, b: int) -> tuple[int, int, int]:
    x0, x1, y0, y1 = 1, 0, 0, 1
    while b:
        q, a, b = a // b, b, a % b
        x0, x1, y0, y1 = x1, x0 - q * x1, y1, y0 - q * y1
    return a, x0, y0


def invmod(a: int, m: int) -> int:
    return pow(a, -1, m)


def crt(remainders: list[int], moduli: list[int]) -> int:
    """Chinese remainder theorem for pairwise coprime moduli."""
    n = reduce(lambda a, b: a * b, moduli)
    return sum(r * (n // m) * invmod(n // m, m) for r, m in zip(remainders, moduli)) % n


def iroot(x: int, k: int) -> tuple[int, bool]:
    """Integer k-th root and whether it is exact."""
    if gmpy2 is not None:
        r, exact = gmpy2.iroot(x, k)
        return int(r), bool(exact)
    lo, hi = 0, 1 << ((x.bit_length() + k - 1) // k + 1)
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if mid ** k <= x:
            lo = mid
        else:
            hi = mid - 1
    return lo, lo ** k == x


# ---------------------------------------------------------------- RSA patterns
def rsa_decrypt(c: int, p: int, q: int, e: int = 65537) -> int:
    return pow(c, invmod(e, (p - 1) * (q - 1)), p * q)


def rsa_small_e(c: int, e: int = 3) -> int | None:
    """m**e < n: the ciphertext is a plain integer power."""
    m, exact = iroot(c, e)
    return m if exact else None


def rsa_common_modulus(c1: int, c2: int, e1: int, e2: int, n: int) -> int:
    """Same message and n, coprime exponents."""
    g, a, b = egcd(e1, e2)
    if g != 1:
        raise ValueError("exponents are not coprime")
    return (pow(c1, a, n) * pow(c2, b, n)) % n


def rsa_hastad(ciphertexts: list[int], moduli: list[int], e: int = 3) -> int | None:
    """Same message sent to e recipients with small e."""
    m, exact = iroot(crt(ciphertexts, moduli), e)
    return m if exact else None


def fermat_factor(n: int, max_steps: int = 1_000_000) -> tuple[int, int] | None:
    """p and q close together."""
    a, _ = iroot(n, 2)
    a += 1
    for _ in range(max_steps):
        b2 = a * a - n
        b, exact = iroot(b2, 2)
        if exact:
            return a - b, a + b
        a += 1
    return None


def shared_prime(n1: int, n2: int) -> int | None:
    g = math.gcd(n1, n2)
    return g if 1 < g < n1 else None


def wiener(e: int, n: int) -> int | None:
    """Recover a small private exponent d from the continued fraction of e/n."""
    def convergents(num: int, den: int):
        h0, h1, k0, k1 = 0, 1, 1, 0
        while den:
            a = num // den
            num, den = den, num - a * den
            h0, h1, k0, k1 = h1, a * h1 + h0, k1, a * k1 + k0
            yield h1, k1
    for k, d in convergents(e, n):
        if k == 0 or (e * d - 1) % k:
            continue
        phi = (e * d - 1) // k
        s = n - phi + 1
        disc = s * s - 4 * n
        if disc >= 0:
            r, exact = iroot(disc, 2)
            if exact and (s + r) % 2 == 0:
                return d
    return None


def _self_test() -> None:
    p, q, e = 1000003, 1000033, 65537
    n, m = p * q, 424242
    assert rsa_decrypt(pow(m, e, n), p, q, e) == m
    assert rsa_small_e(pow(7, 3)) == 7
    assert fermat_factor(n) == (p, q)
    assert rsa_common_modulus(pow(m, 3, n), pow(m, 5, n), 3, 5, n) == m
    assert crt([2, 3, 2], [3, 5, 7]) == 23
    moduli = [1000003 * 1000033, 1000037 * 1000039, 1000081 * 1000099]
    assert rsa_hastad([pow(m, 3, mod) for mod in moduli], moduli, 3) == m
    phi, d = (p - 1) * (q - 1), 13   # small d, coprime to phi
    assert wiener(invmod(d, phi), n) == d
    assert xor(xor(b"flag{x}", b"k3y"), b"k3y") == b"flag{x}"
    assert i2b(b2i(b"CTF")) == b"CTF"
    print("crypto_helpers self-test OK")


if __name__ == "__main__":
    _self_test()
