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

---Lateral offsets from the road centre (positive is left), finest near the road.
---@return number[]
local function buildOffsets()
  local cfg = aLongDrive_config
  local halfRoad = cfg.road.width / 2
  local shoulderEdge = halfRoad + cfg.terrain.shoulder
  local outer = {}
  local o = shoulderEdge + cfg.terrain.cell
  while o < cfg.terrain.halfWidth do
    outer[#outer + 1] = o
    o = o + cfg.terrain.cell
  end
  outer[#outer + 1] = cfg.terrain.halfWidth

  local offsets = {}
  for i = #outer, 1, -1 do offsets[#offsets + 1] = -outer[i] end
  offsets[#offsets + 1] = -shoulderEdge
  offsets[#offsets + 1] = -halfRoad
  offsets[#offsets + 1] = halfRoad
  offsets[#offsets + 1] = shoulderEdge
  for _, v in ipairs(outer) do offsets[#offsets + 1] = v end
  return offsets
end

---@param i integer node index
---@return table node, number tx, number ty, number nx, number ny
local function frame(i)
  local prev, next = aLongDrive_road.getNode(math.max(i - 1, 0)), aLongDrive_road.getNode(i + 1)
  local tx, ty = next.x - prev.x, next.y - prev.y
  local len = math.sqrt(tx * tx + ty * ty)
  tx, ty = tx / len, ty / len
  return aLongDrive_road.getNode(i), tx, ty, -ty, tx
end

---@param faces table[]
local function emit(faces, a, b, c)
  for _, v in ipairs({ a, b, c }) do
    faces[#faces + 1] = { v = v, u = v, n = v }
  end
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

---@param first integer
---@param last integer
---@param offset vec3
local function buildRoad(first, last, offset)
  local cfg = aLongDrive_config
  local halfRoad = cfg.road.width / 2
  local top = {}
  for i = first, last do
    local node, _, _, nx, ny = frame(i)
    local v = i * cfg.road.spacing / cfg.road.textureLength
    top[#top + 1] = {}
    for side = -1, 1, 2 do
      top[#top][#top[#top] + 1] = {
        x = node.x + nx * halfRoad * side - offset.x,
        y = node.y + ny * halfRoad * side - offset.y,
        z = node.z,
        nx = 0, ny = 0, nz = 1,
        u = (side + 1) / 2, v = v,
      }
    end
  end
  local mesh = newMesh(cfg.road.material)
  addSlab(mesh, top, #top, 2)
  return mesh
end

---@param first integer
---@param last integer
---@param offset vec3
local function buildTerrain(first, last, offset)
  local cfg = aLongDrive_config
  local terrain = cfg.terrain
  local halfRoad = cfg.road.width / 2
  local shoulderEdge = halfRoad + terrain.shoulder
  local offsets = buildOffsets()
  local cols = #offsets

  local lowRow, highRow = math.max(first - 1, 0), last + 1
  local grid = {}
  for r = lowRow, highRow do
    local node, _, _, nx, ny = frame(r)
    grid[r] = {}
    for c, o in ipairs(offsets) do
      local x, y = node.x + nx * o, node.y + ny * o
      local distance = math.abs(o)
      local hills = terrain.relief * reliefNoise(x, y) * smoothstep(shoulderEdge, shoulderEdge + terrain.blendDistance, distance)
      local edgeFade = 1 - smoothstep(terrain.halfWidth * 0.5, terrain.halfWidth, distance)
      grid[r][c] = { x = x, y = y, z = (node.z + hills) * edgeFade }
    end
  end

  -- vertex normals from neighbouring rows and columns
  local points = {}
  for r = first, last do
    local before, after = grid[math.max(r - 1, lowRow)], grid[r + 1]
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
        u = p.x / terrain.textureScale, v = p.y / terrain.textureScale,
      }
    end
  end

  -- one slab each side of the road; the road ribbon fills the strip between the road edges
  local mesh = newMesh(terrain.material)
  local leftEnd, rightStart
  for c, o in ipairs(offsets) do
    if o == -halfRoad then leftEnd = c end
    if o == halfRoad then rightStart = c end
  end
  for _, range in ipairs({ { 1, leftEnd }, { rightStart, cols } }) do
    local slab = {}
    for r = first, last do
      slab[#slab + 1] = {}
      for c = range[1], range[2] do slab[#slab][#slab[#slab] + 1] = points[r][c] end
    end
    addSlab(mesh, slab, #slab, range[2] - range[1] + 1)
  end
  return mesh
end

---@param chunk integer
---@param offset vec3 virtual position = world position + offset
---@return {road: table, terrain: table} one mesh per ProceduralMesh object, since only one mesh per object renders
function M.build(chunk, offset)
  local nodes = aLongDrive_config.chunks.nodes
  local first = chunk * (nodes - 1)
  local last = first + nodes - 1
  return { road = buildRoad(first, last, offset), terrain = buildTerrain(first, last, offset) }
end

return M
