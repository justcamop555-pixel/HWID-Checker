# What the identifiers mean

[Back to the main README](../README.md)

There is no single universal HWID number for an entire PC. The checker shows the different values Windows exposes and preserves their device/source context.

| Identifier | Describes | Limit |
| --- | --- | --- |
| Component serial number | A value supplied by a component or its firmware | May be missing, generic or duplicated |
| System UUID | The system UUID reported by firmware | May be unavailable or a placeholder |
| CPU ProcessorId | Processor identification data | Not a guaranteed unique CPU serial |
| Hardware ID | A device model/function used for driver matching | Many devices can share it |
| Compatible ID | A broader driver-matching identifier | May be missing normally |
| Device instance ID | A Windows device node | May depend on bus/port and enumeration |
| Disk/partition GUID | A disk layout or partition identifier | Applies to relevant disk formats; differs from a factory serial |
| Volume serial number | A filesystem volume identifier | Can change when a volume is formatted |
| MAC / permanent address | Network-interface address reported by Windows | Current and permanent addresses can differ |
| Windows Machine GUID | An identifier associated with the Windows installation | Not a component serial number |

**[2]** gives a short table. **[3] > [6]** browses present device IDs. **[5]** shows full arrays and source details. **[6]** exports the snapshot.

In **[2]**, use the numbered section shortcuts: **1 PC & firmware**, **2 CPU & RAM**, **3 Storage**, **4 Monitor/network**, and **5 Windows**. Only groups containing selected fields are offered. **0** or Enter returns to the menu. Chassis serials are included, and network rows distinguish the current MAC from the permanent MAC. An older snapshot without a permanent-address field does not acquire a made-up missing value.

**OK** means Windows supplied a value; it is not a uniqueness check. Separate components can report the same value. Disk serials are kept separate from volume IDs, CPU identifiers and the Windows installation ID. **NOT READ** names sections that could not be read. Long values are visibly shortened in the quick table; **[5]** and saved JSON retain full values.

The scan rejects arrays, booleans or objects where a scalar serial/device key is expected, using **READ-06**. A blank scalar serial remains a missing value in an otherwise readable record. Hardware/compatible-ID lists remain lists; leading zeros and original report text are preserved. Console control characters are removed from displayed labels/values so they cannot change table colors or move the cursor.

The optional **[9] > [4]** extended scan includes hidden/remembered Windows records, parent links and available status properties. Physical devices, virtual devices and old records must be interpreted separately. No scan can guarantee every manufacturer's private identifier or discover hardware that Windows does not expose.

For official definitions, see Microsoft's [hardware IDs](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/hardware-ids), [device instance IDs](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/device-instance-ids), [system UUID](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-computersystemproduct) and [processor data](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-processor).
