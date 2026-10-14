-- A Long Drive: endless procedural road and terrain with a floating origin.

local M = {}
M.dependencies = { "ui_imgui", "aLongDrive_config", "aLongDrive_road", "aLongDrive_meshBuilder", "aLongDrive_pickups", "aLongDrive_hud" }

local TELEPORT_GRACE_FRAMES = 3
local ORBIT_WORLD_POSITIONS = { "camLastTargetPos", "camLastTargetPos2", "camLastPos", "camLastPos2", "camLastPosPerp", "preResetPos" }

local active = false
local offset = vec3(0, 0, 0) -- virtual position = world position + offset
local carNode = 0
local distance = 0 -- metres driven since start
local lastVirtual -- last car position in virtual coordinates
local chunks = {} -- chunk index -> { road, terrain } ProceduralMesh objects
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
  local meshes = aLongDrive_meshBuilder.build(c, offset)
  chunks[c] = {
    createMeshObject("aLongDrive_road_" .. c, meshes.road),
    createMeshObject("aLongDrive_terrain_" .. c, meshes.terrain),
  }
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
  local carChunk = math.floor(carNode / stride)
  local first, last = math.max(0, carChunk - cfg.behind), carChunk + cfg.ahead
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

---@param pos vec3 world position
local function advanceCarNode(pos)
  local vx, vy = pos.x + offset.x, pos.y + offset.y
  local function distSq(i)
    local n = aLongDrive_road.getNode(i)
    return (n.x - vx) ^ 2 + (n.y - vy) ^ 2
  end
  while distSq(carNode + 1) < distSq(carNode) do
    carNode = carNode + 1
  end
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

---Moves the car back to the world origin without losing momentum, and the chunks with it.
---@param veh table
---@param pos vec3
local function shiftOrigin(veh, pos)
  local shift = vec3(pos.x, pos.y, 0)
  veh:setClusterPosRelRot(veh:getRefNodeId(), 0, 0, pos.z, 0, 0, 0, 1)
  offset = offset + shift
  shiftOrbitCamera(veh, shift)
  for _, objects in pairs(chunks) do
    for _, object in ipairs(objects) do object:setPosition(object:getPosition() - shift) end
  end
  aLongDrive_pickups.shift(shift)
  be:reloadCollision()
  aLongDrive_pickups.collisionReloaded()
end

---@param seed? number
function M.start(seed)
  local veh = be:getPlayerVehicle(0)
  if not veh then
    log("W", "aLongDrive", "No player vehicle, not starting")
    return
  end
  M.stop()
  seed = seed or os.time()
  local pos, dir = veh:getPosition(), veh:getDirectionVector()
  offset = vec3(0, 0, 0)
  carNode = 0
  distance, lastVirtual = 0, nil
  aLongDrive_pickups.reset(seed)
  aLongDrive_road.reset(seed, pos.x, pos.y, aLongDrive_config.hills.minHeight, math.atan2(dir.y, dir.x))
  aLongDrive_meshBuilder.setSeed(seed)
  setPlaneMaterial(aLongDrive_config.terrain.material)
  core_vehicleBridge.registerValueChangeNotification(veh, "fuelVolume")
  core_vehicleBridge.registerValueChangeNotification(veh, "fuelCapacity")
  active = true
  updateChunks()
end

---@param enabled boolean
function M.setDevMode(enabled)
  aLongDrive_config.devMode = enabled
  aLongDrive_pickups.refresh()
end

function M.stop()
  active = false
  clearChunks()
  setPlaneMaterial(nil)
end

---@param pos vec3 world position
local function trackDistance(pos)
  local virtual = vec3(pos.x + offset.x, pos.y + offset.y, 0)
  if lastVirtual then distance = distance + (virtual - lastVirtual):length() end
  lastVirtual = virtual
end

---@param veh table
local function drawHud(veh)
  local id = veh:getId()
  aLongDrive_hud.draw({
    fuel = core_vehicleBridge.getCachedVehicleData(id, "fuelVolume"),
    fuelCapacity = core_vehicleBridge.getCachedVehicleData(id, "fuelCapacity"),
    scrap = aLongDrive_pickups.getStats().scrap,
    distance = distance,
  })
end

local function onExtensionLoaded()
  loadJsonMaterialsFile("/art/aLongDrive/main.materials.json")
end

local function onUpdate()
  if not active then return end
  local veh = be:getPlayerVehicle(0)
  if not veh then return end
  local pos = veh:getPosition()
  advanceCarNode(pos)
  trackDistance(pos)
  aLongDrive_pickups.update(pos, offset)
  drawHud(veh)
  if math.max(math.abs(pos.x), math.abs(pos.y)) > aLongDrive_config.shiftDistance then
    shiftOrigin(veh, pos)
  else
    updateChunks()
  end
end

M.onExtensionLoaded = onExtensionLoaded
M.onUpdate = onUpdate
M.onClientEndMission = M.stop
M.onExtensionUnloaded = M.stop

return M
