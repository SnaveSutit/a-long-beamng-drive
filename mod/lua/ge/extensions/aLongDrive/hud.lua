-- Minimal on-screen readout: fuel, scrap and distance.

local M = {}

local im = ui_imgui

local FLAGS = bit.bor(
  im.WindowFlags_NoTitleBar, im.WindowFlags_NoResize, im.WindowFlags_NoMove, im.WindowFlags_NoScrollbar,
  im.WindowFlags_NoCollapse, im.WindowFlags_AlwaysAutoResize, im.WindowFlags_NoInputs,
  im.WindowFlags_NoSavedSettings, im.WindowFlags_NoFocusOnAppearing
)
local LOW_FUEL = 0.15

---@param data {fuel: number?, fuelCapacity: number?, scrap: number, distance: number, prompt: string?} distance in metres
function M.draw(data)
  im.SetNextWindowPos(im.ImVec2(24, 24), im.Cond_Always)
  im.SetNextWindowBgAlpha(0.45)
  im.Begin("A Long Drive HUD", nil, FLAGS)
  im.SetWindowFontScale(1.3)

  if data.fuel and data.fuelCapacity then
    local low = data.fuel < data.fuelCapacity * LOW_FUEL
    im.TextColored(low and im.ImVec4(1, 0.35, 0.3, 1) or im.ImVec4(1, 1, 1, 1), string.format("Fuel      %.1f / %.0f L", data.fuel, data.fuelCapacity))
  else
    im.Text("Fuel      --")
  end
  im.Text(string.format("Scrap     %d", data.scrap))
  im.Text(string.format("Distance  %.2f km", data.distance / 1000))
  if data.prompt then
    im.Separator()
    im.TextColored(im.ImVec4(1, 0.85, 0.3, 1), data.prompt)
  end

  im.End()
end

return M
