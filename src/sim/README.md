# SP Vision RoboMaster Simulator

Godot 4.x closed-loop simulator for `sp_vision_25`.

**3v3 multi-robot mode (current main scene):** six robots (red 0–2, blue 3–5), each with an isolated
vision engine in a shared worker process. Frames are tagged with `robot_id`/`team` over GDExtension,
multiplexed to per-robot YOLO + EKF + Planner state. See `VERIFY_3V3.md` for validation steps.

Legacy single-shooter description: the native extension receives images from each robot
`SubViewport`, runs OpenVINO YOLO on the CPU, and returns gimbal/fire commands to the simulation.

## Runtime tuning

Launch the project and press `C` in the Godot window to open the compact runtime YAML panel.
`Save YAML` writes only changed runtime values to `godot/configs/sim.runtime.yaml`; the worker merges
that file over `godot/configs/sim.yaml` on startup. `Apply` restarts only the isolated vision worker,
while `Reload base` removes the runtime override and reloads `sim.yaml`.

The panel computes the virtual-camera intrinsics from the actual Godot render state on every captured
frame:

```text
fy = image_height / (2 * tan(vertical_fov / 2))
fx = fy
cx = image_width / 2
cy = image_height / 2
```

The camera-to-gimbal extrinsics are also read from the current `Camera3D` transform relative to the
pitch axis. Godot uses `+X right, +Y up, -Z forward`; the bridge converts this to OpenCV camera axes
and the vision stack's `+X forward, +Y left, +Z up` gimbal axes before calling the solver.

## Automatic Hand-Eye Output

The runtime panel's `Auto hand-eye` command extracts the current virtual-camera calibration directly
from Godot and writes `godot/configs/handeye.auto.yaml`. It contains the live pinhole camera matrix,
zero distortion coefficients, and the camera-to-gimbal rotation/translation in the coordinate system
expected by `sp_vision_25`.

This is an automatic simulator calibration result, not a substitute for the real robot's multi-pose
circle-grid/PnP procedure in `sp_vision_25/calibration/calibrate_handeye.cpp`. The simulation has
access to the exact camera and gimbal transforms, so it can generate ground-truth calibration YAML
without a physical board or camera. The solver always uses these current engine-derived intrinsics and
extrinsics per captured frame, so a runtime resolution, FOV, or camera-mount transform change cannot
leave stale calibration in the closed loop.

`target_spin_rad_s` controls the enemy's rotation in target mode `3`. It is applied immediately from
the panel, accepts `-20..20 rad/s`, uses a negative value for reverse rotation, and uses `0` to keep
the lateral motion without self-rotation. The value is also persisted in `sim.runtime.yaml`.

The external OpenCV window `aim_error_scope` is intended for this validation. Yellow is Godot target
truth, green is the EKF target, red is the auto-aim command, and cyan is actual gimbal motion. Its
error graph separates vision error (`tracked - truth`) from servo tracking error (`gimbal - command`).
The displayed lead delta is the intentional prediction/ballistic command offset (`command - tracked`),
not a calibration error.

## Driving Controls

The first-person robot uses the common RoboMaster keyboard/mouse control split while retaining the
reference-inspired cascaded gimbal controller:

- `W` / `S`: move forward/backward in the current gimbal-facing direction.
- `A` / `D`: mecanum-style left/right translation.
- `Shift`: switch the chassis from the electrical control's 0.8 m/s normal limit to its 2.2 m/s
  burst limit.
- `Q` / `E`: toggle counterclockwise/clockwise gyroscope mode. Press the active direction again to
  return to gimbal-follow mode; pressing the other key reverses it directly.
- Mouse movement: set the manual yaw/pitch target; the gimbal follows through angle-to-speed and
  speed-PI loops rather than snapping the camera.
- Hold right mouse: enable auto-aim command takeover. Release it to return to manual control without
  an angle jump.
- Hold left mouse: fire visible simulated projectiles at the 0.12 s trigger interval. Automatic fire
  is disabled by default and can be enabled explicitly in the runtime YAML panel.
- `C`: open/close the runtime YAML panel and release/recapture the mouse.
- `Esc`: release the mouse. Left-click the game view to capture it again.
- `1` / `2` / `3`: stationary, lateral, or lateral-plus-spin target motion.
- `R`: reset the robot pose, gimbal state, tracker, shots, and hits (simulation-only shortcut).

The chassis follows the same control model as the complete 2026 infantry firmware from the reference
team: translation stays in the gimbal coordinate system, follow mode uses a 15-degree dead zone and
`Kp=2.5`, and the mecanum wheel command is scaled only when a wheel would exceed 3.2 m/s. The supplied
2027 sentry repository currently contains only the lower-level motor/PID foundation, so it does not yet
provide a chassis or keyboard-control task to mirror directly.

The HUD displays hits, shots, and hit percentage. A projectile that intersects an armor `Area3D`
records the hit and disappears immediately. A miss remains visible and continues along the gravity
trajectory until its two-second/40-meter cleanup limit.

The default muzzle speed is `23 m/s`, matching the nominal fallback in `sp_vision_25`. The
runtime panel writes the same `bullet_speed` value to both the Planner input and the physical projectile,
whose flight uses the same `9.7833 m/s^2` gravity-only trajectory model.

## Moving gyro regression

The graphical regression runs the complete Godot capture, OpenVINO YOLO, Solver, Tracker, Planner,
and gimbal-control path. It requires a display because headless mode intentionally skips viewport
capture. The test fails on poor detection/control rates, capture stalls, or rapid A-B-A armor switches.

```bash
SP_GYRO_SPIN=4.0 SP_GYRO_TRAVEL_SPEED=1.2 SP_GYRO_FRAMES=1500 \
  godot --path sim/godot --script res://tests/moving_gyro_test.gd

SP_GYRO_SPIN=-4.0 SP_GYRO_TRAVEL_SPEED=1.2 SP_GYRO_FRAMES=1200 \
  godot --path sim/godot --script res://tests/moving_gyro_test.gd
```

## Dependencies

- Godot 4.7
- CMake 3.20+
- OpenCV, OpenVINO, Eigen3, fmt, spdlog, yaml-cpp
- A Godot 4.7-compatible `godot-cpp` checkout at `sim/third_party/godot-cpp`

## Build

```bash
cmake -S sim/native -B sim/native/build -DCMAKE_BUILD_TYPE=Release
cmake --build sim/native/build -j
godot --path sim/godot
```

The extension is written to `sim/godot/bin/linux-x86_64/libsp_vision_sim.so`. Runtime model paths
are resolved from `sim/godot/configs/sim.yaml`; update them when exporting or relocating the app.
