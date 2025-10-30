# Roblox Tank Physics Sandbox

This project contains ModuleScripts and example server/client scripts for building a historically inspired tank-physics sandbox in Roblox. The focus is on suspension fidelity, track behaviour, and configurable terrain interaction.

## Folder layout

```
src/
  Modules/
    Suspension.lua
    WheelContact.lua
    SoilModel.lua
    Powertrain.lua
    UI.lua
  TankSandbox.server.lua
  Client/
    TankSandbox.client.lua
```

## Getting started in Roblox Studio

1. **Create shared modules**
   - In `ReplicatedStorage`, make a folder named `TankModules`.
   - Add ModuleScripts named `Suspension`, `WheelContact`, `SoilModel`, `Powertrain`, and `UI`.
   - Paste the contents of the matching files from `src/Modules` into those ModuleScripts.

2. **Server setup**
   - In `ServerScriptService`, create a Script named `TankSandbox`.
   - Add a child Folder called `Modules` only if you prefer to organise, but the script expects to pull from `ReplicatedStorage.TankModules`.
   - Paste the contents of `src/TankSandbox.server.lua` into the Script.

3. **Client setup**
   - In `StarterPlayerScripts`, create a LocalScript named `TankSandboxClient`.
   - Paste the contents of `src/Client/TankSandbox.client.lua` into the LocalScript.

4. **Play test**
   - Start Play mode. A hull with configurable road wheels, drive sprockets, and idlers will spawn along with the UI.

## Features

- **Modular suspension**
  - Supports torsion-bar swing arms (torque ∝ twist), Christie coil-spring bogies (long vertical travel), and a rigid test mode.
  - Semi-implicit Euler integration on `RunService.Heartbeat` drives custom spring-damper forces (or SpringConstraints if you adapt the module).
  - Optional dampers on historically accurate stations.
  - Debug overlays for arm angle, bump-stop engagement, per-wheel forces, contact points, and estimated slip/sinkage.

- **Track drivetrain**
  - Dual sprockets with neutral steer through independent angular velocity targets.
  - Configurable gear ratios, torque curve, braking torque, and sprocket backlash limit to reduce chatter.
  - Rear-drive sprocket and adjustable front idler that works with the tension setting to keep the track seated.

- **Terrain interaction**
  - Coulomb friction with slip ratio/angle blending for each road wheel.
  - Simplified Bekker–Wong pressure–sinkage model with Janosi–Hanamoto shear term for soft soil thrust and rolling drag.
  - Soil presets (Hard Road, Firm Dirt, Soft Sand) toggle cohesive/frictional parameters and rolling resistance.

- **UI and telemetry**
  - Panel to select suspension type, adjust spring/damper rates, preload, arm length, wheelbase, track width, idler offset, track tension, CG height, and soil preset.
  - Live readouts per wheel (deflection, slip, sinkage) plus key forces for quick tuning.
  - Keyboard bindings (W/S throttle, A/D steer, Space brake) feed the drivetrain.

- **Example presets**
  - *WWII torsion-bar, 6 road wheels/side*: tight torsion rates with dampers on the leading and trailing stations.
  - *Christie cruiser, 5 large wheels/side*: tall wheels with long arm travel and selective damping to emulate fast inter-war cruisers.

## Extending the sandbox

- Add more soil presets by extending `SoilModel.lua` (parameters are cohesion/friction coefficients and Bekker stiffness terms).
- Swap the spring-damper numerical integrator with Roblox `SpringConstraint`s by wiring them in `Suspension:createRoadWheels`.
- Implement projectile or weight-drop tests by spawning additional Parts and watching the telemetry overlay.

## Physical assumptions & notes

- Torsion bars resist twist, so torque is proportional to the arm angle relative to preload.
- Christie bogies place coil springs in tall housings, providing longer wheel travel for high-speed operation.
- Track tension is simplified as a scalar multiplier on normal force and idler position; it does not currently simulate separate track links.
- Soft soil calculations assume uniform contact pressure and use average sinkage across the patch; this approximates Bekker–Wong behaviour without iterative solvers.
- Drivetrain backlash is modelled as a small angular deadband that suppresses torque reversals when the sprocket speed matches the desired speed.

## Troubleshooting tips

- Ensure the `TankModules` folder exists in both server and client context (ReplicatedStorage replicates to both).
- If wheels jitter excessively on soft ground, lower the spring rate `k` or increase damping `c` via the UI.
- Increase `trackTension` or idler offset if the track slips too much or exhibits unrealistic slack.

Enjoy experimenting with historically grounded tank suspension behaviours!
