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
