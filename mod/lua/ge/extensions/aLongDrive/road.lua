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
    nodes = { { x = startX, y = startY, z = startZ } },
  }
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
