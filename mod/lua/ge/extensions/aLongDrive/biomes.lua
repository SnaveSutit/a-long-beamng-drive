-- Biomes: each one overrides parts of the base config, merged over it. See config.lua for what a biome may change.

local M = {}

local cache = {} -- biome index -> merged config

---@param value any
---@return any deep copy
local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for k, v in pairs(value) do result[k] = copy(v) end
  return result
end

---Tables merge key by key; lists and plain values in `over` replace what is in `base`.
---@param base table
---@param over table
---@return table a new table
local function merge(base, over)
  local result = copy(base)
  for k, v in pairs(over) do
    if type(v) == "table" and type(result[k]) == "table" and v[1] == nil then
      result[k] = merge(result[k], v)
    else
      result[k] = copy(v)
    end
  end
  return result
end

---@param index integer
---@return string
local function moduleName(index)
  return "aLongDrive_biomes_" .. aLongDrive_config.biomes[index]
end

---@return integer
function M.count()
  return #aLongDrive_config.biomes
end

---@return string[] extension names of the biome files, so a reload can unload them
function M.moduleNames()
  local names = {}
  for index in ipairs(aLongDrive_config.biomes) do names[#names + 1] = moduleName(index) end
  return names
end

---A biome's own definition: name, weight, minLength, maxLength and its config overrides.
---@param index integer
---@return {name: string, weight: number, minLength: number, maxLength: number, config: table?}
function M.def(index)
  local name = moduleName(index)
  if not _G[name] then extensions.load(name) end
  return _G[name]
end

---The whole config as this biome sees it. Cached, so a change made to the result lasts until reset().
---@param index integer
---@return table
function M.get(index)
  if not cache[index] then cache[index] = merge(aLongDrive_config, M.def(index).config or {}) end
  return cache[index]
end

---@param name string
---@return integer? index
function M.indexOf(name)
  for index, biomeName in ipairs(aLongDrive_config.biomes) do
    if biomeName == name then return index end
  end
end

---Forget the merged configs, so the next get() starts from the files again.
function M.reset()
  cache = {}
end

return M
