# HWID Checker

Read local Windows hardware identifiers, save a snapshot, and see which IDs changed between scans. The checker is read-only: it does not change hardware identifiers or device settings.

**Current version: 3.54** · Windows · PowerShell 5.1 or newer

## Start here

1. Download the repository using **Code > Download ZIP**, then extract it. If you cloned it with Git, open the cloned folder.
2. Double-click **`hwid.bat`**. Keep `Start-HWID.ps1` beside it if you use the alternative PowerShell launcher.
3. Wait for the scan, press **Enter** to continue, then choose **[1] Summary** or **[2] ID numbers**.

Start as a standard user. If a section reports access denied, you can run it as administrator and rescan. Administrator access does not guarantee that firmware exposes every serial number.

The program needs Windows and PowerShell 5.1+ in FullLanguage mode. If a required runtime is unavailable or restricted, the launcher explains the problem. See [help and compatibility](docs/USAGE.md#compatibility-and-common-problems).

## What to choose

Type a menu number, then press Enter. Empty Enter is ignored on the main menu.

| Number | Use it to |
| --- | --- |
| **1** | Read the scan summary and coverage |
| **2** | See a short table of ID numbers and serials |
| **3** | Browse hardware categories and device IDs |
| **4** | Understand missing values, warnings and conflicts |
| **5** | Read the full inventory |
| **6** | Save the current snapshot as TXT and JSON |
| **7** | Compare a saved JSON snapshot with the current scan |
| **8** | Saved reports: open the folder and review storage status |
| **9** | Rescan, inspect extended devices, or open help |
| **0** | Exit |

**To find changed numbers:** save a baseline with **[6]**, rescan later using **[9] > [1]**, then use **[7]** to compare with that saved JSON. Use **[9] > [3]** for changes from the last rescan in this session.

## What it scans

The normal scan reads 17 sections covering system/firmware, CPU, memory, disks, volumes, partitions, graphics, monitors, network, Windows and present Plug and Play devices. **[9] > [4]** also reads Windows' hidden and remembered device records.

Windows may omit an identifier, report a default value, or retain an old device record. A hardware ID often describes a device model, rather than a unique physical unit. See [what the IDs mean](docs/IDENTIFIERS.md).

## Files in this repository

```text
hwid.bat          Main checker — double-click to start
Start-HWID.ps1    Alternative launcher; requires hwid.bat beside it
docs/             Usage, identifier explanations and recent changes
tests/            Developer checks; not needed to run the checker
```

Saved reports appear in `HWID-Reports/` beside the checker. They contain serial numbers and other identifying information. Reports, local backups and test output are ignored by Git; review files before uploading them manually.

Older script copies have been removed from the current repository layout. Previously committed versions remain accessible through Git history. Local backup files are stored outside the repository.

## More help

- [Save, compare, rescan and troubleshoot](docs/USAGE.md)
- [Understand the different identifiers](docs/IDENTIFIERS.md)
- [Recent changes](docs/CHANGELOG.md)
- [Run developer checks](tests/README.md)
