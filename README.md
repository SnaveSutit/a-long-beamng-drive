# A Long BeamNG Drive

A BeamNG.drive mod inspired by A Long Drive: an endless, procedurally generated post-apocalyptic road. Collect fuel and scrap on the way, and keep driving.

Work in progress. The prototype runs on the `smallgrid` level.

## Run it

1. Symlink `mod/` into your BeamNG mods folder:
   `ln -s "$PWD/mod" <user folder>/mods/unpacked/a_long_drive`
2. Start BeamNG and load the Grid, Small, Pure level (`smallgrid`).
3. Open the in-game Lua console (`~`) and run `extensions.load("aLongDrive"); aLongDrive.start(1234)`. The number is the seed; leave it out for a random road.
4. `aLongDrive.stop()` removes the road and restores the grid.
5. `aLongDrive.setDevMode(true)` makes pickups frequent for testing; `false` goes back to the normal, rare rates.

## Tune it

Everything adjustable lives in `mod/lua/ge/extensions/aLongDrive/config.lua`: road width, hill height and grade, terrain width and relief, materials. After editing, reload with `extensions.reload("aLongDrive")`.

## How it works

- The road is generated ahead of the car and deleted behind it, from a seed.
- At 1.5 km from the origin the car and the world shift back together without losing speed, which keeps floats precise.
- Road and terrain are closed, solid meshes: collision in BeamNG only works on closed volumes.
