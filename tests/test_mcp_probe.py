"""Tests for the --out confinement in rangekit/mcp/tools/mcp_probe.py."""
import os
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parents[1] / "rangekit" / "mcp" / "tools"
STUBS = {
    "mcp": types.SimpleNamespace(ClientSession=None, StdioServerParameters=None),
    "mcp.client": types.SimpleNamespace(),
    "mcp.client.stdio": types.SimpleNamespace(stdio_client=None),
}


def load_probe():
    with patch.dict(sys.modules, STUBS), patch.object(sys, "path", [str(TOOLS), *sys.path]):
        sys.modules.pop("mcp_probe", None)
        import mcp_probe
        return mcp_probe


class ConfinedOutputPathTests(unittest.TestCase):
    def setUp(self):
        self.probe = load_probe()

    def test_paths_under_cwd_or_temp_are_allowed(self):
        resolved = self.probe.confined_output_path("evidence/out.json")
        self.assertTrue(resolved.endswith(os.path.join("evidence", "out.json")))
        inside_temp = os.path.join(tempfile.gettempdir(), "probe.json")
        self.assertEqual(os.path.realpath(inside_temp), self.probe.confined_output_path(inside_temp))

    def test_escapes_are_refused(self):
        for raw in ("../../escape.json", os.path.join(os.path.abspath(os.sep), "outside-root.json")):
            with self.subTest(raw=raw), self.assertRaises(SystemExit):
                self.probe.confined_output_path(raw)

    def test_other_drive_is_refused_instead_of_crashing(self):
        with patch.object(self.probe.os.path, "commonpath", side_effect=ValueError("different drives")), \
             self.assertRaises(SystemExit):
            self.probe.confined_output_path("elsewhere.json")


if __name__ == "__main__":
    unittest.main()
