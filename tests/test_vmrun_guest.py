import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from rangekit.vm import vmrun_guest


class DefaultVmrunTests(unittest.TestCase):
    def test_environment_variable_wins(self):
        with patch.dict(os.environ, {"VM_VMRUN": "D:/vm/vmrun.exe"}), \
             patch.object(vmrun_guest.shutil, "which", return_value="C:/on/path/vmrun.exe"):
            self.assertEqual("D:/vm/vmrun.exe", vmrun_guest.default_vmrun())

    def test_path_lookup_comes_before_the_standard_install(self):
        with patch.dict(os.environ, {}, clear=False), \
             patch.object(vmrun_guest.shutil, "which", return_value="C:/on/path/vmrun.exe"):
            os.environ.pop("VM_VMRUN", None)
            self.assertEqual("C:/on/path/vmrun.exe", vmrun_guest.default_vmrun())

    def test_standard_install_is_the_last_resort(self):
        with patch.dict(os.environ, {}, clear=False), \
             patch.object(vmrun_guest.shutil, "which", return_value=None):
            os.environ.pop("VM_VMRUN", None)
            self.assertEqual(vmrun_guest.STANDARD_VMRUN, vmrun_guest.default_vmrun())

    def test_default_credentials_file_is_the_ignored_dotenv(self):
        self.assertEqual(".env", Path(vmrun_guest.DEFAULT_CREDS_FILE).name)
        self.assertEqual(Path(vmrun_guest.REPO_ROOT), Path(__file__).resolve().parents[1])


class CredsFileTests(unittest.TestCase):
    def setUp(self):
        self.repo = Path(tempfile.mkdtemp(prefix="test_vmrun_creds_"))
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        (self.repo / ".gitignore").write_text(".env\n", encoding="utf-8")

    def tearDown(self):
        shutil.rmtree(self.repo, ignore_errors=True)

    def test_ignored_file_is_read_and_unknown_keys_are_skipped(self):
        path = self.repo / ".env"
        path.write_text("# comment\nVM_GU=analyst\nVM_GP=placeholder\nOTHER=x\n", encoding="utf-8")
        creds = vmrun_guest.load_creds_file(str(path), str(self.repo))
        self.assertEqual({"VM_GU": "analyst", "VM_GP": "placeholder"}, creds)

    def test_tracked_location_is_refused(self):
        path = self.repo / "creds.txt"
        path.write_text("VM_GU=analyst\n", encoding="utf-8")
        with self.assertRaises(vmrun_guest.VMError):
            vmrun_guest.load_creds_file(str(path), str(self.repo))


if __name__ == "__main__":
    unittest.main()
