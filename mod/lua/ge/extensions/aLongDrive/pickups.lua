-- Fuel cans and scrap piles beside the road. Placement is deterministic per seed and chunk.
-- Each pickup is a game prop (barrel, cardboard box) spawned as a small physics vehicle.

local M = {}

local seed = 0
local props = {} -- pickup kind -> configured props that exist
local COLLISION_SETTLE_FRAMES = 10 -- props spawned sooner fall through terrain whose collision isn't live yet

local active = {} -- chunk -> { pickup }
local pending = {} -- chunk -> placements waiting for collision
local settleFrames = 0
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
---@return table[] placements { kind, slot, config, yaw, x, y, z } in virtual coordinates, minus anything already collected
local function placementsFor(chunk)
  local cfg = aLongDrive_config
  local rates = cfg.devMode and cfg.pickups.dev or cfg.pickups.normal
  local random = randomFor(chunk)
  local firstNode = chunk * (cfg.chunks.nodes - 1)
  local list, slots = {}, 0

  local function place(kind)
    if #props[kind] == 0 then return end
    local along = random() * (cfg.chunks.nodes - 1)
    local i = firstNode + math.floor(along)
    local side = random() < 0.5 and -1 or 1
    local lateral = side * (cfg.pickups.lateralMin + random() * (cfg.pickups.lateralMax - cfg.pickups.lateralMin))
    local p = roadPoint(aLongDrive_road.getNode(i), aLongDrive_road.getNode(i + 1), along % 1, lateral)
    slots = slots + 1
    local prop = props[kind][1 + math.floor(random() * #props[kind])]
    p.kind, p.chunk, p.slot = kind, chunk, slots
    p.model, p.config = prop.model, prop.config
    p.yaw = random() * 2 * math.pi
    if not collected[chunk .. ":" .. slots] then list[#list + 1] = p end
  end

  if random() < rates.fuelChance then place("fuel") end
  for _ = 1, rates.scrapMin + math.floor(random() * (rates.scrapMax - rates.scrapMin + 1)) do
    place("scrap")
  end
  return list
end

---@param p table placement
---@param offset vec3
local function spawnProp(p, offset)
  local options = fillVehicleSpawnOptionDefaults(p.model, { config = string.format("vehicles/%s/%s.pc", p.model, p.config) })
  options.autoEnterVehicle = false
  options.canSpawnAnotherVehicleCheck = false
  options.pos = vec3(p.x - offset.x, p.y - offset.y, p.z + 0.3)
  options.rot = quatFromEuler(0, 0, p.yaw)
  p.vehicle = core_vehicles.spawnNewVehicle(p.model, options)
end

---Spawns a prop per placement and returns only the ones that spawned.
---@param placements table[]
---@param offset vec3
---@return table[]
local function spawnAll(placements, offset)
  local spawned = {}
  for _, p in ipairs(placements) do
    spawnProp(p, offset)
    if p.vehicle then
      spawned[#spawned + 1] = p
    else
      log("W", "aLongDrive", string.format("Could not spawn %s/%s for a %s pickup", p.model, p.config, p.kind))
    end
  end
  return spawned
end

---@param list table[]
local function deleteProps(list)
  for _, p in ipairs(list) do p.vehicle:delete() end
end

---Queues a chunk's pickups; they spawn once the terrain's collision has settled.
---@param chunk integer
function M.spawn(chunk)
  if active[chunk] or pending[chunk] then return end
  pending[chunk] = placementsFor(chunk)
end

---@param chunk integer
function M.despawn(chunk)
  deleteProps(active[chunk] or {})
  active[chunk], pending[chunk] = nil, nil
end

---Call after rebuilding the collision world.
function M.collisionReloaded()
  settleFrames = COLLISION_SETTLE_FRAMES
end

---@param offset vec3 virtual position = world position + offset
local function spawnPending(offset)
  for chunk, placements in pairs(pending) do
    active[chunk] = spawnAll(placements, offset)
    pending[chunk] = nil
  end
end

---Keeps only configured props that exist and warns about the rest: the game would quietly
---spawn the model's default config for a typo instead.
local function loadProps()
  props = {}
  for kind, entries in pairs(aLongDrive_config.pickupProps) do
    props[kind] = {}
    for _, prop in ipairs(entries) do
      if FS:fileExists(string.format("/vehicles/%s/%s.pc", prop.model, prop.config)) then
        props[kind][#props[kind] + 1] = prop
      else
        log("W", "aLongDrive", string.format("pickupProps.%s: no config /vehicles/%s/%s.pc, skipping it", kind, prop.model, prop.config))
      end
    end
    if #props[kind] == 0 then log("W", "aLongDrive", "pickupProps." .. kind .. " has no usable props, so no " .. kind .. " pickups will spawn") end
  end
end

---@param newSeed number
function M.reset(newSeed)
  loadProps()
  for chunk in pairs(active) do M.despawn(chunk) end
  pending = {}
  collected, stats = {}, { scrap = 0 }
  seed = newSeed
end

---Re-rolls the pickups of the loaded chunks, after the pickup rates change.
function M.refresh()
  collected = {}
  local chunks = {}
  for chunk in pairs(active) do chunks[#chunks + 1] = chunk end
  for chunk in pairs(pending) do chunks[#chunks + 1] = chunk end
  for _, chunk in ipairs(chunks) do
    M.despawn(chunk)
    M.spawn(chunk)
  end
end

---Moves the props with the world when the origin shifts.
---@param shift vec3
function M.shift(shift)
  for _, list in pairs(active) do
    for _, p in ipairs(list) do
      local veh, pos = p.vehicle, p.vehicle:getPosition()
      veh:setClusterPosRelRot(veh:getRefNodeId(), pos.x - shift.x, pos.y - shift.y, pos.z, 0, 0, 0, 1)
    end
  end
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

---Collects any pickup within reach of the car. Props can roll, so distance uses their live position.
---@param carPos vec3 world position
---@param offset vec3 virtual position = world position + offset
function M.update(carPos, offset)
  if settleFrames > 0 then
    settleFrames = settleFrames - 1
  elseif next(pending) then
    spawnPending(offset)
  end
  local radiusSq = aLongDrive_config.pickups.collectRadius ^ 2
  for chunk, list in pairs(active) do
    for i = #list, 1, -1 do
      local p = list[i]
      local pos = p.vehicle:getPosition()
      local dx, dy = pos.x - carPos.x, pos.y - carPos.y
      if dx * dx + dy * dy < radiusSq and math.abs(pos.z - carPos.z) < 3 then
        collect(p)
        collected[chunk .. ":" .. p.slot] = true
        p.vehicle:delete()
        table.remove(list, i)
      end
    end
  end
end

---@return {scrap: number}
function M.getStats()
  return stats
end

return M
