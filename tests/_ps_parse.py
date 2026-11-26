"""Parse PowerShell scripts with pwsh without running them (shared by the guest-script tests)."""
import shutil
import subprocess
from pathlib import Path

HAVE_PWSH = shutil.which("pwsh") is not None


def parse_failures(scripts: list[Path]) -> tuple[int, str]:
    """(number of scripts with parse errors, pwsh output naming the first error of each)."""
    # Extra arguments after -Command are appended to the command text, so the
    # paths are embedded as a single-quoted PowerShell array instead.
    paths = ", ".join("'" + str(p).replace("'", "''") + "'" for p in scripts)
    command = (
        f"$bad = 0; foreach ($f in @({paths})) {{ $t = $null; $e = $null; "
        "[System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$t, [ref]$e) | Out-Null; "
        "if ($e) { $bad++; Write-Output ($f + ': ' + $e[0].Message) } }; exit $bad"
    )
    res = subprocess.run(
        ["pwsh", "-NoProfile", "-NonInteractive", "-Command", command],
        capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120, check=False,
    )
    return res.returncode, res.stdout + res.stderr
