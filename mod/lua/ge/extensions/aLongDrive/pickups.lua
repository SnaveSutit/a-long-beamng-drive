-- Fuel cans and scrap piles beside the road. Placement is deterministic per seed and chunk.
-- Pickups are visual only: the boxes are wound so their collision never catches the car.

local M = {}

local seed = 0
local active = {} -- chunk -> { pickup }
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
---@return table position and road direction
local function roadPoint(node, nextNode, t, lateral)
  local dx, dy = nextNode.x - node.x, nextNode.y - node.y
  local len = math.sqrt(dx * dx + dy * dy)
  dx, dy = dx / len, dy / len
  local cx, cy = node.x + (nextNode.x - node.x) * t, node.y + (nextNode.y - node.y) * t
  return {
    x = cx - dy * lateral, y = cy + dx * lateral,
    z = node.z + (nextNode.z - node.z) * t,
    dx = dx, dy = dy,
  }
end

---@param chunk integer
---@return table[] placements { kind, slot, x, y, z, dx, dy } in virtual coordinates
local function placementsFor(chunk)
  local cfg = aLongDrive_config
  local random = randomFor(chunk)
  local firstNode = chunk * (cfg.chunks.nodes - 1)
  local list = {}

  local function place(kind)
    local along = random() * (cfg.chunks.nodes - 1)
    local i = firstNode + math.floor(along)
    local side = random() < 0.5 and -1 or 1
    local lateral = side * (cfg.pickups.lateralMin + random() * (cfg.pickups.lateralMax - cfg.pickups.lateralMin))
    local p = roadPoint(aLongDrive_road.getNode(i), aLongDrive_road.getNode(i + 1), along % 1, lateral)
    p.kind, p.slot = kind, #list + 1
    list[#list + 1] = p
  end

  if random() < cfg.pickups.fuelChance then place("fuel") end
  for _ = 1, cfg.pickups.scrapMin + math.floor(random() * (cfg.pickups.scrapMax - cfg.pickups.scrapMin + 1)) do
    place("scrap")
  end
  return list
end

---A box lying on the ground at the placement, aligned with the road.
---@param p table placement
---@param offset vec3
---@return table mesh
local function boxMesh(p, offset)
  local kind = aLongDrive_config.pickups[p.kind]
  local sx, sy, sz = kind.size[1] / 2, kind.size[2] / 2, kind.size[3]
  local verts = {}
  for corner = 0, 7 do
    local ax = (corner % 2 == 0 and -1 or 1) * sx
    local ay = (math.floor(corner / 2) % 2 == 0 and -1 or 1) * sy
    local az = math.floor(corner / 4) * sz
    verts[#verts + 1] = {
      x = p.x + p.dx * ax - p.dy * ay - offset.x,
      y = p.y + p.dy * ax + p.dx * ay - offset.y,
      z = p.z + az,
    }
  end

  local normals = { { x = 0, y = 0, z = 1 }, { x = 0, y = 0, z = -1 }, { x = p.dy, y = -p.dx, z = 0 }, { x = -p.dy, y = p.dx, z = 0 }, { x = p.dx, y = p.dy, z = 0 }, { x = -p.dx, y = -p.dy, z = 0 } }
  local quads = {
    { 4, 5, 7, 6, 0 }, -- top
    { 0, 2, 3, 1, 1 }, -- bottom
    { 0, 1, 5, 4, 2 }, -- -across side
    { 2, 6, 7, 3, 3 }, -- +across side
    { 1, 3, 7, 5, 4 }, -- +along end
    { 0, 4, 6, 2, 5 }, -- -along end
  }
  local faces = {}
  for _, q in ipairs(quads) do
    for _, c in ipairs({ q[1], q[2], q[3], q[1], q[3], q[4] }) do
      faces[#faces + 1] = { v = c, u = 0, n = q[5] }
    end
  end
  return { verts = verts, uvs = { { u = 0, v = 0 } }, normals = normals, faces = faces, material = kind.material }
end

---@param p table placement
---@param offset vec3
local function spawnObject(p, offset)
  local object = createObject("ProceduralMesh")
  object:setPosition(vec3(0, 0, 0))
  object.canSave = false
  object:registerObject(string.format("aLongDrive_pickup_%d_%d", p.chunk, p.slot))
  scenetree.MissionGroup:add(object.obj)
  object:createMesh({ { boxMesh(p, offset) } })
  p.object = object
end

---@param newSeed number
function M.reset(newSeed)
  M.clear()
  seed = newSeed
  collected = {}
  stats = { scrap = 0 }
end

---@param chunk integer
---@param offset vec3
function M.spawn(chunk, offset)
  if active[chunk] then return end
  local list = {}
  for _, p in ipairs(placementsFor(chunk)) do
    p.chunk = chunk
    if not collected[chunk .. ":" .. p.slot] then
      spawnObject(p, offset)
      list[#list + 1] = p
    end
  end
  active[chunk] = list
end

---@param chunk integer
function M.despawn(chunk)
  for _, p in ipairs(active[chunk] or {}) do p.object:delete() end
  active[chunk] = nil
end

function M.clear()
  for chunk in pairs(active) do M.despawn(chunk) end
end

---@param shift vec3
function M.shift(shift)
  for _, list in pairs(active) do
    for _, p in ipairs(list) do p.object:setPosition(p.object:getPosition() - shift) end
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

---Collects any pickup within reach of the car.
---@param carPos vec3 world position
---@param offset vec3
function M.update(carPos, offset)
  local radiusSq = aLongDrive_config.pickups.collectRadius ^ 2
  for chunk, list in pairs(active) do
    for i = #list, 1, -1 do
      local p = list[i]
      local dx, dy = p.x - offset.x - carPos.x, p.y - offset.y - carPos.y
      if dx * dx + dy * dy < radiusSq and math.abs(p.z - carPos.z) < 3 then
        collect(p)
        collected[chunk .. ":" .. p.slot] = true
        p.object:delete()
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
