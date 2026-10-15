-- Builds the meshes for one terrain chunk: a square of the world, one mesh per biome in it.
-- Positions are computed in virtual coordinates and emitted minus the current world offset.

local M = {}

local ROWS_PER_SLICE = 4 -- rows of work between yields, when building in slices
local SKIRT_WIDTH = 1 -- the road bed's slope carries on this far past its foot, down under the ground, so there is no gap along its edge
local SKIRT_DEPTH = 1.2 -- how far below the foot it goes: past the ground beside the road, which sits just under the foot

---@param faces table[]
local function emit(faces, a, b, c)
  local n = #faces
  faces[n + 1] = { v = a, u = a, n = a }
  faces[n + 2] = { v = b, u = b, n = b }
  faces[n + 3] = { v = c, u = c, n = c }
end

---A mesh with one material. It holds its own copies of the points it uses.
---@param material string
---@param uv? fun(p: table): number, number texture coordinates of a point, if not its own u and v
---@return table group { mesh, vertexAt, uv }
local function newGroup(material, uv)
  return { mesh = { verts = {}, uvs = {}, normals = {}, faces = {}, material = material }, vertexAt = {}, uv = uv }
end

local function smoothstep(a, b, x)
  local t = math.max(0, math.min(1, (x - a) / (b - a)))
  return t * t * (3 - 2 * t)
end

---Index of a grid point in a group's mesh, adding it the first time.
---@param group table
---@param grid table[][]
---@param r integer
---@param c integer
---@return integer
local function vertexIn(group, grid, r, c)
  local key = r * 65536 + c
  local index = group.vertexAt[key]
  if not index then
    local p, mesh = grid[r][c], group.mesh
    local u, v = p.u, p.v
    if group.uv then u, v = group.uv(p) end
    index = #mesh.verts
    mesh.verts[index + 1] = { x = p.x, y = p.y, z = p.z }
    mesh.normals[index + 1] = { x = p.nx, y = p.ny, z = p.nz }
    mesh.uvs[index + 1] = { u = u, v = v }
    group.vertexAt[key] = index
  end
  return index
end

---Adds the quad between rows r and r + 1 and columns c and c + 1 of a grid to a group.
---@param group table
---@param grid table[][]
local function addQuad(group, grid, r, c)
  local faces = group.mesh.faces
  local a, b = vertexIn(group, grid, r, c), vertexIn(group, grid, r + 1, c)
  local cc, d = vertexIn(group, grid, r + 1, c + 1), vertexIn(group, grid, r, c + 1)
  emit(faces, a, d, cc)
  emit(faces, a, cc, b)
end

---@class ChunkMesh
---@field name string used to name the scene object
---@field mesh table

