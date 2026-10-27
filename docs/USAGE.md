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

## Read the summary clearly

| Summary item | What it counts |
| --- | --- |
| Read status | Normal queries read versus not read; this is not a hardware-health guarantee |
| Identifier fields | Found, missing and default values supplied for individual fields |
| Review | All findings, including missing/default IDs; **[4]** explains them |
| Present devices | Windows records, distinct classes and records with hardware IDs; physical and virtual nodes are included |
| Extended devices | A separate catalog of known records, including hidden and remembered records |
| Uncertainty | Extended records with unread hiding flags or unknown presence; these groups can overlap |

**PREVIOUS catalog / refresh NOT READ** means the latest extended refresh failed and the older catalog was retained. The displayed extended capture time belongs to that older data. Check **[4]** for the latest failure and retry **[9] > [4]**. If the first attempt failed before a catalog existed, the summary says **NOT READ**, rather than Not scanned. A later successful refresh clears that failure status.

The summary can show all normal queries read while an optional extended refresh failed. Read status remains partial in that case. Class counts ignore casing/edge-space differences, while the full report preserves original provider text.

## Understand unreadable results

The scan's **NOT READ** label means the query did not supply usable records. **CHECK** means records were read but some fields or device records need review. The finish line counts read and not-read sections separately. When an extended catalog was requested, the same line also says **extended READ** or **extended NOT READ**. A failed extended read keeps the finish line amber even if all 17 normal queries succeeded.

| Code | Reason | Suggested action |
| --- | --- | --- |
| READ-01 | Access blocked | Run as administrator if appropriate, then rescan |
| READ-02 | Provider timed out | Retry the scan; the Windows provider may be slow or stalled |
| READ-03 | Provider unavailable | Check runtime/provider details in **[5]**; the Windows version may not expose it |
| READ-04 | No records returned | Check whether the device is expected or connected, then rescan |
| READ-05 | Other Windows read failure | Retry and inspect technical details in **[5]** or saved reports |
| READ-06 | Invalid scan data | Rescan; the provider returned unusable records rather than valid hardware data |

Main **[4]** groups conflicts, device findings, unreadable sections, and missing/default IDs separately. Use **1** for the top, **2** for devices, **3** for unreadable sections, **4** for ID fields, and **5** for conflicts. Missing instance IDs and unread device status are review findings; they do not establish that hardware is broken. Raw technical messages remain in the full report and exports.

Failure classification uses available typed errors/codes first, then known message patterns. An unfamiliar localized message without a recognized code remains READ-05. A timeout setting does not guarantee an overall scan deadline.

If a query emits an uncaught error after returning some records, that section is marked NOT READ rather than presented as a complete list. This prevents incomplete data from appearing as confirmed hardware removals during comparison. Successful fallbacks that handle their own errors remain usable. A missing serial within an otherwise valid record remains a missing-ID finding, separate from invalid scan data.

Network and extended-device readers retry their fallback when the primary reader fails or returns no records, including null-only results. Extended fallback enumeration stays unfiltered so remembered records can be included. The full report records which reader succeeded; extended capture information also records why fallback was needed. If both readers fail, technical details retain both messages; the failure reason describes the final reader. Direct and live-progress scans preserve the same error categories.

## Understand warnings and conflicts

The review summary counts findings, not unique devices. A device can have an unread status and a missing instance ID, producing two findings. Repeated instance IDs belong to the Conflicts group and are not counted again as ordinary device findings.

| Finding | What it means | Next step |
| --- | --- | --- |
| Source clash | Two unambiguously matched Windows storage records report different serials | Review both displayed values, rescan, and inspect the sources in **[5]** |
| Duplicate device key | More than one record has the same matching key | Rescan and inspect records in **[5]**; comparisons skip ambiguous keys |
| Repeated instance ID | Multiple PnP records claim the same instance ID | Rescan before comparing; this does not prove two physical devices share a factory serial |
| Disabled | Windows reports code 22 | Check whether disabling was intentional in Device Manager |
| Disconnected | Windows reports code 45 | Check the connection and refresh the scan |
| Unknown status | Windows supplied no readable status | Rescan and inspect device details; do not assume working or broken |

Disk sources are joined only when each has one valid record for the same disk number. Duplicate disk numbers remain separate records, preventing guessed matches from producing false serial clashes or filling the wrong device's missing serial. A source disagreement alone does not prove disk failure.

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
