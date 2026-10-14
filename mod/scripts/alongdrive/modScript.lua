local modules = {
  "aLongDrive", "aLongDrive_config", "aLongDrive_biomes", "aLongDrive_road", "aLongDrive_meshBuilder", "aLongDrive_pickups", "aLongDrive_hud",
  "aLongDrive_biomes_desert", "aLongDrive_biomes_badlands", "aLongDrive_biomes_saltPlain",
}
for _, name in ipairs(modules) do
  setExtensionUnloadMode(name, "manual")
end
