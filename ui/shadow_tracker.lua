local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[
  typedef uint64_t UniverseID;
	typedef struct {
		int x;
		int y;
	} Coord2D;

  UniverseID GetPlayerID(void);

	Coord2D GetCenteredMousePos(void);

  double GetCurrentGameTime(void);
]]

local debugLevel = "none" -- "none", "debug", "trace"

local texts = {
  shadowTracker = ReadText(1972092415, 1),
}


local shadowTracker = {
  playerId = nil,
  menuMap = nil,
  menuMapConfig = {},
  variableId = "shadowTracker",
  tabIcon = "mapst_ol_shadow_tracker",
  trackerMode = "shadowTracker",
  posX = nil,
  posY = nil,
  optimizeRename = true
}

local config = {}
local function debug(message)
  if debugLevel ~= "none" then
    local text = "ShadowTracker: " .. message
    if type(DebugError) == "function" then
      DebugError(text)
    end
  end
end

local function trace(message)
  ---@diagnostic disable-next-line: unnecessary-if
  if debugLevel == "trace" then
    debug(message)
  end
end

local function bind(obj, methodName)
  return function(...)
    return obj[methodName](obj, ...)
  end
end

function shadowTracker.Init(menuMap)
  trace("shadowTracker.Init called at " .. tostring(C.GetCurrentGameTime()))
  shadowTracker.menuMap = menuMap
  shadowTracker.menuMapConfig = menuMap.uix_getConfig()
  menuMap.registerCallback("createPropertyOwned_on_add_other_objects_infoTableData", shadowTracker.prepareTabData)
  menuMap.registerCallback("createPropertyOwned_on_createPropertySection_unassignedships", shadowTracker.displayTabData)
  menuMap.registerCallback("onRenderTargetSelect_on_propertyowned_newmode", shadowTracker.selectTabForPlayerPoiItems)
  RegisterEvent("ShadowTracker.ConfigChanged", shadowTracker.onConfigChanged)
  AddUITriggeredEvent("ShadowTracker", "Reloaded")
  shadowTracker.setupTab()
end

function shadowTracker.getConfig()
  local variableId = string.format("$%s", shadowTracker.variableId)
  local config = GetNPCBlackboard(shadowTracker.playerId, variableId)
  if config == nil then
    debug("Config is nil for variableId: " .. tostring(variableId))
    return nil
  end
  return config
end

function shadowTracker.onConfigChanged(_, _)
  local config = shadowTracker.getConfig()
  if config == nil then
    return
  end
  debugLevel = config.debugLevel or "none"
  debug("Configuration changed: debugLevel=" .. tostring(debugLevel))
end

function shadowTracker.resetData()
end

function shadowTracker.setupTab()
  local menu = shadowTracker.menuMap
  if menu == nil then
    debug("Menu map is not initialized")
    return
  end
  local config = shadowTracker.menuMapConfig
  local propertyCategories = config and config.propertyCategories or nil
  if propertyCategories == nil then
    debug("Property categories are not defined in menu map config")
    return
  end
  for i = #propertyCategories, 1, -1 do
    local category = propertyCategories[i]
    trace("Checking category with category: " .. tostring(category.category))
    if string.sub(category.category, 1, 10) ~= "custom_tab" then
      if category.category == shadowTracker.trackerMode then
        trace("Found shadowTracker category in menu map config")
      else
        local poiTab = {
          category = shadowTracker.trackerMode,
          name = texts.shadowTracker,
          icon = shadowTracker.tabIcon,
        }
        if i == #propertyCategories then
          propertyCategories[#propertyCategories + 1] = poiTab
        else
          table.insert(propertyCategories, i + 1, poiTab)
        end
      end
      return
    end
  end
end

function shadowTracker.prepareTabData(infoTableData)
  local menu = shadowTracker.menuMap
  if menu == nil then
    debug("Menu map is not initialized")
    return
  end
  if infoTableData == nil then
    debug("Info table data is nil")
    return
  end
  if infoTableData.shadowTracker ~= nil then
    trace("Player POI data already prepared, skipping")
    return
  end
  infoTableData.shadowTracker = {}
  local shadowTrackerList = infoTableData.shadowTracker
  local config = shadowTracker.getConfig()
  if config == nil then
    debug("Config is nil, cannot prepare player POI data")
    return
  end
  if config.installed == nil or #config.installed == 0 then
    trace("No installed trackers in config, skipping player POI data preparation")
    return
  end
  local objects = {}
  for i = 1, #config.installed do
    local object = config.installed[i]
    local name, hull, purpose, uiRelation, sector, classId, realClassId, idCode, fleetName = GetComponentData(object, "name", "hullpercent", "primarypurpose", "uirelation", "sector", "classid", "realclassid", "idcode", "fleetname")
    objects[#objects + 1] = { id = object, name = name, fleetname = fleetName, objectid = idCode, classid = classId, realclassid = realClassId, hull = hull, purpose = purpose, relation = uiRelation, sector = sector }
  end
  table.sort(objects, menu.componentSorter(menu.propertySorterType))
  for i = 1, #objects do
    local object = objects[i]
    table.insert(shadowTrackerList, object.id)
  end
  trace("Prepared Shadow Tracker data with " .. tostring(#shadowTrackerList) .. " entries")
end

function shadowTracker.displayTabData(numDisplayed, instance, ftable, infoTableData)
  local menu = shadowTracker.menuMap
  if menu == nil then
    debug("Menu map is not initialized")
    return { numdisplayed = numDisplayed }
  end
  infoTableData.shadowTracker = infoTableData.shadowTracker or {}
  if menu.propertyMode == shadowTracker.trackerMode then
    numDisplayed = menu.createPropertySection(instance, "owneddeployables", ftable, texts.shadowTracker, infoTableData.shadowTracker, "-- " .. ReadText(1001, 34) .. " --", nil, numDisplayed, nil, menu.propertySorterType)
  end
  return { numdisplayed = numDisplayed }
end

function shadowTracker.selectTabForPlayerPoiItems(pickedComponent64, newMode)
  trace("pickedComponent64: " .. tostring(pickedComponent64))
  local config = shadowTracker.getConfig()
  if config == nil then
    debug("Config is nil, cannot select tab for player POI items")
    return { newmode = newMode }
  end
  for i = 1, #config.installed do
    local trackerId = ConvertStringTo64Bit(tostring(config.installed[i]))
    if trackerId == pickedComponent64 then
      newMode = shadowTracker.trackerMode
      break
    end
  end
  return { newmode = newMode }
end

local function Init()
  shadowTracker.playerId = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
  shadowTracker.onConfigChanged()
  debug("Initializing ShadowTracker UI extension with PlayerID: " .. tostring(shadowTracker.playerId))
  local menuMap = Helper.getMenu("MapMenu")
  if menuMap == nil or type(menuMap.registerCallback) ~= "function" then
    debug("Failed to get MapMenu or registerCallback is not a function")
    return
  end
  trace(string.format("menuMap is %s", tostring(menuMap)))
  shadowTracker.Init(menuMap)
end


Register_OnLoad_Init(Init)
