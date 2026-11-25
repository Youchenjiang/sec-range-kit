# rangekit.dfir

Evidence parsers and query helpers. Every evidence or output path goes through `rangekit.common.safe_paths`, so it must sit inside the working directory, this repository, the temp directory, `RANGE_KIT_DATA_ROOT` or a root listed in `RANGE_KIT_ALLOWED_ROOTS`.

## Setup

```bash
pip install -e ".[dfir]"     # pinned dissect.target / dissect.esedb stack
export RANGE_KIT_DATA_ROOT=/path/to/event-data   # evidence lives outside the repository
```

The pinned versions (`dissect.target==3.20`, `dissect.esedb==3.18`) are the known-good stack on Windows with Python 3.14; `dissect.target` 3.25.1 failed there.

## Tools

| Module | Purpose |
|---|---|
| `rangekit.dfir.query` | E01 / triage-bundle preflight and queries: directory list, stat, extract, raw `$MFT` name search, deleted MFT recovery, Registry, EVTX, SQLite, bounded artifact search |
| `rangekit.dfir.ese` | Bounded read-only ESE tables / schema / records (`SRUDB.dat`, `Windows.edb`) |
| `rangekit.dfir.ad1` | AD1 image list / metadata / extraction without FTK Imager |
| `rangekit.dfir.linux_audit` | Rebuild auditd events (SYSCALL, EXECVE, CWD, PATH, PROCTITLE) without `ausearch` |
| `response/linux_triage.sh` | Read-only Linux endpoint triage |
| `response/emergency_contain.sh`, `.ps1` | Reversible containment; status-only by default, apply and rollback need explicit scope variables |

Run preflight before the clock starts so parser problems surface early. Preflight fails closed when it sees `SRUDB.dat` or `Windows.edb` and the ESE backend is missing or the wrong version.

```bash
# Full E01
python -m rangekit.dfir.query preflight --image <sample.E01>
python -m rangekit.dfir.query find-mft --image <sample.E01> --name Settings.sqlite
python -m rangekit.dfir.query search-file --image <sample.E01> --path /pagefile.sys --needle <keyword>

# KAPE / triage bundle
python -m rangekit.dfir.query preflight --evidence-root <TriageDir>
python -m rangekit.dfir.ese tables --database <SRUDB.dat>
python -m rangekit.dfir.ese records --database <Windows.edb> --table SystemIndex_PropertyStore --contains <keyword>

# AD1
python -m rangekit.dfir.ad1 --list <image.ad1>
```

Extract and recover never overwrite existing output. Do not write recovered secrets into the repository.

## Origin

Ported from `security/tools/` in [sec-compendium](https://github.com/Youchenjiang/sec-compendium) (HITCON 2026 range toolchain). The old `SECURITY_LAB_DATA_ROOT` / `SECURITY_TOOLS_ALLOWED_ROOTS` variables still work when the new names are unset.
