# Code Review Plan — pokie_pacdrive

## Summary

Overall the codebase is small, focused, and well-structured. The latest refactor
introduced good optimizations (state caching, bitmask precomputation). The issues
below range from potential bugs to robustness and maintainability improvements.

---

## EmulateLEDs.ahk

### 1. Bug — PacInitialize failure is silently ignored

**Location:** `EmulateLEDs.ahk:82-86`

The `PacInitialize` call result is checked but the error path is commented out.
If no Ultimarc devices are connected, the script continues silently and all
subsequent DllCalls will operate against a non-existent device, producing
undefined behavior.

**Plan:** Uncomment the error check (lines 83-86) so the script exits with a
clear message when no device is found. If there is a valid reason to keep it
commented (e.g., testing without hardware), add a `skipDeviceCheck` config
variable instead of dead code.

---

### 2. Robustness — No error handling on DllCall results

**Location:** `EmulateLEDs.ahk:76, 82, 89, 94, 126, 180`

None of the `DllCall` invocations check their return values beyond
`LoadLibrary` and the (commented-out) `PacInitialize` check. If the device is
disconnected mid-session, LED calls will fail silently.

**Plan:** At minimum, check the return value of `Pac64SetLEDIntensity` during
initialization (line 89) and `Pac64SetLEDStates` during the timer loop
(line 126). Log or surface errors so the user knows the device has
disconnected.

---

### 3. Robustness — PacDrive shutdown not called

**Location:** `EmulateLEDs.ahk:175-182`

The `finish` exit handler frees the DLL module via `FreeLibrary` but never
calls `PacShutdown` from the PacDrive SDK. The SDK documentation indicates
`PacShutdown` should be called before unloading to release internal resources.

**Plan:** Add a `DllCall(dllName . "\PacShutdown")` before the `FreeLibrary`
call in `finish()`. The `dllName` variable will need to be declared `global`
in `finish()` or captured at script scope.

---

### 4. Robustness — `finish()` only frees the library, does not turn off LEDs

**Location:** `EmulateLEDs.ahk:177-181`

When the script exits, LEDs remain in whatever state they were last set to.
This may leave LEDs lit after the emulator is closed.

**Plan:** Before freeing the library, iterate over `groups` and call
`Pac64SetLEDStates` with state `0` for each group to turn all LEDs off on
exit.

---

### 5. Correctness — `litButtonColor` comparison may be case-sensitive

**Location:** `EmulateLEDs.ahk:117`

`PixelGetColor` returns a string like `"0xRRGGBB"`. The comparison
`color = litButtonColor` works because `litButtonColor` is set as a numeric
literal `0xFFFF00` which AHK v2 stores as an integer. However, if a future
change stores it as a string, the comparison could break due to case
differences in hex digits.

**Plan:** This is low-risk given the current code, but add a brief inline
comment documenting the assumption that `litButtonColor` must remain a numeric
literal (not a string) for the equality check to work reliably.

---

### 6. Design — `leds` array is unused beyond brightness initialization

**Location:** `EmulateLEDs.ahk:15, 88-91`

The `leds` array is only used to set brightness during startup. The actual LED
control is driven entirely by `buttn` / `buttonBindings`. If a user adds an
entry to `leds` but not to `buttn`, or vice versa, the configuration is
inconsistent.

**Plan:** Add a comment clarifying the relationship between `leds` and `buttn`
to prevent user confusion. Optionally, derive the `leds` list automatically
from the `buttn` array to eliminate the redundancy.

---

### 7. Design — `groups` array is manually specified but could be derived

**Location:** `EmulateLEDs.ahk:14`

The group numbers are derivable from the LED numbers in `buttn`
(`Floor(ledNumber / 8) + 1`). Manually specifying them risks getting out of
sync if the button map changes.

**Plan:** Consider deriving `groups` from `buttn` during the precomputation
step (lines 45-56). This removes a source of configuration mismatch.

---

### 8. Style — Magic numbers in button coordinate table

**Location:** `EmulateLEDs.ahk:27-42`

The button coordinates (700, 780, 860, etc.) are hard-coded without
explanation of what screen resolution or emulator window size they correspond
to.

**Plan:** Add a comment above the `buttn` array documenting the expected
emulator window position and resolution these coordinates target.

---

### 9. Cleanup — README mentions "debug code" that doesn't exist

**Location:** `README.md:37`

The README states "The script contains debug code for development purposes"
but no debug code is present in the current `EmulateLEDs.ahk`. This was
likely true of a previous version.

