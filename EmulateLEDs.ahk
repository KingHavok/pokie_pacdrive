;This code is written in AutoHotkey V2 and is designed to control the LEDs via an Ultimarc PacDrive device.
;It uses the PacDrive SDK DLL to communicate with the device and control LEDs based on MK6 Emulator button colors.
;
;Button colors are read via a single GDI BitBlt screen capture per tick so that all pixels are sampled at the
;same instant, eliminating timing mismatches when the emulator updates its buttons sequentially.
;
;Inspired by the work of ShaunJay https://shaunjay.com/2020/05/18/homemade-pokie-machine/#autohotkeycolour
;Written with the assistance of ChatGPT.

#Requires AutoHotkey v2.0
#SingleInstance
Persistent

; Opt into per-monitor DPI awareness so screen coordinates are not silently
; scaled on high-DPI displays. Harmless on standard-DPI systems.
DllCall("SetThreadDpiAwarenessContext", "Ptr", -3, "Ptr")

; The following can be modified before compiling to suit your use case.
ledBright := 55 ; intensity of the leds 0-100
deviceID := 0 ; note device uses 0 based numbering
groups := [1, 2] ; leds are grouped into blocks of 8. 0-7 = group 1, 8-15 = group 2 etc
leds := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13] ; led's being accessed. In this example we are using 14 LEDs. Some games use 16.

; Optional override. Leave blank for automatic architecture detection.
; Valid values: "PacDrive32.dll" or "PacDrive64.dll"
preferredDllName := ""

; Timer interval in milliseconds for polling emulator button colors.
checkIntervalMs := 20

; Target pixel color for lit MK6 buttons (RGB).
litButtonColor := 0xFFFF00

; GDI GetPixel returns BGR (0x00BBGGRR), not RGB. Pre-convert once so we
; avoid a per-pixel conversion inside the timer loop.
litButtonColorBGR := ((litButtonColor & 0xFF) << 16) | (litButtonColor & 0xFF00) | ((litButtonColor >> 16) & 0xFF)

