# A Long BeamNG Drive

A BeamNG.drive mod inspired by A Long Drive: an endless, procedurally generated post-apocalyptic world with roads running through it. Drive the road, or leave it and explore in any direction.

Work in progress. The prototype runs on the `smallgrid` level.

## Run it

1. Symlink `mod/` into your BeamNG mods folder:
   `ln -s "$PWD/mod" <user folder>/mods/unpacked/a_long_drive`
2. Start BeamNG and load the Grid, Small, Pure level (`smallgrid`).
3. Get in the car you want to drive, open the pause menu and go to **Mods > A Long Drive**. **New game, random seed** builds a world from a random seed and puts your car on the nearest road. The seed is shown on the page, so a world can be repeated from the Lua console (`~`) with `aLongDrive.start(<seed>)`.
4. **Stop** removes the world and restores the level. **Reload mod** reloads the Lua code, config and materials without restarting the game, and restarts a running world with the same seed (console: `aLongDrive.reload()`). **Reload UI** is for edits to the page itself.

## How it works

- The world is streamed in chunks around you: square terrain chunks (240 m) and segments of road (240 m), built a few milliseconds per frame, so nothing hitches at speed.
- Everything is a pure function of position and the seed: the height of the ground (`world.lua`), the biome (`world.lua`) and the roads (`roads.lua`). Any chunk can be built alone, in any order, which is what lets you go in any direction.
- At 15 km from the origin the car and the world shift back together without losing speed, which keeps floats precise.
- Terrain is a top-only surface: a car collides with it without a closed volume under it. Rebuilding the collision world costs about 0.4 ms per chunk, so it is done once after new chunks arrive.
- Fog hides the edge of the loaded world (see `fogDensity`), where the terrain stops short of the level's flat plain. A far-terrain ring would remove the need for it.

## The roads

Roads are contour lines of a warped coordinate, so they never meet or cross: they run roughly alongside each other, 2 to 2.7 km apart, and each is smooth and endless. Where they point comes from the seed. There are no junctions yet.

The ground near a road is levelled to the road's height out past the foot of its bed (`road.flatMargin`, a terrain mesh cell, so the coarse mesh can never poke through the bed) and eases back to the natural ground over `road.blendDistance`. The terrain's small bumps (the layers the road doesn't follow) come back over the same stretch, so the corridor isn't a smooth ribbon through rough ground. The road bed stands a little proud of the levelled ground and slopes down to it, gently and over a few metres: the drop is `moundHeight` plus the lean plus `BED_CLEARANCE` in `world.lua`, and the slope run is that drop times `embankment`. The road follows the terrain's broad hills (layers with waves at least `road.minWavelength` long), not the small bumps. Paved stretches have white edge lines and a dashed yellow centre line, painted into the paved road texture (`mod/art/aLongDrive/road_paved.png`). Regenerate it with `bun tools/make-road-texture.ts`; keep the road width and texture length in the script in step with the paved surface in the desert biome.

Each biome sets how its roads behave: `road.bends` (how big the sideways bends are; bigger means more turning), `road.minWavelength` (how much of the terrain's hills the road follows; lower means more crests and dips) and `road.features`. The road always follows the land. Features reshape the land around it so the drive has some shape: `hills` builds hills across the road, which climbs over them, and `sides` raises mountains beside it, so it runs along their foot for a stretch before the mountain gives way or switches sides. Heights are per biome: the desert has none, the badlands the most. Each surface also sets `roll`: the most the road leans to one side, in degrees, with the lean wandering at random along the road (dirt leans up to 4 degrees, paved up to 1; badlands dirt up to 6). The ground around the road leans with it. Where biomes meet, the bends ease over `road.bendTransition` (long, so roads do not fold). The desert is the base: smooth bends and long straights. On top of the bends, a biome can set `road.esses`: big swings that snake the road from side to side at three scales at once (long sweepers, medium bends and tight esses), with their pace drifting along the road and a second harmonic so no two bends match. They come in sections, between open stretches (`road.technical*` set how often). They only push the road along its own direction, so they can be big and tight without roads folding back on each other. Badlands have the most (bends down to about 20 m across, about a quarter of the road under 100 m radius, steeper crests and dips), the salt plain a gentler set. After changing any of these, run `tools/check-roads.lua` in the game console: it reports the turning, tightest bend, grades and the gap to the next road per biome. `tools/check-road-clipping.lua` checks that the road and shoulder never dip below the terrain beside them.

## Biomes

The world is split into biomes: the cells of a jittered grid about `biomeSize` metres across, each holding one biome centre. A point belongs to the nearest centre, and near a border the terrain eases from one biome's shape to the other's over `biomeTransition` metres. The ground material switches at the border. A biome overrides parts of the base config in `mod/lua/ge/extensions/aLongDrive/config.lua`: its terrain layers and ground material, and its road surfaces (and each surface's `width`, `moundHeight`, `shoulder` and `embankment`). Tables merge key by key over the base; lists such as `layers` and `surfaces` are replaced whole. Surfaces take stretches of the road in proportion to their `weight`.

| Biome | Hills | Ground | Road |
|---|---|---|---|
| desert | rolling, up to about 75 m | brown | paved and dirt |
| badlands | steep and choppy, up to about 90 m | red | mostly dirt, narrow |
| saltPlain | gently rolling, up to about 45 m | pale | wide, paved |

To add a biome, copy one of the files in `aLongDrive/biomes/`, change what you want, and list its name in `M.biomes` in `config.lua`.

## Tune it

The base settings live in `mod/lua/ge/extensions/aLongDrive/config.lua` (biomes override them): terrain layers, road spacing, curves and cross-section, chunk size and range, fog, materials. After editing, press **Reload mod**.

## Pickups

Paused. Fuel and scrap props beside the road are out until the world has points of interest (structures) that hold them. `pickups.lua` is left as it was and is not loaded.