**Plan:** Remove or update the debugging section in `README.md` to reflect
the current state of the code.

---

## scripts/check_ahk_v2_syntax.sh

### 10. Bug — `Sleep` pattern has false positives

**Location:** `check_ahk_v2_syntax.sh:13`

The pattern `'^[[:space:]]*Sleep[[:space:]]+[0-9]+'` flags v1-style
`Sleep 1000` but AHK v2 also accepts `Sleep 1000` (without parentheses) as a
valid function call due to single-parameter command-style invocation. This
pattern will produce false positives on valid v2 code.

**Plan:** Refine the pattern to only flag `Sleep` when it is clearly using v1
command syntax (e.g., `Sleep, 1000` with a comma), or remove the `Sleep`
check entirely since AHK v2 is tolerant of parenthesis-free single-arg calls.

---

### 11. Improvement — Script depends on `rg` (ripgrep) without checking

**Location:** `check_ahk_v2_syntax.sh:26, 28, 32`

The script uses `rg` (ripgrep) for both file discovery and pattern matching.
If `rg` is not installed, the script fails with an unhelpful "command not
found" error.

**Plan:** Add a guard at the top of the script:
```bash
command -v rg >/dev/null 2>&1 || { echo "Error: ripgrep (rg) is required"; exit 1; }
```

---

### 12. Portability — `rg --files -g '*.ahk'` may miss files in subdirectories

**Location:** `check_ahk_v2_syntax.sh:32`

`rg --files -g '*.ahk'` searches recursively by default, so this is fine for
subdirectories. However, if a `.gitignore` or `.rgignore` excludes certain
paths, those `.ahk` files will be silently skipped.

**Plan:** Document this behavior or add `--no-ignore` if the intent is to
check all `.ahk` files regardless of ignore rules.

---

## scripts/create_full_backup.sh

### 13. Portability — `sha256sum` not available on macOS

**Location:** `create_full_backup.sh:31`

macOS ships `shasum -a 256` instead of `sha256sum`. The script will fail on
macOS.

**Plan:** Use a portable wrapper:
```bash
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$bundle_path" "$tar_path" > "$sha_path"
else
  shasum -a 256 "$bundle_path" "$tar_path" > "$sha_path"
fi
```

---

### 14. Minor — Backup restore command in heredoc uses wrong quoting

**Location:** `create_full_backup.sh:40`

The restore instruction `git clone "$bundle_path"` is inside a heredoc. The
`$bundle_path` will be expanded when the heredoc is printed, which is correct.
However, the output will show the literal expanded path without quotes around
it, which could break if the path contains spaces.

**Plan:** Wrap the variable in escaped quotes in the heredoc output, or
switch to a quoted heredoc (`<<'MSG'`) and use a separate `echo` for the
dynamic paths.

---

## .gitignore

### 15. Missing entries

**Location:** `.gitignore`

The `.gitignore` only covers backup artifacts. Consider adding:
- `*.exe` — compiled AutoHotkey binaries
- `*.dll` — PacDrive DLLs (usually vendor-supplied, not source-controlled)
- Editor swap/temp files (`*.swp`, `*~`, `.vscode/`, etc.)

**Plan:** Add common exclusions relevant to AutoHotkey development.

---

## Priority Summary

| # | Severity | File | Issue |
|---|----------|------|-------|
| 1 | High | EmulateLEDs.ahk | PacInitialize failure silently ignored |
| 3 | High | EmulateLEDs.ahk | PacShutdown never called |
| 4 | Medium | EmulateLEDs.ahk | LEDs not turned off on exit |
| 2 | Medium | EmulateLEDs.ahk | No error handling on DllCall results |
| 10 | Medium | check_ahk_v2_syntax.sh | Sleep pattern false positives |
| 11 | Low | check_ahk_v2_syntax.sh | Missing rg dependency check |
| 13 | Low | create_full_backup.sh | sha256sum not portable to macOS |
| 9 | Low | README.md | Stale debug code reference |
| 6 | Low | EmulateLEDs.ahk | leds/buttn redundancy |
| 7 | Low | EmulateLEDs.ahk | groups could be auto-derived |
| 5 | Low | EmulateLEDs.ahk | litButtonColor type assumption |
| 8 | Info | EmulateLEDs.ahk | Undocumented coordinate assumptions |
| 12 | Info | check_ahk_v2_syntax.sh | rg respects ignore files |
| 14 | Info | create_full_backup.sh | Heredoc quoting edge case |
| 15 | Info | .gitignore | Missing common exclusions |

