-- Builds the meshes for one chunk: a road ribbon plus the terrain corridor around it.
-- Positions are computed in virtual coordinates and emitted minus the current world offset.

local M = {}

local seedShift = 0

---@param seed number
function M.setSeed(seed)
  seedShift = (seed % 1000) * 7.31
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function smoothstep(a, b, x)
  local t = clamp((x - a) / (b - a), 0, 1)
  return t * t * (3 - 2 * t)
end

local function hash(ix, iy)
  local s = math.sin(ix * 127.1 + iy * 311.7 + seedShift) * 43758.5453
  return s - math.floor(s)
end

---@return number smooth noise in [0, 1)
local function valueNoise(x, y)
  local ix, iy = math.floor(x), math.floor(y)
  local fx, fy = x - ix, y - iy
  local ux, uy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
  local a, b = hash(ix, iy), hash(ix + 1, iy)
  local c, d = hash(ix, iy + 1), hash(ix + 1, iy + 1)
  local bottom, top = a + (b - a) * ux, c + (d - c) * ux
  return bottom + (top - bottom) * uy
end

---@return number off-road hill shape in [0, 1)
local function reliefNoise(x, y)
  local scale = aLongDrive_config.terrain.reliefScale
  return 0.65 * valueNoise(x / scale, y / scale) + 0.35 * valueNoise(x / (scale * 0.4) + 17.3, y / (scale * 0.4) + 9.1)
end

