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
# optional params, per kind
OPTIONAL: dict[str, tuple[str, ...]] = {"local_user": ("password_env",)}
# file names created under the scenario's stage directory
FILE_PARAMS = {"blob_file", "out_file", "file", "staged_file"}

SAFE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$")
SAFE_GROUP = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 _.-]{0,63}$")
ENV_NAME = re.compile(r"^[A-Z][A-Z0-9_]{2,63}$")
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


def _text(value: object) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _name(value: object) -> bool:
    return isinstance(value, str) and bool(SAFE_NAME.fullmatch(value))


# param -> (accepts the value, message when it does not)
PARAM_RULES: dict[str, tuple] = {
    **{key: (_name, "must be letters, digits, _ . - (max 64)")
       for key in ("task", "service", "value", "user", "filter", "consumer")},
    **{key: (_name, "must be a bare file name") for key in FILE_PARAMS},
    **{key: (_text, "must be a non-empty string") for key in ("command", "data", "marker", "source", "stream")},
    "group": (lambda v: isinstance(v, str) and bool(SAFE_GROUP.fullmatch(v)),
              "must be letters, digits, space, _ . - (max 64)"),
    "process": (lambda v: _name(v) and not v.lower().endswith(".exe"),
                "must be a process name without .exe (as Get-Process expects)"),
    "url": (lambda v: isinstance(v, str) and v.startswith("https://"), "must be an https URL"),
    "users": (lambda v: isinstance(v, list) and bool(v) and all(_name(u) for u in v),
              "must be a non-empty list of simple names"),
    "access": (lambda v: isinstance(v, list) and bool(v)
               and all(isinstance(m, int) and 0 < m <= 0x1FFFFF for m in v),
               "must be a non-empty list of process access masks (1..0x1FFFFF)"),
    "attempts_per_user": (lambda v: isinstance(v, int) and 1 <= v <= 20, "must be an integer 1..20"),
    "password_env": (lambda v: isinstance(v, str) and bool(ENV_NAME.fullmatch(v)),
                     "must be an UPPER_CASE environment variable name"),
}


def _check_params(where: str, kind: str, params: dict) -> list[str]:
    allowed = KINDS[kind] + OPTIONAL.get(kind, ())
    problems = [f"{where}: {kind} needs params.{key}" for key in KINDS[kind] if key not in params]
    for key, value in params.items():
        if key not in allowed:
            problems.append(f"{where}: params.{key} is not used by {kind}")
            continue
        accepts, message = PARAM_RULES[key]
        if not accepts(value):
            problems.append(f"{where}: params.{key} {message}")
    return problems


def _step_label(index: int, step: dict, seen_ids: set[str]) -> tuple[str, list[str]]:
    """How problems refer to the step, plus any problem with its id."""
    sid = step.get("id")
    if not isinstance(sid, str) or not STEP_ID.fullmatch(sid):
        return f"steps[{index}]", [f"steps[{index}].id must match {STEP_ID.pattern}"]
    if sid in seen_ids:
        return f"steps[{index}]", [f"steps[{index}].id {sid!r} is used twice"]
    seen_ids.add(sid)
    return f"step {sid}", []


def _check_step(index: int, step: object, seen_ids: set[str]) -> list[str]:
    if not isinstance(step, dict):
        return [f"steps[{index}] must be an object"]
    where, problems = _step_label(index, step, seen_ids)
    kind = step.get("kind")
    if kind not in KINDS:
        return problems + [f"{where}.kind {kind!r} is not one of {', '.join(sorted(KINDS))}"]
    if not (isinstance(step.get("technique"), str) and TECHNIQUE.fullmatch(step["technique"])):
        problems.append(f"{where}.technique must look like T1234 or T1234.001")
    if not _text(step.get("name")):
        problems.append(f"{where}.name is required")
    expect = step.get("expect", {})
    if not isinstance(expect, dict) or set(expect) - set(EXPECT_KEYS):
        problems.append(f"{where}.expect may only hold {', '.join(EXPECT_KEYS)}")
    params = step.get("params", {})
    if not isinstance(params, dict):
        return problems + [f"{where}.params must be an object"]
    return problems + _check_params(where, kind, params)


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
