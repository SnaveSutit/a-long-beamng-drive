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

- [ ] More dirt detail, then grass
- [ ] Road markings and a better asphalt
- [ ] Smooth the 0.5 m step at the road start
- [ ] Post-apocalyptic atmosphere: abandoned wrecks, landmarks, day and night, weather
- [ ] Check the corridor edge where the shaped terrain meets the flat plain
- [ ] Decide on real terrain streaming or a custom level, if the plain ever limits us

## Known issues

- [ ] Check the seams between chunks (every ~570 m) for bumps; neighbouring chunks are separate collision meshes
- [ ] The camera fix at world shifts covers the orbit camera only. Chase, external and others may flicker
- [ ] The vanilla recover keys (Home and Insert) may not use the on-road reset
- [ ] Stepping out of the car means pressing the vanilla walking key (F) at a standstill
- [ ] After a game restart the mod folder may need an unmount and mount before it loads

## Engineering

- [ ] Automated tests for the seeded road and pickup placement
- [ ] Profile chunk creation for hitches at speed (about 35 ms per chunk now; could be spread over frames)
- [ ] Package the mod as a zip for release, and write a how-to-run for it
- [ ] Demo and sign-off once the prototype loop (drive, collect, spend) works end to end
