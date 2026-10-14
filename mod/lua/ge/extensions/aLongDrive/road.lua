-- Deterministic endless road. Nodes are generated in order from the seed and cached.

local M = {}

local TURN_MEMORY = 0.92 -- how much of the previous turn rate carries over
local ROLLER_SCALE = 0.35 -- rollers are this fraction of the hill wavelength
local CONTRAST = 1.7 -- smooth noise hugs the middle, so stretch it to use the height range
local EASE_IN_DISTANCE = 400 -- the road starts at ground level and eases into the hills over this distance

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
---@return number pseudo-random value in [0, 1) for a lattice point of the height noise
local function latticeValue(i)
  local v = math.sin(i * 127.1 + state.heightSeed) * 43758.5453
  return v - math.floor(v)
end

---@param x number
---@return number smooth 1D noise in [0, 1)
local function smoothNoise(x)
  local i = math.floor(x)
  local f = x - i
  local u = f * f * (3 - 2 * f)
  local a = latticeValue(i)
  return a + (latticeValue(i + 1) - a) * u
end

---Target road height at a distance along the road: big hills with shorter rollers on top.
---@param distance number metres from the start
---@return number
local function heightAt(distance)
  local hills = aLongDrive_config.hills
  local big = smoothNoise(distance / hills.wavelength)
  local rollers = smoothNoise(distance / (hills.wavelength * ROLLER_SCALE) + 31.7)
  local mix = (1 - hills.rollers) * big + hills.rollers * rollers
  local fraction = clamp(0.5 + (mix - 0.5) * CONTRAST, 0, 1)
  local ease = clamp(distance / EASE_IN_DISTANCE, 0, 1)
  ease = ease * ease * (3 - 2 * ease)
  return hills.minHeight + (hills.maxHeight - hills.minHeight) * fraction * ease
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
    heightSeed = (seed % 10007) * 0.73,
    surfaceRng = (seed * 2654435761 + 97) % 4294967296, -- separate from the road's own random stream
    surfaceRuns = {},
    nodes = { { x = startX, y = startY, z = startZ } },
  }
end

---@return number random value in [0, 1) from the surface stream
local function surfaceRandom()
  state.surfaceRng = (state.surfaceRng * 1664525 + 1013904223) % 4294967296
  return state.surfaceRng / 4294967296
end

---Appends the next stretch of one surface: a different one from the last, picked by weight.
local function addSurfaceRun()
  local cfg = aLongDrive_config
  local list, runs = cfg.surfaces, state.surfaceRuns
  local previous = runs[#runs]

  local chosen, total = 1, 0
  for k, surface in ipairs(list) do
    if not previous or k ~= previous.surface then total = total + surface.weight end
  end
  if previous and #list > 1 then
    local pick = surfaceRandom() * total
    for k, surface in ipairs(list) do
      if k ~= previous.surface then
        pick = pick - surface.weight
        chosen = k
        if pick <= 0 then break end
      end
    end
  end

  local surface = list[chosen]
  local length = surface.minLength + surfaceRandom() * (surface.maxLength - surface.minLength)
  local first = previous and previous.last + 1 or 0
  runs[#runs + 1] = { first = first, last = first + math.max(1, math.ceil(length / cfg.road.spacing)) - 1, surface = chosen }
end

---Index of the run covering segment i, generating runs as far as needed.
---@param i integer segment index
---@return integer
local function runIndexFor(i)
  local runs = state.surfaceRuns
  while #runs == 0 or runs[#runs].last < i do addSurfaceRun() end
  for k = #runs, 1, -1 do
    if runs[k].first <= i then return k end
  end
  return 1
end

---@param i integer segment index: the stretch from node i to node i + 1
---@return integer index into config.surfaces
function M.getSurface(i)
  return state.surfaceRuns[runIndexFor(i)].surface
end

local PROFILE_KEYS = { "width", "moundHeight", "shoulder", "embankment" }

---A surface's own road settings: what its `road` table sets, and the shared defaults for the rest.
---@param index integer index into config.surfaces
---@return {width: number, moundHeight: number, shoulder: number, embankment: number}
function M.getSurfaceProfile(index)
  local cfg = aLongDrive_config
  local overrides = cfg.surfaces[index].road or {}
  local profile = {}
  for _, key in ipairs(PROFILE_KEYS) do profile[key] = overrides[key] or cfg.road[key] end
  return profile
end

---The road's cross-section settings at a position along it. Within a surface they are that surface's own;
---around a boundary they ease from one surface's to the other's over config.surfaceTransition metres.
---@param f number fractional node index
---@return {width: number, moundHeight: number, shoulder: number, embankment: number}
function M.getProfile(f)
  local cfg = aLongDrive_config
  local k = runIndexFor(math.floor(f))
  local runs = state.surfaceRuns
  local run = runs[k]
  local profile = M.getSurfaceProfile(run.surface)

  local half = cfg.surfaceTransition / cfg.road.spacing / 2 -- nodes either side of a boundary
  if half <= 0 then return profile end
  local fromStart, fromEnd = f - run.first, run.last + 1 - f
  local neighbour, distance
  if fromStart <= fromEnd then
    neighbour, distance = runs[k - 1], fromStart
  else
    runIndexFor(run.last + 1) -- make sure the next run exists
    neighbour, distance = runs[k + 1], fromEnd
  end
  if not neighbour or distance >= half then return profile end

  -- the neighbour's share is half at the boundary, so both sides agree there, and fades out smoothly
  local t = distance / half
  local share = 0.5 * (1 - t * t * (3 - 2 * t))
  local other = M.getSurfaceProfile(neighbour.surface)
  for _, key in ipairs(PROFILE_KEYS) do profile[key] = profile[key] + (other[key] - profile[key]) * share end
  return profile
end

---@param i integer node index, 0-based
---@return {x: number, y: number, z: number}
function M.getNode(i)
  local cfg = aLongDrive_config
  local nodes = state.nodes
  while #nodes <= i do
    local last = nodes[#nodes]
    state.turn = clamp(state.turn * TURN_MEMORY + (nextRandom() - 0.5) * 0.04, -cfg.road.maxTurn, cfg.road.maxTurn)
    state.heading = state.heading + state.turn
    local maxStep = cfg.hills.maxGrade * cfg.road.spacing
    nodes[#nodes + 1] = {
      x = last.x + math.cos(state.heading) * cfg.road.spacing,
      y = last.y + math.sin(state.heading) * cfg.road.spacing,
      z = clamp(heightAt(#nodes * cfg.road.spacing), last.z - maxStep, last.z + maxStep),
    }
  end
  return nodes[i + 1]
end

return M
