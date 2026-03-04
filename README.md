# Missile Defense Game (Godot 4)

This repository is a 2D missile-defense arcade game built in Godot 4 with GDScript.

## Current Gameplay Loop (as implemented)

1. Start from `MainMenu.tscn`.
2. Enter `Main.tscn` gameplay scene.
3. Defend buildings by firing timed-detonation projectiles.
4. Survive waves; wave 10 is treated as a boss wave in `GameManager`.
5. When all buildings are gone, load `UpgradeScreen.tscn`.
6. Spend resources and continue into a fresh run.

## Project Structure

- `project.godot` configures startup and autoloads `GameManager`.
- `Scene/` contains Godot scenes (`Main`, `MainMenu`, `UpgradeScreen`, prefabs).
- `Scripts/` contains gameplay logic for cannon, enemies, spawner, progression, UI flow.

## System Overview (Code-Mapped)

### Global progression (`Scripts/GameManager.gd`)

`GameManager` is an autoload singleton and currently tracks:

- `current_wave`, `current_world`
- `player_resources`
- upgrade state (`ammo_level`, `reload_speed_level`, `reload_upgrade_bought`, `extra_buildings`)
- wave state (`enemies_alive`, `wave_active`, `is_boss_wave`)
- active spawner reference (`spawner`)

Main responsibilities:

- Start and pace waves (`start_wave`, `spawn_enemies_gradually`)
- Track kills through enemy `enemy_died` signals (`_on_enemy_died`)
- Advance wave/world (`next_wave_or_boss`)
- Handle death/upgrade transition (`player_died`, `load_upgrade_screen`, `continue_from_upgrades`)

### Main game scene orchestration (`Scripts/Main.gd`)

`Main.gd` drives runtime UI and session flow:

- Hooks pause menu + debug destroy-all-buildings button
- Starts `GameManager.start_wave()`
- Displays ammo/wave/resources each frame
- Activates/deactivates building 5/6 based on `GameManager.extra_buildings`
- Detects run loss when building group is empty, then calls `GameManager.player_died()`

### Combat systems

- **Cannon (`Scripts/Cannon.gd`)**
  - Rotates to mouse
  - Fires projectile on left click if not on cooldown and ammo > 0
  - Reloads one ammo at a time via timer using `GameManager` upgrade values

- **Projectile (`Scripts/projectile.gd`)**
  - Moves toward clicked target point
  - Spawns an explosion on arrival
  - Can also explode when entering an enemy area

- **Explosion (`Scripts/explosion.gd`)**
  - Area2D with tweened growth/shrink
  - Destroys enemies in radius via `area_entered`
  - Uses `gives_reward` to control whether resulting kills should grant resources

- **Enemy (`Scripts/enemy.gd`)**
  - Falls along a velocity vector from top toward bottom target
  - Emits `enemy_died` signal when dying
  - On death, optionally grants resources and can spawn explosion (chain reaction)

### Wave and spawning (`Scripts/Spawner.gd`)

- Stores viewport size and registers itself into `GameManager.spawner`
- `spawn_enemy` creates falling enemies with randomized top spawn and bottom target
- `spawn_boss` exists and currently spawns `boss_scene` as if it were an enemy-like actor

### Economy + upgrades (`Scripts/UpgradeScreen.gd`)

Current purchasable upgrades:

- Max ammo (+2 per level)
- Ammo factory / reload upgrade
- Building 5 unlock
- Building 6 unlock

Resource spending mutates `GameManager` state directly and `continue_game` re-enters the run.

### Menus

- `MainMenu.gd`: start/quit
- `PauseMenu.gd`: resume/main-menu/quit with tree pause support

## Important Implementation Notes (Current Gaps)

1. **Boss implementation is incomplete.**
   - `BossUfo.gd` is a stub and has no behavior yet.
   - `Spawner.spawn_boss` expects enemy-like properties (`velocity`, `enemy_died` signal).

2. **Path/name consistency issues likely to break scene loads on some branches.**
   - `GameManager` has references to mixed paths like `res://scenes/...`, `res://MainGame.tscn`, `res://BossFight.tscn` that do not match current repo paths under `Scene/`.

