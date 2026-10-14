-- Deterministic endless road. Nodes are generated in order from the seed and cached.
-- The road is a sequence of regions, each one a surface inside a biome, also generated from the seed.

local M = {}

local FOLLOW = 0.4 -- how hard the road chases its target height each node; lower means a softer, laggier ride
local VARIATION_WAVELENGTH = 3500 -- the slow noise that makes some stretches hillier than others
local EASE_IN_DISTANCE = 400 -- the road starts at ground level and eases into the hills over this distance

local ROAD_KEYS = { "width", "moundHeight", "shoulder", "embankment" }
local TERRAIN_KEYS = { "relief", "reliefScale", "blendDistance" }

local state

---@return number random value in [0, 1)
local function nextRandom()
  state.rng = (state.rng * 1664525 + 1013904223) % 4294967296
  return state.rng / 4294967296
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

---@param i integer
---@param layer number which noise layer, so layers do not repeat each other
---@return number pseudo-random value in [0, 1) for a lattice point of the height noise
local function latticeValue(i, layer)
  local v = math.sin(i * 127.1 + layer * 311.7 + state.heightSeed) * 43758.5453
  return v - math.floor(v)
end

---@param x number
---@param layer number
---@return number smooth 1D noise in [0, 1). The quintic fade keeps the curvature continuous, so no lumps at the lattice points.
local function smoothNoise(x, layer)
  local i = math.floor(x)
  local f = x - i
  local u = f * f * f * (f * (f * 6 - 15) + 10)
  local a = latticeValue(i, layer)
  return a + (latticeValue(i + 1, layer) - a) * u
end

---Target road height at a distance along the road for one biome's hills: layers of noise, long and short,
---with a slow noise making some stretches hillier than others. Saturates smoothly at the height limits.
---@param hills table that biome's hills config
---@param distance number metres from the start
---@return number
local function heightFor(hills, distance)
  local sum, total = 0, 0
  for k, layer in ipairs(hills.layers) do
    sum = sum + (smoothNoise(distance / layer.wavelength, k) - 0.5) * layer.weight
    total = total + layer.weight
  end
  local deviation = sum / total * 2 -- about -1..1, usually within +-0.5

  local slow = smoothNoise(distance / VARIATION_WAVELENGTH, 97)
  local amplitude = 1 - hills.variation + hills.variation * slow
  local fraction = 0.5 + 0.5 * math.tanh(hills.gain * deviation * amplitude)
  return hills.minHeight + (hills.maxHeight - hills.minHeight) * fraction
end

---@param seed number
---@param startX number
---@param startY number
---@param startZ number
---@param heading number radians
function M.reset(seed, startX, startY, startZ, heading)
  state = {
    rng = seed % 4294967296,
    heading = heading,
    turn = 0,
    slope = 0, -- metres climbed per node
    turnSign = 1,
    turnLeft = 0, -- nodes left in the current stretch of curve
    turnTarget = 0,
    heightSeed = (seed % 10007) * 0.73,
    regionRng = (seed * 2654435761 + 97) % 4294967296, -- separate from the road's own random stream
    regions = {},
    biomeEnd = -1, -- last node of the biome stretch being laid out
    nodes = { { x = startX, y = startY, z = startZ } },
  }
end

---@return number random value in [0, 1) from the region stream
local function regionRandom()
  state.regionRng = (state.regionRng * 1664525 + 1013904223) % 4294967296
  return state.regionRng / 4294967296
end

---Index of the entry in `list` picked by weight, skipping `skip`. Nil if nothing is left to pick.
---@param list table[] entries with a weight
---@param skip integer?
---@return integer?
local function pickWeighted(list, skip)
  local total = 0
  for k, entry in ipairs(list) do
    if k ~= skip then total = total + entry.weight end
  end
  if total <= 0 then return nil end
  local pick, chosen = regionRandom() * total, nil
  for k, entry in ipairs(list) do
    if k ~= skip then
      chosen = k
      pick = pick - entry.weight
      if pick <= 0 then break end
    end
  end
  return chosen
end

