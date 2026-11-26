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


# repository-location variables a hook may export; the fixtures build their own repositories
GIT_LOCATION_VARS = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY",
                     "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_COMMON_DIR")
# a stand-in for tools/build_runner.py that records what the hook's test step would see
ENV_PROBE = 'import os, pathlib\npathlib.Path("gitdir_seen.txt").write_text(os.environ.get("GIT_DIR", ""))\n'


def git(cwd: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    env = {k: v for k, v in os.environ.items()
           if k not in ("ALLOW_DIRECT_PUSH", "PR_BODY_FILE", "CLICKRA_PR_BODY_FILE", *GIT_LOCATION_VARS)}
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
        hook = self.work / ".git" / "hooks" / "pre-push"
        shutil.copy2(HOOK, hook)
        hook.chmod(0o755)  # git skips a non-executable hook on POSIX
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

    def test_push_from_a_linked_worktree_hides_git_dir_from_the_test_step(self) -> None:
        # git runs a hook in a linked worktree with an absolute GIT_DIR; a test that
        # then ran "git init" or "git config" in its own temp dir rewrote the real repo
        (self.work / "tools" / "build_runner.py").write_text(ENV_PROBE, encoding="utf-8")
        git(self.work, "add", "-A")
        git(self.work, "commit", "-m", "test: add the environment probe")
        linked = self.tmp / "linked"
        git(self.work, "worktree", "add", "-b", "event/2026-linked", str(linked))
        res = git(linked, "push", "origin", "refs/heads/event/2026-linked:refs/heads/event/2026-linked",
                  check=False)
        self.assertEqual(0, res.returncode, res.stderr)
        self.assertEqual("", (linked / "gitdir_seen.txt").read_text())


if __name__ == "__main__":
    unittest.main()
