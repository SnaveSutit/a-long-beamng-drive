-- Fuel cans and scrap piles beside the road. Placement is deterministic per seed and chunk.
-- Placeholders are drawn each frame with the debug drawer, so they have no collision.

local M = {}

local seed = 0
local active = {} -- chunk -> { placement }
local collected = {} -- "chunk:slot" -> true
local stats = { scrap = 0 }

---@return fun(): number random values in [0, 1)
local function randomFor(chunk)
  local rng = (seed * 1000003 + chunk * 7919 + 12345) % 4294967296
  return function()
    rng = (rng * 1664525 + 1013904223) % 4294967296
    return rng / 4294967296
  end
end

---@param node {x: number, y: number, z: number}
---@param nextNode {x: number, y: number, z: number}
---@param t number 0..1 between the nodes
---@param lateral number metres left of the centre line (negative is right)
---@return {x: number, y: number, z: number} virtual position
local function roadPoint(node, nextNode, t, lateral)
  local dx, dy = nextNode.x - node.x, nextNode.y - node.y
  local len = math.sqrt(dx * dx + dy * dy)
  dx, dy = dx / len, dy / len
  return {
    x = node.x + dx * len * t - dy * lateral,
    y = node.y + dy * len * t + dx * lateral,
    z = node.z + (nextNode.z - node.z) * t,
  }
end

---@param chunk integer
---@return table[] placements { kind, slot, x, y, z } in virtual coordinates, minus anything already collected
local function placementsFor(chunk)
  local cfg = aLongDrive_config
  local rates = cfg.devMode and cfg.pickups.dev or cfg.pickups.normal
  local random = randomFor(chunk)
  local firstNode = chunk * (cfg.chunks.nodes - 1)
  local list, slots = {}, 0

  local function place(kind)
    local along = random() * (cfg.chunks.nodes - 1)
    local i = firstNode + math.floor(along)
    local side = random() < 0.5 and -1 or 1
    local lateral = side * (cfg.pickups.lateralMin + random() * (cfg.pickups.lateralMax - cfg.pickups.lateralMin))
    local p = roadPoint(aLongDrive_road.getNode(i), aLongDrive_road.getNode(i + 1), along % 1, lateral)
    slots = slots + 1
    p.kind, p.chunk, p.slot = kind, chunk, slots
    if not collected[chunk .. ":" .. slots] then list[#list + 1] = p end
  end

  if random() < rates.fuelChance then place("fuel") end
  for _ = 1, rates.scrapMin + math.floor(random() * (rates.scrapMax - rates.scrapMin + 1)) do
    place("scrap")
  end
  return list
end

---@param newSeed number
function M.reset(newSeed)
  active, collected, stats = {}, {}, { scrap = 0 }
  seed = newSeed
end

---@param chunk integer
function M.spawn(chunk)
  if not active[chunk] then active[chunk] = placementsFor(chunk) end
end

---@param chunk integer
function M.despawn(chunk)
  active[chunk] = nil
end

---Re-rolls the pickups of the loaded chunks, after the pickup rates change.
function M.refresh()
  collected = {}
  for chunk in pairs(active) do active[chunk] = placementsFor(chunk) end
end

---@param p table
local function collect(p)
  local cfg = aLongDrive_config.pickups
  if p.kind == "fuel" then
    be:getPlayerVehicle(0):queueLuaCommand(string.format([[
      for _, s in pairs(energyStorage.getStorages()) do
        if s.fuelLiquidDensity and s.energyCapacity > 0 then
          s:setRemainingVolume(s.storedEnergy / s.energyCapacity * s.capacity + %f)
        end
      end]], cfg.fuelLiters))
    ui_message(string.format("+%g L fuel", cfg.fuelLiters), 2, "aLongDrive")
  else
    stats.scrap = stats.scrap + cfg.scrapAmount
    ui_message(string.format("+%g scrap", cfg.scrapAmount), 2, "aLongDrive")
  end
end

---Collects any pickup within reach of the car and draws the rest.
---@param carPos vec3 world position
---@param offset vec3 virtual position = world position + offset
function M.update(carPos, offset)
  local cfg = aLongDrive_config.pickups
  local radiusSq = cfg.collectRadius ^ 2
  for chunk, list in pairs(active) do
    for i = #list, 1, -1 do
      local p = list[i]
      local x, y = p.x - offset.x, p.y - offset.y
      local dx, dy = x - carPos.x, y - carPos.y
      if dx * dx + dy * dy < radiusSq and math.abs(p.z - carPos.z) < 3 then
        collect(p)
        collected[chunk .. ":" .. p.slot] = true
        table.remove(list, i)
      else
        local kind = cfg[p.kind]
        local base = vec3(x, y, p.z)
        local cross = Point2F(kind.size[1], kind.size[2])
        debugDrawer:drawSquarePrism(base, base + vec3(0, 0, kind.size[3]), cross, cross, ColorF(kind.color[1], kind.color[2], kind.color[3], 1))
      end
    end
  end
end

---@return {scrap: number}
function M.getStats()
  return stats
end

return M
