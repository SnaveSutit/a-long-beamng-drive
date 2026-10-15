-- The shape of the world: a height, a biome and a road cross-section for every point, from the seed alone.
-- All of it is a pure function of position, so any chunk can be built on its own, in any order.
--
-- Biomes are the cells of a jittered grid (Voronoi): each grid cell holds one biome centre, and a point belongs
-- to the nearest. Near a border the heights of the neighbouring biomes are blended. Near a road the ground
-- is graded to the road's height.

local M = {}

local CHANNEL_OFFSET = 17.3 -- keeps the noise layers from repeating each other
local JITTER_MIN, JITTER_MAX = 0.25, 0.75 -- where in its grid cell a biome centre sits; this range keeps the nearest centre within 3 x 3 cells
local ROAD_KEYS = { "width", "moundHeight", "shoulder", "embankment", "roll" }
local MIN_SPACING = 0.25 -- road columns never sit closer than this, so a zero shoulder or mound makes no degenerate triangles
local BED_CLEARANCE = 0.15 -- the bed stands at least this far above the ground beside it, since the terrain mesh is coarser than the road and its triangles cut corners
local SLOPE_DIVISIONS = 3

local centres = {} -- [i][j] -> { x, y, biome }, filled as needed
local weights = {} -- biome index -> blend weight, reused between calls
local bendWeights = {} -- the same, blended over the longer road.bendTransition
local bends = {} -- the road's sideways bend amplitudes, blended
local nearby = { biome = {}, distance = {} } -- the 3 x 3 centres around a point, reused between calls
local shares = {} -- surface index -> share, reused between calls
local scratchProfile = {}

---@param seed number
function M.setSeed(seed)
  aLongDrive_noise.setSeed(seed)
  centres = {}
end

local function smoothstep(a, b, x)
  local t = math.max(0, math.min(1, (x - a) / (b - a)))
  return t * t * (3 - 2 * t)
end

---@param pick number in [0, 1)
---@return integer biome index, picked by weight
local function pickBiome(pick)
  local count = aLongDrive_biomes.count()
  local total = 0
  for index = 1, count do total = total + aLongDrive_biomes.def(index).weight end
  pick = pick * total
  for index = 1, count do
    pick = pick - aLongDrive_biomes.def(index).weight
    if pick < 0 then return index end
  end
  return count
end

---@param i integer grid cell
---@param j integer
---@return {x: number, y: number, biome: integer}
local function centreIn(i, j)
  local row = centres[i]
  if not row then
    row = {}
    centres[i] = row
  end
  local centre = row[j]
  if not centre then
    local size, hash = aLongDrive_config.biomeSize, aLongDrive_noise.hash
    centre = {
      x = (i + JITTER_MIN + hash(i, j, 1) * (JITTER_MAX - JITTER_MIN)) * size,
      y = (j + JITTER_MIN + hash(i, j, 2) * (JITTER_MAX - JITTER_MIN)) * size,
      biome = pickBiome(hash(i, j, 3)),
    }
    row[j] = centre
  end
  return centre
end

---Fills `out` with how much of each biome applies at a point: all of the nearest centre's, and a share of
---any other whose distance is within `blend` of it, easing to nothing. Right on a border the two are equal.
---@param out table biome index -> weight
---@param blend number metres
local function blendAt(x, y, out, blend)
  local size = aLongDrive_config.biomeSize
  local ci, cj = math.floor(x / size), math.floor(y / size)
  local nearest, count = math.huge, 0
  for i = ci - 1, ci + 1 do
    for j = cj - 1, cj + 1 do
      local centre = centreIn(i, j)
      local d = math.sqrt((centre.x - x) ^ 2 + (centre.y - y) ^ 2)
      count = count + 1
      nearby.biome[count], nearby.distance[count] = centre.biome, d
      nearest = math.min(nearest, d)
    end
  end

  for index = 1, aLongDrive_biomes.count() do out[index] = 0 end
  for k = 1, count do
    local t = math.max(0, 1 - (nearby.distance[k] - nearest) / blend)
    out[nearby.biome[k]] = out[nearby.biome[k]] + t * t
  end
end

