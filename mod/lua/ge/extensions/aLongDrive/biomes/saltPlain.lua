-- Salt plain: almost flat and pale, with a wide paved road all the way, and fuel a little easier to find.
return {
  name = "saltPlain",
  weight = 1,
  minLength = 5000,
  maxLength = 15000,
  config = {
    hills = { minHeight = 0.5, maxHeight = 10, wavelength = 1500, rollers = 0.1, maxGrade = 0.03 },
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
