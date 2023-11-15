;This code is written in AutoHotkey V2 and is designed to control the LEDs via an Ultimarc PacDrive64 device. The code uses the PacDrive SDK Dll library to communicate with the device and control the LEDs. The code starts by checking if the correct version of the DLL (32 or 64 bit) is available based on the system architecture. It then loads the DLL and initializes it, sets the brightness of the LEDs, and turns all the LEDs off.
;
;This code is designed to be used in conjunction with the Aristocrat MK6 Emulator, which is an emulator for fruit machines. The code is checking the state of the virtual buttons in the emulator and controlling the LEDs of the PacDrive64 device accordingly. It also uses Sleep() function to take short breaks between certain operations; either to enable visual checks of LEDs or to reduce the load on the PacDrive device.

;The code uses a for loop to iterate through a list of buttons (stored in the 'buttn' array) and switch on or off each LED. The 'x' and 'y' coordinates represent the on-screen location of each virtual button and are used to check if the button light in the emulator is in an on or off state (Either yellow or not - using HEX colour codes). If the button is on, the corresponding LED is turned on. If the button is not on, the corresponding LED is turned off.

;This code could be improved further by creating an array to store the current state of each LED and only sending a command to the device if the state needs to change. This would reduce the load on the PacDrive64. Not currently implemented because I couldnt get the logic to work.

;Inspired by the work of ShaunJay https://shaunjay.com/2020/05/18/homemade-pokie-machine/#autohotkeycolour
;Written with the assistance of ChatGPT.

#Requires AutoHotkey v2.0
#SingleInstance
Persistent


; The folloing can be modified before compiling to suit your use case. At a minimum you will have to modify the x & y values in the button array.
ledBright := 55 ; intensity of the leds 0-100
deviceID := 0 ; note device uses 0 based numbering
groups := [1, 2] ; leds are grouped into blocks of 8. 0-7 = group 1, 8-15 = group 2 etc
leds := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13] ; led's being accessed. In this example we are using 14 LEDs. Some games use 16.
dllName := "PacDrive64.dll" ; set this to 32 or 64 bit depending on your use case. Note when compiling this code the app and the dll must be the same architecture. 32bit exe cant call 64bit DLL and vice versa. If you arent sure just set this to 32bit and compile 32bit.
buttn := [ ;Each button requires [x coord, y coord, LED #]. x&y refer to the screen coordinates within "MK6 Emulator" to look for button on/off state. Note ahk arrays start at 1 but pac64led LED's start at 0.
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
; Don't change the below values.
ledNumber := 0 ; creating a variable for use later
state := 0 ; creating a variable for use later
grp := 1 ; creating a variable for use later

; Begin Code

; Determine if correct PacDrive DLL has been selected based on the pointer size of the current system (ie has this been compiled in 32 or 64 bit)
if (A_PtrSize = 4 and dllName = "PacDrive32.dll") {
    }
else if (A_PtrSize = 8 and dllName = "PacDrive64.dll") {
    }
else {
    MsgBox "Mismatch between DLL and Application/System Architecture. The app wont work - refer dllName variable in source for instructions"
    ExitApp
}

hModule := DllCall("LoadLibrary", "Str", dllName) ; load the PacDrive DLL
if (hModule == 0) { ; test for success
    MsgBox "Failed to load " dllName ". File must be in either " A_WorkingDir " or " A_WinDir "\System32. You can download it from Ultimarc - it's within the PacDrive SDK"
    ExitApp
}

initDll := DllCall(dllName . "\PacInitialize") ; initialise the PacLED64
;if (initDll = 0) { ; test for failure
;    MsgBox "Failed to initialise. No Ultimarc devices found."
;    ExitApp
;}

for led in leds { ; sets LED brightness for use later based on ledBright value. All LEDs will light up during this process.
    DllCall(dllName . "\Pac64SetLEDIntensity", "Int", deviceID, "Int", led, "Int", ledBright)
    Sleep (125) ; the process illuminates ~4 LEDs per second. Enables visual check that all LEDs are working. Increase the sleep timer (ms) to slow it down.
}
;MsgBox "All the LEDs should be on. Press ok when ready to continue" ; enable this line if you have a faulty lED and you want to pause the script here to fix it.

for grp in groups { ; turn all LEDs off. LEDs will turn off in groups.
    DllCall(dllName . "\Pac64SetLEDStates", "Int", deviceID, "Int", grp, "Int", 0)
}
;MsgBox "All the LEDs should be off. Press ok when ready to continue" ; enable this line if you want to check this code working.

; During testing I needed this loop. Settimer should have been enough but I added it because the the program would exiting unexpectedly. Re-enable if you experience the same issue.
;Loop {
    SetTimer checkButtons, 20 ; Call the checkButtons function every 20ms.
;    Msgbox "Starting Loop " A_Index ; debug code to make sure this loop executes
;    }


; Define the checkButtons function that will be called repeatedly
checkButtons() {
    ProcessWait("MK6Emu.exe")
    ;MsgBox "CheckButtons function called"  ; debug code to make sure this function executes
    CoordMode  "Pixel", "Screen"

    ; Loop through all the values in the buttn array
    for index, value in buttn {
        color := Pixelgetcolor(value[1], value[2])
        ledNumber := value[3]
        ;MsgBox "Colour detected is " color " for LED " ledNumber " at screen coordinates " value[1] "," value[2] ; debug code to make sure this loop executes and pixelgetcolor returns correct values
        ; Check the color of the pixel and set the state accordingly
        if (color = 0xFFFF00) {
            state := 1
        }
        else {
            state := 0
        }

        ; Call the LightUp function to turn on or off the LED
        LightUp(ledNumber, state)
    }
}

; Define the LightUp function that takes in an LED number and state and turns on or off the LED accordingly
LightUp(ledNumber, state) {
    ;MsgBox "LightUp Function called for LED number " ledNumber
    if (ledNumber <= 7) {
        ; LED is in group 1
        grp := 1
        port := ledNumber
    } else {
        ; LED is in group 2
        grp := 2
        port := ledNumber - 8
    }

    ; Call the Pac64SetLEDState function to turn on or off the LED
    DidItWork := DllCall(dllName . "\Pac64SetLEDState", "Int", deviceID, "Int", grp, "Int", port, "Int", state)
    ;MsgBox "Dll called for DeviceID " deviceID ". Group " grp ". Port " port ". State " state ". Response was " DidItWork  ; debug code to see what was attempted. Response 1 means the card executed the command successfully.
}

OnExit finish

finish(ExitReason, ExitCode) {
    DllCall("FreeLibrary", "Str", dllName) ; Unload the PacDrive DLL
}



