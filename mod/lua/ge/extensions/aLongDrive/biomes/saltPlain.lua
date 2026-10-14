-- Salt plain: almost flat and pale, with a wide paved road all the way, and fuel a little easier to find.
return {
  name = "saltPlain",
  weight = 1,
  minLength = 5000,
  maxLength = 15000,
  config = {
    hills = {
      minHeight = 0.5, maxHeight = 10, maxGrade = 0.03, maxBend = 0.3, gain = 2, variation = 0.3,
      layers = { { wavelength = 3000, weight = 1 }, { wavelength = 1200, weight = 0.5 }, { wavelength = 450, weight = 0.15 } },
    },
    road = { turns = {
      { name = "straight", weight = 5, minLength = 1000, maxLength = 4000, minTurn = 0, maxTurn = 0.003 },
      { name = "gentle", weight = 2, minLength = 600, maxLength = 1800, minTurn = 0.006, maxTurn = 0.02 },
      { name = "sweeping", weight = 1, minLength = 400, maxLength = 1000, minTurn = 0.02, maxTurn = 0.04 },
    } },
    terrain = { relief = 1.5, reliefScale = 300, blendDistance = 120, material = "aLongDrive_dirt_salt" },
    surfaces = {
      {
        name = "paved", material = "aLongDrive_asphalt", textureLength = 16, weight = 1, minLength = 3000, maxLength = 12000,
        road = { width = 9, moundHeight = 0.3, shoulder = 3, embankment = 5 },
      },
    },
    pickups = { normal = { fuelChance = 0.2, scrapMin = 0, scrapMax = 1 } },
  },
}
