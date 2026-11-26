"""The CTF kit's scripts parse, its helpers work and its README links resolve."""
import re
import shutil
import subprocess
import sys
import unittest
from pathlib import Path

if str(Path(__file__).resolve().parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).resolve().parent))

from _ps_parse import HAVE_PWSH, parse_failures  # noqa: E402

CTF = Path(__file__).resolve().parents[1] / "rangekit" / "ctf"
SETUP_SH = CTF / "setup" / "ctf_setup.sh"
TEMPLATES = sorted((CTF / "templates").glob("*.py"))
BASH = shutil.which("bash")


class CtfKitTests(unittest.TestCase):
    def test_templates_compile(self) -> None:
        self.assertGreaterEqual(len(TEMPLATES), 3)
        for path in TEMPLATES:
            with self.subTest(template=path.name):
                compile(path.read_text(encoding="utf-8"), str(path), "exec")

    def test_crypto_helpers_self_test(self) -> None:
        res = subprocess.run([sys.executable, str(CTF / "templates" / "crypto_helpers.py")],
                             capture_output=True, text=True, timeout=60, check=False)
        self.assertEqual(0, res.returncode, res.stdout + res.stderr)
        self.assertIn("self-test OK", res.stdout)

    @unittest.skipUnless(BASH, "bash is required")
    def test_setup_script_is_valid_bash(self) -> None:
        res = subprocess.run([BASH, "-n", str(SETUP_SH)], capture_output=True, text=True, check=False)
        self.assertEqual(0, res.returncode, res.stderr)

    def test_setup_script_keeps_env_assignments_working_as_root(self) -> None:
        # "$SUDO VAR=x cmd" runs a command named "VAR=x" when $SUDO is empty (root)
        text = SETUP_SH.read_text(encoding="utf-8")
        self.assertIsNone(re.search(r"\$SUDO\s+[A-Z_]+=", text))

    def test_pip_install_gets_package_names_only(self) -> None:
        # pip_install installs each argument on its own, so an option would become a "package"
        for line in SETUP_SH.read_text(encoding="utf-8").splitlines():
            if line.strip().startswith("pip_install "):
                with self.subTest(line=line.strip()):
                    self.assertNotIn(" -", " " + line.strip()[len("pip_install "):])

    @unittest.skipUnless(HAVE_PWSH, "pwsh is required to parse scripts")
    def test_windows_script_parses(self) -> None:
        failures, output = parse_failures(sorted((CTF / "setup").glob("*.ps1")))
        self.assertEqual(0, failures, output)

    def test_readme_links_resolve(self) -> None:
        readme = CTF / "README.md"
        for target in re.findall(r"\]\(([^)#]+)\)", readme.read_text(encoding="utf-8")):
            if "://" in target:
                continue
            with self.subTest(link=target):
                self.assertTrue((readme.parent / target).exists(), target)


if __name__ == "__main__":
    unittest.main()