---

# Implementation Plan — Bitmap Snapshot Pixel Reading

## Goal

Replace the 14 individual `PixelGetColor` calls per timer tick with a single
GDI `BitBlt` screen capture, then read all 14 pixels from the in-memory
bitmap. This achieves two things:

1. **Consistency**: All 14 button colors are captured at the same instant,
   eliminating the mid-cycle timing mismatch where physical LEDs briefly show
   a half-updated state because the emulator was partway through rendering
   when the script read the pixels.
2. **Speed**: One GDI call to the screen instead of 14, allowing faster ticks
   or lower CPU usage (or both).

---

## What changes and what stays the same

**Stays the same:**
- The `buttn` array and button coordinate format
- The `buttonBindings` precomputation and bitmask logic
- The `lastGroupStates` caching and change-detection
- All PacDrive DLL calls (`Pac64SetLEDStates`, etc.)
- The `ResolvePacDriveDll` function
- The `finish()` exit handler
- The timer-based polling model

**Changes:**
- `checkButtons()` inner loop: replace `PixelGetColor` with `GetPixel` from
  a memory DC
- New helper: `CaptureButtonRegion()` — performs a single `BitBlt` of the
  screen rectangle containing all buttons
- New helper: `ReleaseCapture()` — frees GDI resources after each tick
- New startup precomputation: calculate the bounding rectangle of all button
  coordinates once
- `buttonBindings` gains two new fields per entry: the button's x/y offset
  relative to the capture region origin
- `litButtonColor` is pre-converted to BGR format for direct comparison
  against raw `GetPixel` output (avoids per-pixel conversion)

---

## Critical detail — Color format

`PixelGetColor` returns RGB (`0xRRGGBB`). GDI `GetPixel` returns BGR
(`0x00BBGGRR`). The existing `litButtonColor` is `0xFFFF00` (RGB yellow).
In BGR that's `0x00FFFF`.

**Plan:** Add a one-time conversion at startup:
```ahk
litButtonColorBGR := ((litButtonColor & 0xFF) << 16)
                   | (litButtonColor & 0xFF00)
                   | ((litButtonColor >> 16) & 0xFF)
```
Then compare against `litButtonColorBGR` inside the loop. This avoids doing
a conversion on every pixel read every tick. The original `litButtonColor`
variable is unchanged so the config stays human-readable as RGB.

---

## Step-by-step implementation

### Step 1 — Compute the capture bounding box (startup, one-time)

After the existing `buttonBindings` precomputation loop (line 45-56), add
code that walks all button coordinates to find the min/max x and y values.
Add a small margin (e.g., 2px each side) to avoid edge-pixel issues.

Store as globals: `captureX`, `captureY`, `captureW`, `captureH`.

Also update each entry in `buttonBindings` to include `"localX"` and
`"localY"` — the button's position relative to the capture origin:
```
"localX" = button_x - captureX
"localY" = button_y - captureY
```

This avoids doing subtraction on every pixel read every tick.

### Step 2 — Pre-convert litButtonColor to BGR (startup, one-time)

Add a single line after `litButtonColor` is defined:
```ahk
litButtonColorBGR := ((litButtonColor & 0xFF) << 16)
                   | (litButtonColor & 0xFF00)
                   | ((litButtonColor >> 16) & 0xFF)
```

### Step 3 — Create GDI resources once at startup (not per-tick)

Rather than creating and destroying GDI objects every 20ms, create them once
during initialization and reuse them. This eliminates repeated allocation
overhead. The resources are:

```ahk
hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
hdcMem    := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
hBitmap   := DllCall("CreateCompatibleBitmap", "Ptr", hdcScreen,
                      "Int", captureW, "Int", captureH, "Ptr")
hOldBmp   := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hBitmap, "Ptr")
```

These four handles become globals. They persist for the life of the script
and are cleaned up in `finish()`.

**Why this is safe:** The memory DC and bitmap are a fixed-size scratch buffer.
`BitBlt` writes into it each tick, overwriting the previous contents. No
accumulation, no leak.

### Step 4 — Rewrite checkButtons() inner loop

Replace the current pixel-reading section:

```ahk
; CURRENT (remove this):
for binding in buttonBindings {
    color := PixelGetColor(binding["x"], binding["y"])
    if (color = litButtonColor) {
        ...
    }
}
```

With:

