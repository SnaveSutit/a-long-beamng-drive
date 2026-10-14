-- Deterministic endless road. Nodes are generated in order from the seed and cached.

local M = {}

local TURN_MEMORY = 0.92 -- how much of the previous turn rate carries over
local SLOPE_MEMORY = 0.96
local HEIGHT_PULL = 0.0001 -- slope change per node per metre away from mid-height

local state

---@return number random value in [0, 1)
local function nextRandom()
  state.rng = (state.rng * 1664525 + 1013904223) % 4294967296
  return state.rng / 4294967296
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
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
    slope = 0,
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
    local pull = ((cfg.hills.minHeight + cfg.hills.maxHeight) / 2 - last.z) * HEIGHT_PULL
    state.slope = clamp(state.slope * SLOPE_MEMORY + (nextRandom() - 0.5) * 0.012 + pull, -cfg.hills.maxGrade, cfg.hills.maxGrade)
    nodes[#nodes + 1] = {
      x = last.x + math.cos(state.heading) * cfg.road.spacing,
      y = last.y + math.sin(state.heading) * cfg.road.spacing,
      z = clamp(last.z + state.slope * cfg.road.spacing, cfg.hills.minHeight, cfg.hills.maxHeight),
    }
  end
  return nodes[i + 1]
end

return M
