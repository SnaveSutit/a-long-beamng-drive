-- Checks that the road and its shoulder never dip below the terrain mesh beside them, which shows as ground poking
-- through the road. Paste it into the game's Lua console (~) with the mod loaded. It rebuilds the terrain's triangles
-- from the height function (12 m cells, as in config.chunks.cell) and compares them with the road's cross-section along
-- 15 km of road for five seeds. The lowest value should stay above zero; if it goes negative, raise BED_CLEARANCE in
-- world.lua. The slope past the shoulder is left out: it is meant to run into the ground.
local R,W,B=aLongDrive_roads,aLongDrive_world,aLongDrive_biomes
local function interp(px,py)
  local x0,y0=math.floor(px/12)*12,math.floor(py/12)*12
  local fx,fy=(px-x0)/12,(py-y0)/12 -- 0..1 from the SW corner
  local sw,se,nw,ne=W.heightAt(x0,y0),W.heightAt(x0+12,y0),W.heightAt(x0,y0+12),W.heightAt(x0+12,y0+12)
  -- diagonal SE-NW: points with fx+fy<=1 are in triangle SW,SE,NW
  if fx+fy<=1 then return sw+(se-sw)*fx+(nw-sw)*fy end
  return ne+(nw-ne)*(1-fx)+(se-ne)*(1-fy)
end
local out={}
for _,seed in ipairs({1,2,3,7,12}) do
  W.setSeed(seed) R.setSeed(seed) B.reset()
  local x,y=R.poseNear(0,0) local _,_,_,k=R.frameAt(x,y)
  local worst,worstDirt,worstAt=1e9,1e9,""
  local count=0
  for v=0,15000,6 do
    local cx,cy,tx,ty=R.centreAt(k,v) local profile=W.profileAt(cx,cy)
    local half,sh,se,drop=W.layout(profile)
    local z=W.roadHeightAt(cx,cy,k,v) local t=W.tiltAt(k,v,profile) local ground=z-drop
    for o=-sh,sh,1 do
      local bed=z+t*math.max(-sh,math.min(sh,o))
      local zr=ground+(bed-ground)*(1-(function(a,b,x) local u=math.max(0,math.min(1,(x-a)/(b-a))) return u*u*(3-2*u) end)(sh,se,math.abs(o)))
      local d=zr-interp(cx-ty*o,cy+tx*o)
      if d<worst then worst=d worstAt=string.format("v=%d o=%.0f",v,o) end
      count=count+1
    end
  end
  out[#out+1]=string.format("seed %d: lowest road and shoulder above terrain mesh %.3f m (%s), %d samples",seed,worst,worstAt,count)
end
return table.concat(out,"\n")
