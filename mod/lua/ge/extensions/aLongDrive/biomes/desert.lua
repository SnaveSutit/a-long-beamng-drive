-- Desert flats: rolling hills, brown ground, paved and dirt road. This is the base config itself, so it
-- overrides nothing; see badlands.lua and saltPlain.lua for what a biome can change.
return {
  name = "desert",
  weight = 1, -- how often it is picked when the road moves to a new biome
  minLength = 8000, -- metres a stretch of it lasts, picked between these
  maxLength = 25000,
  config = {},
}
