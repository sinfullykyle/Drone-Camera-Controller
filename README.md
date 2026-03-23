# Roblox camera control system

![Luau](https://img.shields.io/badge/Luau-Roblox-blue)
![Type](https://img.shields.io/badge/System-Camera_Controller-green)
![Status](https://img.shields.io/badge/Status-Active-success)

A custom camera controller built in Luau that simulates responsive, physics-based motion using springs.
This system focuses on **mouse-driven camera sway, recoil effects, and real-time feedback**, designed for immersive experiences and FPS-style games.

---

## Features

* Spring-based camera motion system
* Mouse-driven sway with smoothing and clamping
* Multiple recoil profiles (light, medium, heavy)
* Toggleable camera system (**E key**)
* Aim mode with reduced intensity (**Z key**)
* Live sensitivity adjustment (**[ and ] keys**)
* Optional axis inversion (**X / Y keys**)
* Dynamic FOV response based on mouse movement
* Idle camera motion when inactive
* Real-time debug interface

---

## Systems Used

* CFrame transformation and layered composition
* Metatable-based object design (Spring + Controller)
* Mouse delta processing and smoothing
* RenderStep camera pipeline
* Modular state handling
* Dynamic parameter tuning

---

## Controls

| Key           | Action                          |
| ------------- | ------------------------------- |
| **E**         | Toggle camera system            |
| **Q / R / T** | Recoil (light / medium / heavy) |
| **Z**         | Toggle aim mode                 |
| **[ / ]**     | Adjust sensitivity              |
| **X / Y**     | Toggle axis inversion           |
| **F3**        | Toggle debug UI                 |

---

## Usage

Place the script in a **LocalScript** inside:

```plaintext
StarterPlayerScripts
```

## Notes

* Built as a **single-file system** to demonstrate structure and clarity
* Focused on **responsive camera feedback**, not simple interpolation
* Designed to be **easy to expand into full FPS

---