buttons := [ ;Each button requires [x coord, y coord, LED #].
	[700, 35, 12], ; Reserve/Gamble
	[780, 35, 0], ; Bet 1
	[860, 35, 1], ; Bet 2
	[940, 35, 2], ; Bet 5
	[1020, 35, 3], ; Bet 10
	[1100, 35, 4], ; Bet 25
	[700, 100, 5], ; Take Win
	[780, 100, 11], ; Play 1
	[860, 100, 10], ; Play 5
	[940, 100, 9], ; Play 10
	[1020, 100, 8], ; Play 15
	[1100, 100, 7], ; Play 20
	[1180, 100, 6], ; Feature
	[1260, 100, 13] ; Spin
]

; Compute the bounding box of all button coordinates so we can capture the
; entire region in a single BitBlt call. A 2px margin avoids edge-pixel issues.
captureMargin := 2
captureMinX := buttons[1][1]
captureMinY := buttons[1][2]
captureMaxX := buttons[1][1]
captureMaxY := buttons[1][2]
for button in buttons {
    if (button[1] < captureMinX)
        captureMinX := button[1]
    if (button[2] < captureMinY)
        captureMinY := button[2]
    if (button[1] > captureMaxX)
        captureMaxX := button[1]
    if (button[2] > captureMaxY)
        captureMaxY := button[2]
}
captureX := captureMinX - captureMargin
captureY := captureMinY - captureMargin
captureW := (captureMaxX - captureMinX) + (captureMargin * 2) + 1
captureH := (captureMaxY - captureMinY) + (captureMargin * 2) + 1

; Precompute per-button lookup values once to avoid repeated math per timer tick.
; localX/localY are the button's offset within the capture bitmap.
buttonBindings := []
for button in buttons {
    ledNumber := button[3]
    grp := (ledNumber // 8) + 1
    port := Mod(ledNumber, 8)
    buttonBindings.Push({
        localX: button[1] - captureX,
        localY: button[2] - captureY,
        grp: grp,
        mask: 1 << port
    })
}

; Tracks the previously-written 8-bit LED state per group.
; We only call Pac64SetLEDStates when a group state changes.
lastGroupStates := Map()
for grp in groups {
    lastGroupStates[grp] := -1
}

; Begin Code

dllInfo := ResolvePacDriveDll(preferredDllName)
if !dllInfo["ok"] {
    MsgBox dllInfo["message"]
    ExitApp
}

dllName := dllInfo["name"]
dllPath := dllInfo["path"]

hModule := DllCall("LoadLibrary", "Str", dllPath, "Ptr") ; load the PacDrive DLL
if (hModule = 0) {
    MsgBox "Failed to load " dllName ". Tried: " dllPath
    ExitApp
}

initDll := DllCall(dllName . "\PacInitialize", "Int") ; initialise the PacLED64
if (initDll = 0) {
    MsgBox "Failed to initialise. No Ultimarc devices found."
    ExitApp
}

for led in leds { ; sets LED brightness for use later based on ledBright value.
    DllCall(dllName . "\Pac64SetLEDIntensity", "Int", deviceID, "Int", led, "Int", ledBright, "Int")
    Sleep(125)
}

for grp in groups { ; turn all LEDs off. LEDs will turn off in groups.
    DllCall(dllName . "\Pac64SetLEDStates", "Int", deviceID, "Int", grp, "Int", 0, "Int")
    lastGroupStates[grp] := 0
}

; Create GDI resources once and reuse them every tick. BitBlt overwrites the
; bitmap contents each time so there is no accumulation or leak.
hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
if (hdcScreen = 0) {
    MsgBox "Failed to get screen device context."
    ExitApp
}
hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
hBitmap := DllCall("CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", captureW, "Int", captureH, "Ptr")
hOldBmp := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hBitmap, "Ptr")
if (hdcMem = 0 || hBitmap = 0) {
    MsgBox "Failed to create GDI resources for screen capture."
    ExitApp
}

SetTimer(checkButtons, checkIntervalMs) ; Call the checkButtons function every checkIntervalMs.

checkButtons() {
    global buttonBindings, groups, deviceID, dllName, lastGroupStates, litButtonColorBGR
    global hdcScreen, hdcMem, captureX, captureY, captureW, captureH
    static desiredGroupStates := Map()

    ; Do not block the timer callback while waiting for the emulator process.
    if !ProcessExist("MK6Emu.exe") {
        return
    }

    ; Reuse this map each tick to reduce allocations.
    for grp in groups {
        desiredGroupStates[grp] := 0
    }

    ; Snapshot the button region — one GDI call captures all 14 buttons at the
    ; same instant, eliminating mid-update timing mismatches.
    if !DllCall("BitBlt", "Ptr", hdcMem, "Int", 0, "Int", 0,
            "Int", captureW, "Int", captureH,
            "Ptr", hdcScreen, "Int", captureX, "Int", captureY,
            "UInt", 0x00CC0020) {  ; SRCCOPY
        return  ; screen capture failed this tick; retry next tick
    }

    for binding in buttonBindings {
        ; CLR_INVALID (0xFFFFFFFF) won't match litButtonColorBGR, so
        ; a failed GetPixel safely leaves the LED off.
        color := DllCall("GetPixel", "Ptr", hdcMem,
                         "Int", binding.localX,
                         "Int", binding.localY, "UInt")
        if (color = litButtonColorBGR) {
            grp := binding.grp
            desiredGroupStates[grp] := desiredGroupStates[grp] | binding.mask
        }
    }

    ; Write to hardware only when a full group state changed.
    for grp, desiredState in desiredGroupStates {
        if (lastGroupStates[grp] != desiredState) {
            DllCall(dllName . "\Pac64SetLEDStates", "Int", deviceID, "Int", grp, "Int", desiredState, "Int")
            lastGroupStates[grp] := desiredState
        }
    }
}

ResolvePacDriveDll(preferredDllName) {
    expectedDllName := (A_PtrSize = 8) ? "PacDrive64.dll" : "PacDrive32.dll"

    if (preferredDllName != "") {
        if ((preferredDllName != "PacDrive32.dll") and (preferredDllName != "PacDrive64.dll")) {
            return Map(
                "ok", false,
                "message", "preferredDllName must be blank, PacDrive32.dll, or PacDrive64.dll"
            )
        }

        if (preferredDllName != expectedDllName) {
            return Map(
                "ok", false,
                "message", "DLL mismatch: this AutoHotkey runtime requires " expectedDllName " but preferredDllName is " preferredDllName
            )
        }
    }

    dllName := (preferredDllName != "") ? preferredDllName : expectedDllName

    candidatePaths := [
        A_ScriptDir "\" dllName,
        A_WorkingDir "\" dllName,
        A_WinDir "\System32\" dllName
    ]

    for candidatePath in candidatePaths {
        if FileExist(candidatePath) {
            return Map(
                "ok", true,
                "name", dllName,
                "path", candidatePath
            )
        }
    }

    return Map(
        "ok", false,
        "message", "Could not find " dllName ". Searched:`n - " candidatePaths[1] "`n - " candidatePaths[2] "`n - " candidatePaths[3]
    )
}

OnExit(finish)

finish(_ExitReason, _ExitCode) {
    global hModule, hdcScreen, hdcMem, hBitmap, hOldBmp, dllName, groups, deviceID

    ; Turn all LEDs off before shutting down.
    for grp in groups {
        DllCall(dllName . "\Pac64SetLEDStates", "Int", deviceID, "Int", grp, "Int", 0, "Int")
    }

    ; Shut down the PacDrive SDK before unloading the DLL.
    DllCall(dllName . "\PacShutdown")

    ; Restore original bitmap and release GDI resources.
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
