"""Guest collection scripts stay generic, ASCII-only and parseable."""
import re
import sys
import unittest
from pathlib import Path

if str(Path(__file__).resolve().parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).resolve().parent))

from _ps_parse import HAVE_PWSH, parse_failures  # noqa: E402

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

    @unittest.skipUnless(HAVE_PWSH, "pwsh is required to parse scripts")
    def test_scripts_parse(self) -> None:
        failures, output = parse_failures(SCRIPTS)
        self.assertEqual(0, failures, output)


if __name__ == "__main__":
    unittest.main()
