-- Seeded lattice noise, shared by the terrain, the biomes and the roads.

local M = {}

local seedShift = 0

---@param seed number
function M.setSeed(seed)
  seedShift = (seed % 1000) * 7.31
end

---@param salt? number tells apart the values asked for at one lattice point
---@return number pseudo-random value in [0, 1) for a lattice point
function M.hash(ix, iy, salt)
  local s = math.sin(ix * 127.1 + iy * 311.7 + (salt or 0) * 74.7 + seedShift) * 43758.5453
  return s - math.floor(s)
end

---@return number smooth noise in [0, 1). The quintic fade keeps the curvature continuous across lattice lines.
function M.value(x, y)
  local hash = M.hash
  local ix, iy = math.floor(x), math.floor(y)
  local fx, fy = x - ix, y - iy
  local ux = fx * fx * fx * (fx * (fx * 6 - 15) + 10)
  local uy = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
  local a, b = hash(ix, iy), hash(ix + 1, iy)
  local c, d = hash(ix, iy + 1), hash(ix + 1, iy + 1)
  local bottom, top = a + (b - a) * ux, c + (d - c) * ux
  return bottom + (top - bottom) * uy
end

return M
