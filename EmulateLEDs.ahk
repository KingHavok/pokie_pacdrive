;This code is written in AutoHotkey V2 and is designed to control the LEDs via an Ultimarc PacDrive device.
;It uses the PacDrive SDK DLL to communicate with the device and control LEDs based on MK6 Emulator button colors.
;
;Inspired by the work of ShaunJay https://shaunjay.com/2020/05/18/homemade-pokie-machine/#autohotkeycolour
;Written with the assistance of ChatGPT.

#Requires AutoHotkey v2.0
#SingleInstance
Persistent

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

; Target pixel color for lit MK6 buttons.
litButtonColor := 0xFFFF00

buttn := [ ;Each button requires [x coord, y coord, LED #].
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

; Precompute per-button lookup values once to avoid repeated math per timer tick.
buttonBindings := []
for button in buttn {
    ledNumber := button[3]
    grp := Floor(ledNumber / 8) + 1
    port := Mod(ledNumber, 8)
    buttonBindings.Push(Map(
        "x", button[1],
        "y", button[2],
        "grp", grp,
        "mask", 1 << port
    ))
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
;if (initDll = 0) {
;    MsgBox "Failed to initialise. No Ultimarc devices found."
;    ExitApp
;}

for led in leds { ; sets LED brightness for use later based on ledBright value.
    DllCall(dllName . "\Pac64SetLEDIntensity", "Int", deviceID, "Int", led, "Int", ledBright, "Int")
    Sleep(125)
}

for grp in groups { ; turn all LEDs off. LEDs will turn off in groups.
    DllCall(dllName . "\Pac64SetLEDStates", "Int", deviceID, "Int", grp, "Int", 0, "Int")
    lastGroupStates[grp] := 0
}

CoordMode("Pixel", "Screen")
SetTimer(checkButtons, checkIntervalMs) ; Call the checkButtons function every checkIntervalMs.

checkButtons() {
    global buttonBindings, groups, deviceID, dllName, lastGroupStates, litButtonColor
    static desiredGroupStates := Map()

    ; Do not block the timer callback while waiting for the emulator process.
    if !ProcessExist("MK6Emu.exe") {
        return
    }

    ; Reuse this map each tick to reduce allocations.
    for grp in groups {
        desiredGroupStates[grp] := 0
    }

    for binding in buttonBindings {
        color := PixelGetColor(binding["x"], binding["y"])
        if (color = litButtonColor) {
            grp := binding["grp"]
            desiredGroupStates[grp] := desiredGroupStates[grp] | binding["mask"]
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

finish(ExitReason, ExitCode) {
    global hModule
    if (hModule != 0) {
        DllCall("FreeLibrary", "Ptr", hModule)
    }
}
