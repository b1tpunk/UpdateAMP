# UpdateAMP

![Windows](https://img.shields.io/badge/platform-Windows-blue)
![Batch](https://img.shields.io/badge/script-Batch%20%28.cmd%2F.bat%29-lightgrey)
![Status](https://img.shields.io/badge/status-stable-brightgreen)
![License](https://img.shields.io/badge/license-MIT-green)

A safe, production-grade Windows batch script for updating **AMP Instance Manager** and upgrading AMP instances (including ADS).

This script is designed for real-world server environments where reliability, logging, and safety matter.

---

## Features

### Safety
- Confirmation prompts before stopping services and installing
- Automatic restore on abort
- Lock file prevents concurrent runs

### Logging
- Timestamped main log
- Separate MSI installer log
- Download progress logged and displayed live

### Intelligent Control
- Detects whether ADS is service-backed
- Uses Windows service control when applicable
- Falls back to `ampinstmgr` when needed

### Windows Server Aware
- Detects workstation vs server
- Automatically elevates `upgradeall` when required

---

## Files

```
UpdateAMP.bat     Main script
README.md         This file
CHANGELOG.md      Version history
RELEASE_NOTES.md  Release template
.gitignore        Excludes logs, MSI, lock file
logs/             Created automatically
```

---

## Usage

### Default instance (ADS01)

```
UpdateAMP
```

### Custom instance

```
UpdateAMP MyInstance
```

If a service-style name is passed (for example `AMP-ADS01`), the script will normalize it automatically.

---

## What It Does

1. Acquires a lock to prevent concurrent runs
2. Prompts for confirmation
3. Stops all AMP instances
4. Stops the ADS service if present
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

## Versioning Scheme

This project follows a semantic-style versioning scheme:

```
MAJOR.MINOR.PATCH
```

- MAJOR: Breaking behavior changes
- MINOR: New features
- PATCH: Bug fixes and reliability improvements

Example:
- v1.0.0 – First stable release
- v1.1.0 – Adds dry-run mode
- v1.1.1 – Fixes service wait bug

---

## Requirements

- Windows
- PowerShell
- AMP Instance Manager

---

## Known Limitations

- Batch scripting limitations apply
- Ctrl+C cannot reliably clean up the lock file
- Requires admin rights on Windows Server

---

## Roadmap

Planned enhancements:

- --yes unattended mode
- --dry-run mode
- Version comparison (skip MSI if current)
- Step timing metrics
- Timeout-aware service waits
- Structured logging

---

## License

MIT

---

## Author

Created by **b1tpunk**
