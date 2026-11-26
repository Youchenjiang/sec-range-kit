"""Scenario validation on the host, and its agreement with the guest runner."""
import contextlib
import copy
import io
import json
import re
import shutil
import subprocess
import unittest
from pathlib import Path

from rangekit.vm import scenario as sc

SCENARIO_DIR = Path(__file__).resolve().parents[1] / "rangekit" / "vm" / "scenario"
EXAMPLE = SCENARIO_DIR / "scenario.example.json"
RUNNER = SCENARIO_DIR / "run_scenario.ps1"
SCRIPTS = sorted(SCENARIO_DIR.glob("*.ps1"))
EVENT_MARKERS = re.compile(r"day1b|day2|hitcon|sprint|C:\\Users\\", re.IGNORECASE)


def example() -> dict:
    return json.loads(EXAMPLE.read_text(encoding="utf-8"))


class ExampleTests(unittest.TestCase):
    def test_example_is_valid_and_covers_every_kind(self) -> None:
        data = example()
        self.assertEqual(sc.validate(data), [])
        self.assertEqual({s["kind"] for s in data["steps"]}, set(sc.KINDS))

    def test_example_holds_no_secret_or_event_name(self) -> None:
        text = EXAMPLE.read_text(encoding="utf-8")
        self.assertIsNone(EVENT_MARKERS.search(text))
        self.assertNotIn('"password"', text)

    def test_cleanup_plan_removes_newest_first(self) -> None:
        plan = sc.cleanup_plan(example())
        self.assertTrue(plan[0].startswith("WMI binding"))
        self.assertEqual(plan[-1], "scheduled task RangeKitDemo")
        self.assertIn("local account rk_demo_svc", plan)
        self.assertIn("file C:\\Windows\\Temp\\rk_net.exe", plan)

    def test_cli_validate_and_plan(self) -> None:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(sc.main(["validate", str(EXAMPLE)]), 0)
            self.assertEqual(sc.main(["plan", str(EXAMPLE)]), 0)
        self.assertIn("14 steps", out.getvalue())
        self.assertIn("scheduled task RangeKitDemo", out.getvalue())


class RejectionTests(unittest.TestCase):
    def problems(self, mutate) -> list[str]:
        data = copy.deepcopy(example())
        mutate(data)
        return sc.validate(data)

    def assert_rejected(self, mutate, fragment: str) -> None:
        problems = self.problems(mutate)
        self.assertTrue(any(fragment in p for p in problems), problems)

    def test_unknown_kind(self) -> None:
        self.assert_rejected(lambda d: d["steps"][0].update(kind="format_disk"), "is not one of")

    def test_duplicate_id(self) -> None:
        self.assert_rejected(lambda d: d["steps"][1].update(id="S01"), "used twice")

    def test_unsafe_name_cannot_reach_a_command_line(self) -> None:
        self.assert_rejected(lambda d: d["steps"][0]["params"].update(task="x & del C:\\"), "must be letters")

    def test_file_names_cannot_leave_the_stage_dir(self) -> None:
        self.assert_rejected(lambda d: d["steps"][7]["params"].update(out_file="..\\evil.ps1"), "bare file name")

    def test_missing_and_unused_params(self) -> None:
        self.assert_rejected(lambda d: d["steps"][0]["params"].pop("command"), "needs params.command")
        self.assert_rejected(lambda d: d["steps"][0]["params"].update(extra="1"), "not used by")

    def test_a_password_literal_is_refused(self) -> None:
        self.assert_rejected(lambda d: d["steps"][3]["params"].update(password="Secret1"), "not used by")

    def test_group_add_needs_an_account_created_by_the_scenario(self) -> None:
        self.assert_rejected(lambda d: d["steps"][4]["params"].update(user="Administrator"), "not created")

    def test_plain_http_and_bad_stage_dir(self) -> None:
        self.assert_rejected(lambda d: d["steps"][9]["params"].update(url="http://example.com"), "https")
        self.assert_rejected(lambda d: d.update(stage_dir="C:\\Windows\\..\\Temp"), "stage_dir")

    def test_access_masks_and_technique(self) -> None:
        self.assert_rejected(lambda d: d["steps"][12]["params"].update(access=["0x1000"]), "access masks")
        self.assert_rejected(lambda d: d["steps"][0].update(technique="persistence"), "technique")


class GuestScriptTests(unittest.TestCase):
    def test_runner_implements_exactly_the_validated_kinds(self) -> None:
        text = RUNNER.read_text(encoding="ascii").replace("\r\n", "\n")
        block = text[text.index("$Kinds = @{"):text.index("\n}\n", text.index("$Kinds = @{"))]
        kinds = set(re.findall(r"^    ([a-z_]+) = @\{", block, re.MULTILINE))
        self.assertEqual(kinds, set(sc.KINDS))

    def test_scripts_are_ascii_parameterised_and_generic(self) -> None:
        for path in SCRIPTS:
            raw = path.read_bytes()
            with self.subTest(script=path.name):
                self.assertTrue(raw.isascii())
                text = raw.decode("ascii")
                self.assertIn("[CmdletBinding()]", text)
                self.assertIsNone(EVENT_MARKERS.search(text))

    @unittest.skipUnless(shutil.which("pwsh"), "pwsh is required to parse scripts")
    def test_scripts_parse(self) -> None:
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
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)


if __name__ == "__main__":
    unittest.main()
