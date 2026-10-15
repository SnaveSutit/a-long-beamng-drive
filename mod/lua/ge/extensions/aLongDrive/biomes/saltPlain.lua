-- Salt plain: pale, gently rolling ground with a wide paved road that winds across it.
return {
  name = "saltPlain",
  weight = 1,
  config = {
    road = {
      bends = { 235, 105, 40, 6 },
      esses = { 170, 50, 12 }, -- big swings too, but gentler
      features = { hills = { height = 20 }, sides = { height = 50 } },
    },
    terrain = {
      layers = {
        { wavelength = 1800, amplitude = 20 }, { wavelength = 650, amplitude = 12 }, { wavelength = 250, amplitude = 6 },
        { wavelength = 100, amplitude = 4 }, { wavelength = 50, amplitude = 2 }, { wavelength = 30, amplitude = 0.8 },
        { wavelength = 18, amplitude = 0.4 },
      },
      material = "aLongDrive_dirt_salt",
    },
    surfaces = {
      {
        name = "paved", material = "aLongDrive_asphalt", textureLength = 16, weight = 1,
        road = { width = 9, moundHeight = 0.12, shoulder = 3, embankment = 7, roll = 0.8 },
      },
    },
    pickups = { normal = { fuelChance = 0.2, scrapMin = 0, scrapMax = 1 } },
  },
}
