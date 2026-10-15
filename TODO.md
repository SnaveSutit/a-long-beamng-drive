# TODO

Rough order within each section. Done items live in git history, not here.

## Pickups

- [ ] Physics-based grabbing: pick up a prop with your hands and carry it
- [ ] Pouring: carry a fuel barrel to the car and pour it into the tank, instead of the instant collect
- [ ] Walking camera: confirm the first-person view feels right, and check it across world shifts
- [ ] Props: try other models (crates, tires, coils) and see which rest and behave well on slopes
- [ ] Props show up when cycling vehicles with the switch-vehicle key; hide them from that if possible
- [ ] Balance: pickup rarity against fuel use. Normal rates are a first guess

## Core loop

- [ ] Spend scrap: repairs and part upgrades (decide what it buys first)
- [ ] Fuel: low-fuel warning, a "ran out of fuel" state, and a restart
- [ ] Choose the beater: the player picks a beater vehicle config to start with (part of the new-game flow, below)
- [ ] Save scrap and progress between sessions

## Start and UI

- [ ] A proper new-game flow: enter a seed and pick the beater. The Mods page only has a debug random-seed button for now
- [ ] Polish the HUD (layout, units, fuel gauge)
- [ ] Show the collect key from the real binding instead of the `keyLabel` setting

## World

- [ ] More biomes (forest, swamp, snow, ruined city) with their own textures; the three now only differ in tint, shape and surfaces
- [ ] Atmosphere per biome: sky, fog, time of day, weather
- [ ] Blend ground materials between biomes instead of switching at the boundary
- [ ] More dirt detail, then grass
- [ ] Worn paint and cracked asphalt for the post-apocalyptic look (more texture variants), potholes and sand drifts
- [ ] Give the generated asphalt a normal map; its grain is flatter than the game's own asphalt
- [ ] More surfaces (gravel, sand, broken asphalt), and a blended transition between surfaces
- [ ] Wheel ruts on the dirt road; its texture is a plain tint for now
- [ ] Road crown (camber) so the middle sits slightly above the edges
- [ ] Post-apocalyptic atmosphere: abandoned wrecks, landmarks, day and night, weather
- [ ] Junctions and forks, so roads connect. Roads never cross today (see README), which avoids overlapping road meshes
- [ ] A far-terrain ring (coarse, a few km out) so the fog that hides the edge of the loaded world can go. If the collision rebuild still hurts, try a native TerrainBlock
- [ ] Points of interest: structures that spawn in the world and hold props (fuel, scrap), to bring pickups back. `pickups.lua` is parked until then

## Known issues

- [ ] The camera fix at world shifts covers the orbit camera only. Chase, external and others may flicker
- [ ] The vanilla recover keys (Home and Insert) may not use the reset spot (the ground under the car, refreshed every second)
- [ ] Stepping out of the car means pressing the vanilla walking key (F) at a standstill
- [ ] After a game restart the mod folder may need an unmount and mount before it loads

## Engineering

- [ ] Markings are baked into one texture, so lane layout changes mean regenerating it. The game's DecalRoad doesn't project onto our road mesh, so decals aren't an option for now
- [ ] Automated tests for the seeded world: heights, biomes, road positions and chunk seams
- [ ] Package the mod as a zip for release, and write a how-to-run for it
- [ ] Demo and sign-off once the prototype loop (drive, collect, spend) works end to end
