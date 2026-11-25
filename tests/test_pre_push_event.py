"""The pre-push hook lets event/* branches through without a PR body, but not other branches."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOOK = ROOT / "scripts" / "hooks" / "pre-push"
LINT = ROOT / "tools" / "lint_commits.py"


def git(cwd: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    env = {k: v for k, v in os.environ.items()
           if k not in ("ALLOW_DIRECT_PUSH", "PR_BODY_FILE", "CLICKRA_PR_BODY_FILE")}
    return subprocess.run(
        ["git", "-c", "user.name=Test", "-c", "user.email=test@example.local",
         "-c", "init.defaultBranch=main", *args],
        cwd=cwd, env=env, capture_output=True, text=True, encoding="utf-8", check=check,
    )


@unittest.skipUnless(shutil.which("git"), "git is required")
class EventBranchPushTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="test_pre_push_event_"))
        remote = self.tmp / "remote.git"
        git(self.tmp, "init", "--bare", str(remote))
        self.work = self.tmp / "work"
        self.work.mkdir()
        git(self.work, "init")
        shutil.copy2(HOOK, self.work / ".git" / "hooks" / "pre-push")
        (self.work / "tools").mkdir()
        shutil.copy2(LINT, self.work / "tools" / "lint_commits.py")
        git(self.work, "remote", "add", "origin", str(remote))
        (self.work / "README.md").write_text("x\n", encoding="utf-8")
        git(self.work, "add", "-A")
        git(self.work, "commit", "-m", "chore(setup): scaffold project from the minimal template")
        git(self.work, "push", "--no-verify", "origin", "main:main")

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def push_branch(self, branch: str) -> subprocess.CompletedProcess:
        git(self.work, "switch", "-c", branch)
        (self.work / "notes.md").write_text("event notes\n", encoding="utf-8")
        git(self.work, "add", "-A")
        git(self.work, "commit", "-m", "docs: add event notes")
        return git(self.work, "push", "origin", f"refs/heads/{branch}:refs/heads/{branch}", check=False)

    def test_event_branch_pushes_without_a_pr_body(self) -> None:
        res = self.push_branch("event/2026-hitcon")
        self.assertEqual(0, res.returncode, res.stderr)
        self.assertIn("Event branch", res.stdout + res.stderr)

    def test_feature_branch_still_needs_a_pr_body(self) -> None:
        res = self.push_branch("feat/event-notes")
        self.assertNotEqual(0, res.returncode)
        self.assertIn("PR_BODY_FILE", res.stderr)


if __name__ == "__main__":
    unittest.main()
