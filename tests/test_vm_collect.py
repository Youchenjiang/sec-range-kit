"""Guest collection scripts stay generic, ASCII-only and parseable."""
import re
import shutil
import subprocess
import unittest
from pathlib import Path

COLLECT = Path(__file__).resolve().parents[1] / "rangekit" / "vm" / "collect"
SCRIPTS = sorted(COLLECT.glob("*.ps1"))
# Event-specific names and personal profile paths belong on event branches, not here.
EVENT_MARKERS = re.compile(r"day1b|day2|hitcon|sprint|C:\\Users\\(?!<)", re.IGNORECASE)


class CollectScriptTests(unittest.TestCase):
    def test_scripts_exist(self) -> None:
        self.assertGreaterEqual(len(SCRIPTS), 7)

    def test_ascii_only(self) -> None:
        # PowerShell 5.1 reads a BOM-less .ps1 in the ANSI code page. Line endings
        # are not checked: the index stores LF and only Windows checkouts get CRLF.
        for path in SCRIPTS:
            with self.subTest(script=path.name):
                self.assertTrue(path.read_bytes().isascii())

    def test_parameterised(self) -> None:
        for path in SCRIPTS:
            with self.subTest(script=path.name):
                self.assertIn("[CmdletBinding()]", path.read_text(encoding="ascii"))

    def test_no_event_specific_values(self) -> None:
        for path in SCRIPTS:
            with self.subTest(script=path.name):
                self.assertIsNone(EVENT_MARKERS.search(path.read_text(encoding="ascii")))

    @unittest.skipUnless(shutil.which("pwsh"), "pwsh is required to parse scripts")
    def test_scripts_parse(self) -> None:
        # Extra arguments after -Command are appended to the command text, so the
        # paths are embedded as a single-quoted PowerShell array instead.
        paths = ", ".join("'" + str(p).replace("'", "''") + "'" for p in SCRIPTS)
        command = (
            f"$bad = 0; foreach ($f in @({paths})) {{ $t = $null; $e = $null; "
            "[System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$t, [ref]$e) | Out-Null; "
            "if ($e) { $bad++; Write-Output ($f + ': ' + $e[0].Message) } }; exit $bad"
        )
        res = subprocess.run(
            ["pwsh", "-NoProfile", "-NonInteractive", "-Command", command],
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120, check=False,
        )
        self.assertEqual(0, res.returncode, res.stdout + res.stderr)


if __name__ == "__main__":
    unittest.main()
