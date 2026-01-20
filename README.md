# UpdateAMP

A safe, production‑grade Windows batch script for updating **AMP Instance Manager** and upgrading AMP instances (including ADS) with:

- Live download progress
- Full timestamped logging
- MSI result handling (including reboot-required codes)
- Instance/service detection
- Automatic elevation on Windows Server
- Concurrency locking (prevents double-runs)
- Safe rollback on failure

This script was designed for real-world admin usage on long-running AMP servers where reliability matters.

---

## Features

### Safe by default
- Prompts before stopping instances
- Prompts before downloading/installing
- Automatically restarts services/instances on abort
- Lock file prevents multiple runs at once

### Logging
- All actions are logged with timestamps
- MSI installer output is logged separately
- Download progress is logged and shown live

### Intelligent control
- Detects if ADS is service-backed
- Uses Windows service control when applicable
- Falls back to `ampinstmgr` when no service exists

### Windows Server aware
- Detects Server vs Workstation
- Elevates `upgradeall` automatically when required

---

## Files

```
UpdateAMP.bat     # Main script
.gitignore        # Ignores logs, MSI, lock file
logs/             # Created automatically
```

---

## Usage

### Default (ADS01)

```bat
UpdateAMP
```

### Explicit instance

```bat
UpdateAMP MyInstance
```

If you pass a service name accidentally (e.g. `AMP-ADS01`), the script will normalize it automatically.

---

## What it does

1. Acquires a lock to prevent concurrent runs
2. Prompts for confirmation
3. Stops all AMP instances
4. Stops the ADS service (if present)
5. Downloads the latest AMP installer with live progress
6. Installs AMP silently
7. Handles MSI return codes correctly
8. Runs `ampinstmgr upgradeall`
9. Restarts the ADS service or instance
10. Releases the lock

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0    | Success |
| 1    | Failure |
| 2    | Lock already exists |
| 3010 | Success, reboot required (handled) |

---

## Logging

Main log:
```
logs/UpdateAMP-<instance>-<timestamp>.log
```

Installer log:
```
logs/AMPInstall-<timestamp>.log
```

---

## Locking Behavior

The script creates:

```
logs/UpdateAMP.lock
```

This prevents multiple simultaneous executions. If the script crashes or is force-killed, delete this file manually.

---

## Requirements

- Windows
- PowerShell
- Git (for version control)
- AMP Instance Manager

---

## Known Limitations

- Batch scripting limitations apply
- Ctrl+C cannot reliably clean up the lock file
- Requires admin rights on Windows Server

---

## Roadmap

Planned enhancements:

- `--yes` unattended mode
- `--dry-run` mode
- Version comparison (skip MSI if current)
- Step timing metrics
- Timeout-aware service waits
- Structured JSON logs

---

## License

MIT (recommended)

---

## Author

Created by **b1tpunk**

