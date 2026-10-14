-- Tunables for A Long Drive. Distances are in metres. Reload with: extensions.reload("aLongDrive")

local M = {}

M.road = {
  spacing = 30, -- between nodes
  maxTurn = 0.05, -- radians per node
  startNodesBehind = 2, -- road behind the car when it starts
  width = 8,
  textureLength = 8,
  material = "a_asphalt_01_a",
}

M.hills = {
  minHeight = 0.5, -- keeps the road clear of the flat plain beneath it
  maxHeight = 25, -- road stays between minHeight and this above the plain
  wavelength = 600, -- metres between the crests of the main hills
  rollers = 0.3, -- 0 to 1: how much of the height comes from shorter rollers on top of the hills
  maxGrade = 0.08, -- rise over run; the steepest the road is allowed to get
}

M.terrain = {
  halfWidth = 250, -- shaped terrain each side of the road, fading to the flat plain at the edge
  cell = 10, -- lateral spacing of terrain vertices
  shoulder = 6, -- flat ground beside the road edge
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
  lateralMin = 7, -- from the road centre; stay within the flat shoulder
  lateralMax = 9,
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

M.shiftDistance = 1500 -- distance from the origin before the car and world are shifted back

return M
