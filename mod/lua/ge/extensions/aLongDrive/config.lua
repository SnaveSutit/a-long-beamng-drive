-- Tunables for A Long Drive. Distances are in metres. Reload with: extensions.reload("aLongDrive")
--
-- This file is the base: it describes the default (desert) look and holds the settings that apply everywhere.
-- Each biome in aLongDrive/biomes/ overrides what it wants, merged over this. Tables merge key by key;
-- lists (surfaces, pickupProps) are replaced whole. A biome only changes these:
--   road.width, moundHeight, shoulder, embankment (as defaults for its surfaces), surfaces, hills,
--   terrain.relief, reliefScale, blendDistance, material, pickups and pickupProps.
-- Everything else here is read from this file only.

local M = {}

-- Shared road settings. width, moundHeight, shoulder and embankment are only defaults: each surface below
-- has its own `road` table that overrides them.
M.road = {
  spacing = 30, -- between nodes
  meshStep = 5, -- target metres between mesh rows; smaller is smoother and heavier
  maxTurn = 0.1, -- radians per node; no turn is ever sharper than this
  turnResponse = 0.3, -- how quickly the road swings onto a new turn rate, per node
  turnWobble = 0.006, -- small random wander on top of the turns
  turnFlip = 0.6, -- chance a new curve bends the opposite way, which makes S-curves
  -- Kinds of curve, picked by weight. Lengths are metres; turns are radians per node (30 m), a gentle 0.02 is a
  -- 1.5 km radius and 0.1 is a 300 m one. A biome can replace the whole list.
  turns = {
    { name = "straight", weight = 2, minLength = 300, maxLength = 1500, minTurn = 0, maxTurn = 0.004 },
    { name = "gentle", weight = 3, minLength = 400, maxLength = 1400, minTurn = 0.008, maxTurn = 0.025 },
    { name = "sweeping", weight = 2, minLength = 300, maxLength = 1000, minTurn = 0.025, maxTurn = 0.055 },
    { name = "tight", weight = 1, minLength = 90, maxLength = 300, minTurn = 0.06, maxTurn = 0.1 },
  },
  startNodesBehind = 20, -- road behind the car when it starts
  width = 8,
  moundHeight = 0.5, -- the road bed sits this far above the ground beside it
  shoulder = 2, -- flat ground beside the road edge, before the embankment starts
  embankment = 3, -- metres of slope per metre of drop. The drop is an S-curve, so its steepest part is 1.5x the average
}

-- The biomes the road passes through, by file name in aLongDrive/biomes/. The first is where the road starts.
M.biomes = { "desert", "badlands", "saltPlain" }

-- Where two surfaces meet, the road eases from one's cross-section to the other's over this many metres.
M.surfaceTransition = 60

-- The same for two biomes, which also ease hill height, wavelength and the terrain's relief. Longer, since more changes.
M.biomeTransition = 400

-- The road switches between these as it goes. Each stretch lasts a random length in metres.
-- The first is where the road starts. textureLength is the metres along the road one texture repeat covers;
-- the paved texture has the lane markings painted in, made by tools/make-road-texture.ts.
M.surfaces = {
  {
    name = "paved", material = "aLongDrive_asphalt", textureLength = 16, weight = 1, minLength = 2000, maxLength = 10000,
    road = { width = 8, moundHeight = 0.5, shoulder = 2, embankment = 3 }, -- keep width in step with the texture tool
  },
  {
    name = "dirt", material = "aLongDrive_roaddirt", textureLength = 6, weight = 1, minLength = 800, maxLength = 5000,
    road = { width = 6, moundHeight = 0.1, shoulder = 1, embankment = 4 },
  },
}

M.hills = {
  minHeight = 0.5, -- keeps the road clear of the flat plain beneath it
  maxHeight = 100, -- road stays between minHeight and this above the plain
  -- Layers of noise added together, from broad hills down to bumps. wavelength is metres between crests;
  -- weight is how much of the shape the layer makes up.
  layers = {
    { wavelength = 2600, weight = 1 },
    { wavelength = 1100, weight = 0.8 },
    { wavelength = 520, weight = 0.4 },
    { wavelength = 240, weight = 0.12 },
  },
  -- Keep wavelengths above about 200 m: nodes are 30 m apart, and a shorter layer can't be drawn smoothly, so it
  -- shows up as lumps.
  gain = 3, -- how much of the height range the layers use; higher means more of the road sits near the limits
  variation = 0.6, -- 0 to 1: how much some stretches are hillier than others
  maxGrade = 0.1, -- rise over run; the steepest the road is allowed to get
  maxBend = 0.3, -- 0 to 1: the most the slope can change per node, as a fraction of maxGrade. Lower means rounder crests
}

M.terrain = {
  halfWidth = 500, -- shaped terrain each side of the road, fading to the flat plain at the edge
  fineWidth = 1, -- terrain this close to the road gets the fine rows; beyond it, one row per road node. Widened if the mound needs more
  cell = 10, -- lateral spacing of terrain vertices within fineWidth
  farCell = 30, -- and beyond it
  blendDistance = 60, -- from the shoulder to full hill relief
  relief = 12, -- extra height of off-road hills
  reliefScale = 150, -- wavelength of off-road hills
  textureScale = 10,
  material = "aLongDrive_dirt" -- defined in art/aLongDrive/main.materials.json,
}

M.devMode = false -- more pickups for testing; toggle with aLongDrive.setDevMode(true)

-- Which game props stand in for each pickup. One entry is picked at random per pickup, so repeat an
-- entry to make it more common. model and config are a folder and a .pc file in the game's vehicles/ folder.
M.pickupProps = {
  fuel = {
    { model = "barrels", config = "filled_oil" },
  },
  scrap = {
    { model = "cardboard_box", config = "small" },
    { model = "cardboard_box", config = "large" },
  },
}

M.pickups = {
  normal = { fuelChance = 0.12, scrapMin = 0, scrapMax = 1 }, -- per chunk
  dev = { fuelChance = 0.5, scrapMin = 1, scrapMax = 3 },
  shoulderMargin = 4, -- pickups keep this far from both edges of the shoulder
  reach = 2.5, -- how close, on foot, you must be to collect a pickup
  keyLabel = "G", -- shown in the prompt; the key itself is in settings/inputmaps/keyboard_aLongDrive.json
  fuelLiters = 8,
  scrapAmount = 1,
}

M.thickness = 2 -- solid depth under the road and terrain; collision only works on closed volumes

M.chunks = {
  nodes = 20, -- road nodes per chunk
  ahead = 4,
  behind = 1,
}

M.shiftDistance = 15000 -- distance from the origin before the car and world are shifted back

return M
