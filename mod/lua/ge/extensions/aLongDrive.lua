-- A Long Drive: endless procedural world, streamed in chunks, with a floating origin.

local M = {}
M.dependencies = { "ui_imgui", "aLongDrive_config", "aLongDrive_biomes", "aLongDrive_noise", "aLongDrive_roads", "aLongDrive_world", "aLongDrive_meshBuilder", "aLongDrive_hud" }

local RESET_HEIGHT = 0.5 -- reset position above the ground
-- unload order for a reload: the extension first, then what it depends on, the biome files last
local MODULES = { "aLongDrive", "aLongDrive_hud", "aLongDrive_meshBuilder", "aLongDrive_world", "aLongDrive_roads", "aLongDrive_noise", "aLongDrive_biomes", "aLongDrive_config" }
local UNPACKED_MOD = "/mods/unpacked/a_long_drive/"
local TELEPORT_GRACE_FRAMES = 3
local ORBIT_WORLD_POSITIONS = { "camLastTargetPos", "camLastTargetPos2", "camLastPos", "camLastPos2", "camLastPosPerp", "preResetPos" }

local active = false
local offset = vec3(0, 0, 0) -- virtual position = world position + offset
local carId -- the vehicle the player started in; it stays put while they walk
local playerVirtual = vec3(0, 0, 0) -- player position in virtual coordinates, drives chunk streaming
local FUEL_POLL_SECONDS = 0.25
local RESET_UPDATE_SECONDS = 1
local distance = 0 -- metres driven since start
local lastVirtual -- last car position in virtual coordinates
local resetTimer = 0 -- seconds until the car's reset transform is refreshed
local fuel, fuelCapacity -- litres, reported back by the car
local fuelPollTimer = 0
local currentSeed -- seed of the running world
local collisionStale = false -- chunks changed since the collision world was last rebuilt
local job -- the chunk being built a slice at a time: { entry, thread }
local chunks = {} -- key -> { entry, objects = ProceduralMesh objects }
local originalPlaneMaterials = {} -- ground plane name -> material
local originalFogDensity -- the level's own, while ours is in effect

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

---A thing that is streamed in: a square of terrain, or a segment of road.
---@class ChunkEntry
---@field key string
---@field kind "terrain"|"road"
---@field a integer terrain: chunk column; road: which road
---@field b integer terrain: chunk row; road: which segment along it
---@field x number virtual position of its middle
---@field y number

---@return ChunkEntry
local function terrainEntry(cx, cy)
  local size = aLongDrive_config.chunks.size
  return { key = "t:" .. cx .. ":" .. cy, kind = "terrain", a = cx, b = cy, x = (cx + 0.5) * size, y = (cy + 0.5) * size }
end

---@return ChunkEntry
local function roadEntry(k, j)
  local x, y = aLongDrive_roads.centreAt(k, (j + 0.5) * aLongDrive_config.road.segment)
  return { key = "r:" .. k .. ":" .. j, kind = "road", a = k, b = j, x = x, y = y }
end

---@param entry ChunkEntry
---@param yield? fun()
---@return ChunkMesh[]
local function buildEntry(entry, yield)
  if entry.kind == "terrain" then return aLongDrive_meshBuilder.build(entry.a, entry.b, offset, yield) end
  return aLongDrive_meshBuilder.buildRoad(entry.a, entry.b, offset, yield)
end

