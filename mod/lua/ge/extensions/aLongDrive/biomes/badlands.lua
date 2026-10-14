-- Badlands: steep, choppy hills over rough red ground, mostly dirt road, and fewer fuel cans.
return {
  name = "badlands",
  weight = 1,
  minLength = 5000,
  maxLength = 15000,
  config = {
    hills = { minHeight = 0.5, maxHeight = 140, wavelength = 420, rollers = 0.5, maxGrade = 0.14 },
    terrain = { relief = 35, reliefScale = 90, blendDistance = 40, material = "aLongDrive_dirt_red" },
    surfaces = {
      {
        name = "dirt", material = "aLongDrive_roaddirt", textureLength = 6, weight = 3, minLength = 2000, maxLength = 9000,
        road = { width = 5.5, moundHeight = 0.2, shoulder = 0.5, embankment = 2.5 },
      },
      {
        name = "paved", material = "aLongDrive_asphalt", textureLength = 16, weight = 1, minLength = 800, maxLength = 3000,
        road = { width = 7, moundHeight = 0.3, shoulder = 1, embankment = 2.5 },
      },
    },
    pickups = { normal = { fuelChance = 0.08, scrapMin = 0, scrapMax = 2 } },
  },
}