3. **Reward pathway currently can double-count in chained edge cases.**
   - Reward is granted inside `enemy.die` and explosions can trigger further deaths; logic is mostly right but should be centralized to avoid future duplication.

4. **Upgrade reset semantics for next world are not yet designed in code.**
   - Existing upgrades currently persist while `current_world` increments.

## Recommended Next Architecture (for Planet Worlds)

To support "new planet = fresh local upgrades" while preserving long-term progress:

### A. Split progression into two layers

1. **Run/World-local upgrades** (reset when traveling to next planet)
   - Ammo level
   - Reload modifier
   - Temporary defensive unlocks

2. **Meta/campaign upgrades or unlock currency** (persist across planets and deaths)
   - Permanent economy multipliers
   - Boss token wallet
   - Planet unlock state

### B. Add explicit world transition rewards

When boss dies, grant one or more:

- **Planet Core** (guaranteed): required to unlock travel to next planet
- **Boss Salvage** (randomized): spend in an inter-world shop before landing
- **Bonus resources** based on remaining buildings and clear time

### C. Add a pre-planet "Loadout" step

Flow proposal:

- Boss defeated -> World Rewards Screen
- Convert reward into limited loadout picks for next world
- Enter next planet with reset local upgrades + chosen loadout perks

This preserves the fun of rebuilding while giving satisfying momentum.

### D. Define world difficulty profile data

Add per-world configuration (dictionary or resource):

- enemy speed multiplier
- spawn delay floor
- enemy HP variants/special missiles
- boss behavior set
- visual theme (planet palette/background)

## Suggested Implementation Order

1. **Stabilize scene path references in `GameManager`**
2. **Complete boss wave actor contract** (single base interface used by enemies + bosses)
3. **Implement world transition screen + reward model**
4. **Refactor upgrades into `run_upgrades` vs `meta_upgrades`**
5. **Add world config data and scaling hooks in `Spawner`/`Enemy`**
6. **Implement first real UFO boss behavior (teleport + missile fire + enemy rain)**

## Learning Guide (How to read this project)

If you want to learn while building, read in this order:

1. `Scripts/GameManager.gd` (game state and flow)
2. `Scripts/Main.gd` (scene orchestration + loss detection)
3. `Scripts/Spawner.gd` and `Scripts/enemy.gd` (wave pressure)
4. `Scripts/Cannon.gd`, `projectile.gd`, `explosion.gd` (combat core)
5. `Scripts/UpgradeScreen.gd` (economy/progression)
6. `Scene/Main.tscn` (how everything is wired together)

## Immediate Next Milestone

Implement **World Transition MVP**:

- After wave 10 boss defeat:
  - show rewards panel
  - apply world increment
  - reset run-local upgrades
  - keep meta currency
  - load next world scene/theme

This will establish the core "planet hopping" identity and make future bosses/upgrades easier to design.


## Node + Script Workflow (How I can help you in Godot)

To keep scene setup and scripts in sync while we build, we now have a reusable node contract helper: `Scripts/NodeContracts.gd`.

How we should use it every time we add a system:

1. I define the script API and required scene nodes up front (exact node paths + expected types).
2. We add those nodes in the scene tree (or I tell you exactly where to create them).
3. In `_ready()`, we call `NodeContracts.require_nodes_with_types(...)` so missing/wrong nodes are reported immediately.
4. You run the scene once and get clear console errors if anything is miswired.

Example (already added to `Main.gd`):

- Validates that `Cannon`, `Spawner`, key `UI` labels/buttons, and `PauseMenu` exist with expected Godot classes.

This lets us move faster without guessing whether a bug is logic vs scene wiring.

### What I’ll do for you going forward

For each new feature (boss UI, world transition screen, new weapons, etc.), I can provide:

- A **Node Checklist** (what to add in the scene tree)
- A **Signal Checklist** (what to connect)
- A **Script Contract** (expected exported vars, methods, and node paths)
- A **quick validation snippet** using `NodeContracts`

That gives you a repeatable “build + learn” loop in Godot instead of trial-and-error.