---@param entry ChunkEntry
---@param meshes ChunkMesh[]
local function createObjects(entry, meshes)
  local objects = {}
  for _, mesh in ipairs(meshes) do
    local name = string.format("aLongDrive_%s_%d_%d", mesh.name, entry.a, entry.b):gsub("-", "n")
    objects[#objects + 1] = createMeshObject(name, mesh.mesh)
  end
  chunks[entry.key] = { entry = entry, objects = objects }
  collisionStale = true
end

---@param key string
local function deleteChunk(key)
  for _, object in ipairs(chunks[key].objects) do object:delete() end
  chunks[key] = nil
  collisionStale = true
end

local function clearChunks()
  for key in pairs(chunks) do deleteChunk(key) end
  be:reloadCollision()
  collisionStale = false
end

---Builds the job's chunk for a few milliseconds, and creates it when the last slice is done.
---@return boolean finished
local function advanceJob()
  local start = os.clock()
  repeat
    local ok, result = coroutine.resume(job.thread)
    if not ok then error(debug.traceback(job.thread, result)) end
    if coroutine.status(job.thread) == "dead" then
      createObjects(job.entry, result)
      job = nil
      return true
    end
  until (os.clock() - start) * 1000 >= aLongDrive_config.chunks.buildBudgetMs
  return false
end

---Loads the chunks around the player, nearest first, and drops the ones left behind.
---Chunks are dropped one ring beyond the loaded area, so crossing a border back and forth rebuilds nothing.
---Moving, one chunk at a time is built in slices of a few milliseconds per frame.
---@param all? boolean build every missing chunk now, in one go
local function updateChunks(all)
  local cfg = aLongDrive_config.chunks
  local px, py = playerVirtual.x, playerVirtual.y
  local centerX, centerY = math.floor(px / cfg.size), math.floor(py / cfg.size)

  local wanted, wantedKeys = {}, {}
  for dx = -cfg.radius, cfg.radius do
    for dy = -cfg.radius, cfg.radius do wanted[#wanted + 1] = terrainEntry(centerX + dx, centerY + dy) end
  end
  for _, segment in ipairs(aLongDrive_roads.segmentsNear(px, py, (cfg.radius + 0.5) * cfg.size)) do
    wanted[#wanted + 1] = roadEntry(segment.k, segment.j)
  end
  for _, entry in ipairs(wanted) do
    entry.distanceSq = (entry.x - px) ^ 2 + (entry.y - py) ^ 2
    wantedKeys[entry.key] = true
  end
  table.sort(wanted, function(a, b) return a.distanceSq < b.distanceSq end)

  local dropReach = (cfg.radius + 1.5) * cfg.size
  for key, chunk in pairs(chunks) do
    local entry = chunk.entry
    local kept
    if entry.kind == "terrain" then
      kept = math.max(math.abs(entry.a - centerX), math.abs(entry.b - centerY)) <= cfg.radius + 1
    else
      kept = (entry.x - px) ^ 2 + (entry.y - py) ^ 2 <= dropReach * dropReach
    end
    if not kept then deleteChunk(key) end
  end
  if job and not wantedKeys[job.entry.key] then job = nil end

  local missing = {}
  for _, entry in ipairs(wanted) do
    if not chunks[entry.key] then missing[#missing + 1] = entry end
  end

  local pending = #missing
  if all then
    job = nil
    for _, entry in ipairs(missing) do createObjects(entry, buildEntry(entry)) end
    pending = 0
  else
    if not job and pending > 0 then
      local entry = missing[1]
      job = { entry = entry, thread = coroutine.create(function() return buildEntry(entry, coroutine.yield) end) }
    end
    if job and advanceJob() then pending = pending - 1 end
  end
  -- rebuilding collision costs about 0.4 ms per chunk in the world whatever changed, so do it once, when the new chunks are all in
  if collisionStale and not job and pending == 0 then
    be:reloadCollision()
    collisionStale = false
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

---@param density? number nil restores the level's own
local function setFogDensity(density)
  local info = scenetree.theLevelInfo
  if not info then return end
  if density then
    originalFogDensity = originalFogDensity or info:getField("fogDensity", 0)
    info:setField("fogDensity", 0, tostring(density))
  elseif originalFogDensity then
    info:setField("fogDensity", 0, originalFogDensity)
    originalFogDensity = nil
  end
  info:postApply()
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

---Where the car belongs on the ground under a position, level and facing the way it points.
---@param pos vec3 world position
---@param dir vec3 the way the car points
---@return vec3? position, quat? rotation nil when the car points straight up or down
local function groundPose(pos, dir)
  local forward = vec3(dir.x, dir.y, 0)
  if forward:length() < 0.1 then return end
  local height = aLongDrive_world.surfaceHeightAt(pos.x + offset.x, pos.y + offset.y)
  return vec3(pos.x, pos.y, height + RESET_HEIGHT), quatFromDir(forward, vec3(0, 0, 1)) * quat(0, 0, 1, 0) -- vehicle forward is inverted
end

---Points the car's reset position at the ground under it, so a reset puts it back upright where it is.
---@param car table
---@param dtReal number
local function updateResetTransform(car, dtReal)
  resetTimer = resetTimer - dtReal
  if resetTimer > 0 then return end
  local pos, rot = groundPose(car:getPosition(), car:getDirectionVector())
  if not pos then return end
  car:setOriginalTransform(pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, rot.w)
  resetTimer = RESET_UPDATE_SECONDS
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
  job = nil -- it was built against the old offset
  resetTimer = 0
  shiftOrbitCamera(player, shift)
  for _, chunk in pairs(chunks) do
    for _, object in ipairs(chunk.objects) do object:setPosition(object:getPosition() - shift) end
  end
  be:reloadCollision()
  collisionStale = false
end

---@return boolean
local function isWalking()
  return gameplay_walk ~= nil and gameplay_walk.isWalking()
end

---@return integer a seed that differs between clicks made within the same second
local function randomSeed()
  return math.floor(os.time() * 1000 + os.clock() * 1000) % 1000000000 + 1
end

---Sets everything up for a new world. May throw; M.start catches that.
---@param veh table the player's vehicle
---@param seed integer
local function begin(veh, seed)
  carId = veh:getId()
  currentSeed = seed
  local pos = veh:getPosition()
  offset = vec3(-pos.x, -pos.y, 0) -- the car starts at the virtual origin, so a seed gives the same world wherever it starts
  distance, lastVirtual, resetTimer, job = 0, nil, 0, nil
  aLongDrive_biomes.reset()
  aLongDrive_world.setSeed(seed)
  aLongDrive_roads.setSeed(seed)
  setPlaneMaterial(aLongDrive_config.terrain.material)
  setFogDensity(aLongDrive_config.fogDensity)
  fuel, fuelCapacity, fuelPollTimer = nil, nil, 0
  active = true

  -- the car starts on the nearest road, pointing the way it already pointed
  local roadX, roadY, dirX, dirY = aLongDrive_roads.poseNear(0, 0)
  local carDir = veh:getDirectionVector()
  if dirX * carDir.x + dirY * carDir.y < 0 then dirX, dirY = -dirX, -dirY end
  playerVirtual = vec3(roadX, roadY, 0)
  updateChunks(true)
  local groundPos, groundRot = groundPose(vec3(roadX - offset.x, roadY - offset.y, 0), vec3(dirX, dirY, 0))
  veh:setPositionRotation(groundPos.x, groundPos.y, groundPos.z, groundRot.x, groundRot.y, groundRot.z, groundRot.w)
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
  local ok, err = xpcall(begin, debug.traceback, veh, seed or randomSeed())
  if not ok then
    log("E", "aLongDrive", "Could not start: " .. tostring(err))
    pcall(M.stop)
    return false, "Starting failed. Check the log."
  end
  return true
end

---Starts a fresh world from a random seed.
---@return {ok: boolean, error: string?, seed: integer?}
function M.newGame()
  local ok, reason = M.start()
  return { ok = ok, error = reason, seed = ok and currentSeed or nil }
end

---For the settings page.
---@return {active: boolean, seed: integer?, walking: boolean, biome: string}
function M.getState()
  local biome = active and aLongDrive_world.biomeAt(playerVirtual.x, playerVirtual.y) or 1
  return {
    active = active,
    seed = active and currentSeed or nil,
    walking = isWalking(),
    biome = aLongDrive_biomes.def(biome).name,
  }
end

---Reloads every module of the mod from disk. A world that was running restarts with the same seed.
---Meant for development: it picks up code, config and material edits without restarting the game.
---@return {ok: boolean, restarted: boolean, error: string?}
function M.reload()
  local wasActive, seed = active, currentSeed

  if FS:directoryExists(UNPACKED_MOD) then -- a stale mount hides new or renamed files
    FS:unmount(UNPACKED_MOD)
    FS:mount(UNPACKED_MOD)
  end
  local biomeModules = aLongDrive_biomes.moduleNames()
  for _, name in ipairs(MODULES) do extensions.unload(name) end
  for _, name in ipairs(biomeModules) do extensions.unload(name) end
  extensions.load("aLongDrive")
  if not aLongDrive then return { ok = false, restarted = false, error = "The mod failed to load again. Check the log." } end

  if not wasActive then return { ok = true, restarted = false } end
  local ok, reason = aLongDrive.start(seed)
  return { ok = ok, restarted = ok, error = reason }
end

function M.stop()
  active = false
  job = nil
  currentSeed = nil
  clearChunks()
  setPlaneMaterial(nil)
  setFogDensity(nil)
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

local function drawHud()
  aLongDrive_hud.draw({
    fuel = fuel,
    fuelCapacity = fuelCapacity,
    scrap = 0,
    distance = distance,
  })
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

local function update(dtReal)
  if not active then return end
  local player, car = be:getPlayerVehicle(0), be:getObjectByID(carId)
  if not player then return end
  if not car then
    log("W", "aLongDrive", "The car is gone, stopping")
    M.stop()
    return
  end
  local pos = player:getPosition()
  playerVirtual = vec3(pos.x + offset.x, pos.y + offset.y, 0)
  updateResetTransform(car, dtReal)
  fuelPollTimer = fuelPollTimer - dtReal
  if fuelPollTimer <= 0 then
    fuelPollTimer = FUEL_POLL_SECONDS
    requestFuel(car)
  end
  trackDistance(pos)
  drawHud()
  if math.max(math.abs(pos.x), math.abs(pos.y)) > aLongDrive_config.shiftDistance then
    shiftOrigin(player, pos)
  else
    updateChunks()
  end
end

---An error in an extension's onUpdate stops the game's whole update hook for every extension after it,
---every frame. So catch it, stop the mod and log once instead.
---@param dtReal number
local function onUpdate(dtReal)
  local ok, err = xpcall(update, debug.traceback, dtReal)
  if not ok then
    log("E", "aLongDrive", "Stopping after an error: " .. tostring(err))
    pcall(M.stop)
  end
end

M.onExtensionLoaded = onExtensionLoaded
M.onUpdate = onUpdate
M.onClientEndMission = M.stop
M.onExtensionUnloaded = M.stop

return M