---Mirrors a list of positive offsets into a left-to-right list.
---@param positive number[] ascending
---@return number[]
local function mirrored(positive)
  local all = {}
  for i = #positive, 1, -1 do all[#all + 1] = -positive[i] end
  for _, v in ipairs(positive) do all[#all + 1] = v end
  return all
end

---Positive lateral offsets from `from` to `to`, spaced `step` apart, always including both ends.
---@return number[]
local function steps(from, to, step)
  local list = { from }
  local o = from + step
  while o < to - 1e-6 do
    list[#list + 1] = o
    o = o + step
  end
  if to > from then list[#list + 1] = to end
  return list
end

---A point on a smooth curve through the road nodes (Catmull-Rom), so slope and heading change
---gradually instead of kinking at every node.
---@param f number fractional node index
---@return {x: number, y: number, z: number} point, number nx, number ny the left-hand normal
local function centerAt(f)
  f = math.max(f, 0)
  local i = math.floor(f)
  local t = f - i
  local t2, t3 = t * t, t * t * t
  local road = aLongDrive_road
  local p0, p1, p2, p3 = road.getNode(math.max(i - 1, 0)), road.getNode(i), road.getNode(i + 1), road.getNode(i + 2)

  local function value(a, b, c, d)
    return 0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (3 * b - a - 3 * c + d) * t3)
  end
  local function slope(a, b, c, d)
    return 0.5 * ((c - a) + 2 * (2 * a - 5 * b + 4 * c - d) * t + 3 * (3 * b - a - 3 * c + d) * t2)
  end

  local tx, ty = slope(p0.x, p1.x, p2.x, p3.x), slope(p0.y, p1.y, p2.y, p3.y)
  local len = math.sqrt(tx * tx + ty * ty)
  return { x = value(p0.x, p1.x, p2.x, p3.x), y = value(p0.y, p1.y, p2.y, p3.y), z = value(p0.z, p1.z, p2.z, p3.z) }, -ty / len, tx / len
end

---@return integer mesh rows per node segment
local function rowsPerNode()
  local road = aLongDrive_config.road
  return math.max(1, math.floor(road.spacing / road.meshStep + 0.5))
end

---@param faces table[]
local function emit(faces, a, b, c)
  local n = #faces
  faces[n + 1] = { v = a, u = a, n = a }
  faces[n + 2] = { v = b, u = b, n = b }
  faces[n + 3] = { v = c, u = c, n = c }
end

---Appends a closed slab under a grid of top points: top, bottom and side walls.
---Collision only works on closed volumes, and the engine treats clockwise-from-above triangles as front-facing.
---@param mesh table verts, uvs, normals and faces arrays
---@param top table[][] top[row][col] = { x, y, z, nx, ny, nz, u, v }, columns running left from the road
---@param rows integer
---@param cols integer
local function addSlab(mesh, top, rows, cols)
  local thickness = aLongDrive_config.thickness
  local base, count = #mesh.verts, rows * cols
  local function index(r, c) return base + (r - 1) * cols + (c - 1) end

  for layer = 0, 1 do
    for r = 1, rows do
      for c = 1, cols do
        local p = top[r][c]
        mesh.verts[#mesh.verts + 1] = { x = p.x, y = p.y, z = p.z - layer * thickness }
        mesh.normals[#mesh.normals + 1] = { x = p.nx, y = p.ny, z = p.nz }
        mesh.uvs[#mesh.uvs + 1] = { u = p.u, v = p.v }
      end
    end
  end

  for r = 1, rows - 1 do
    for c = 1, cols - 1 do
      local a, b, cc, d = index(r, c), index(r + 1, c), index(r + 1, c + 1), index(r, c + 1)
      emit(mesh.faces, a, d, cc)
      emit(mesh.faces, a, cc, b)
      emit(mesh.faces, a + count, b + count, cc + count)
      emit(mesh.faces, a + count, cc + count, d + count)
    end
  end

  local function wall(p, q)
    emit(mesh.faces, q, p, p + count)
    emit(mesh.faces, q, p + count, q + count)
  end
  for c = 1, cols - 1 do
    wall(index(1, c), index(1, c + 1))
    wall(index(rows, c + 1), index(rows, c))
  end
  for r = 1, rows - 1 do
    wall(index(r, cols), index(r + 1, cols))
    wall(index(r + 1, 1), index(r, 1))
  end
end

---@return table mesh
local function newMesh(material)
  return { verts = {}, uvs = {}, normals = {}, faces = {}, material = material }
end

---@param first integer first node of the chunk
---@param offset vec3
---@return table<integer, table> road meshes by surface index
local function buildRoad(first, offset)
  local cfg = aLongDrive_config
  local halfRoad = cfg.road.width / 2
  local perNode = rowsPerNode()
  local segments = cfg.chunks.nodes - 1

  local rows = {} -- rows[r] = { f = fractional node index, left, right }
  for r = 0, segments * perNode do
    local f = first + r / perNode
    local center, nx, ny = centerAt(f)
    rows[r] = { f = f }
    for side = -1, 1, 2 do
      rows[r][#rows[r] + 1] = {
        x = center.x + nx * halfRoad * side - offset.x,
        y = center.y + ny * halfRoad * side - offset.y,
        z = center.z,
        nx = 0, ny = 0, nz = 1,
        u = (side + 1) / 2,
      }
    end
  end

  -- one closed slab per stretch of segments with the same surface; the texture runs along the road
  local meshes = {}
  local runStart = 0
  for segment = 0, segments - 1 do
    local surface = aLongDrive_road.getSurface(first + segment)
    local nextSurface = segment + 1 < segments and aLongDrive_road.getSurface(first + segment + 1)
    if surface ~= nextSurface then
      local def = cfg.surfaces[surface]
      meshes[surface] = meshes[surface] or newMesh(def.material)
      local top = {}
      for r = runStart * perNode, (segment + 1) * perNode do
        local v = rows[r].f * cfg.road.spacing / def.textureLength
        top[#top + 1] = {
          { x = rows[r][1].x, y = rows[r][1].y, z = rows[r][1].z, nx = 0, ny = 0, nz = 1, u = 0, v = v },
          { x = rows[r][2].x, y = rows[r][2].y, z = rows[r][2].z, nx = 0, ny = 0, nz = 1, u = 1, v = v },
        }
      end
      addSlab(meshes[surface], top, #top, 2)
      runStart = segment + 1
    end
  end
  return meshes
end


---Width of the embankment slope beside the shoulder.
---@return number
local function embankmentWidth()
  local road = aLongDrive_config.road
  return road.moundHeight * road.embankment
end

---Terrain height at a point, given the road height beside it and its distance from the road. The road bed
---is a mound: flat out to the shoulder edge, then sloping down to the ground, which rolls on from there.
---@return number
local function terrainHeight(x, y, roadZ, distance)
  local cfg = aLongDrive_config
  local terrain = cfg.terrain
  local shoulderEdge = cfg.road.width / 2 + terrain.shoulder
  local slope = embankmentWidth()
  local drop = slope > 0 and cfg.road.moundHeight * clamp((distance - shoulderEdge) / slope, 0, 1) or 0
  local hillsStart = shoulderEdge + slope
  local hills = terrain.relief * reliefNoise(x, y) * smoothstep(hillsStart, hillsStart + terrain.blendDistance, distance)
  local edgeFade = 1 - smoothstep(terrain.halfWidth * 0.5, terrain.halfWidth, distance)
  return (roadZ - drop + hills) * edgeFade
end

---Where a node's row puts the terrain at a lateral offset: the samples the coarse mesh is made of.
---@param i integer node index
---@param o number lateral offset
---@return table { x, y, z }
local function nodePoint(i, o)
  local center, nx, ny = centerAt(i)
  local x, y = center.x + nx * o, center.y + ny * o
  return { x = x, y = y, z = terrainHeight(x, y, center.z, math.abs(o)) }
end

---Fine rows: follows the smooth centre line near the road, and eases onto the straight lines between
---node samples towards fineWidth, so its edge meets the coarse mesh with no crack.
---@param f number fractional node index
---@param o number lateral offset
---@return table { x, y, z }
local function finePoint(f, o)
  local terrain = aLongDrive_config.terrain
  local shoulderEdge = aLongDrive_config.road.width / 2 + terrain.shoulder
  local distance = math.abs(o)

  local center, nx, ny = centerAt(f)
  local x, y = center.x + nx * o, center.y + ny * o
  local z = terrainHeight(x, y, center.z, distance)

  local w = smoothstep(shoulderEdge, terrain.fineWidth, distance)
  if w == 0 then return { x = x, y = y, z = z } end
  local i = math.floor(f)
  local t = f - i
  local a, b = nodePoint(i, o), nodePoint(i + 1, o)
  return {
    x = x + (a.x + (b.x - a.x) * t - x) * w,
    y = y + (a.y + (b.y - a.y) * t - y) * w,
    z = z + (a.z + (b.z - a.z) * t - z) * w,
  }
end

---Turns a grid of positions into shaded, textured points with vertex normals.
---@param grid table[][] grid[row][col] = { x, y, z }, with one spare row at each end
---@param firstRow integer
---@param lastRow integer
---@param offset vec3
---@return table[][] points[row][col]
local function shade(grid, firstRow, lastRow, offset)
  local textureScale = aLongDrive_config.terrain.textureScale
  local points = {}
  for r = firstRow, lastRow do
    local before, after = grid[r - 1], grid[r + 1]
    local cols = #grid[r]
    points[r] = {}
    for c = 1, cols do
      local p = grid[r][c]
      local left, right = grid[r][math.min(c + 1, cols)], grid[r][math.max(c - 1, 1)]
      local ax, ay, az = after[c].x - before[c].x, after[c].y - before[c].y, after[c].z - before[c].z
      local bx, by, bz = left.x - right.x, left.y - right.y, left.z - right.z
      local nx, ny, nz = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
      local len = math.sqrt(nx * nx + ny * ny + nz * nz)
      points[r][c] = {
        x = p.x - offset.x, y = p.y - offset.y, z = p.z,
        nx = nx / len, ny = ny / len, nz = nz / len,
        u = p.x / textureScale, v = p.y / textureScale,
      }
    end
  end
  return points
end

---Adds slabs for one side of the road from a shaded grid, for a range of its columns.
---@param mesh table
---@param points table[][]
---@param firstRow integer
---@param lastRow integer
---@param fromCol integer
---@param toCol integer
local function addSlabFromGrid(mesh, points, firstRow, lastRow, fromCol, toCol)
  local slab = {}
  for r = firstRow, lastRow do
    slab[#slab + 1] = {}
    for c = fromCol, toCol do slab[#slab][#slab[#slab] + 1] = points[r][c] end
  end
  addSlab(mesh, slab, #slab, toCol - fromCol + 1)
end

---@param first integer first node of the chunk
---@param offset vec3
local function buildTerrain(first, offset)
  local cfg = aLongDrive_config
  local terrain = cfg.terrain
  local halfRoad = cfg.road.width / 2
  local shoulderEdge = halfRoad + terrain.shoulder
  local nodes = cfg.chunks.nodes
  local perNode = rowsPerNode()
  local mesh = newMesh(terrain.material)

  -- Near the road: fine rows. Columns run left to right: -fineWidth .. -halfRoad, then halfRoad .. fineWidth.
  local slopeEnd = math.min(shoulderEdge + embankmentWidth(), terrain.fineWidth)
  local innerPositive = { halfRoad, shoulderEdge }
  for _, o in ipairs(steps(slopeEnd, terrain.fineWidth, terrain.cell)) do innerPositive[#innerPositive + 1] = o end
  local innerOffsets = mirrored(innerPositive)
  local lastFine = (nodes - 1) * perNode
  local fine = {}
  for r = -1, lastFine + 1 do
    fine[r] = {}
    local f = first + r / perNode
    for c, o in ipairs(innerOffsets) do fine[r][c] = finePoint(math.max(f, 0), o) end
  end
  local finePoints = shade(fine, 0, lastFine, offset)
  local leftEnd, rightStart = #innerPositive, #innerPositive + 1 -- the road strip sits between them
  addSlabFromGrid(mesh, finePoints, 0, lastFine, 1, leftEnd)
  addSlabFromGrid(mesh, finePoints, 0, lastFine, rightStart, #innerOffsets)

  -- Far from the road: coarse rows, one per node, and wider columns.
  local outerPositive = steps(terrain.fineWidth, terrain.halfWidth, terrain.farCell)
  local outerOffsets = mirrored(outerPositive)
  local coarse = {}
  for r = -1, nodes do
    coarse[r] = {}
    for c, o in ipairs(outerOffsets) do coarse[r][c] = nodePoint(math.max(first + r, 0), o) end
  end
  local coarsePoints = shade(coarse, 0, nodes - 1, offset)
  addSlabFromGrid(mesh, coarsePoints, 0, nodes - 1, 1, #outerPositive)
  addSlabFromGrid(mesh, coarsePoints, 0, nodes - 1, #outerPositive + 1, #outerOffsets)
  return mesh
end

---@class ChunkMesh
---@field name string used to name the scene object
---@field mesh table

---@param chunk integer
---@param offset vec3 virtual position = world position + offset
---@return ChunkMesh[] one mesh per ProceduralMesh object, since only one mesh per object renders
function M.build(chunk, offset)
  local cfg = aLongDrive_config
  local first = chunk * (cfg.chunks.nodes - 1)
  local meshes = {}
  for surface, mesh in pairs(buildRoad(first, offset)) do
    meshes[#meshes + 1] = { name = "road_" .. cfg.surfaces[surface].name, mesh = mesh }
  end
  meshes[#meshes + 1] = { name = "terrain", mesh = buildTerrain(first, offset) }
  return meshes
end

return M
