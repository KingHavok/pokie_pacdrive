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

# Development Note
Development on this project has ceased. The current implementation could be optimized further by reducing PacDrive calls. This can be achieved by storing the LED states and updating only when a change is detected. Contributions and optimizations through pull requests are welcome.

# Debugging
The script contains debug code for development purposes. You can omit these lines for regular use.

# Acknowledgements
Thanks to ShaunJay for the initial project idea and the AutoHotkey community for their support. https://shaunjay.com/2020/05/18/homemade-pokie-machine/

# Disclaimer
This project is for educational purposes and does not support real gambling.
