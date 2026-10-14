# A Long BeamNG Drive

A BeamNG.drive mod inspired by A Long Drive: an endless, procedurally generated post-apocalyptic road. Collect fuel and scrap on the way, and keep driving.

Work in progress. The prototype runs on the `smallgrid` level.

## Run it

1. Symlink `mod/` into your BeamNG mods folder:
   `ln -s "$PWD/mod" <user folder>/mods/unpacked/a_long_drive`
2. Start BeamNG and load the Grid, Small, Pure level (`smallgrid`).
3. Get in the car you want to drive, open the pause menu and go to **Mods > A Long Drive**. **New game, random seed** builds a new road from a random seed and puts your car on it. The seed is shown on the page, so a run can be repeated from the Lua console (`~`) with `aLongDrive.start(<seed>)`.
4. **Stop** removes the road and restores the grid. **Frequent pickups** makes fuel and scrap spawn far more often, for testing; the console equivalent is `aLongDrive.setDevMode(true)`. **Reload mod** reloads the Lua code, config and materials without restarting the game, and restarts a running road with the same seed (console: `aLongDrive.reload()`). **Reload UI** is for edits to the page itself.

## The road

The road bed is a mound: flat out to the shoulder, then an embankment sloping down to the ground. Paved stretches have white edge lines and a dashed yellow centre line, painted into the paved road texture (`mod/art/aLongDrive/road_paved.png`). Regenerate it with `bun tools/make-road-texture.ts`; keep the road width and texture length in the script in step with `config.lua`. The road switches between surfaces (paved and dirt to start with) in stretches of a random length, set from the seed. Each surface has its own material and ground type, so the car grips differently. Each surface has its own `road` table in `config.lua` (`width`, `moundHeight`, `shoulder`, `embankment`), which overrides the shared defaults in `M.road`. Where two surfaces meet, the road eases from one cross-section to the other over `surfaceTransition` metres. The Mods page has a shoulder width slider per surface; pickups sit on the shoulder wherever it is set.

## Collect pickups

Pickups are real props beside the road: steel barrels for fuel, cardboard boxes for scrap. Driving past them does nothing. Stop, press `F` to step out of the car (the game's walking mode), walk up to a prop and press `G` to collect it. Fuel goes into the car's tank wherever it is parked. The `G` binding ships with the mod and can be changed in Options > Controls (Gameplay > Collect pickup).

## Tune it

Everything adjustable lives in `mod/lua/ge/extensions/aLongDrive/config.lua`: road width, hill height, steepness, spacing, roughness and mesh detail, terrain width and relief, materials. After editing, reload with `extensions.reload("aLongDrive")`.

## Pick the pickup props

`pickupProps` in the same config lists the game props that stand in for each pickup, as `{ model, config }` pairs. One is picked at random per pickup, so repeat an entry to make it more common. A model is a zip in the game's `content/vehicles/` folder (for example `barrels.zip`), and its configs are the `vehicles/<model>/*.pc` files inside (`filled_oil`). The vehicle selector shows display names, not these, so list the folder instead. Entries that don't exist are skipped with a warning in the log.

## How it works

- The road is generated ahead of the car and deleted behind it, from a seed.
- At 1.5 km from the origin the car and the world shift back together without losing speed, which keeps floats precise.
- Road and terrain are closed, solid meshes: collision in BeamNG only works on closed volumes.
