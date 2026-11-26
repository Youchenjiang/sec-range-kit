"""rangekit.vm.scenario - validate a known-answer scenario before it reaches the VM.

A scenario file (JSON) lists the steps ``scenario/run_scenario.ps1`` performs in
the guest. Each step names a ``kind`` the runner implements, the ATT&CK technique
it stands for, the names it uses and the events it is expected to produce. The
runner derives the cleanup of every step from the same file, so the names used
to create an artifact are always the names used to remove it.

Secrets never live in the file: the account a ``local_user`` step creates gets
its password from an environment variable in the guest (or a random one), and
``failed_logons`` generates its wrong passwords at run time.

Usage:
    python -m rangekit.vm.scenario validate rangekit/vm/scenario/scenario.example.json
    python -m rangekit.vm.scenario plan rangekit/vm/scenario/scenario.example.json
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from rangekit.common.safe_paths import UnsafePathError, resolve_cli_path

# kind -> required params (all strings unless listed in LIST_PARAMS / INT_PARAMS)
KINDS: dict[str, tuple[str, ...]] = {
    "scheduled_task": ("task", "command"),
    "service": ("service", "command"),
    "run_key": ("value", "data"),
    "local_user": ("user",),
    "group_add": ("user", "group"),
    "failed_logons": ("users", "attempts_per_user"),
    "encoded_powershell": ("marker",),
    "certutil_decode": ("marker", "blob_file", "out_file"),
    "ads": ("file", "stream", "data"),
    "lolbin_egress": ("source", "staged_file", "url"),
    "discovery": (),
    "eicar": ("file",),
    "process_open": ("process", "access"),
    "wmi_subscription": ("filter", "consumer", "command"),
}
LIST_PARAMS = {"users", "access"}
INT_PARAMS = {"attempts_per_user"}
# names that end up in task, service, account, registry and WMI object names
NAME_PARAMS = {"task", "service", "value", "user", "group", "filter", "consumer", "process"}
# file names created under the scenario's stage directory
FILE_PARAMS = {"blob_file", "out_file", "file", "staged_file"}

SAFE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$")
SAFE_GROUP = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 _.-]{0,63}$")
STEP_ID = re.compile(r"^[A-Za-z0-9_-]{1,16}$")
TECHNIQUE = re.compile(r"^T\d{4}(\.\d{3})?$")
# each segment starts with its own backslash, so matching stays linear
STAGE_DIR = re.compile(r"^[A-Za-z]:(?:\\[A-Za-z0-9_. -]{1,64}){0,16}\\?$")
EXPECT_KEYS = ("sysmon", "security", "other")
# Default staging directory INSIDE THE GUEST VM; this module never writes there.
# Staging in the system temp directory is deliberate: detection rules key on it.
GUEST_STAGE_DIR = "C:\\Windows\\Temp"  # NOSONAR guest path string, never opened on the host


class ScenarioError(ValueError):
    """The scenario file is unusable; the message lists every problem."""


def _check_param(kind: str, key: str, value: object) -> str | None:
    if key in LIST_PARAMS:
        if not isinstance(value, list) or not value:
            return f"{key} must be a non-empty list"
        if key == "users" and not all(isinstance(v, str) and SAFE_NAME.fullmatch(v) for v in value):
            return f"{key} entries must be simple names"
        if key == "access" and not all(isinstance(v, int) and 0 < v <= 0x1FFFFF for v in value):
            return f"{key} entries must be process access masks (1..0x1FFFFF)"
        return None
    if key in INT_PARAMS:
        return None if isinstance(value, int) and 1 <= value <= 20 else f"{key} must be an integer 1..20"
    if not isinstance(value, str) or not value.strip():
        return f"{key} must be a non-empty string"
    if key == "group" and not SAFE_GROUP.fullmatch(value):
        return f"{key} {value!r} has characters outside letters, digits, space, _ . -"
    if key in NAME_PARAMS - {"group"} and not SAFE_NAME.fullmatch(value):
        return f"{key} {value!r} must be letters, digits, _ . - (max 64)"
    if key in FILE_PARAMS and not SAFE_NAME.fullmatch(value):
        return f"{key} {value!r} must be a bare file name"
    if key == "url" and not value.startswith("https://"):
        return f"{key} must be an https URL"
    if kind == "process_open" and key == "process" and value.lower().endswith(".exe"):
        return "process is the name without .exe (as Get-Process expects)"
    return None


def _check_step(index: int, step: object, seen_ids: set[str]) -> list[str]:
    where = f"steps[{index}]"
    if not isinstance(step, dict):
        return [f"{where} must be an object"]
    problems: list[str] = []
    sid = step.get("id")
    if not isinstance(sid, str) or not STEP_ID.fullmatch(sid):
        problems.append(f"{where}.id must match {STEP_ID.pattern}")
    elif sid in seen_ids:
        problems.append(f"{where}.id {sid!r} is used twice")
    else:
        seen_ids.add(sid)
        where = f"step {sid}"
    kind = step.get("kind")
    if kind not in KINDS:
        problems.append(f"{where}.kind {kind!r} is not one of {', '.join(sorted(KINDS))}")
        return problems
    if not isinstance(step.get("technique"), str) or not TECHNIQUE.fullmatch(step["technique"]):
        problems.append(f"{where}.technique must look like T1234 or T1234.001")
    if not isinstance(step.get("name"), str) or not step["name"].strip():
        problems.append(f"{where}.name is required")
    params = step.get("params", {})
    if not isinstance(params, dict):
        return problems + [f"{where}.params must be an object"]
    for key in KINDS[kind]:
        if key not in params:
            problems.append(f"{where}: {kind} needs params.{key}")
    for key, value in params.items():
        if key not in KINDS[kind] and key != "password_env":
            problems.append(f"{where}: params.{key} is not used by {kind}")
            continue
        if key == "password_env":
            if kind != "local_user" or not isinstance(value, str) or not re.fullmatch(r"[A-Z][A-Z0-9_]{2,63}", value):
                problems.append(f"{where}: password_env must be an UPPER_CASE variable name on a local_user step")
            continue
        issue = _check_param(kind, key, value)
        if issue:
            problems.append(f"{where}: {issue}")
    expect = step.get("expect", {})
    if not isinstance(expect, dict) or set(expect) - set(EXPECT_KEYS):
        problems.append(f"{where}.expect may only hold {', '.join(EXPECT_KEYS)}")
    return problems


def validate(data: object) -> list[str]:
    """Every problem in a parsed scenario; an empty list means it is usable."""
    if not isinstance(data, dict):
        return ["the scenario must be a JSON object"]
    problems: list[str] = []
    if not isinstance(data.get("name"), str) or not SAFE_NAME.fullmatch(data["name"]):
        problems.append("name must be letters, digits, _ . - (max 64)")
    stage = data.get("stage_dir", GUEST_STAGE_DIR)
    if not isinstance(stage, str) or len(stage) > 260 or not STAGE_DIR.fullmatch(stage) or ".." in stage:
        problems.append("stage_dir must be an absolute Windows directory without ..")
    steps = data.get("steps")
    if not isinstance(steps, list) or not steps:
        return problems + ["steps must be a non-empty list"]
    seen: set[str] = set()
    for index, step in enumerate(steps):
        problems += _check_step(index, step, seen)
    return problems + _check_group_targets(steps)


def _check_group_targets(steps: list) -> list[str]:
    """group_add may only touch an account the scenario itself creates (and removes)."""
    def users_of(kind: str) -> list[tuple[object, object]]:
        return [
            (step.get("id"), (step.get("params") or {}).get("user"))
            for step in steps
            if isinstance(step, dict) and step.get("kind") == kind and isinstance(step.get("params"), dict)
        ]

    created = {user for _, user in users_of("local_user")}
    return [
        f"step {sid}: group_add user {user!r} is not created by a local_user step"
        for sid, user in users_of("group_add")
        if user not in created
    ]


def cleanup_plan(data: dict) -> list[str]:
    """What ``run_scenario.ps1 -Cleanup`` removes, one line per artifact, in removal order."""
    stage = data.get("stage_dir", GUEST_STAGE_DIR).rstrip("\\")
    lines: list[str] = []
    for step in reversed(data["steps"]):
        p = step.get("params", {})
        kind = step["kind"]
        if kind == "scheduled_task":
            lines.append(f"scheduled task {p['task']}")
        elif kind == "service":
            lines.append(f"service {p['service']}")
        elif kind == "run_key":
            lines.append(f"HKCU Run value {p['value']}")
        elif kind == "local_user":
            lines.append(f"local account {p['user']}")
        elif kind == "wmi_subscription":
            lines.append(f"WMI binding, consumer {p['consumer']} and filter {p['filter']}")
        for key in sorted(FILE_PARAMS & set(p)):
            lines.append(f"file {stage}\\{p[key]}")
    return lines


def load(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    problems = validate(data)
    if problems:
        raise ScenarioError("\n".join(problems))
    return data


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("command", choices=("validate", "plan"))
    parser.add_argument("scenario")
    args = parser.parse_args(argv)
    try:
        data = load(resolve_cli_path(args.scenario))
    except (OSError, json.JSONDecodeError, ScenarioError, UnsafePathError) as exc:
        print(f"INVALID {args.scenario}:\n{exc}", file=sys.stderr)
        return 1
    if args.command == "validate":
        print(f"OK {args.scenario}: {len(data['steps'])} steps")
    else:
        for line in cleanup_plan(data):
            print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
