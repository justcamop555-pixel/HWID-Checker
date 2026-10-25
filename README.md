# HWID Checker

A read-only PowerShell and Batch script to inventory hardware identifiers for debugging and system comparison.

## Features
- Gathers CPU, Motherboard, BIOS, Disk, and Network identifiers.
- Outputs to a clean console UI (v3.13+).
- Export options for TXT and JSON reports.
- Compare current hardware against previously saved JSON reports to detect hardware changes.

## Security Warning
This script collects highly sensitive system identifiers (Serial Numbers, UUIDs, MAC addresses, MachineGUID). 
**Never share generated reports publicly.** The `.gitignore` in this repository is configured to prevent accidental upload of generated reports.

## Usage
1. Download the latest version (e.g., `hwid.v3.13-backup-20261024-001359.bat`).
2. Right-click the file and select **Run as administrator** for the most accurate results.
3. Use the menu to view, save, or compare hardware IDs.

## Version History
- **v1.0**: Basic CMD queries.
- **v3.13**: Modern UI, improved navigation, safe console handling, and JSON comparison.
