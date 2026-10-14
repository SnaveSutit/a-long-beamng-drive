-- A Long Drive: endless procedural road and terrain with a floating origin.

local M = {}
M.dependencies = { "ui_imgui", "aLongDrive_config", "aLongDrive_road", "aLongDrive_meshBuilder", "aLongDrive_pickups", "aLongDrive_hud" }

local RESET_HEIGHT = 0.5 -- reset position above the road surface
-- unload order for a reload: the extension first, then what it depends on
local MODULES = { "aLongDrive", "aLongDrive_hud", "aLongDrive_pickups", "aLongDrive_meshBuilder", "aLongDrive_road", "aLongDrive_config" }
local UNPACKED_MOD = "/mods/unpacked/a_long_drive/"
local TELEPORT_GRACE_FRAMES = 3
local ORBIT_WORLD_POSITIONS = { "camLastTargetPos", "camLastTargetPos2", "camLastPos", "camLastPos2", "camLastPosPerp", "preResetPos" }

local active = false
local offset = vec3(0, 0, 0) -- virtual position = world position + offset
local carId -- the vehicle the player started in; it stays put while they walk
local playerNode = 0 -- road node nearest the player (car or on foot), drives chunk streaming
local carRoadNode = 0 -- road node nearest the car, drives its reset position
local IN_CAR_HINT_DISTANCE = 6 -- tell a driver who is this close to a pickup to get out
local FUEL_POLL_SECONDS = 0.25
local distance = 0 -- metres driven since start
local lastVirtual -- last car position in virtual coordinates
local resetNode -- road node the vehicle's reset transform currently points at
local fuel, fuelCapacity -- litres, reported back by the car
local fuelPollTimer = 0
local currentSeed -- seed of the running road
local chunks = {} -- chunk index -> ProceduralMesh objects: road per surface, terrain
local originalPlaneMaterials = {} -- ground plane name -> material

---@param name string
---@param mesh table
---@return table ProceduralMesh
local function createMeshObject(name, mesh)
  local object = createObject("ProceduralMesh")
  object:setPosition(vec3(0, 0, 0))
  object.canSave = false
  object:registerObject(name)
  scenetree.MissionGroup:add(object.obj)
  object:createMesh({ { mesh } })
  return object
end

