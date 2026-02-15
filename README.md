# pokie_pacdrive
Custom Pokie Machine LED Control using AutoHotkey V2

# Overview
This project enhances the LED control of a custom-built pokie machine, using AutoHotkey V2 and an Ultimarc PacDrive64 device. Inspired by ShaunJay's Homemade Pokie Machine, it offers an improved implementation for synchronizing LEDs with the Aristocrat MK6 Emulator.

# Features
Efficient LED control with PacDrive64.
Customizable script for various machine configurations.
Debug code included for troubleshooting.

# Requirements
AutoHotkey v2.0
Ultimarc PacDrive64 with appropriate DLLs.

# Installation
Follow the steps outlined in the script comments to set up and customize your machine.

# Usage
Run the script alongside the MK6 Emulator to achieve synchronized LED effects.

# Customization
Modify script variables like ledBright, deviceID, leds, and buttn as needed.

DLL selection is now automatic based on the AutoHotkey runtime architecture (`A_PtrSize`):
- 64-bit runtime -> `PacDrive64.dll`
- 32-bit runtime -> `PacDrive32.dll`

If you need to force validation against a specific file name, set `preferredDllName` in `EmulateLEDs.ahk` to `PacDrive32.dll` or `PacDrive64.dll`. Leave it blank for automatic selection.

# Development Note
Development on this project has ceased.

Optimization update: the AutoHotkey v2 script now caches LED group state and only sends PacDrive updates when a group bitmask actually changes. It also precomputes button-to-group bitmasks and reuses timer-loop state maps to reduce per-cycle overhead. This reduces unnecessary PacDrive calls while preserving the existing behavior. Contributions and further optimizations through pull requests are still welcome.

# Debugging
The script contains debug code for development purposes. You can omit these lines for regular use.

# Acknowledgements
Thanks to ShaunJay for the initial project idea and the AutoHotkey community for their support. https://shaunjay.com/2020/05/18/homemade-pokie-machine/

# Disclaimer
This project is for educational purposes and does not support real gambling.

# Backup and Rollback
Create a full backup (repository history + working tree snapshot) with:

```bash
./scripts/create_full_backup.sh
```

Backup files are written to `./backups/` by default:
- `.bundle` file: full Git history and refs
- `.tar.gz` file: current working tree snapshot
- `.sha256` file: checksums for verification

You can pass a custom output directory:

```bash
./scripts/create_full_backup.sh /path/to/output
```



# AutoHotkey v2 syntax note
All script code in this repository targets AutoHotkey v2 (`#Requires AutoHotkey v2.0`). If you contribute changes, ensure no AutoHotkey v1-only syntax is introduced.

# AutoHotkey v2 Compliance Check
You can run a heuristic regression check to catch common AutoHotkey v1 command syntax:

```bash
./scripts/check_ahk_v2_syntax.sh
```

This does not replace runtime testing, but it helps prevent accidental reintroduction of v1-style commands.

