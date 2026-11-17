# Frequently asked questions

This FAQ describes the current source. Downloaded releases and older screenshots can differ; check the Desktop and scanner versions shown in the app.

**38 questions** about scan limits, PC-model differences, saving, comparison and troubleshooting.

- [Basics and identifier meanings](#basics-and-identifier-meanings)
- [Starting and reading scans](#starting-and-reading-scans)
- [Saving and comparison](#saving-and-comparison)
- [Installation, controls and troubleshooting](#installation-controls-and-troubleshooting)
- [Model-dependent scan results](#model-dependent-scan-results)

## Basics and identifier meanings

### 1. What does HWID Checker do?

It collects hardware information and identifiers exposed by local Windows providers, displays them in BAT or Desktop, and lets you save and compare captures. It reports readings; it does not certify hardware health or authenticity.

### 2. Is there one HWID number for my whole PC?

No. Firmware UUIDs, component serials, device IDs, network addresses and Windows installation identifiers describe different things. See the [identifier reference](IDENTIFIERS.md).

### 3. Can it recover every identifier on every PC model?

No. Available fields depend on the PC, firmware, drivers, Windows providers and permissions. The checker cannot manufacture a serial or recover a manufacturer-private value that Windows does not expose.

### 4. Are hardware IDs and device instance IDs the same as serial numbers?

No. Hardware IDs help Windows match devices to drivers; device instance IDs identify Windows device nodes. Neither label automatically means a factory serial. See Microsoft's [hardware ID](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/hardware-ids) and [device instance ID](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/device-instance-ids) definitions.

### 5. Why is a system UUID missing or all zeros?

The Windows-reported firmware value may be unavailable. Microsoft documents an all-zero UUID when the underlying system UUID is unavailable; this is not a usable unique identifier. [System UUID definition](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-computersystemproduct)

### 6. Is ProcessorId a unique CPU serial number?

Do not assume so. The checker labels it as processor identification data and preserves the Windows-reported value; it does not perform a uniqueness or authenticity check.

### 7. Why do two PC models expose different fields?

Manufacturers and drivers do not supply identical data, and Windows providers vary. A compatible fallback may recover a reading, but an absent optional field can remain unavailable without making the whole PC unreadable.

## Starting and reading scans

### 8. How do I start or repeat a scan?

In Desktop, choose **Scan this PC**. BAT scans at startup; after reaching its menu, use **[9] > [1]** for a full rescan. Both collect the normal hardware sections and the Windows-known device catalog.

### 9. What Windows and PowerShell versions are supported?

The Desktop package targets Windows x64 and includes its .NET runtime. Collection needs an allowed Windows PowerShell 5.1 or PowerShell 7 runtime in FullLanguage mode and working Windows providers. See [compatibility](../README.md#compatibility) and the [setup guide](../desktop/installer/README.md); a technical installer minimum is not a promise that every Windows build was tested.

### 10. Must I run every scan as administrator?

No. Normal scans can run as a standard user, although some providers may deny access. An authorized administrator run can help with a permission-specific read failure; it cannot create missing firmware values.

### 11. Why does Overview say Not scanned or Not checked before a scan?

No completed capture exists yet. These neutral labels are not warnings or zero-result claims. Review becomes meaningful after a scan is accepted.

### 12. What do READ, CHECK and NOT READ mean?

**READ** received usable data. **CHECK** received data with values or device records to review. **NOT READ** means that reader did not supply usable results; it is separate from a missing serial within a readable record.

### 13. Do missing or generic IDs mean my hardware is broken?

No. Firmware may return blanks or generic defaults, and some providers omit optional fields. Read the explanation in **Review** or BAT **[4]**, then inspect the full source details before drawing conclusions.

### 14. Is no battery an error on a desktop PC?

No. A successful empty battery query is reported as no battery reported by Windows; it does not prove that physically installed hardware is absent. Battery hardware is optional. A Windows battery device ID is not presented as a manufacturer serial. [Windows battery class](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-battery)

### 15. Does an unread Secure Boot or TPM field mean it is disabled or absent?

No. Unsupported firmware, missing providers or blocked access can prevent the reading. The Windows inventory includes separate Secure Boot and TPM read-status/code fields. An unknown value stays unknown; it is not changed to Disabled or No TPM. Microsoft's Secure Boot command distinguishes a disabled state from an unsupported platform and an access failure. [Secure Boot command behavior](https://learn.microsoft.com/en-us/powershell/module/secureboot/confirm-securebootuefi)

### 16. Why are there more device records than physical components?

Windows exposes virtual devices, multiple nodes for one physical device, and remembered disconnected devices. The all-known catalog is a list of Windows records, not a physical-component count. A guest VM scan describes what its guest Windows exposes; there is no host-hardware recovery feature.

### 17. Does Windows error code 12 prove a resource conflict?

No. It can indicate insufficient assigned resources, and firmware allocation can be involved. The checker keeps it visible as a device finding rather than treating it alone as proof of a collision. [Microsoft's code 12 explanation](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-normal-conflict)

### 18. Do duplicate IDs or conflicting readings prove spoofing or replacement?

No. Shared model IDs can be normal; duplicate matching keys or disagreeing sources require review. The checker retains the observations and skips ambiguous comparisons rather than guessing a match.

### 19. Why can network or storage readings differ between PCs or scans?

Different readers may expose different interfaces, fields or address types. The checker records available collection sources and separates current MAC addresses, permanent addresses, disk serials and volume IDs. A source change or disagreement alone does not establish a hardware change.

### 20. Why can progress reach 100% while some sections were not read?

Progress counts finished attempts, not successful reads. The current full scan has 18 normal checks plus the device catalog; inspect the read/failed counts and catalog status. Desktop also finalizes and validates the result before replacing the active capture.

### 21. Can I cancel a scan or rescan?

Desktop provides **Cancel scan** and keeps the previous completed capture until a replacement is accepted. Failed or cancelled attempts do not consume a successful scan number. BAT provides its documented scan/menu controls; Desktop's Cancel button is not a BAT keyboard shortcut.

### 22. Why can a scan take longer on another PC?

Windows providers, storage, system load, drivers and device counts affect query time. Fallback reads also take time. A per-reader timeout is not a guaranteed overall scan deadline; use the read details rather than assuming that waiting alone means a crash.

## Saving and comparison

### 23. How do I save a snapshot?

Choose **Save snapshot** in Desktop or **[6]** in BAT after the scan you want to keep. The engine writes and verifies a TXT/JSON pair using a new filename; the JSON is the comparison baseline.

### 24. Does saving twice collect another scan?

No. Both saves can contain the same active capture. Rescan first when you want a new set of readings; a rescan does not automatically save it.

### 25. Where are reports saved?

The configured shared save folder takes precedence. Otherwise, portable and installed copies use their documented report-folder defaults; BAT can fall back to the current user's LocalAppData report folder if the preferred location is unwritable. The save result shows the actual path.

### 26. Are reports private, encrypted or automatically redacted?

Reports and clipboard copies contain full identifiers and are not encrypted or automatically redacted by HWID Checker. Scanning uses local Windows APIs; update requests contact GitHub without including scan reports. OneDrive, other folder sync, or clipboard sync may copy data independently. Review or redact a separate copy before sharing.

### 27. How do I compare old and current identifiers?

In Desktop, compare the current scan with an older JSON, or choose two saved JSON files without scanning. In BAT, choose **[7]** and select the older capture. TXT can refer to its matching JSON; TXT alone and CSV/HTML reading exports are not replacement comparison inputs.

### 28. Why does comparison show no changes, or Not compared?

Two captures may contain the same supported values. **Not compared** identifies missing, unread or ambiguous information, so no changes does not establish that every identifier matched. A changed captured value also does not by itself prove physical replacement.

### 29. Why is a saved snapshot missing or outdated in the library?

Check **Folder settings**, search filters, file access, JSON validity and the import-size/version limits. Use manual **Refresh** to force fresh validation; automatic Desktop refreshes may reuse bounded preview metadata for unchanged files. Wait for another writer or sync to finish, then retry. The library uses local files, not a separate database.

## Installation, controls and troubleshooting

### 30. What if someone deletes the BAT or its launcher?

Desktop **Open BAT console** checks the scanner and can ask before restoring its embedded copy to the current user's local data folder. It does not overwrite custom files, download a scanner or repair a blocked PowerShell runtime. For the full installation, use its setup repair option.

### 31. Why is startup slow or the EXE missing companion files?

Extract the complete portable ZIP before launching and keep the EXE, managed app, DLLs, configuration files and language folders together. Running inside an archive or waiting for cloud-only files can delay startup. The loading window appears when Windows permits the launcher to run; startup time still depends on the PC.

### 32. Can I install without administrator access, and will uninstall erase reports?

The current setup offers **Just for me** for a normal non-admin launch and **All users** with administrator approval. Repair and updates keep the selected installation mode. Uninstall keeps saved reports, custom files and per-user settings; see the [setup guide](../desktop/installer/README.md) for scope and older-release differences.

### 33. How do I disable animations?

For BAT, set the process environment variable before launching from PowerShell:

```powershell
$env:HWID_NO_ANIMATION = '1'
.\hwid.bat
```

Desktop motion follows the Windows animation preference. Disabling motion does not reduce scan coverage.

### 34. How do updates work, and why might a local version be newer than GitHub?

Open Desktop **Updates** or BAT **[9] > [5]**. Automatic checks start enabled; portable copies prepare verified compatible packages, while setup-managed copies use the appropriate setup mode to update. A locally built candidate can be newer than a published release; an older release is not an upgrade. See [update behavior](UPDATES.md).

### 35. What should I do if startup or a menu action fails?

Keep the displayed error code and failure stage. Check an approved PowerShell 5.1/7 runtime and complete companion files; `Start-HWID.ps1` is the alternative launcher when usable. Recoverable BAT **UI-01** errors keep the active capture, but fatal **CRASH-01** recovery does not automatically save one; existing saved reports are not deleted. For a bug report, include app/scanner versions, Windows build, PowerShell version and steps, with identifiers and computer names redacted. See [startup and recovery](USAGE.md#startup-and-recovery).


## Model-dependent scan results

### 36. Why are no monitor identification records reported even though my display works?

Windows may expose no `WmiMonitorID` records for a headless, remote, virtual or non-reporting display configuration. A successful empty query is shown as a collection-status entry with **0 identification records**, without inventing a serial or missing-ID finding. The entry is a read result, not a physical monitor. Access denial, timeouts, missing providers and invalid data still retain their real failure status. See [Microsoft's monitor identification class](https://learn.microsoft.com/en-us/windows/win32/wmicoreprov/wmimonitorid).

### 37. What happens if the primary device reader returns malformed data?

The checker can try one compatible present-only reader and validate its complete result before accepting it. It retains the original failure and the reader source; it does not mix rejected partial records into the accepted inventory. If the alternate read also fails, the failure remains explicit. Access and timeout failures do not trigger that extra present-device recovery attempt.

### 38. What does Scan coverage mean, and can the scan finish with it?

A scan can finish reading useful device records while additional identification properties remain blocked, unreturned or inconsistent. **Scan coverage** describes that collection limit; it is separate from a device-status fault and from an entirely unread section. Inspect the listed source and counters, then retry if appropriate. A generic error after a partial property batch can trigger one bounded retry for missed nodes. Successful records and exact IDs are retained. If a primary all-known-device reader exposes no instance keys, one validated alternate may recover them; unmatched source observations remain separate. No completion label guarantees access to every private or manufacturer-specific identifier.