---Appends the next stretch of one surface. When the biome stretch is used up, a different biome starts.
local function addRegion()
  local spacing = aLongDrive_config.road.spacing
  local biomes = aLongDrive_biomes
  local regions = state.regions
  local previous = regions[#regions]
  local first = previous and previous.last + 1 or 0

  local biome, newBiome = previous and previous.biome or 1, not previous
  if previous and first > state.biomeEnd then
    local defs = {}
    for index = 1, biomes.count() do defs[index] = biomes.def(index) end
    biome = pickWeighted(defs, biomes.count() > 1 and previous.biome or nil) or previous.biome
    newBiome = biome ~= previous.biome
  end
  if not previous or first > state.biomeEnd then
    local def = biomes.def(biome)
    state.biomeEnd = first + math.max(1, math.ceil((def.minLength + regionRandom() * (def.maxLength - def.minLength)) / spacing)) - 1
  end

  local surfaces = biomes.get(biome).surfaces
  local surface
  if not previous then
    surface = 1 -- the road starts on the first surface of the first biome
  elseif newBiome then
    surface = pickWeighted(surfaces, nil) or 1
  else
    surface = pickWeighted(surfaces, previous.surface)
    if not surface then -- the biome has one surface: carry on with it to the end of the stretch
      previous.last = state.biomeEnd
      return
    end
  end

  local def = surfaces[surface]
  local length = math.max(1, math.ceil((def.minLength + regionRandom() * (def.maxLength - def.minLength)) / spacing))
  regions[#regions + 1] = { first = first, last = math.min(first + length - 1, state.biomeEnd), biome = biome, surface = surface }
end

---Index of the region covering segment i, generating regions as far as needed.
---@param i integer segment index
---@return integer
local function regionIndexFor(i)
  local regions = state.regions
  while #regions == 0 or regions[#regions].last < i do addRegion() end
  for k = #regions, 1, -1 do
    if regions[k].first <= i then return k end
  end
  return 1
end

---@param i integer segment index: the stretch from node i to node i + 1
---@return {biome: integer, surface: integer} indexes into the biome list and that biome's surfaces
function M.getRegion(i)
  local region = state.regions[regionIndexFor(i)]
  return { biome = region.biome, surface = region.surface }
end

---The region at f and, when f is close to a boundary, the region across it and how much of it to mix in.
---The neighbour's share is half at the boundary, so both sides agree there, and fades out smoothly.
---@param f number fractional node index
---@return table region, table? neighbour, number? share
local function blendAt(f)
  local cfg = aLongDrive_config
  local k = regionIndexFor(math.floor(f))
  local regions = state.regions
  local region = regions[k]

  local fromStart, fromEnd = f - region.first, region.last + 1 - f
  local neighbour, distance
  if fromStart <= fromEnd then
    neighbour, distance = regions[k - 1], fromStart
  else
    regionIndexFor(region.last + 1) -- make sure the next region exists
    neighbour, distance = regions[k + 1], fromEnd
  end
  if not neighbour then return region end

  local length = neighbour.biome ~= region.biome and cfg.biomeTransition or cfg.surfaceTransition
  local half = length / cfg.road.spacing / 2 -- nodes either side of the boundary
  if half <= 0 or distance >= half then return region end
  local t = distance / half
  return region, neighbour, 0.5 * (1 - t * t * (3 - 2 * t))
end

---The numbers a region sets for the cross-section of the road and the shape of the terrain around it.
---@param region {biome: integer, surface: integer}
---@return {width: number, moundHeight: number, shoulder: number, embankment: number, relief: number, reliefScale: number, blendDistance: number}
function M.getRegionProfile(region)
  local biomeConfig = aLongDrive_biomes.get(region.biome)
  local overrides = biomeConfig.surfaces[region.surface].road or {}
  local profile = {}
  for _, key in ipairs(ROAD_KEYS) do profile[key] = overrides[key] or biomeConfig.road[key] end
  for _, key in ipairs(TERRAIN_KEYS) do profile[key] = biomeConfig.terrain[key] end
  return profile
end

---The settings at a position along the road. Inside a region they are its own; around a boundary they
---ease from one region's to the other's, over config.surfaceTransition or config.biomeTransition metres.
---@param f number fractional node index
---@return {width: number, moundHeight: number, shoulder: number, embankment: number, relief: number, reliefScale: number, blendDistance: number}
function M.getProfile(f)
  local region, neighbour, share = blendAt(f)
  local profile = M.getRegionProfile(region)
  if not neighbour then return profile end
  local other = M.getRegionProfile(neighbour)
  for key, value in pairs(profile) do profile[key] = value + (other[key] - value) * share end
  return profile
end

---@param f number fractional node index
---@return integer biome index of the region at f
function M.getBiome(f)
  return state.regions[regionIndexFor(math.floor(f))].biome
end

---Target height, steepest grade and the most the slope may change per node, for the node at index i.
---Blends the hills of two biomes across a boundary.
---@param i integer node index
---@param spacing number
---@return number height, number maxGrade, number maxBend
local function hillsAt(i, spacing)
  local distance = i * spacing
  local region, neighbour, share = blendAt(i)
  local hills = aLongDrive_biomes.get(region.biome).hills
  local height, grade, bend = heightFor(hills, distance), hills.maxGrade, hills.maxBend
  if neighbour and neighbour.biome ~= region.biome then
    local other = aLongDrive_biomes.get(neighbour.biome).hills
    height = height + (heightFor(other, distance) - height) * share
    grade = grade + (other.maxGrade - grade) * share
    bend = bend + (other.maxBend - bend) * share
  end
  local ease = clamp(distance / EASE_IN_DISTANCE, 0, 1)
  ease = ease * ease * (3 - 2 * ease)
  local floor = hills.minHeight
  return floor + (height - floor) * ease, grade, bend
end

---Starts the next stretch of curve: a kind picked by weight, a length and a turn rate within the kind's range.
---@param turns table[] the biome's turn kinds
local function startTurnStretch(turns)
  local spacing = aLongDrive_config.road.spacing
  local total = 0
  for _, kind in ipairs(turns) do total = total + kind.weight end
  local pick, chosen = nextRandom() * total, turns[1]
  for _, kind in ipairs(turns) do
    chosen = kind
    pick = pick - kind.weight
    if pick <= 0 then break end
  end
  if chosen.maxTurn > 0.004 and nextRandom() < aLongDrive_config.road.turnFlip then state.turnSign = -state.turnSign end
  state.turnLeft = math.max(1, math.ceil((chosen.minLength + nextRandom() * (chosen.maxLength - chosen.minLength)) / spacing))
  state.turnTarget = state.turnSign * (chosen.minTurn + nextRandom() * (chosen.maxTurn - chosen.minTurn))
end

---@param i integer node index, 0-based
---@return {x: number, y: number, z: number}
function M.getNode(i)
  local cfg = aLongDrive_config
  local nodes = state.nodes
  while #nodes <= i do
    local last = nodes[#nodes]
    if state.turnLeft <= 0 then startTurnStretch(aLongDrive_biomes.get(M.getBiome(#nodes)).road.turns) end
    state.turnLeft = state.turnLeft - 1
    local wobble = (nextRandom() - 0.5) * cfg.road.turnWobble
    state.turn = clamp(state.turn + (state.turnTarget - state.turn) * cfg.road.turnResponse + wobble, -cfg.road.maxTurn, cfg.road.maxTurn)
    state.heading = state.heading + state.turn

    local target, grade, bend = hillsAt(#nodes, cfg.road.spacing)
    local maxStep = grade * cfg.road.spacing
    -- The slope chases a slope that would reach the target, but may only change by a limited amount per node.
    -- That keeps crests and dips rounded, however suddenly the target moves, and the climb within the grade limit.
    local wanted = clamp((target - last.z) * FOLLOW, -maxStep, maxStep)
    local limit = maxStep * bend
    state.slope = clamp(state.slope + clamp(wanted - state.slope, -limit, limit), -maxStep, maxStep)
    local step = state.slope
    nodes[#nodes + 1] = {
      x = last.x + math.cos(state.heading) * cfg.road.spacing,
      y = last.y + math.sin(state.heading) * cfg.road.spacing,
      z = last.z + step,
    }
  end
  return nodes[i + 1]
end

return M
