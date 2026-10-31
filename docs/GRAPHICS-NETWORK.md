# Graphics and network: field audit

[Main README](../README.md) · [Usage guide](USAGE.md)

This audit compares the checker's labels with Windows provider definitions and tests the conversions against actual local provider output. It does not independently authenticate hardware, serials, addresses or driver reports.

## Open the organized view

Choose Main **[3]**, then **[4] Graphics & network**. Shortcuts **1**, **2** and **3** jump to graphics adapters, network adapters and monitors. Enter or **0** returns to the main menu. The view reads the captured snapshot; Main **[9]** provides rescanning, and Main **[5]** retains raw details.

## Claims checked and corrected in 3.70

| Previous label or inference | Actual evidence | Corrected behavior |
| --- | --- | --- |
| One entry in the CIM address list was treated as the current MAC | `NetworkAddresses` lists port addresses without identifying the current one. [MSFT_NetAdapter](https://learn.microsoft.com/en-us/windows/win32/fwp/wmi/netadaptercimprov/msft-netadapter) | Keep current address unknown; show a sole distinct candidate separately as unverified. Preserve the full raw list. |
| Generic fallback link speed | Modern fields distinguish receive/transmit directions in bits/s; legacy `Speed` can be an estimate. [Modern provider](https://learn.microsoft.com/en-us/windows/win32/fwp/wmi/netadaptercimprov/msft-netadapter), [legacy provider](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-networkadapter) | Name receive/transmit rates separately; label legacy bandwidth as an estimate. Retain raw values. |
| Permanent address could imply an immutable factory value | Firmware/software may change the reported address. [MSFT_NetAdapter](https://learn.microsoft.com/en-us/windows/win32/fwp/wmi/netadaptercimprov/msft-netadapter) | Label it Windows-reported and keep it separate from current address. |
| Missing IDs on a non-hardware interface said “not used” | `HardwareInterface` describes hardware backing, not whether an absent ID is impossible. [MSFT_NetAdapter](https://learn.microsoft.com/en-us/windows/win32/fwp/wmi/netadaptercimprov/msft-netadapter) | Say not supplied / may not apply. Do not infer a specific virtual technology. |
| Generic graphics resolution | Controller dimensions are WMI-reported pixels; non-WDDM hardware can report inaccurate values. [Win32_VideoController](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-videocontroller) | Show a mode only for two valid positive dimensions. Describe missing/incomplete/invalid values; do not map controllers to monitors. |
| A generic `Speed` field could inherit the RAM MHz label in the hardware viewer | Network bandwidth and memory clocks use different units. [Win32_NetworkAdapter](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-networkadapter) | Use a network-specific bits/s label when displaying a raw network `Speed` field. Normal network collection uses named link-rate fields. |

## Reader coverage and comparison

The primary reader uses [Get-NetAdapter -IncludeHidden](https://learn.microsoft.com/en-us/powershell/module/netadapter/get-netadapter), which requests visible and hidden adapters. The direct CIM fallback has no matching switch in this application and can expose fewer records. The legacy reader is another compatibility source; its returned set can differ too. A read count is not proof of complete physical-device discovery.

Only explicitly supplied current addresses participate in current-address comparison. An unverified candidate cannot create a current-MAC change. Old snapshots that contain an inferred current address may consequently show a field as not compared with a new CIM-fallback capture. JSON preserves the reported candidate, raw list, directional rates and reader; existing saved files are not rewritten.

The application does not test internet speed/connectivity, verify factory addresses, calculate GPU VRAM, or establish GPU-to-monitor wiring from these fields.

## Validation on the development PC

- 50 focused checks cover direct/worker readers, labels, malformed metadata, grouping, snapshots, comparisons and native scrolling at 80/24 columns.
- Live audits on Windows PowerShell 5.1 and PowerShell 7.6.5: each matched 16 primary adapters by interface ID, with zero differences across current/permanent address, hardware flag, link rate and state.
- Forced direct CIM fallback: 4 records, with current address unresolved on all 4; all directional formatted rates matched retained raw values. Three records supplied address lists, whose sole candidates agreed with the primary reader on this PC. Agreement does not establish a current-address guarantee for other providers.
- One graphics controller supplied a complete WMI mode. This checks formatter consistency, not the physical display configuration.
- The full suite passed 1,504 checks per runtime. A read-only live scan/rescan read all 17 sections, refreshed both extended catalogs and preserved the previous snapshot.

Live diagnostics output counts only; identifiers are compared in memory. These observations describe one PC, not a compatibility or authenticity guarantee.
