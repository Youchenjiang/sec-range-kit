# rangekit.vm

Run commands and move files inside a VMware analysis VM through VMware Tools (VMCI), with no SSH, WinRM or open guest ports.

## Setup

Copy `.env.example` to `.env` (git-ignored) and set `VM_VMX`, `VM_GU` and `VM_GP`. `.env` is the default `--creds-file`; a credentials file inside the repository is used only when Git confirms it is ignored. `VM_VMRUN` is optional: the tool looks for `vmrun` on `PATH`, then the standard VMware Workstation path.

## vmrun_guest

```bash
python -m rangekit.vm.vmrun_guest tools                     # VMware Tools state
python -m rangekit.vm.vmrun_guest exec "whoami /all"
python -m rangekit.vm.vmrun_guest powershell "Get-Service | Select-Object -First 5"
python -m rangekit.vm.vmrun_guest put <host_path> <guest_path>
python -m rangekit.vm.vmrun_guest get <guest_path> <host_path>
python -m rangekit.vm.vmrun_guest kill cmd.exe powershell.exe
```

Why a wrapper:
- `vmrun` waits forever on bad or missing credentials, so every call has a timeout.
- `runProgramInGuest` returns no stdout, so output is redirected to a guest file and copied back.
- A timeout stops only the host-side `vmrun`; a leftover guest `cmd.exe` keeps the output file open and the next call reads stale output. Run `kill cmd.exe powershell.exe` and retry.

## Guest setup scripts (`setup/`)

| Script | Purpose |
|---|---|
| `vm_setup_dfir.ps1` | Install Eric Zimmerman Tools, Chainsaw, Hayabusa, Sysmon and optional EVTX samples; idempotent, `-DryRun` supported |
| `vm_ez_fix.ps1` | Detect and work around a broken `Expand-Archive` (missing `Microsoft.PowerShell.Archive`) |
| `vm_dfir_verify.ps1` | Verify the installed DFIR toolchain |
| `vm_tool_inventory.ps1` | List the tools present in the guest |
| `validate_ps1_syntax.ps1` | Parse scripts on the host before uploading; a syntax error costs minutes inside the VM |

```bash
python -m rangekit.vm.vmrun_guest put rangekit/vm/setup/vm_setup_dfir.ps1 'C:\Windows\Temp\setup_dfir.ps1'
python -m rangekit.vm.vmrun_guest exec "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Windows\Temp\setup_dfir.ps1 -DryRun"
```

Guest scripts print ASCII only: the guest console code page (for example CP950) turns other text into mojibake once stdout is redirected to a file.

## Guest collection scripts (`collect/`)

Generic Windows DFIR collectors. Every path is a parameter whose default matches the `vm_setup_dfir.ps1` layout (`C:\Tools\DFIR`); outputs go under `C:\Tools\DFIR\out\` unless `-OutDir` / `-BaseDir` says otherwise.

| Script | Changes the guest | Purpose |
|---|---|---|
| `telemetry_recon.ps1` | no | Identity, Sysmon service and config, audit policy, Defender, log sizes, Sysmon EID mix, local accounts |
| `audit_baseline.ps1` | yes | Back up the audit policy, enable 4688 (with command line), 4698, 4776 and 4104, enlarge logs, enable TaskScheduler/Operational, flag inert Sysmon sections |
| `evtx_export.ps1` | no | Export the key channels, write an EID census for `-WindowMinutes`, run EvtxECmd, Hayabusa and Chainsaw over the same set (`-SkipTools` to export only) |
| `hayabusa_run.ps1` | Hayabusa folder only | Fetch the missing `rules/config` with `update-rules` (`-SkipUpdate` offline), then run `dfir-timeline` |
| `artifact_recon.ps1` | no | Prefetch, Amcache, Shimcache, USBSTOR, UserAssist, ConsentStore, EZ Tools presence, Prefetch baseline for `-BaselineExes` |
| `user_hive_probe.ps1` | no | Resolve which user hive holds UserAssist / ConsentStore when HKCU points at `.DEFAULT` under vmrun |
| `artifact_parse.ps1` | hive copies only | Parse `snapshot\` and `hives\` copies with PECmd, AmcacheParser, AppCompatCacheParser and RECmd batches |

```bash
python -m rangekit.vm.vmrun_guest put rangekit/vm/collect/audit_baseline.ps1 'C:\Windows\Temp\audit_baseline.ps1'
python -m rangekit.vm.vmrun_guest exec "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Windows\Temp\audit_baseline.ps1 -OutDir C:\Tools\DFIR\out\baseline"
```

Revert `audit_baseline.ps1` with `auditpol /restore /file:<OutDir>\auditpol_backup.csv`. `tests/test_vm_collect.py` keeps these scripts ASCII, parameterised, parseable and free of event-specific names.

## Known-answer scenarios (`scenario/`)

A scenario file lists benign, reversible steps that make specific telemetry appear, so a detection exercise has an answer key. `scenario.example.json` covers every step kind with neutral names; each event keeps its own scenario file next to its other material.

| File | Purpose |
|---|---|
| `scenario.example.json` | Example scenario: 14 steps from scheduled task to WMI subscription, each with its ATT&CK technique and expected Sysmon / Security / other events |
| `run_scenario.ps1` | Guest runner. Resets leftovers, runs each step, writes `ground_truth.csv`, `sim_log.txt` and `window.txt`; `-Cleanup` removes every artifact newest first and verifies each is gone |
| `process_access_check.ps1` | Adds one Sysmon ProcessAccess rule for `-TargetImage`, reloads Sysmon, opens handles with each `-Access` mask and saves the EID 10 events; `-Revert` reloads the baseline config |

Step kinds: `scheduled_task`, `service`, `run_key`, `local_user`, `group_add`, `failed_logons`, `encoded_powershell`, `certutil_decode`, `ads`, `lolbin_egress`, `discovery`, `eicar`, `process_open`, `wmi_subscription`. Cleanup is derived from the same names, so what a step creates is exactly what `-Cleanup` removes.

No secret goes in the file: a `local_user` step reads its password from the guest environment variable named in `password_env` (or uses a random one), and `failed_logons` generates its wrong passwords at run time.

```bash
python -m rangekit.vm.scenario validate my-event.json     # names, kinds, params, no stray keys
python -m rangekit.vm.scenario plan my-event.json         # what -Cleanup will remove
python -m rangekit.vm.vmrun_guest put my-event.json 'C:\Windows\Temp\scenario.json'
python -m rangekit.vm.vmrun_guest put rangekit/vm/scenario/run_scenario.ps1 'C:\Windows\Temp\run_scenario.ps1'
python -m rangekit.vm.vmrun_guest exec "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Windows\Temp\run_scenario.ps1 -Scenario C:\Windows\Temp\scenario.json"
python -m rangekit.vm.vmrun_guest exec "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Windows\Temp\run_scenario.ps1 -Scenario C:\Windows\Temp\scenario.json -Cleanup"
```

Run `audit_baseline.ps1` first so the expected Security events are actually written. `tests/test_vm_scenario.py` checks the validator, that the runner implements exactly the validated kinds, and that the example stays valid and generic.

## Origin

Ported from `security/tools/` in [sec-compendium](https://github.com/Youchenjiang/sec-compendium). The `collect/` and `scenario/` scripts are generalised from the 2026 HITCON practice scripts; artifact staging and deliverables are still being turned into templates driven by per-event config.