```ahk
; NEW:
; Snapshot the button region — one GDI call captures all 14 buttons at once.
DllCall("BitBlt", "Ptr", hdcMem, "Int", 0, "Int", 0,
        "Int", captureW, "Int", captureH,
        "Ptr", hdcScreen, "Int", captureX, "Int", captureY,
        "UInt", 0x00CC0020)  ; SRCCOPY

for binding in buttonBindings {
    color := DllCall("GetPixel", "Ptr", hdcMem,
                     "Int", binding["localX"],
                     "Int", binding["localY"], "UInt")
    if (color = litButtonColorBGR) {
        grp := binding["grp"]
        desiredGroupStates[grp] := desiredGroupStates[grp] | binding["mask"]
    }
}
```

The rest of checkButtons() (the group state comparison and `Pac64SetLEDStates`
calls) stays exactly as-is.

### Step 5 — Update finish() for GDI cleanup

Add GDI resource cleanup before the existing `FreeLibrary` call:

```ahk
finish(ExitReason, ExitCode) {
    global hModule, hdcScreen, hdcMem, hBitmap, hOldBmp
    ; Restore original bitmap and release GDI resources
    if (hdcMem != 0) {
        DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hOldBmp, "Ptr")
        DllCall("DeleteDC", "Ptr", hdcMem)
    }
    if (hBitmap != 0) {
        DllCall("DeleteObject", "Ptr", hBitmap)
    }
    if (hdcScreen != 0) {
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
    }
    if (hModule != 0) {
        DllCall("FreeLibrary", "Ptr", hModule)
    }
}
```

### Step 6 — Remove the CoordMode call

The current `CoordMode("Pixel", "Screen")` on line 98 exists because
`PixelGetColor` needs it. `BitBlt` with `GetDC(0)` always operates in
screen coordinates regardless of AHK's CoordMode. This line can be removed
(or kept as a no-op comment for clarity — it won't hurt anything).

### Step 7 — Update globals list in checkButtons()

The `global` declaration in `checkButtons()` (line 102) needs to add
`hdcMem`, `hdcScreen`, `captureX`, `captureY`, `captureW`, `captureH`,
and `litButtonColorBGR`. Remove `litButtonColor` from it since we now
compare against the BGR version.

---

## DPI awareness consideration

On high-DPI displays, Windows may silently scale the coordinates passed to
`BitBlt`, causing the wrong region to be captured. This would also have
affected the original `PixelGetColor` calls, so it's not a new problem —
but since we're touching this code anyway, it's worth adding a DPI fix.

**Plan:** Add one line near the top of the script, after `Persistent`:
```ahk
DllCall("SetThreadDpiAwarenessContext", "Ptr", -3, "Ptr")
```

This tells Windows "I'm handling my own DPI, don't scale my coordinates."
The value `-3` is `DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE` and works on
Windows 10 1607+. Since this is a pokie cabinet PC, it's very likely running
a fixed resolution with no DPI scaling, so this is a safety net rather than
a critical fix.

---

## Performance comparison

| Metric | Current (v2) | After bitmap snapshot |
|--------|-------------|----------------------|
| GDI calls to screen per tick | 14 (`PixelGetColor`) | 1 (`BitBlt`) |
| Pixel reads per tick | 14 (from live screen) | 14 (from memory — near-zero cost) |
| All pixels from same instant? | No | **Yes** |
| PacDrive calls per tick | 0-2 (unchanged) | 0-2 (unchanged) |
| GDI resource creation per tick | 0 | 0 (reused from startup) |

---

## Risk assessment

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| BGR/RGB mixup causes wrong color comparison | Medium if done carelessly | Pre-convert once at startup, add comment explaining the format |
| GDI resource leak if script crashes | Low (OS reclaims on process exit) | `finish()` cleanup handles normal exit; OS handles crashes |
| DPI scaling breaks coordinates | Low (fixed-res cabinet) | `SetThreadDpiAwarenessContext` guard |
| BitBlt fails (returns 0) | Very low | Add a check; if it fails, skip the tick (same as ProcessExist guard) |
| GetPixel on out-of-bounds coordinate | Very low | Bounding box includes all buttons; precomputed localX/Y are validated at startup |

---

## Files modified

Only **one file** changes: `EmulateLEDs.ahk`

No new files needed. The `buttn` config format is unchanged. The
`check_ahk_v2_syntax.sh` script does not need updating (no v1 syntax
introduced). The README could optionally mention the optimization but
that's cosmetic.
