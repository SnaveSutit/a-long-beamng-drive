-- Badlands: steep, choppy hills over rough red ground, and a mostly dirt road that winds and climbs more than the desert's.
return {
  name = "badlands",
  weight = 1,
  config = {
    road = {
      bends = { 235, 110, 45, 9 }, -- tighter, more frequent bends than the base
      esses = { 260, 80, 18 }, -- and big swings, from long sweepers down to tight esses
      minWavelength = 140, -- the road follows more of the hills, so it has crests and dips
      features = { hills = { height = 40 }, sides = { height = 100 } }, -- the road climbs over hills and runs along the foot of mountains
    },
    terrain = {
      layers = {
        { wavelength = 900, amplitude = 38 }, { wavelength = 350, amplitude = 24 }, { wavelength = 150, amplitude = 15 },
        { wavelength = 70, amplitude = 9 }, { wavelength = 40, amplitude = 4 }, { wavelength = 28, amplitude = 3 },
        { wavelength = 17, amplitude = 1.6 },
      },
      material = "aLongDrive_dirt_red",
    },
    surfaces = {
      {
        name = "dirt", material = "aLongDrive_roaddirt_red", textureLength = 6, weight = 3,
        road = { width = 5.5, moundHeight = 0.05, shoulder = 2, embankment = 6, roll = 6 },
      },
      {
        name = "paved", material = "aLongDrive_asphalt", textureLength = 16, weight = 1,
        road = { width = 7, moundHeight = 0.12, shoulder = 3, embankment = 6, roll = 1.5 },
      },
    },
    pickups = { normal = { fuelChance = 0.08, scrapMin = 0, scrapMax = 2 } },
  },
}
