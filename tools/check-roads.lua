-- Checks how the roads wind and climb in each biome, over ten seeds and 30 km of road each.
-- Run it by pasting it into the game's Lua console (~) with the mod loaded. Watch the gap to the next road (it should stay well above 1000 m, or roads are folding back
-- on themselves), the minimum radius (below about 100 m is a hairpin) and how far the road stands above the open
-- ground beside it (embankments much over 15 m look like walls).
local R, W, B = aLongDrive_roads, aLongDrive_world, aLongDrive_biomes
local names = {}
for i = 1, B.count() do names[i] = B.def(i).name end
local stats = {}
for i = 1, B.count() do stats[i] = { n = 0, minRadius = 1e9, maxGrade = 0, sumGrade = 0, sumTurn = 0, maxFill = 0 } end
local minGap, worstSeed = 1e9, 0
for seed = 1, 10 do
  W.setSeed(seed) R.setSeed(seed)
  local x, y = R.poseNear(0, 0)
  local _, _, _, k = R.frameAt(x, y)
  local pdx, pdy, pz
  for v = 0, 30000, 12 do
    local cx, cy, tx, ty = R.centreAt(k, v)
    local z = W.roadHeightAt(cx, cy)
    local s = stats[W.biomeAt(cx, cy)]
    if pdx then
      local a = math.acos(math.max(-1, math.min(1, tx * pdx + ty * pdy)))
      s.n = s.n + 1
      s.sumTurn = s.sumTurn + a
      if a > 0 and 12 / a < s.minRadius then s.minRadius = 12 / a end
      local g = math.abs(z - pz) / 12
      s.sumGrade = s.sumGrade + g
      if g > s.maxGrade then s.maxGrade = g end
    end
    -- how far the road stands above (or below) the open ground 90 m to its side, past where it is graded
    local fill = math.abs(z - W.heightAt(cx - ty * 90, cy + tx * 90))
    if fill > s.maxFill then s.maxFill = fill end
    pdx, pdy, pz = tx, ty, z
    if v % 240 == 0 then
      local ax, ay = R.centreAt(k + 1, v)
      local d = math.sqrt((ax - cx) ^ 2 + (ay - cy) ^ 2)
      if d < minGap then minGap, worstSeed = d, seed end
    end
  end
end
local out = { string.format("min gap to next road %.0f m (seed %d)", minGap, worstSeed) }
for i, s in ipairs(stats) do
  if s.n > 0 then
    out[#out + 1] = string.format("%-9s min radius %4.0f m | turning %.1f deg/100m | grade avg %.3f max %.3f | road above/below open ground up to %.0f m", names[i], s.minRadius, math.deg(s.sumTurn) / (s.n * 12) * 100, s.sumGrade / s.n, s.maxGrade, s.maxFill)
  end
end
return table.concat(out, "\n")
