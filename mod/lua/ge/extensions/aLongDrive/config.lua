-- Tunables for A Long Drive. Distances are in metres. Reload with: extensions.reload("aLongDrive")
--
-- This file is the base: it describes the default (desert) look and holds the settings that apply everywhere.
-- Each biome in aLongDrive/biomes/ overrides what it wants, merged over this. Tables merge key by key;
-- lists (layers, surfaces, pickupProps) are replaced whole. A biome only changes these:
--   road.width, moundHeight, shoulder, embankment, roll (as defaults for its surfaces), surfaces,
--   road.bends, minWavelength and features, terrain.layers and material, pickups and pickupProps.
-- Everything else here is read from this file only.

local M = {}

-- The roads: contour lines of a warped coordinate, so they never meet or cross. See roads.lua.
-- width, moundHeight, shoulder and embankment are only defaults: each surface below has its own `road` table.
M.road = {
  spacing = 2400, -- average metres between roads; they range from about 0.4 to 1.6 times that
  -- How far the road wanders sideways, as layers of noise: bendWavelengths are the metres between bends, and
  -- bends the most each layer adds, which a biome can change. Bigger amplitudes or shorter wavelengths tighten
  -- the bends, and past a point roads fold back on themselves or touch: run tools/check-roads.lua after changing them.
  bendWavelengths = { 2000, 800, 350, 160 },
  bends = { 220, 70, 25, 0 },
  -- Swings: the road snakes from side to side, at several scales at once: long sweepers, medium bends, tight esses.
  -- Unlike the bends above they only push the road along its own direction, so they can be big and tight without
  -- roads folding back on each other. essWavelengths are metres per swing and `esses` (set by each biome) the
  -- amplitude of each. A slow noise (technicalWavelength metres across) gates each one between technicalFloor and 1,
  -- so they come in sections, with open stretches between. technicalStart and technicalFull are the noise values
  -- (it sits mostly between 0.3 and 0.7) where a swing begins and reaches full size; lower values make more of the
  -- road technical. Past a point they make hairpins too tight to drive: run tools/check-roads.lua after changing any of this.
  essWavelengths = { 1300, 560, 250 },
  esses = { 0, 0, 0 },
  essDrift = 0.3, -- how far the pace of the swings drifts along the road, in swings: higher is less regular, and tighter at the fast end
  essHarmonic = 0.35, -- how much of a second, twice-as-fast swing is mixed in, which reshapes the bends (0 is plain back and forth)
  technicalWavelength = 1600,
  technicalFloor = 0.1,
  technicalStart = 0.2,
  technicalFull = 0.5,
  bendTransition = 1200, -- where biomes meet, the bends ease over this many metres: long, so roads do not fold
  -- The land is reshaped around the roads so they are not just highways over the same terrain. A biome sets the
  -- heights (metres; the base is none): hills.height builds hills across the road, which climbs over them, and
  -- sides.height raises mountains alongside it, so it follows their foot for a stretch. Both come and go along each road.
  features = {
    hills = { height = 0, wavelength = 1400, width = 350 }, -- width: how far out the hill reaches either side of the road
    sides = { height = 0, wavelength = 1800, offset = 30, plateau = 150 }, -- offset: where the slope starts; plateau: width of the top
  },
  segment = 240, -- metres of road per mesh
  meshStep = 4, -- target metres between mesh rows along the road; smaller is smoother and heavier
  flatMargin = 12, -- the ground is levelled with the road this far past the foot of its bed. The terrain mesh has a vertex
  -- every chunks.cell metres and its triangles reach that far, so any rise closer than that would poke through the bed
  flatWidth = 26, -- but never past this far from the centre of the road
  blendDistance = 45, -- and eases back to the natural ground over this much further
  minWavelength = 300, -- the road follows the terrain's layers with waves at least this long, not the small bumps. Lower is hillier
  surfaceWavelength = 3500, -- how long a stretch of one surface lasts, roughly
  rollWavelength = 120, -- how quickly the road's lean changes along it; each surface sets how far it may lean
  surfaceBlend = 0.04, -- how softly one surface gives way to the next, as a share of the surface noise
  width = 8,
  moundHeight = 0.15, -- the road bed sits this far above the ground beside it, before any lean
  shoulder = 2, -- flat ground beside the road edge, before the embankment starts
  embankment = 3, -- metres of slope per metre of drop. The drop is an S-curve, so its steepest part is 1.5x the average
  roll = 1, -- the most the road leans to one side, in degrees. The lean wanders at random along the road
}

-- The biomes of the world, by file name in aLongDrive/biomes/.
M.biomes = { "desert", "badlands", "saltPlain" }

-- Biomes are the cells of a jittered grid this many metres across, so a biome is about this wide.
M.biomeSize = 2500

-- Where two biomes meet, the terrain eases from one's shape to the other's over this many metres.
M.biomeTransition = 400

-- The road switches between these as it goes, in stretches set by a slow noise. Each takes a share of the road by its
-- weight. textureLength is the metres along the road one texture repeat covers;
-- the paved texture has the lane markings painted in, made by tools/make-road-texture.ts.
M.surfaces = {
  {
    name = "paved", material = "aLongDrive_asphalt", textureLength = 16, weight = 1,
    road = { width = 8, moundHeight = 0.15, shoulder = 2, embankment = 6, roll = 1 }, -- keep width in step with the texture tool
  },
  {
    name = "dirt", material = "aLongDrive_roaddirt", textureLength = 6, weight = 1,
    road = { width = 6, moundHeight = 0.05, shoulder = 1, embankment = 6, roll = 4 },
  },
}

M.terrain = {
  -- Layers of noise added together, from broad hills down to bumps. wavelength is metres between crests;
  -- amplitude is the most height the layer adds.
  layers = {
    { wavelength = 1200, amplitude = 32 },
    { wavelength = 400, amplitude = 16 },
    { wavelength = 160, amplitude = 12 },
    { wavelength = 70, amplitude = 7 },
    { wavelength = 40, amplitude = 3 },
    -- The mesh has a vertex every 12 m, so waves shorter than about 36 m can't be drawn as waves: they show as
    -- rough, uneven ground, which is what these are for.
    { wavelength = 28, amplitude = 1.6 },
    { wavelength = 17, amplitude = 0.8 },
  },
  base = 2, -- everything sits at least this far above the level's flat plain, which would hide or cut into anything below it
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

M.chunks = {
  size = 240, -- metres per side
  cell = 12, -- metres between mesh vertices; must divide size
  radius = 2, -- chunks loaded each way around the player, so 5 x 5
  buildBudgetMs = 2, -- milliseconds per frame spent building a chunk while the player moves
}

-- Fog hides the edge of the loaded world, where the terrain stops short of the level's flat plain.
-- Visibility is roughly 3 / fogDensity metres; the level's own value is restored when the world stops.
M.fogDensity = 0.005

M.shiftDistance = 15000 -- distance from the origin before the car and world are shifted back

return M
