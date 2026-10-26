# Recent changes

[Back to the main README](../README.md)

## 3.41

- Fixed device browsing so USB input devices, cameras, audio and Bluetooth devices appear under their function. Unclassified USB nodes still appear under USB.
- Added unread/malformed Windows device status to review counts with an explicit unknown-condition explanation. Null provider rows are ignored.
- Accepted matching single or double quotes around pasted comparison paths. Apostrophes and other literal path characters are preserved; unmatched quotes, empty quoted paths and control characters get specific errors.
- Validation: 484 regression checks pass under Windows PowerShell 5.1 and PowerShell 7.6.5, plus eight launcher checks and native console diagnostics.

Grouping follows Microsoft's distinction between [device setup classes and interface classes](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/comparison-of-setup-classes-and-interface-classes) and its [system-defined setup classes](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/system-defined-device-setup-classes-available-to-vendors).

## 3.40

- Reorganized scan overview into results, query coverage and next actions.
- Separated identifier counts, present devices and extended-device groups.
- Kept unknown counts distinct from zero, with separate extended capture times.
- Verified normal, extended and failed summaries in the standard console, plus narrow-window scrolling.

## 3.39

- Added runtime/version checks and clearer compatibility errors.
- Added the alternative `Start-HWID.ps1` launcher.
- Improved handling of missing optional Windows commands and providers.

## 3.38

- Improved Next, Back and Exit animations.
- Preserved report text, colors, scrollback and queued keyboard input during transitions.

## Earlier improvements

Added hidden/remembered device details, rescanning, device-arrival/removal review, clearer saved-report comparisons and safer TXT/JSON export handling.

Older versions already committed to this repository are available through Git history. Loose local backups are not release files and are excluded from Git.
