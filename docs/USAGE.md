# Using HWID Checker

[Back to the main README](../README.md)

## Read a scan

Use **[1]** for the overview. It separates normal query coverage, identifier fields, present devices and optional extended records.

| Label | Meaning |
| --- | --- |
| Found | Windows supplied a value that is not recognized as a default |
| Missing | An expected field was not supplied |
| Default | Windows supplied a known placeholder value |
| NOT READ | A query or optional catalog could not be read |
| Not scanned | The optional extended scan has not been requested |
| Conflict | Sources disagree, or records cannot be matched reliably |
| Status not supplied | Windows did not return a readable device status; condition is unknown and included in review |

Found does not prove that an identifier is unique or authentic. Missing/default values are different from failed queries. **[4]** explains findings; **[5]** shows full values and sources. Extended records have their own capture time and are not added to the normal identifier-field total.

## Save a baseline

1. Finish the scan you want to keep.
2. Choose **[6]** to create a TXT and JSON pair.
3. Choose **[8]** to open `HWID-Reports/` beside `hwid.bat`.

TXT is for reading. JSON is for comparison. Saves use new filenames rather than overwriting previous reports. Rescanning does not save automatically.

## Find which numbers changed

1. Keep a saved JSON baseline from **[6]**.
2. After changing hardware or connecting devices, choose **[9] > [1]** to refresh the current scan.
3. Choose **[7]** and enter the path to the baseline JSON.
4. Read the previous/current values and the indicated character differences.

Pasted paths can use matching single or double quotes. Brackets, apostrophes and ampersands are treated as literal filename characters. The checker does not execute pasted text or expand shell commands.

Comparison also identifies added/removed records. Missing or duplicate matching keys can prevent a reliable match; the checker explains skipped comparisons rather than guessing. A changed device-instance ID can reflect a different port or Windows device record.

For two consecutive scans in the same session, **[9] > [3]** reopens the last rescan comparison. Save with **[6]** if you need a snapshot after closing.

## Scan hidden and remembered devices

Choose **[9] > [4]**. Windows may expose hidden flags, disabled devices, disconnected records, unknown presence and additional device properties. The extended view provides numbered shortcuts for these groups.

Hidden and remembered are different properties, and their groups can overlap. A remembered record does not prove that hardware is still connected. Unknown presence or unread visibility stays unknown. Once an extended catalog has been collected, a PC rescan also attempts to refresh it.

## Navigation

- Main menu: type **0–9**, then Enter. Empty Enter is ignored.
- Reports in the checker's readable console: scroll with the wheel, arrows, Page Up/Down or Home/End. Use any numbered shortcuts printed on that page.
- Report pages: Enter returns to the menu. Where the footer offers **0**, that also returns.
- Navigation animations can be disabled by setting `HWID_NO_ANIMATION=1` before launching.

## Compatibility and common problems

The checker requires Windows and PowerShell 5.1 or newer in FullLanguage mode. Current validation covers Windows PowerShell 5.1 and PowerShell 7.6.5 on a Windows PC; it does not establish support for every historical Windows build.

| Problem | What to do |
| --- | --- |
| COMPAT-01 / no suitable PowerShell | Use an installed PowerShell 5.1+ runtime approved for your Windows version. The checker does not install one. |
| COMPAT-02 / restricted execution | Ask your administrator about approved execution. The checker does not change persistent policy. |
| COMPAT-03 from the PS1 launcher | Read the accompanying message. Keep `Start-HWID.ps1` and `hwid.bat` together. |
| CMD is unavailable | Use `Start-HWID.ps1` in an approved PowerShell session. Normal script policies still apply. |
| A section is unavailable | Open **[4]**. A provider may be absent, blocked, or unable to expose data. Other sections remain usable. |
| Access denied | If appropriate, run as administrator and rescan. Permissions cannot supply values missing from firmware. |
| A value is shortened | Open **[5]** or save with **[6]** for full values. |
| Nothing changes in a saved report | Saved files are snapshots. Rescan and choose **[6]** to create a new pair. |
| A JSON report cannot be compared | Use the JSON exported by a supported checker version, not TXT. Keep the original error message for troubleshooting. |

If both CMD and a suitable PowerShell runtime are unavailable, this script-based checker cannot run. Windows-specific hardware providers may limit coverage even when the runtime is supported.