---@param c integer
local function createChunk(c)
  local objects = {}
  for _, entry in ipairs(aLongDrive_meshBuilder.build(c, offset)) do
    objects[#objects + 1] = createMeshObject(string.format("aLongDrive_%s_%d", entry.name, c), entry.mesh)
  end
  chunks[c] = objects
  aLongDrive_pickups.spawn(c)
end

local function deleteChunk(c)
  for _, object in ipairs(chunks[c]) do object:delete() end
  aLongDrive_pickups.despawn(c)
  chunks[c] = nil
end

local function clearChunks()
  for c in pairs(chunks) do deleteChunk(c) end
  be:reloadCollision()
end

local function updateChunks()
  local cfg = aLongDrive_config.chunks
  local stride = cfg.nodes - 1 -- neighbouring chunks share one node
  local playerChunk = math.floor(playerNode / stride)
  local first, last = math.max(0, playerChunk - cfg.behind), playerChunk + cfg.ahead
  local changed = false
  for c in pairs(chunks) do
    if c < first or c > last then
      deleteChunk(c)
      changed = true
    end
  end
  for c = first, last do
    if not chunks[c] then
      createChunk(c)
      changed = true
    end
  end
  if changed then
    be:reloadCollision()
    aLongDrive_pickups.collisionReloaded()
  end
end

---Walks a road node index forward to the node nearest a position.
---@param node integer
---@param pos vec3 world position
---@return integer
local function advanceNode(node, pos)
  local vx, vy = pos.x + offset.x, pos.y + offset.y
  local function distSq(i)
    local n = aLongDrive_road.getNode(i)
    return (n.x - vx) ^ 2 + (n.y - vy) ^ 2
  end
  while distSq(node + 1) < distSq(node) do
    node = node + 1
  end
  return node
end

---Swaps the level's ground plane material, remembering the originals.
---@param material? string nil restores the originals
local function setPlaneMaterial(material)
  for _, name in ipairs(scenetree.findClassObjects("GroundPlane")) do
    local plane = scenetree.findObject(name)
    if plane then
      originalPlaneMaterials[name] = originalPlaneMaterials[name] or plane:getField("material", 0)
      plane:setField("material", 0, material or originalPlaneMaterials[name])
      plane:postApply()
    end
  end
  if not material then originalPlaneMaterials = {} end
end

---A teleport makes the orbit camera reset its speed-based pitch and drop its FOV boost.
---For the next few frames, hide the shift from it and keep the previous velocity.
---@param orbit table
local function ignoreShiftInOrbitCamera(orbit)
  local framesLeft = TELEPORT_GRACE_FRAMES
  orbit.update = function(self, data)
    framesLeft = framesLeft - 1
    if framesLeft <= 0 then self.update = nil end
    if data.teleported then
      data.teleported = false
      data.vel:set(data.prevVel)
    end
    return getmetatable(self).update(self, data)
  end
end

---The orbit camera trails the car using stored world positions; without this it swings toward the pre-shift spot.
---@param veh table
---@param shift vec3
local function shiftOrbitCamera(veh, shift)
  local cameras = core_camera.getCameraDataById(veh:getId())
  local orbit = cameras and cameras.orbit
  if not orbit then return end
  for _, field in ipairs(ORBIT_WORLD_POSITIONS) do
    if orbit[field] then orbit[field]:setSub(shift) end
  end
  ignoreShiftInOrbitCamera(orbit)
end

---Road position and heading at a node, in world coordinates.
---@param i integer node index
---@return vec3 position, quat rotation
local function roadPose(i)
  local node, nextNode = aLongDrive_road.getNode(i), aLongDrive_road.getNode(i + 1)
  local forward = vec3(nextNode.x - node.x, nextNode.y - node.y, 0)
  local rotation = quatFromDir(forward, vec3(0, 0, 1)) * quat(0, 0, 1, 0) -- vehicle forward is inverted
  return vec3(node.x - offset.x, node.y - offset.y, node.z + RESET_HEIGHT), rotation
end

---Points the car's reset position at the road under it, so a reset puts it back on the road.
---@param car table
local function updateResetTransform(car)
  if resetNode == carRoadNode then return end
  local pos, rot = roadPose(carRoadNode)
  car:setOriginalTransform(pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, rot.w)
  resetNode = carRoadNode
end

---Moves every vehicle, the player's included, so the car and any parked or prop vehicles stay in place
---relative to the player, and the chunks with them.
---@param player table
---@param pos vec3 the player's world position, which becomes the new origin
local function shiftOrigin(player, pos)
  local shift = vec3(pos.x, pos.y, 0)
  for _, veh in activeVehiclesIterator() do
    local p = veh:getPosition()
    veh:setClusterPosRelRot(veh:getRefNodeId(), p.x - shift.x, p.y - shift.y, p.z, 0, 0, 0, 1)
  end
  offset = offset + shift
  resetNode = nil
  shiftOrbitCamera(player, shift)
  for _, objects in pairs(chunks) do
    for _, object in ipairs(objects) do object:setPosition(object:getPosition() - shift) end
  end
  be:reloadCollision()
  aLongDrive_pickups.collisionReloaded()
end

---@return boolean
local function isWalking()
  return gameplay_walk ~= nil and gameplay_walk.isWalking()
end

---@return integer a seed that differs between clicks made within the same second
local function randomSeed()
  return math.floor(os.time() * 1000 + os.clock() * 1000) % 1000000000 + 1
end

---@param seed? number random if omitted
---@return boolean ok, string? reason
function M.start(seed)
  local veh = be:getPlayerVehicle(0)
  if not veh then
    log("W", "aLongDrive", "No player vehicle, not starting")
    return false, "No vehicle to drive. Spawn a car first."
  end
  if isWalking() then
    log("W", "aLongDrive", "Get in a car before starting")
    return false, "Get in a car first."
  end
  M.stop()
  carId = veh:getId()
  seed = seed or randomSeed()
  currentSeed = seed
  local pos, dir = veh:getPosition(), veh:getDirectionVector()
  local heading = math.atan2(dir.y, dir.x)
  local behind = aLongDrive_config.road.startNodesBehind
  local back = behind * aLongDrive_config.road.spacing
  offset = vec3(0, 0, 0)
  playerNode, carRoadNode = behind, behind
  distance, lastVirtual, resetNode = 0, nil, nil
  aLongDrive_pickups.reset(seed)
  aLongDrive_road.reset(seed, pos.x - math.cos(heading) * back, pos.y - math.sin(heading) * back, aLongDrive_config.hills.minHeight, heading)
  aLongDrive_meshBuilder.setSeed(seed)
  setPlaneMaterial(aLongDrive_config.terrain.material)
  fuel, fuelCapacity, fuelPollTimer = nil, nil, 0
  active = true
  updateChunks()
  local roadPos, roadRot = roadPose(carRoadNode)
  veh:setPositionRotation(roadPos.x, roadPos.y, roadPos.z, roadRot.x, roadRot.y, roadRot.z, roadRot.w)
  updateResetTransform(veh)
  return true
end

---@param enabled boolean
function M.setDevMode(enabled)
  aLongDrive_config.devMode = enabled
  aLongDrive_pickups.refresh()
end

---Starts a fresh road from a random seed.
---@return {ok: boolean, error: string?, seed: integer?}
function M.newGame()
  local ok, reason = M.start()
  return { ok = ok, error = reason, seed = ok and currentSeed or nil }
end

---For the settings page.
---@return {active: boolean, seed: integer?, devMode: boolean, walking: boolean}
function M.getState()
  return {
    active = active,
    seed = active and currentSeed or nil,
    devMode = aLongDrive_config.devMode,
    walking = isWalking(),
  }
end

---Reloads every module of the mod from disk. A road that was running restarts with the same seed.
---Meant for development: it picks up code, config and material edits without restarting the game.
---@return {ok: boolean, restarted: boolean, error: string?}
function M.reload()
  local wasActive, seed, devMode = active, currentSeed, aLongDrive_config.devMode

  if FS:directoryExists(UNPACKED_MOD) then -- a stale mount hides new or renamed files
    FS:unmount(UNPACKED_MOD)
    FS:mount(UNPACKED_MOD)
  end
  for _, name in ipairs(MODULES) do extensions.unload(name) end
  extensions.load("aLongDrive")
  if not aLongDrive then return { ok = false, restarted = false, error = "The mod failed to load again. Check the log." } end

  aLongDrive_config.devMode = devMode
  if not wasActive then return { ok = true, restarted = false } end
  local ok, reason = aLongDrive.start(seed)
  return { ok = ok, restarted = ok, error = reason }
end

function M.stop()
  active = false
  currentSeed = nil
  clearChunks()
  setPlaneMaterial(nil)
end

---@param pos vec3 world position
local function trackDistance(pos)
  local virtual = vec3(pos.x + offset.x, pos.y + offset.y, 0)
  if lastVirtual then distance = distance + (virtual - lastVirtual):length() end
  lastVirtual = virtual
end

---Called by the car's own Lua with its tank levels. The vehicle bridge's cache goes stale once you
---step out of the car, so the car reports its fuel back instead.
---@param liters number
---@param capacity number
function M.setFuel(liters, capacity)
  fuel, fuelCapacity = liters, capacity
end

---@param car table
local function requestFuel(car)
  car:queueLuaCommand([[
    local liters, capacity = 0, 0
    for _, s in pairs(energyStorage.getStorages()) do
      if s.fuelLiquidDensity and s.energyCapacity > 0 then
        liters = liters + s.storedEnergy / s.energyCapacity * s.capacity
        capacity = capacity + s.capacity
      end
    end
    obj:queueGameEngineLua(string.format("if aLongDrive then aLongDrive.setFuel(%f, %f) end", liters, capacity))
  ]])
end

---@param player table
local function drawHud(player)
  local prompt
  if isWalking() then
    local pickup = aLongDrive_pickups.nearest(player:getPosition(), aLongDrive_config.pickups.reach)
    if pickup then prompt = string.format("[%s] Collect %s", aLongDrive_config.pickups.keyLabel, pickup.kind) end
  end
  aLongDrive_hud.draw({
    fuel = fuel,
    fuelCapacity = fuelCapacity,
    scrap = aLongDrive_pickups.getStats().scrap,
    distance = distance,
    prompt = prompt,
  })
end

---Bound to the collect key: picks up the pickup in reach while on foot.
function M.collect()
  local player, car = be:getPlayerVehicle(0), be:getObjectByID(carId or -1)
  if not (active and player and car) then return end
  if isWalking() then
    aLongDrive_pickups.collectNearest(player:getPosition(), car)
  elseif aLongDrive_pickups.nearest(player:getPosition(), IN_CAR_HINT_DISTANCE) then
    ui_message("Get out of the car to pick that up", 3, "aLongDrive")
  end
end

local MATERIALS_FILE = "/art/aLongDrive/main.materials.json"

---Loading the file registers new materials but doesn't refresh ones the renderer already has,
---so reload them too, which lets edits to the file show up on the next extension load.
local function onExtensionLoaded()
  loadJsonMaterialsFile(MATERIALS_FILE)
  for name in pairs(jsonReadFile(MATERIALS_FILE) or {}) do
    local material = scenetree.findObject(name)
    if material then material:reload() end
  end
end

local function onUpdate(dtReal)
  if not active then return end
  local player, car = be:getPlayerVehicle(0), be:getObjectByID(carId)
  if not player then return end
  if not car then
    log("W", "aLongDrive", "The car is gone, stopping")
    M.stop()
    return
  end
  local pos = player:getPosition()
  playerNode = advanceNode(playerNode, pos)
  carRoadNode = advanceNode(carRoadNode, car:getPosition())
  updateResetTransform(car)
  fuelPollTimer = fuelPollTimer - dtReal
  if fuelPollTimer <= 0 then
    fuelPollTimer = FUEL_POLL_SECONDS
    requestFuel(car)
  end
  trackDistance(pos)
  aLongDrive_pickups.update(offset)
  drawHud(player)
  if math.max(math.abs(pos.x), math.abs(pos.y)) > aLongDrive_config.shiftDistance then
    shiftOrigin(player, pos)
  else
    updateChunks()
  end
end

M.onExtensionLoaded = onExtensionLoaded
M.onUpdate = onUpdate
M.onClientEndMission = M.stop
M.onExtensionUnloaded = M.stop

return M
