# Roblox Camera Controller System

A fully custom camera system built in Luau that simulates realistic movement through spring-based physics, including sway, head bob, recoil, landing impact, and tilt.

## Features

* Spring-based camera physics system
* Movement-based head bob (walk & sprint states)
* Mouse-driven camera sway
* Landing impact detection
* Recoil system with manual testing (Q key)
* Toggle system (E key)
* Directional tilt based on movement
* Real-time debug interface

## Systems Used

* CFrame transformation and composition
* Metatable-based object design
* Velocity and local space calculations
* Humanoid state detection
* RenderStep camera updates

## Usage

Place the script in a LocalScript inside **StarterPlayerScripts**.

Controls:

* **E** → Toggle camera effects
* **Q** → Trigger recoil test

## Demo

This system is demonstrated in a live Roblox place showing:

* Idle / walk / sprint transitions
* Landing impact effects
* Real-time camera feedback

## Notes

This script is written as a single-file system to demonstrate structure, readability, and understanding of Luau systems and Roblox APIs.
