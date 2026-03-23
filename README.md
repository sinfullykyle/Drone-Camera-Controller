# Roblox Camera Controller System

A custom camera controller built in Luau that simulates responsive, physics-based motion using springs. This system focuses on mouse-driven camera sway, recoil effects, and dynamic feedback rather than traditional movement-based bobbing.

## Features

* Spring-based camera motion system
* Mouse-driven sway with smoothing and clamping
* Multiple recoil profiles (light, medium, heavy)
* Toggleable camera system (E key)
* Aim mode with reduced intensity (Z key)
* Sensitivity adjustment in real time ([ and ] keys)
* Optional axis inversion (X / Y keys)
* Dynamic FOV response based on mouse movement
* Idle camera motion when input is inactive
* Real-time debug interface with system data

## Systems Used

* CFrame transformation and layered composition
* Metatable-based object design (Spring + Controller)
* Mouse delta processing and smoothing
* RenderStep-based camera pipeline
* State handling and modular system structure
* Dynamic parameter tuning and input-driven behavior

## Usage

Place the script in a **LocalScript** inside `StarterPlayerScripts`.

## Controls

* **E** → Toggle camera system
* **Q / R / T** → Trigger recoil (light / medium / heavy)
* **Z** → Toggle aim mode
* **[ / ]** → Adjust sensitivity
* **X / Y** → Toggle axis inversion
* **F3** → Toggle debug UI

## Demo

This system is demonstrated in a Roblox place showcasing:

* Mouse-based camera sway and smoothing
* Recoil behavior and recovery
* Aim mode responsiveness
* Real-time debug feedback
* Dynamic FOV adjustments

## Notes

This script is intentionally written as a single-file system to demonstrate structure, readability, and understanding of Luau systems, camera math, and real-time input handling. The focus is on building a responsive and modular camera pipeline rather than relying on basic interpolation.
