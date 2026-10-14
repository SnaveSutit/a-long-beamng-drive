-- Fuel cans and scrap piles beside the road. Placement is deterministic per seed and chunk.
-- Each pickup is a game prop (barrel, cardboard box) spawned as a small physics vehicle.

local M = {}

local seed = 0
local props = {} -- biome index -> pickup kind -> configured props that exist
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
  local firstNode = chunk * (cfg.chunks.nodes - 1)
  -- a chunk takes the pickup settings and props of the biome in its middle
  local biome = aLongDrive_road.getBiome(firstNode + math.floor((cfg.chunks.nodes - 1) / 2))
  local biomeConfig = aLongDrive_biomes.get(biome)
  local rates = cfg.devMode and biomeConfig.pickups.dev or biomeConfig.pickups.normal
  local biomeProps = props[biome]
  local random = randomFor(chunk)
  local list, slots = {}, 0

  local function place(kind)
    if not biomeProps[kind] or #biomeProps[kind] == 0 then return end
    local along = random() * (cfg.chunks.nodes - 1)
    local i = firstNode + math.floor(along)
    local side = random() < 0.5 and -1 or 1
    -- on the flat shoulder, clear of both edges; a shoulder too narrow for that gets them down its middle
    local profile = aLongDrive_road.getProfile(i + along % 1)
    local roadEdge, margin = profile.width / 2, biomeConfig.pickups.shoulderMargin
    local nearest, farthest = roadEdge + margin, roadEdge + profile.shoulder - margin
    if farthest < nearest then nearest, farthest = roadEdge + profile.shoulder / 2, roadEdge + profile.shoulder / 2 end
    local lateral = side * (nearest + random() * (farthest - nearest))
    local p = roadPoint(aLongDrive_road.getNode(i), aLongDrive_road.getNode(i + 1), along % 1, lateral)
    slots = slots + 1
    local prop = biomeProps[kind][1 + math.floor(random() * #biomeProps[kind])]
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
  for biome = 1, aLongDrive_biomes.count() do
    local biomeName = aLongDrive_biomes.def(biome).name
    props[biome] = {}
    for kind, entries in pairs(aLongDrive_biomes.get(biome).pickupProps) do
      props[biome][kind] = {}
      for _, prop in ipairs(entries) do
        if FS:fileExists(string.format("/vehicles/%s/%s.pc", prop.model, prop.config)) then
          props[biome][kind][#props[biome][kind] + 1] = prop
        else
          log("W", "aLongDrive", string.format("%s pickupProps.%s: no config /vehicles/%s/%s.pc, skipping it", biomeName, kind, prop.model, prop.config))
        end
      end
      if #props[biome][kind] == 0 then
        log("W", "aLongDrive", string.format("%s pickupProps.%s has no usable props, so no %s pickups will spawn there", biomeName, kind, kind))
      end
    end
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

---@param p table pickup
---@param car table the vehicle that gets the fuel
local function applyPickup(p, car)
  local cfg = aLongDrive_config.pickups
  if p.kind == "fuel" then
    car:queueLuaCommand(string.format([[
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

---Spawns pickups that were waiting for collision to settle.
---@param offset vec3 virtual position = world position + offset
function M.update(offset)
  if settleFrames > 0 then
    settleFrames = settleFrames - 1
  elseif next(pending) then
    spawnPending(offset)
  end
end

---Props can roll or get knocked, so distance uses their live position.
---@param pos vec3 world position
---@param maxDistance number metres, horizontal
---@return table? pickup, integer? chunk, integer? index
function M.nearest(pos, maxDistance)
  local best, bestChunk, bestIndex, bestDistSq = nil, nil, nil, maxDistance ^ 2
  for chunk, list in pairs(active) do
    for i, p in ipairs(list) do
      local at = p.vehicle:getPosition()
      local dx, dy = at.x - pos.x, at.y - pos.y
      if dx * dx + dy * dy < bestDistSq and math.abs(at.z - pos.z) < 3 then
        best, bestChunk, bestIndex, bestDistSq = p, chunk, i, dx * dx + dy * dy
      end
    end
  end
  return best, bestChunk, bestIndex
end

---Collects the nearest pickup within reach of the player.
---@param pos vec3 the player's world position
---@param car table
---@return boolean collected
function M.collectNearest(pos, car)
  local p, chunk, index = M.nearest(pos, aLongDrive_config.pickups.reach)
  if not p then return false end
  applyPickup(p, car)
  collected[chunk .. ":" .. p.slot] = true
  p.vehicle:delete()
  table.remove(active[chunk], index)
  return true
end

---@return {scrap: number}
function M.getStats()
  return stats
end

return M
