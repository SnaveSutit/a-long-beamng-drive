-- Endless roads that are a pure function of position, so any chunk can find them on its own.
--
-- The roads are the contour lines phi(u, v) = k * spacing of a warped coordinate: u runs across the roads and
-- v along them, in a frame turned by an angle from the seed, and phi = u + wander(u, v). Roads of different k never
-- meet or cross, each is smooth, and each has exactly one point at any v, found by Newton's method.
-- Each biome sets how big the bends are, so roads wind more in some biomes than in others.

local M = {}

local GRADIENT_STEP = 1 -- metres, for the finite-difference slope of phi
local NEWTON_STEPS = 12
local NEWTON_TOLERANCE = 0.005 -- metres

local cosA, sinA = 1, 0

---@param seed number
function M.setSeed(seed)
  aLongDrive_noise.setSeed(seed)
  local angle = aLongDrive_noise.hash(1, 1, 5) * 2 * math.pi
  cosA, sinA = math.cos(angle), math.sin(angle)
end

---@return number u, number v the position in the roads' frame
local function toFrame(x, y)
  return x * cosA + y * sinA, -x * sinA + y * cosA
end

---@return number x, number y
local function fromFrame(u, v)
  return u * cosA - v * sinA, u * sinA + v * cosA
end

local function smoothstep(a, b, x)
  local t = math.max(0, math.min(1, (x - a) / (b - a)))
  return t * t * (3 - 2 * t)
end

---@return number phi, which grows by about a metre per metre across the roads
local function phi(u, v)
  local value = aLongDrive_noise.value
  local road = aLongDrive_config.road
  local x, y = fromFrame(u, v)
  local amplitudes = aLongDrive_world.bendsAt(x, y) -- each biome sets how much the roads bend and swing
  local sum = 0
  local bends = #road.bendWavelengths
  for k, wavelength in ipairs(road.bendWavelengths) do
    if amplitudes[k] > 0 then
      local shift = k * 13.7
      sum = sum + (value(u / wavelength + shift, v / wavelength + shift * 0.61) - 0.5) * 2 * amplitudes[k]
    end
  end
  for k, wavelength in ipairs(road.essWavelengths) do
    local amplitude = amplitudes[bends + k]
    if amplitude > 0 then
      local gate = road.technicalFloor + (1 - road.technicalFloor)
        * smoothstep(road.technicalStart, road.technicalFull, value(x / road.technicalWavelength + 71.3 + k * 9.1, y / road.technicalWavelength + 19.9 - k * 4.3))
      -- the swing's pace drifts along the road, so no two swings are alike, and a second harmonic reshapes each bend
      local theta = 2 * math.pi * (v / wavelength + road.essDrift * value(u / 6000 + k * 3.7, v / 700 + k * 1.3))
      local harmonic = math.sin(2 * theta + 2 * math.pi * value(u / 6000 + k * 5.1 + 9, v / 900 + k * 2.2))
      sum = sum + amplitude * gate * (math.sin(theta) + road.essHarmonic * harmonic) / (1 + road.essHarmonic)
    end
  end
  return u + sum
end

---@return number phi, number dPhiDu, number dPhiDv
local function phiWithSlope(u, v)
  local f = phi(u, v)
  return f, (phi(u + GRADIENT_STEP, v) - f) / GRADIENT_STEP, (phi(u, v + GRADIENT_STEP) - f) / GRADIENT_STEP
end

---The nearest road to a point.
---@param x number virtual position
---@param y number
---@return number distance to the road's centre line, number x, number y the nearest point on it, integer k which road, number side how far to the left of the road's direction (negative: right)
function M.frameAt(x, y)
  local u, v = toFrame(x, y)
  local f, fu, fv = phiWithSlope(u, v)
  local spacing = aLongDrive_config.road.spacing
  local k = math.floor(f / spacing + 0.5)
  local diff = f - k * spacing
  local slopeSq = fu * fu + fv * fv
  local px, py = fromFrame(u - diff * fu / slopeSq, v - diff * fv / slopeSq)
  local distance = math.sqrt(slopeSq)
  return math.abs(diff) / distance, px, py, k, -diff / distance
end

---How far along the roads, in metres, a point is. Together with k it says where on a road.
---@param x number virtual position
---@param y number
---@return number
function M.alongAt(x, y)
  local _, v = toFrame(x, y)
  return v
end

---Where road k is at a position along the roads' frame, and the way it points (towards growing v).
---@param k integer
---@param v number
---@return number x, number y, number dirX, number dirY unit direction
function M.centreAt(k, v)
  local target = k * aLongDrive_config.road.spacing
  local u = target
  local fu, fv
  for _ = 1, NEWTON_STEPS do
    local f
    f, fu, fv = phiWithSlope(u, v)
    local step = (f - target) / fu
    u = u - step
    if math.abs(step) < NEWTON_TOLERANCE then break end
  end
  local x, y = fromFrame(u, v)
  local length = math.sqrt(fu * fu + fv * fv)
  local dirX, dirY = fromFrame(-fv / length, fu / length)
  return x, y, dirX, dirY
end

---The nearest road to a point, as a position on it and the way it points.
---@return number x, number y, number dirX, number dirY
function M.poseNear(x, y)
  local _, px, py, k = M.frameAt(x, y)
  local _, v = toFrame(px, py)
  return M.centreAt(k, v)
end

---Segments of road, each `road.segment` metres along v, whose middle is within `radius` of a point.
---@param x number virtual position
---@param y number
---@param radius number
---@return {k: integer, j: integer}[]
function M.segmentsNear(x, y, radius)
  local road = aLongDrive_config.road
  local u, v = toFrame(x, y)
  local reach = radius + 150 -- roads can lean sideways by that much across a segment
  local list = {}
  for j = math.floor((v - reach) / road.segment), math.floor((v + reach) / road.segment) do
    local middle = (j + 0.5) * road.segment
    local first = math.ceil(phi(u - reach, middle) / road.spacing)
    local last = math.floor(phi(u + reach, middle) / road.spacing)
    for k = first, last do
      local cx, cy = M.centreAt(k, middle)
      if (cx - x) ^ 2 + (cy - y) ^ 2 <= radius * radius then list[#list + 1] = { k = k, j = j } end
    end
  end
  return list
end

return M