---Fills `weights` for a point, over the terrain's biome transition.
local function blendTerrainAt(x, y)
  blendAt(x, y, weights, aLongDrive_config.biomeTransition)
end

---@param x number virtual position
---@param y number
---@return integer biome index the point mostly belongs to
function M.biomeAt(x, y)
  blendTerrainAt(x, y)
  local best, bestWeight = 1, -1
  for index = 1, aLongDrive_biomes.count() do
    if weights[index] > bestWeight then best, bestWeight = index, weights[index] end
  end
  return best
end

---@param layers table[] a biome's terrain layers
---@param minWavelength? number layers with shorter waves count for their average height only
---@return number
local function layersHeight(layers, x, y, minWavelength)
  local value = aLongDrive_noise.value
  local height = 0
  for k, layer in ipairs(layers) do
    if minWavelength and layer.wavelength < minWavelength then
      height = height + layer.amplitude * 0.5
    else
      local shift = k * CHANNEL_OFFSET
      height = height + value(x / layer.wavelength + shift, y / layer.wavelength + shift * 0.53) * layer.amplitude
    end
  end
  return height
end

---The biomes' heights blended by the current `weights`.
---@param broadOnly? boolean only the layers the road follows (each biome's road.minWavelength), the rest at their average
---@return number
local function blendedHeight(x, y, broadOnly)
  local sum, total = 0, 0
  for index = 1, aLongDrive_biomes.count() do
    local weight = weights[index]
    if weight > 0 then
      local config = aLongDrive_biomes.get(index)
      sum = sum + weight * layersHeight(config.terrain.layers, x, y, broadOnly and config.road.minWavelength or nil)
      total = total + weight
    end
  end
  return sum / total
end

---Fills `shares` with how much of each surface applies where the surface noise is n. The surfaces take bands of
---0..1 in proportion to their weights, with the borders between bands eased over road.surfaceBlend.
---@param surfaces table[]
---@param n number
local function surfaceShares(surfaces, n)
  local blend = aLongDrive_config.road.surfaceBlend
  local total = 0
  for _, def in ipairs(surfaces) do total = total + def.weight end
  local edge, above = 0, 1
  for s, def in ipairs(surfaces) do
    edge = edge + def.weight / total
    local next = s < #surfaces and smoothstep(edge - blend, edge + blend, n) or 0
    shares[s] = above - next
    above = next
  end
end

---The road's cross-section at a point, blended over biomes and surfaces, assuming `weights` are current for it.
---@param out table
---@return {width: number, moundHeight: number, shoulder: number, embankment: number, roll: number, biome: integer, surface: integer}
local function fillProfile(x, y, out)
  local road = aLongDrive_config.road
  local n = aLongDrive_noise.value(x / road.surfaceWavelength + 5.1, y / road.surfaceWavelength + 9.7)
  for _, key in ipairs(ROAD_KEYS) do out[key] = 0 end
  local total, bestBiome, bestWeight = 0, 1, -1
  for index = 1, aLongDrive_biomes.count() do
    local weight = weights[index]
    if weight > 0 then
      total = total + weight
      if weight > bestWeight then bestBiome, bestWeight = index, weight end
      local config = aLongDrive_biomes.get(index)
      surfaceShares(config.surfaces, n)
      for s, def in ipairs(config.surfaces) do
        local overrides = def.road or {}
        for _, key in ipairs(ROAD_KEYS) do out[key] = out[key] + weight * shares[s] * (overrides[key] or config.road[key]) end
      end
    end
  end
  for _, key in ipairs(ROAD_KEYS) do out[key] = out[key] / total end

  local surfaces = aLongDrive_biomes.get(bestBiome).surfaces
  surfaceShares(surfaces, n)
  local bestSurface = 1
  for s = 2, #surfaces do
    if shares[s] > shares[bestSurface] then bestSurface = s end
  end
  out.biome, out.surface = bestBiome, bestSurface
  return out
end

---How much the road leans to one side at a point along it, which wanders at random between the limits of its surface.
---@param k integer which road
---@param v number how far along the roads
---@param profile {roll: number} the cross-section there
---@return number slope metres the left edge stands above the right, per metre across
function M.tiltAt(k, v, profile)
  local road = aLongDrive_config.road
  local n = (aLongDrive_noise.value(v / road.rollWavelength + 53.7, k * 2.9 + 8.3) - 0.5) * 3 -- the noise rarely strays far from its middle
  return math.tan(math.rad(profile.roll * math.max(-1, math.min(1, n))))
end

---Where the parts of a road's cross-section start, as distances from its centre, and how far the bed stands above
---the flat ground beside it. The bed can lean, so the ground beside it sits low enough that the leaning edge never
---dips below it: the drop is the mound, plus the most the lean can raise the edge of the shoulder, plus some spare
---so that the coarse terrain mesh never pokes through the shoulder. The bed slopes all the way down to the ground over
---that drop, so the longer it is the gentler the slope.
---@param profile {width: number, moundHeight: number, shoulder: number, embankment: number, roll: number}
---@return number halfRoad, number shoulderEdge, number slopeEnd, number drop
function M.layout(profile)
  local halfRoad = profile.width / 2
  local shoulderEdge = halfRoad + math.max(profile.shoulder, MIN_SPACING)
  local drop = profile.moundHeight + math.tan(math.rad(profile.roll)) * shoulderEdge + BED_CLEARANCE
  local slopeEnd = shoulderEdge + math.max(drop * profile.embankment, MIN_SPACING * SLOPE_DIVISIONS)
  return halfRoad, shoulderEdge, slopeEnd, drop
end

M.SLOPE_DIVISIONS = SLOPE_DIVISIONS

---The road's cross-section at a point.
---@param x number virtual position
---@param y number
---@return {width: number, moundHeight: number, shoulder: number, embankment: number, biome: integer, surface: integer}
function M.profileAt(x, y)
  blendTerrainAt(x, y)
  return fillProfile(x, y, {})
end

---The extra height the biomes' features give the land at a point beside a road, assuming `weights` are current for it.
---@param k integer which road
---@param v number how far along the roads
---@param side number how far to the left of the road's direction (negative: right)
---@return number onRoad height at the road itself, number beside height at this point
local function featureHeight(k, v, side)
  local road = aLongDrive_config.road
  local hills, sides = road.features.hills, road.features.sides
  local hillHeight, sideHeight, total = 0, 0, 0
  for index = 1, aLongDrive_biomes.count() do
    local weight = weights[index]
    if weight > 0 then
      local features = aLongDrive_biomes.get(index).road.features
      hillHeight = hillHeight + weight * features.hills.height
      sideHeight = sideHeight + weight * features.sides.height
      total = total + weight
    end
  end
  hillHeight, sideHeight = hillHeight / total, sideHeight / total

  local value = aLongDrive_noise.value
  local hill = hillHeight * smoothstep(0.35, 0.85, value(v / hills.wavelength + 11.3, k * 5.7 + 3.1))
  local onRoad = hill
  local beside = hill * (1 - smoothstep(hills.width * 0.5, hills.width, math.abs(side)))

  if sideHeight > 0 then
    -- a mountain on one side of the road at a time, with a stretch of open ground between where it changes sides
    local m = value(v / sides.wavelength + 29.1, k * 3.3 + 17.7)
    local strength = side >= 0 and smoothstep(0.45, 0.8, m) or smoothstep(0.45, 0.8, 1 - m)
    local run = sideHeight * 3 -- a gentle slope, about 18 degrees
    local from = sides.offset
    local distance = math.abs(side)
    beside = beside + sideHeight * strength
      * (smoothstep(from, from + run, distance) - smoothstep(from + run + sides.plateau, from + 2 * run + sides.plateau, distance))
  end
  return onRoad, beside
end

---Height of the road's centre line at a point: the terrain's broad hills, without the small bumps, and any hill
---built across the road. Each biome sets which waves the road follows (road.minWavelength).
---@param x number virtual position
---@param y number
---@param k? integer which road, if known
---@param v? number how far along the roads, if known
---@return number
function M.roadHeightAt(x, y, k, v)
  if not k then
    local _, _, _, nearest = aLongDrive_roads.frameAt(x, y)
    k, v = nearest, aLongDrive_roads.alongAt(x, y)
  end
  blendTerrainAt(x, y)
  local sum, total = 0, 0
  for index = 1, aLongDrive_biomes.count() do
    local weight = weights[index]
    if weight > 0 then
      local config = aLongDrive_biomes.get(index)
      sum = sum + weight * layersHeight(config.terrain.layers, x, y, config.road.minWavelength)
      total = total + weight
    end
  end
  local onRoad = featureHeight(k, v, 0)
  return sum / total + aLongDrive_config.terrain.base + onRoad
end

---How far the roads wander sideways at a point, per wavelength in road.bendWavelengths and then road.essWavelengths: each biome's own amplitudes,
---blended over road.bendTransition, which is long so that roads do not fold where the biomes meet.
---@param x number virtual position
---@param y number
---@return number[] amplitudes, reused between calls
function M.bendsAt(x, y)
  blendAt(x, y, bendWeights, aLongDrive_config.road.bendTransition)
  local road = aLongDrive_config.road
  local bendCount, essCount = #road.bendWavelengths, #road.essWavelengths
  for k = 1, bendCount + essCount do bends[k] = 0 end
  local total = 0
  for index = 1, aLongDrive_biomes.count() do
    local weight = bendWeights[index]
    if weight > 0 then
      total = total + weight
      local biomeRoad = aLongDrive_biomes.get(index).road
      for k = 1, bendCount do bends[k] = bends[k] + weight * (biomeRoad.bends[k] or 0) end
      for k = 1, essCount do bends[bendCount + k] = bends[bendCount + k] + weight * (biomeRoad.esses[k] or 0) end
    end
  end
  for k = 1, bendCount + essCount do bends[k] = bends[k] / total end
  return bends
end

---@param x number virtual position
---@param y number
---@return number metres above the level's flat plain: the ground, graded flat to the road near it. Never below terrain.base minus the mound
function M.heightAt(x, y)
  blendTerrainAt(x, y)
  local natural = blendedHeight(x, y) + aLongDrive_config.terrain.base
  local fine = natural - aLongDrive_config.terrain.base - blendedHeight(x, y, true) -- the small bumps the road does not follow
  local road = aLongDrive_config.road
  local distance, roadX, roadY, k, side = aLongDrive_roads.frameAt(x, y)
  local along = aLongDrive_roads.alongAt(roadX, roadY)
  local _, beside = featureHeight(k, along, side)
  natural = natural + beside
  if distance >= road.flatWidth + road.blendDistance then return natural end

  -- The ground is levelled to the road for a few metres past the foot of its bed, then eases back to the natural
  -- ground. The small bumps come back over the same stretch, so the corridor is not a smooth ribbon through rough ground.
  local _, _, slopeEnd, drop = M.layout(fillProfile(x, y, scratchProfile))
  local flat = math.min(road.flatWidth, slopeEnd + road.flatMargin)
  local fade = 1 - smoothstep(flat, flat + road.blendDistance, distance)
  if fade <= 0 then return natural end
  local bumps = fine * smoothstep(flat, flat + road.blendDistance * 0.6, distance)
  return natural + (M.roadHeightAt(roadX, roadY, k, along) - drop + bumps - natural) * fade
end

---Like heightAt, but with the road's bed on top: where a car sits.
---@param x number virtual position
---@param y number
---@return number
function M.surfaceHeightAt(x, y)
  local ground = M.heightAt(x, y)
  local distance, roadX, roadY, k, side = aLongDrive_roads.frameAt(x, y)
  blendTerrainAt(x, y)
  local profile = fillProfile(x, y, scratchProfile)
  local _, shoulderEdge, slopeEnd = M.layout(profile)
  if distance >= slopeEnd then return ground end
  local along = aLongDrive_roads.alongAt(roadX, roadY)
  local lean = M.tiltAt(k, along, profile) * math.max(-shoulderEdge, math.min(shoulderEdge, side))
  local top = M.roadHeightAt(roadX, roadY, k, along) + lean
  return ground + (top - ground) * (1 - smoothstep(shoulderEdge, slopeEnd, distance))
end

return M