---@param cx integer chunk column: the chunk covers virtual x from cx * size to (cx + 1) * size
---@param cy integer chunk row
---@param offset vec3 virtual position = world position + offset
---@param yield? fun() called every few rows; pass coroutine.yield to build in slices, resuming once per frame
---@return ChunkMesh[] one mesh per ProceduralMesh object, since only one mesh per object renders
function M.build(cx, cy, offset, yield)
  local cfg = aLongDrive_config
  local size, cell = cfg.chunks.size, cfg.chunks.cell
  local segments = math.floor(size / cell + 0.5)
  local textureScale = cfg.terrain.textureScale
  local heightAt = aLongDrive_world.heightAt
  local function xAt(c) return (cx + 1) * size - c * cell end
  local function yAt(r) return cy * size + r * cell end

  -- heights with one extra ring around the chunk, so normals come from the height function itself
  -- and shading matches across chunk edges
  local heights = {}
  for r = -1, segments + 1 do
    if yield and r % ROWS_PER_SLICE == 0 then yield() end
    heights[r] = {}
    for c = -1, segments + 1 do heights[r][c] = heightAt(xAt(c), yAt(r)) end
  end

  -- grid[r + 1][c + 1] is the point at row r, column c: rows run north and columns run west
  local grid = {}
  for r = 0, segments do
    if yield and r % ROWS_PER_SLICE == 0 then yield() end
    grid[r + 1] = {}
    for c = 0, segments do
      local x, y = xAt(c), yAt(r)
      local dx = (heights[r][c - 1] - heights[r][c + 1]) / (2 * cell)
      local dy = (heights[r + 1][c] - heights[r - 1][c]) / (2 * cell)
      local len = math.sqrt(dx * dx + dy * dy + 1)
      grid[r + 1][c + 1] = {
        x = x - offset.x, y = y - offset.y, z = heights[r][c],
        nx = -dx / len, ny = -dy / len, nz = 1 / len,
        u = x / textureScale, v = y / textureScale,
      }
    end
  end

  -- Only the top is built: a car driving on it collides fine without a closed volume under it.
  -- The engine treats clockwise-from-above triangles as front-facing. Each square goes to the biome at its middle.
  local groups = {}
  for r = 1, segments do
    if yield and r % ROWS_PER_SLICE == 0 then yield() end
    for c = 1, segments do
      local biome = aLongDrive_world.biomeAt((xAt(c - 1) + xAt(c)) / 2, (yAt(r - 1) + yAt(r)) / 2)
      groups[biome] = groups[biome] or newGroup(aLongDrive_biomes.get(biome).terrain.material)
      addQuad(groups[biome], grid, r, c)
    end
  end

  local meshes = {}
  for biome, group in pairs(groups) do
    meshes[#meshes + 1] = { name = "terrain_" .. aLongDrive_biomes.def(biome).name, mesh = group.mesh }
  end
  return meshes
end

---The cross-section of the road at one row: points from the right edge of the mound to the left, with the
---road's own strip in the middle. Positions are in virtual coordinates.
---@param k integer
---@param v number
---@return table row
local function roadRow(k, v)
  local world = aLongDrive_world
  local x, y, dirX, dirY = aLongDrive_roads.centreAt(k, v)
  local z = world.roadHeightAt(x, y, k, v)
  local profile = world.profileAt(x, y)
  local halfRoad, shoulderEdge, slopeEnd, drop = world.layout(profile)
  local tilt = world.tiltAt(k, v, profile)
  local ground = z - drop -- the flat ground the bed slopes down to
  local divisions = world.SLOPE_DIVISIONS
  local positive = { halfRoad, shoulderEdge }
  for s = 1, divisions - 1 do positive[#positive + 1] = shoulderEdge + (slopeEnd - shoulderEdge) * s / divisions end
  positive[#positive + 1] = slopeEnd
  positive[#positive + 1] = slopeEnd + SKIRT_WIDTH

  local row = { v = v, half = halfRoad, biome = profile.biome, surface = profile.surface, side = #positive }
  for c = 1, 2 * #positive do
    local o = c <= #positive and -positive[#positive + 1 - c] or positive[c - #positive]
    local bed = z + tilt * math.max(-shoulderEdge, math.min(shoulderEdge, o)) -- leans out to the edge of the shoulder
    local height = ground + (bed - ground) * (1 - smoothstep(shoulderEdge, slopeEnd, math.abs(o)))
    if math.abs(o) > slopeEnd then height = ground - SKIRT_DEPTH end
    row[c] = { x = x - dirY * o, y = y + dirX * o, z = height, o = o }
  end
  return row
end

---Meshes for one segment of one road: the road strip per surface, and the ground of the mound beside it per biome.
---@param k integer which road
---@param j integer which segment along it
---@param offset vec3 virtual position = world position + offset
---@param yield? fun() called every few rows; pass coroutine.yield to build in slices
---@return ChunkMesh[]
function M.buildRoad(k, j, offset, yield)
  local cfg = aLongDrive_config
  local road = cfg.road
  local rows = math.max(1, math.floor(road.segment / road.meshStep + 0.5))
  local textureScale = cfg.terrain.textureScale

  local lines = {} -- one spare row each end, so normals match across segments
  for r = -1, rows + 1 do
    if yield and r % ROWS_PER_SLICE == 0 then yield() end
    lines[r] = roadRow(k, j * road.segment + r * road.segment / rows)
  end

  local points = {}
  for r = 0, rows do
    if yield and r % ROWS_PER_SLICE == 0 then yield() end
    local line, before, after = lines[r], lines[r - 1], lines[r + 1]
    local cols = #line
    points[r] = {}
    for c = 1, cols do
      local p = line[c]
      local left, right = line[math.min(c + 1, cols)], line[math.max(c - 1, 1)]
      local ax, ay, az = after[c].x - before[c].x, after[c].y - before[c].y, after[c].z - before[c].z
      local bx, by, bz = left.x - right.x, left.y - right.y, left.z - right.z
      local nx, ny, nz = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
      local len = math.sqrt(nx * nx + ny * ny + nz * nz)
      points[r][c] = {
        x = p.x - offset.x, y = p.y - offset.y, z = p.z,
        nx = nx / len, ny = ny / len, nz = nz / len,
        u = p.x / textureScale, v = p.y / textureScale,
        o = p.o, half = line.half, along = line.v,
      }
    end
  end

  local groups, order = {}, {}
  local function group(key, name, material, uv)
    if not groups[key] then
      groups[key] = { name = name, group = newGroup(material, uv) }
      order[#order + 1] = key
    end
    return groups[key].group
  end

  for r = 0, rows - 1 do
    if yield and r % ROWS_PER_SLICE == 0 then yield() end
    local line = lines[r]
    local biomeConfig = aLongDrive_biomes.get(line.biome)
    local biomeName = aLongDrive_biomes.def(line.biome).name
    local def = biomeConfig.surfaces[line.surface]
    local side = line.side
    local ground = group("ground" .. line.biome, "roadside_" .. biomeName, biomeConfig.terrain.material)
    local surface = group(line.biome .. ":" .. line.surface, "road_" .. biomeName .. "_" .. def.name, def.material, function(p)
      return (p.o + p.half) / (2 * p.half), p.along / def.textureLength
    end)
    for c = 1, side - 1 do addQuad(ground, points, r, c) end
    addQuad(surface, points, r, side)
    for c = side + 1, 2 * side - 1 do addQuad(ground, points, r, c) end
  end

  local meshes = {}
  for _, key in ipairs(order) do meshes[#meshes + 1] = { name = groups[key].name, mesh = groups[key].group.mesh } end
  return meshes
end

return M
