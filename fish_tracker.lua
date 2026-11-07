local api = require("api")

local function safeGetUnitScreenPosition(unit)
    local ok, x, y = false, nil, nil
    if api.Unit ~= nil and api.Unit.GetUnitScreenNameTagOffset ~= nil then
        ok, x, y = pcall(api.Unit.GetUnitScreenNameTagOffset, api.Unit, unit)
        if not ok then x, y = nil, nil end
    end
    if x == nil or y == nil then
        ok, x, y = pcall(api.Unit.GetUnitScreenPosition, api.Unit, unit)
        if not ok then x, y = nil, nil end
    end
    return x or 0, y or 0, 0
end

local function safeGetOverHeadMarkerUnitId(markerIndex)
    local ok, unitId = false, nil
    if api.Unit ~= nil and api.Unit.GetOverHeadMarkerUnitId ~= nil then
        ok, unitId = pcall(api.Unit.GetOverHeadMarkerUnitId, api.Unit, markerIndex)
    end
    if ok then return unitId else return nil end
end

local cachedIconPaths = {}
local function GetCachedIconPath(buffId)
    if not buffId then return "" end
    if not cachedIconPaths[buffId] then
        local t = api.Ability:GetBuffTooltip(buffId, 1)
        cachedIconPaths[buffId] = t and t.path or ""
    end
    return cachedIconPaths[buffId]
end

local cachedBuffNames = {}
local function GetCachedBuffName(buffId)
    if not buffId then return "" end
    if not cachedBuffNames[buffId] then
        local t = api.Ability:GetBuffTooltip(buffId, 1)
        cachedBuffNames[buffId] = t and t.name or ""
    end
    return cachedBuffNames[buffId]
end

local fish_tracker = {}

fish_tracker.enableDeadFishTimers = false
fish_tracker.enableSkillIndicators = false
fish_tracker.enableCustomFishMarkers = false
fish_tracker.enableDebugMode = true
fish_tracker.enableOnlyMyFishes = true
fish_tracker.deadFishContainerPos = {0, 200} -- default position relative to center

local sortedFishes_cache = {}
local markerColors = {
    [1] = {1.0, 0.5, 0.0, 1},
    [2] = {0.5, 1.0, 0.0, 1},
    [3] = {0.0, 1.0, 1.0, 1},
    [4] = {0.2, 0.5, 1.0, 1},
    [5] = {1.0, 0.0, 1.0, 1},
    [6] = {1.0, 1.0, 0.0, 1},
    [7] = {0.0, 0.7, 1.0, 1},
    [8] = {0.6, 0.2, 1.0, 1},
    [9] = {1.0, 0.0, 0.0, 1},
}

local ownersMarkCache = { [4867] = true, [5748] = true, [14470] = true }
local nonOwnersMarkCache = {}
local actionBuffs = {[5264]=true, [5265]=true, [5266]=true, [5267]=true, [5508]=true}
local fishBuffIdsToAlert = {
	[5715] = "Strength Contest",
	[5264] = "Stand Firm Right",
	[5265] = "Stand Firm Left",
	[5266] = "Reel In",
	[5267] = "Give Slack",
	[5508] = "Big Reel In"
}

local actionBuffs = {
	[5264] = true,
	[5265] = true,
	[5266] = true,
	[5267] = true,
	[5508] = true
}

local fishNamesToAlert = {
	-- English
	["Marlin"] = true, ["Blue Marlin"] = true, ["Tuna"] = true, ["Blue Tuna"] = true, ["Bluefin"] = true, ["Bluefin Tuna"] = true, ["Sunfish"] = true,
	["Sailfish"] = true, ["Sturgeon"] = true, ["Pink Pufferfish"] = true,
	["Carp"] = true, ["Arowana"] = true, ["Pufferfish"] = true, ["Eel"] = true, ["Electric Eel"] = true,
	["Pink Marlin"] = true, ["Small Pink Marlin"] = true, ["Medium Pink Marlin"] = true, ["Gargantuan Pink Marlin"] = true, ["Treasure Mimic"] = true,
	-- Korean
	["철갑상어"] = true,
	["청새치"] = true,
	["참다랑어"] = true,
	["돛새치"] = true,
	["개복치"] = true,
	-- Chinese
	["鲟鱼"] = true,
	["枪鱼"] = true,
	["蓝鳍金枪鱼"] = true,
	["旗鱼"] = true,
	["翻车鱼"] = true,
}

local fishTrackerCanvas, targetFishIcon, fishBuffTimeLeftLabel
local strengthContestIcon, strengthContestTimeLabel

local previousXYZ = "0,0,0"
local previousFish

local MARKED_FISH_TIMER = 150000
local deadFishes = {}
local markedFishUI = {}
local markedFishPoolBuilt = false

local customMarkedFishes = {}
local customMarkerUI = {}
local targetBarMarkerUI = nil
local customMarkerPoolBuilt = false
local customMarkerEventWnd = nil

local function isFiniteCoord(n)
    return type(n) == "number" and n == n and n > -1e9 and n < 1e9
end

local function getUIScaleSafe()
    if api and api.Interface and api.Interface.GetUIScale then
        local ok, s = pcall(api.Interface.GetUIScale, api.Interface)
        if ok and type(s) == "number" and s > 0 then
            return s
        end
    end
    return 1
end

local function updateEntryWorldCalibration(entry, tx, ty, tz)
    if not entry or not (isFiniteCoord(entry.wx) and isFiniteCoord(entry.wy) and isFiniteCoord(entry.wz)) then
        return
    end
    if not (isFiniteCoord(tx) and isFiniteCoord(ty)) or (tz and tz < 0) then
        return
    end
    if type(X2Util) ~= "table" or type(X2Util.ConvertWorldToScreen) ~= "function" then
        return
    end

    local scale = getUIScaleSafe()
    local bestDist = 1e9
    local bestMode = nil
    local bestScaleDiv = false
    local bestPx, bestPy = nil, nil

    local okD, dx, dy, dz = pcall(X2Util.ConvertWorldToScreen, entry.wx, entry.wy, entry.wz)
    if okD and isFiniteCoord(dx) and isFiniteCoord(dy) and (dz == nil or dz >= 0) then
        local d1 = math.abs(dx - tx) + math.abs(dy - ty)
        if d1 < bestDist then
            bestDist, bestMode, bestScaleDiv, bestPx, bestPy = d1, "dot", false, dx, dy
        end
        if scale > 0 and scale ~= 1 then
            local sx, sy = dx / scale, dy / scale
            local d2 = math.abs(sx - tx) + math.abs(sy - ty)
            if d2 < bestDist then
                bestDist, bestMode, bestScaleDiv, bestPx, bestPy = d2, "dot", true, sx, sy
            end
        end
    end

    local okC, cx, cy, cz = pcall(X2Util.ConvertWorldToScreen, X2Util, entry.wx, entry.wy, entry.wz)
    if okC and isFiniteCoord(cx) and isFiniteCoord(cy) and (cz == nil or cz >= 0) then
        local d1 = math.abs(cx - tx) + math.abs(cy - ty)
        if d1 < bestDist then
            bestDist, bestMode, bestScaleDiv, bestPx, bestPy = d1, "colon", false, cx, cy
        end
        if scale > 0 and scale ~= 1 then
            local sx, sy = cx / scale, cy / scale
            local d2 = math.abs(sx - tx) + math.abs(sy - ty)
            if d2 < bestDist then
                bestDist, bestMode, bestScaleDiv, bestPx, bestPy = d2, "colon", true, sx, sy
            end
        end
    end

    if bestMode and bestDist < 400 then
        entry.projMode = bestMode
        entry.useScaleDiv = bestScaleDiv
        entry.screenOffsetX = tx - bestPx
        entry.screenOffsetY = ty - bestPy
        entry.worldProjValid = true
    end
end

local function projectEntryWorldToScreen(entry)
    if not entry or not entry.worldProjValid then
        return nil, nil, nil
    end
    if not (isFiniteCoord(entry.wx) and isFiniteCoord(entry.wy) and isFiniteCoord(entry.wz)) then
        return nil, nil, nil
    end
    if type(X2Util) ~= "table" or type(X2Util.ConvertWorldToScreen) ~= "function" then
        return nil, nil, nil
    end

    local ok, px, py, pz
    if entry.projMode == "colon" then
        ok, px, py, pz = pcall(X2Util.ConvertWorldToScreen, X2Util, entry.wx, entry.wy, entry.wz)
    else
        ok, px, py, pz = pcall(X2Util.ConvertWorldToScreen, entry.wx, entry.wy, entry.wz)
    end
    if not (ok and isFiniteCoord(px) and isFiniteCoord(py)) then
        return nil, nil, nil
    end
    if pz ~= nil and pz < 0 then
        return nil, nil, pz
    end
    if entry.useScaleDiv then
        local scale = getUIScaleSafe()
        if scale > 0 then
            px = px / scale
            py = py / scale
        end
    end
    return px + (entry.screenOffsetX or 0), py + (entry.screenOffsetY or 0), pz or 0
end

local function HideAllCustomFishMarkers()
    for i = 1, 9 do
        if customMarkerUI[i] and customMarkerUI[i].canvas then
            customMarkerUI[i].canvas:Show(false)
        end
    end
    if targetBarMarkerUI and targetBarMarkerUI.canvas then
        targetBarMarkerUI.canvas:Show(false)
    end
end

local function LoadMiscSettings()
    local data = api.File:Read("elu_tracker_misc.txt")
    if type(data) == "table" then
        if data.enableDeadFishTimers ~= nil then fish_tracker.enableDeadFishTimers = data.enableDeadFishTimers end
        if data.enableSkillIndicators ~= nil then fish_tracker.enableSkillIndicators = data.enableSkillIndicators end
        if data.enableCustomFishMarkers ~= nil then fish_tracker.enableCustomFishMarkers = data.enableCustomFishMarkers end
        if data.deadFishContainerPos ~= nil then fish_tracker.deadFishContainerPos = data.deadFishContainerPos end
    else
        
        fish_tracker.enableDeadFishTimers = false
        fish_tracker.enableSkillIndicators = false
        fish_tracker.enableCustomFishMarkers = false
        fish_tracker.deadFishContainerPos = {0, 200}
    end
end

local function SaveMiscSettings()
    local data = api.File:Read("elu_tracker_misc.txt")
    if type(data) ~= "table" then data = {} end
    data.enableDeadFishTimers = fish_tracker.enableDeadFishTimers
    data.enableSkillIndicators = fish_tracker.enableSkillIndicators
    data.enableCustomFishMarkers = fish_tracker.enableCustomFishMarkers
    data.deadFishContainerPos = fish_tracker.deadFishContainerPos
    api.File:Write("elu_tracker_misc.txt", data)
end

function fish_tracker.CreateUI(wndParent)
    LoadMiscSettings()
    
    local container = wndParent:CreateChildWidget("emptywidget", "eluFishTrackerToggles", 0, true)
    container:SetExtent(300, 70)
    
    if wndParent.eluAltToggleContainer then
        container:AddAnchor("TOP", wndParent.eluAltToggleContainer, "BOTTOM", 0, 15)
    else
        container:AddAnchor("TOP", wndParent, "TOP", 0, 50)
    end
    wndParent.eluFishTrackerToggles = container
    
    -- Dead Fish Timers Toggle
    local deadFishToggle = container:CreateChildWidget("checkbutton", "deadFishToggle", 0, true)
    deadFishToggle:SetExtent(18, 17)
    deadFishToggle:AddAnchor("TOPLEFT", container, "TOPLEFT", 45, 10)
    
    local bg1 = deadFishToggle:CreateImageDrawable("ui/button/check_button.dds", "background")
    bg1:SetExtent(18, 17)
    bg1:AddAnchor("CENTER", deadFishToggle, 0, 0)
    bg1:SetCoords(0, 0, 18, 17)
    deadFishToggle:SetNormalBackground(bg1)
    
    local bg2 = deadFishToggle:CreateImageDrawable("ui/button/check_button.dds", "background")
    bg2:SetExtent(18, 17)
    bg2:AddAnchor("CENTER", deadFishToggle, 0, 0)
    bg2:SetCoords(18, 0, 18, 17)
    deadFishToggle:SetCheckedBackground(bg2)
    
    local dfLbl = container:CreateChildWidget("label", "dfLbl", 0, true)
    dfLbl:SetAutoResize(true)
    dfLbl:SetText("Enable Dead Fish Timers")
    dfLbl:AddAnchor("LEFT", deadFishToggle, "RIGHT", 5, 0)
    if FONT_COLOR and FONT_COLOR.DEFAULT then
        ApplyTextColor(dfLbl, FONT_COLOR.DEFAULT)
    end
    
    local dfMoveBtn = container:CreateChildWidget("button", "dfMoveBtn", 0, true)
    dfMoveBtn:SetText("Move")
    api.Interface:ApplyButtonSkin(dfMoveBtn, BUTTON_BASIC.DEFAULT)
    dfMoveBtn:AddAnchor("LEFT", dfLbl, "RIGHT", 10, 0)
    dfMoveBtn:SetExtent(50, 25)
    
    deadFishToggle:SetChecked(fish_tracker.enableDeadFishTimers)
    function deadFishToggle:OnCheckChanged()
        fish_tracker.enableDeadFishTimers = self:GetChecked()
        SaveMiscSettings()
        if not fish_tracker.enableDeadFishTimers then
            if type(HideAllDeadFishTimers) == "function" then HideAllDeadFishTimers() end
        end
    end
    deadFishToggle:SetHandler("OnCheckChanged", deadFishToggle.OnCheckChanged)
    
    -- Fish Skill Indicators Toggle
    local skillIndToggle = container:CreateChildWidget("checkbutton", "skillIndToggle", 0, true)
    skillIndToggle:SetExtent(18, 17)
    skillIndToggle:AddAnchor("TOPLEFT", deadFishToggle, "BOTTOMLEFT", 0, 15)
    
    local bg1s = skillIndToggle:CreateImageDrawable("ui/button/check_button.dds", "background")
    bg1s:SetExtent(18, 17)
    bg1s:AddAnchor("CENTER", skillIndToggle, 0, 0)
    bg1s:SetCoords(0, 0, 18, 17)
    skillIndToggle:SetNormalBackground(bg1s)
    
    local bg2s = skillIndToggle:CreateImageDrawable("ui/button/check_button.dds", "background")
    bg2s:SetExtent(18, 17)
    bg2s:AddAnchor("CENTER", skillIndToggle, 0, 0)
    bg2s:SetCoords(18, 0, 18, 17)
    skillIndToggle:SetCheckedBackground(bg2s)
    
    local siLbl = container:CreateChildWidget("label", "siLbl", 0, true)
    siLbl:SetAutoResize(true)
    siLbl:SetText("Enable Fish Skill Indicators")
    siLbl:AddAnchor("LEFT", skillIndToggle, "RIGHT", 5, 0)
    if FONT_COLOR and FONT_COLOR.DEFAULT then
        ApplyTextColor(siLbl, FONT_COLOR.DEFAULT)
    end
    
    skillIndToggle:SetChecked(fish_tracker.enableSkillIndicators)
    function skillIndToggle:OnCheckChanged()
        fish_tracker.enableSkillIndicators = self:GetChecked()
        SaveMiscSettings()
        if not fish_tracker.enableSkillIndicators and fishTrackerCanvas then
            fishTrackerCanvas:Show(false)
        end
    end
    skillIndToggle:SetHandler("OnCheckChanged", skillIndToggle.OnCheckChanged)
    
    local moveMode = false
    function dfMoveBtn:OnClick()
        moveMode = not moveMode
        if moveMode then
            dfMoveBtn:SetText("Save")
            if fish_tracker.deadFishDragBox then
                fish_tracker.deadFishDragBox:Show(true)
                fish_tracker.deadFishDragBox:EnableDrag(true)
            end
        else
            dfMoveBtn:SetText("Move")
            if fish_tracker.deadFishDragBox then
                fish_tracker.deadFishDragBox:Show(false)
                fish_tracker.deadFishDragBox:EnableDrag(false)
                
                local x, y = fish_tracker.deadFishDragBox:GetOffset()
                fish_tracker.deadFishContainerPos = {x, y, "TOPLEFT"}
                SaveMiscSettings()
            end
        end
    end
    dfMoveBtn:SetHandler("OnClick", dfMoveBtn.OnClick)
end

function fish_tracker.CreateCustomMarkersUI(wndParent)
    LoadMiscSettings()

    local container = wndParent:CreateChildWidget("emptywidget", "eluCustomFishMarkerContainer", 0, true)
    container:SetExtent(300, 30)

    if wndParent.eluAltToggleContainer then
        container:AddAnchor("TOP", wndParent.eluAltToggleContainer, "BOTTOM", 0, 10)
    elseif wndParent.eluFishTrackerToggles then
        container:AddAnchor("TOP", wndParent.eluFishTrackerToggles, "BOTTOM", 0, 75)
    else
        container:AddAnchor("TOP", wndParent, "TOP", 0, 195)
    end
    wndParent.eluCustomFishMarkerContainer = container

    local cmToggle = container:CreateChildWidget("checkbutton", "eluCustomFishMarkerCheck", 0, true)
    cmToggle:SetExtent(18, 17)
    cmToggle:AddAnchor("LEFT", container, 45, 0)

    local bg1 = cmToggle:CreateImageDrawable("ui/button/check_button.dds", "background")
    bg1:SetExtent(18, 17)
    bg1:AddAnchor("CENTER", cmToggle, 0, 0)
    bg1:SetCoords(0, 0, 18, 17)
    cmToggle:SetNormalBackground(bg1)

    local bg2 = cmToggle:CreateImageDrawable("ui/button/check_button.dds", "background")
    bg2:SetExtent(18, 17)
    bg2:AddAnchor("CENTER", cmToggle, 0, 0)
    bg2:SetCoords(18, 0, 18, 17)
    cmToggle:SetCheckedBackground(bg2)

    local cmLbl = container:CreateChildWidget("label", "eluCustomFishMarkerLbl", 0, true)
    cmLbl:SetAutoResize(true)
    cmLbl:SetText("Enable Fish Markers (1-9)")
    cmLbl:AddAnchor("LEFT", cmToggle, "RIGHT", 5, 0)
    if FONT_COLOR and FONT_COLOR.DEFAULT then
        ApplyTextColor(cmLbl, FONT_COLOR.DEFAULT)
    end

    cmToggle:SetChecked(fish_tracker.enableCustomFishMarkers)
    function cmToggle:OnCheckChanged()
        fish_tracker.enableCustomFishMarkers = self:GetChecked()
        SaveMiscSettings()
        if not fish_tracker.enableCustomFishMarkers then
            customMarkedFishes = {}
            fish_tracker.nextCustomFishMarker = 0
            HideAllCustomFishMarkers()
        end
    end
    cmToggle:SetHandler("OnCheckChanged", cmToggle.OnCheckChanged)
end

local function RemoveDeadFishByUnitId(uid)
    if not uid then return end
    for k, v in pairs(deadFishes) do
        if type(v) == "table" and v.unitId == uid then
            deadFishes[k] = nil
        end
    end
end

local function BuildCustomMarkerPool()
    if customMarkerPoolBuilt then return end
    customMarkerPoolBuilt = true

    for i = 1, 9 do
        local canvas = api.Interface:CreateEmptyWindow("eluCustomFishMarker" .. i, "UIParent")
        canvas:SetExtent(60, 60)
        canvas:Show(false)
        pcall(function() canvas:Clickable(false) end)
        pcall(function() canvas:EnableHitTest(false) end)

        local numLabel = canvas:CreateChildWidget("label", "numLabel", 0, true)
        numLabel:SetExtent(60, 60)
        numLabel:AddAnchor("CENTER", canvas, "CENTER", 0, 0)
        numLabel.style:SetFontSize(34)
        numLabel.style:SetAlign(ALIGN.CENTER)
        numLabel.style:SetShadow(true)
        pcall(function() numLabel.style:SetOutline(true) end)
        local color = markerColors[i] or {1, 0.8, 0, 1}
        numLabel.style:SetColor(color[1], color[2], color[3], color[4])
        numLabel:SetText(tostring(i))
        pcall(function() numLabel:Clickable(false) end)
        pcall(function() numLabel:EnableHitTest(false) end)

        customMarkerUI[i] = {
            canvas = canvas,
            numLabel = numLabel,
        }
    end

    local tbCanvas = api.Interface:CreateEmptyWindow("eluTargetBarFishMarker", "UIParent")
    tbCanvas:SetExtent(42, 42)
    tbCanvas:Show(false)
    pcall(function() tbCanvas:Clickable(false) end)
    pcall(function() tbCanvas:EnableHitTest(false) end)

    local tbOutlineOffsets = {
        {-2, -1}, {2, -1}, {-2, 1}, {2, 1},
        {0, -2},  {0, 2},  {-2, 0}, {2, 0},
    }
    local tbOutlineLabels = {}
    for idx, off in ipairs(tbOutlineOffsets) do
        local ol = tbCanvas:CreateChildWidget("label", "olLabel" .. idx, 0, true)
        ol:SetExtent(42, 42)
        ol:AddAnchor("CENTER", tbCanvas, "CENTER", off[1], off[2])
        pcall(function() ol.style:SetFont("ui/font/yoon_firedgothic_b.ttf", 25) end)
        ol.style:SetFontSize(25)
        ol.style:SetAlign(ALIGN.CENTER)
        ol.style:SetShadow(false)
        ol.style:SetColor(0, 0, 0, 0.95)
        ol:SetText("")
        pcall(function() ol:Clickable(false) end)
        pcall(function() ol:EnableHitTest(false) end)
        tbOutlineLabels[idx] = ol
    end

    local tbCoreOffsets = { {-1, 0}, {0, 0}, {1, 0} }
    local tbCoreLabels = {}
    for idx, off in ipairs(tbCoreOffsets) do
        local cl = tbCanvas:CreateChildWidget("label", "numLabel" .. idx, 0, true)
        cl:SetExtent(42, 42)
        cl:AddAnchor("CENTER", tbCanvas, "CENTER", off[1], off[2])
        pcall(function() cl.style:SetFont("ui/font/yoon_firedgothic_b.ttf", 25) end)
        cl.style:SetFontSize(25)
        cl.style:SetAlign(ALIGN.CENTER)
        cl.style:SetShadow(true)
        pcall(function() cl.style:SetOutline(true) end)
        cl:SetText("")
        pcall(function() cl:Clickable(false) end)
        pcall(function() cl:EnableHitTest(false) end)
        tbCoreLabels[idx] = cl
    end

    targetBarMarkerUI = {
        canvas = tbCanvas,
        outlineLabels = tbOutlineLabels,
        coreLabels = tbCoreLabels,
        lastMarker = nil,
        anchoredBar = nil,
    }

    customMarkerEventWnd = api.Interface:CreateEmptyWindow("eluCustomFishMarkerEvents", "UIParent")
    customMarkerEventWnd:Show(false)
    function customMarkerEventWnd:OnEvent(event, ...)
        if event == "UNIT_EQUIPMENT_CHANGED" then
            local args = {...}
            local unit = args[1]
            local equipString = args[3]
            if unit == "player" and equipString and string.find(tostring(equipString), "i;") then
                -- Player just equipped a pack onto their back; if they looted a dead marked fish nearby, clear it
                local currentTarget = api.Unit:GetUnitId("target")
                if currentTarget and customMarkedFishes[currentTarget] and customMarkedFishes[currentTarget].isDead then
                    customMarkedFishes[currentTarget] = nil
                    RemoveDeadFishByUnitId(currentTarget)
                    return
                end
                local px, py, pz = api.Unit:UnitWorldPosition("player")
                if isFiniteCoord(px) and isFiniteCoord(py) and isFiniteCoord(pz) then
                    local closestId = nil
                    local closestDistSq = 144 -- within 12m
                    for uid, entry in pairs(customMarkedFishes) do
                        if entry.isDead and isFiniteCoord(entry.wx) and isFiniteCoord(entry.wy) and isFiniteCoord(entry.wz) then
                            local dx = entry.wx - px
                            local dy = entry.wy - py
                            local dz = entry.wz - pz
                            local dSq = dx * dx + dy * dy + dz * dz
                            if dSq < closestDistSq then
                                closestDistSq = dSq
                                closestId = uid
                            end
                        end
                    end
                    if closestId then
                        customMarkedFishes[closestId] = nil
                        RemoveDeadFishByUnitId(closestId)
                    end
                end
            end
        end
    end
    customMarkerEventWnd:SetHandler("OnEvent", customMarkerEventWnd.OnEvent)
    pcall(function() customMarkerEventWnd:RegisterEvent("UNIT_EQUIPMENT_CHANGED") end)
end

-- The dead-fish-timer UI -- the drag box used to reposition it, plus the
-- 9-slot "marked dead fish" pool (10 windows + ~27 child widgets total) --
-- is only ever shown when Enable Dead Fish Timers is on. Both used to be
-- built unconditionally in OnLoad (the drag box directly there, the pool
-- via this function), so every player paid for all of it whether or not
-- they ever turned the feature on. Found 2026-09-07 while reviewing a real
-- gameplay session: the pool itself had already been made lazy, but the
-- drag box was missed -- it's built here too now, lazily, once, the first
-- time it's actually needed (see the enableDeadFishTimers check in OnLoad
-- below, and the safety-net call in OnUpdate in case the setting gets
-- turned on after load). Safe to call more than once: it's a no-op once
-- everything already exists. dfMoveBtn's OnClick handler (above) already
-- nil-checks fish_tracker.deadFishDragBox before using it, so there's
-- nothing else to guard.
local function BuildMarkedFishPool()
    if markedFishPoolBuilt then return end
    markedFishPoolBuilt = true

    local deadFishDragBox = api.Interface:CreateEmptyWindow("eluDeadFishDragBox", "UIParent")
    deadFishDragBox:SetExtent(300, 50)
    deadFishDragBox:AddAnchor("CENTER", "UIParent", "CENTER", fish_tracker.deadFishContainerPos[1], fish_tracker.deadFishContainerPos[2])
    deadFishDragBox:Show(false)

    local bg = deadFishDragBox:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bg:SetTextureInfo("bg_quest")
    bg:SetColor(0, 0, 0, 0.4)
    bg:AddAnchor("TOPLEFT", deadFishDragBox, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", deadFishDragBox, 0, 0)

    deadFishDragBox:SetHandler("OnDragStart", function()
        deadFishDragBox:StartMoving()
    end)
    deadFishDragBox:SetHandler("OnDragStop", function()
        deadFishDragBox:StopMovingOrSizing()
        local x, y = deadFishDragBox:GetOffset()
        deadFishDragBox:RemoveAllAnchors()
        deadFishDragBox:AddAnchor("TOPLEFT", "UIParent", "TOPLEFT", x, y)
        fish_tracker.deadFishContainerPos = {x, y, "TOPLEFT"}
        SaveMiscSettings()
    end)

    if fish_tracker.deadFishContainerPos[3] == "TOPLEFT" then
        deadFishDragBox:RemoveAllAnchors()
        deadFishDragBox:AddAnchor("TOPLEFT", "UIParent", "TOPLEFT", fish_tracker.deadFishContainerPos[1], fish_tracker.deadFishContainerPos[2])
    end

    fish_tracker.deadFishDragBox = deadFishDragBox

    for i = 1, 9 do
        local canvas = api.Interface:CreateEmptyWindow("eluMarkedFishTarget" .. i)
        canvas:SetExtent(40, 60)
        canvas:Show(false)

        local icon = CreateItemIconButton("eluMarkedFishIcon" .. i, canvas)
        icon:AddAnchor("TOPLEFT", canvas, "TOPLEFT", 0, 0)
        icon:Show(true)
        F_SLOT.ApplySlotSkin(icon, icon.back, SLOT_STYLE.DEFAULT)

        local markerLabel = canvas:CreateChildWidget("label", "eluMarkedFishMarkerLabel" .. i, 0, true)
        markerLabel:SetText("")
        markerLabel:AddAnchor("BOTTOM", icon, "TOP", 0, 2)
        markerLabel.style:SetFontSize(22)
        markerLabel.style:SetAlign(ALIGN.CENTER)
        markerLabel.style:SetShadow(true)
        markerLabel.style:SetColor(1, 0.8, 0, 1)

        local timeLabel = canvas:CreateChildWidget("label", "eluMarkedFishTimeLabel" .. i, 0, true)
        timeLabel:SetText("")
        timeLabel:AddAnchor("TOP", icon, "BOTTOM", 0, 2)
        timeLabel.style:SetFontSize(18)
        timeLabel.style:SetAlign(ALIGN.CENTER)
        timeLabel.style:SetShadow(true)
        timeLabel.style:SetColor(1, 0.5, 0, 1)

        function icon:OnClick(arg)
            if arg == "RightButton" or arg == "LeftButton" then
                if canvas.deadFishKey then
                    if canvas.deleteState then
                        local delEntry = deadFishes[canvas.deadFishKey]
                        if type(delEntry) == "table" and delEntry.unitId then
                            customMarkedFishes[delEntry.unitId] = nil
                        end
                        deadFishes[canvas.deadFishKey] = nil
                        canvas:Show(false)
                        canvas.deleteState = false
                    else
                        canvas.deleteState = true
                        canvas.deleteTime = api.Time:GetUiMsec()
                    end
                end
            end
        end
        icon:SetHandler("OnClick", icon.OnClick)

        function icon:OnLeave()
            if canvas.deleteState then
                canvas.deleteState = false
            end
        end
        icon:SetHandler("OnLeave", icon.OnLeave)

        markedFishUI[i] = {
            canvas = canvas,
            icon = icon,
            timeLabel = timeLabel,
            markerLabel = markerLabel
        }
    end
end

function fish_tracker:OnLoad()
    LoadMiscSettings()

    if not fishTrackerCanvas then
        fishTrackerCanvas = api.Interface:CreateEmptyWindow("fishTrackerCanvas")
        fishTrackerCanvas:Show(false)

        targetFishIcon = CreateItemIconButton("targetFishIcon", fishTrackerCanvas)
        targetFishIcon:AddAnchor("TOPLEFT", fishTrackerCanvas, "TOPLEFT", 0, 0)
        targetFishIcon:Show(true)
        F_SLOT.ApplySlotSkin(targetFishIcon, targetFishIcon.back, SLOT_STYLE.DEFAULT)

        fishBuffTimeLeftLabel = fishTrackerCanvas:CreateChildWidget("label", "fishBuffTimeLeftLabel", 0, true)
        fishBuffTimeLeftLabel:SetText("")
        fishBuffTimeLeftLabel:AddAnchor("TOP", targetFishIcon, "BOTTOM", 0, 2)
        fishBuffTimeLeftLabel.style:SetFontSize(18)
        fishBuffTimeLeftLabel.style:SetAlign(ALIGN.CENTER)
        fishBuffTimeLeftLabel.style:SetShadow(true)
        fishBuffTimeLeftLabel.style:SetColor(0, 1, 0, 1)

        strengthContestIcon = CreateItemIconButton("strengthContestIcon", fishTrackerCanvas)
        strengthContestIcon:AddAnchor("LEFT", targetFishIcon, "RIGHT", 5, 0)
        strengthContestIcon:Show(false)
        F_SLOT.ApplySlotSkin(strengthContestIcon, strengthContestIcon.back, SLOT_STYLE.DEFAULT)

        strengthContestTimeLabel = fishTrackerCanvas:CreateChildWidget("label", "strengthContestTimeLabel", 0, true)
        strengthContestTimeLabel:SetText("")
        strengthContestTimeLabel:AddAnchor("TOP", strengthContestIcon, "BOTTOM", 0, 2)
        strengthContestTimeLabel.style:SetFontSize(18)
        strengthContestTimeLabel.style:SetAlign(ALIGN.CENTER)
        strengthContestTimeLabel.style:SetShadow(true)
        strengthContestTimeLabel.style:SetColor(1, 1, 0, 1)
    end

    -- Dead-fish-timer UI (drag box + 9-slot marker pool) is built lazily by
    -- BuildMarkedFishPool -- only up front here if the feature is already
    -- on (so returning users see zero behavior change). If it's off,
    -- OnUpdate's safety-net call builds it the moment it's turned on
    -- instead. See the comment on BuildMarkedFishPool above.
    if fish_tracker.enableDeadFishTimers then
        BuildMarkedFishPool()
    end
    if fish_tracker.enableCustomFishMarkers then
        BuildCustomMarkerPool()
    end

    deadFishes = {}
    customMarkedFishes = {}
    fish_tracker.nextCustomFishMarker = 0

end

function fish_tracker:OnUpdate(dt)
    if not fishTrackerCanvas then return end
    
    local currentTime = api.Time:GetUiMsec()
    local currentTarget = api.Unit:GetUnitId("target")
    local targetName = nil

    local hp = nil
    if currentTarget then
        targetName = api.Unit:GetUnitNameById(currentTarget)
        hp = api.Unit:UnitHealth("target")
    end

    local isTargetingMe = false
    if currentTarget then
        local targetOfTarget = api.Unit:GetUnitId("targettarget")
        local playerUnit = api.Unit:GetUnitId("player")
        if targetOfTarget and playerUnit and targetOfTarget == playerUnit then
            isTargetingMe = true
        end
    end

    if hp ~= nil and hp > 0 then
        fish_tracker.lastTargetTargetingMe = isTargetingMe
    end

    if currentTarget and hp ~= nil and hp <= 0 then
        local px = api.Unit:UnitWorldPosition("target")
        if px == nil then
            customMarkedFishes[currentTarget] = nil
            RemoveDeadFishByUnitId(currentTarget)
        end
    end

    if fish_tracker.enableCustomFishMarkers then
        BuildCustomMarkerPool()
        local isKnownFish = (targetName ~= nil and fishNamesToAlert[targetName] == true)

        if currentTarget and isKnownFish and isTargetingMe and hp ~= nil and hp > 0 then
            if not customMarkedFishes[currentTarget] then
                fish_tracker.nextCustomFishMarker = ((fish_tracker.nextCustomFishMarker or 0) % 9) + 1
                local markerNum = fish_tracker.nextCustomFishMarker
                for uid, existing in pairs(customMarkedFishes) do
                    if existing.marker == markerNum then
                        customMarkedFishes[uid] = nil
                    end
                end
                local wx, wy, wz = api.Unit:UnitWorldPosition("target")
                customMarkedFishes[currentTarget] = {
                    unitId = currentTarget,
                    marker = markerNum,
                    wx = wx,
                    wy = wy,
                    wz = wz,
                    isDead = false,
                    createdTime = currentTime,
                    lastSeenTime = currentTime,
                }
            end
        end

        if currentTarget and customMarkedFishes[currentTarget] then
            local cEntry = customMarkedFishes[currentTarget]
            cEntry.lastSeenTime = currentTime
            local wx, wy, wz = api.Unit:UnitWorldPosition("target")
            local okInfo, uInfo = pcall(api.Unit.GetUnitInfoById, api.Unit, currentTarget)
            if okInfo and uInfo ~= nil then
                cEntry.hadUnitInfo = true
            end
            if hp ~= nil and hp <= 0 then
                if not cEntry.isDead then
                    cEntry.isDead = true
                    cEntry.deathTime = currentTime
                end
                if wx == nil then
                    customMarkedFishes[currentTarget] = nil
                    RemoveDeadFishByUnitId(currentTarget)
                    cEntry = nil
                end
            elseif hp ~= nil and hp > 0 then
                -- Check fishing buffs on live fish to know exact timeout / despawn
                local bCount = api.Unit:UnitBuffCount("target") or 0
                local hasContest = false
                for bi = 1, bCount do
                    local b = api.Unit:UnitBuff("target", bi)
                    if b and b.buff_id then
                        if b.buff_id == 5715 and b.timeLeft then
                            hasContest = true
                            cEntry.hadStrengthContest = true
                            cEntry.strengthContestEndTime = currentTime + b.timeLeft
                        elseif ownersMarkCache[b.buff_id] and b.timeLeft then
                            cEntry.ownerMarkEndTime = currentTime + b.timeLeft
                        end
                    end
                end
                if cEntry.hadStrengthContest and not hasContest then
                    -- Strength Contest buff ended while fish still had HP > 0 -> fish escaped!
                    customMarkedFishes[currentTarget] = nil
                    RemoveDeadFishByUnitId(currentTarget)
                    cEntry = nil
                end
            end
            if cEntry and isFiniteCoord(wx) and isFiniteCoord(wy) and isFiniteCoord(wz) then
                cEntry.wx, cEntry.wy, cEntry.wz = wx, wy, wz
            end
        elseif fish_tracker.lastTargetId and customMarkedFishes[fish_tracker.lastTargetId] and currentTarget == nil then
            -- Target suddenly became nil; check if the previously targeted fish despawned
            local prevUid = fish_tracker.lastTargetId
            local prevEntry = customMarkedFishes[prevUid]
            if prevEntry then
                local okName, uName = pcall(api.Unit.GetUnitNameById, api.Unit, prevUid)
                local okInfo, uInfo = pcall(api.Unit.GetUnitInfoById, api.Unit, prevUid)
                if (not okName or uName == nil or uName == "") or (prevEntry.hadUnitInfo and (not okInfo or uInfo == nil)) then
                    customMarkedFishes[prevUid] = nil
                    RemoveDeadFishByUnitId(prevUid)
                elseif not prevEntry.isDead and prevEntry.strengthContestEndTime and currentTime >= (prevEntry.strengthContestEndTime - 1500) then
                    customMarkedFishes[prevUid] = nil
                    RemoveDeadFishByUnitId(prevUid)
                end
            end
        end
    end

    if fish_tracker.lastTargetId ~= currentTarget then
        fish_tracker.lastTargetId = currentTarget
        fish_tracker.lastTargetHp = hp
    end

    -- 1. Track Target Deaths for Dead Fish Timer
    if currentTarget and targetName and fishNamesToAlert[targetName] then
        if hp ~= nil and hp <= 0 then
            local prevHp = fish_tracker.lastTargetHp
            if prevHp ~= nil and prevHp > 0 then
                if not fish_tracker.enableOnlyMyFishes or fish_tracker.lastTargetTargetingMe then
                    local mIdx = nil
                    local isAutoMarked = false
                    for i = 1, 9 do
                        local mUnit = safeGetOverHeadMarkerUnitId(i)
                        if mUnit and mUnit == currentTarget then
                            mIdx = i
                            break
                        end
                    end
                    if not mIdx and fish_tracker.enableCustomFishMarkers and customMarkedFishes[currentTarget] then
                        mIdx = customMarkedFishes[currentTarget].marker
                        isAutoMarked = true
                    elseif fish_tracker.enableCustomFishMarkers and customMarkedFishes[currentTarget] then
                        isAutoMarked = true
                    end

                    local okInfo, uInfo = pcall(api.Unit.GetUnitInfoById, api.Unit, currentTarget)
                    
                    fish_tracker.nextDeadFishId = (fish_tracker.nextDeadFishId or 0) + 1
                    local uniqueKey = currentTarget .. "_" .. tostring(fish_tracker.nextDeadFishId)
                    
                    deadFishes[uniqueKey] = {
                        time = currentTime,
                        marker = mIdx,
                        unitId = currentTarget,
                        autoMarked = isAutoMarked,
                        hadUnitInfo = (okInfo and uInfo ~= nil),
                    }
                end
            end
        end
        fish_tracker.lastTargetHp = hp
    else
        fish_tracker.lastTargetHp = nil
    end
    


    -- Update Dead Fish Timers UI
    if fish_tracker.enableDeadFishTimers then
        BuildMarkedFishPool()
        local activeTimerCount = 0
        local index = 1
        
        local sortedFishes = sortedFishes_cache
        local sort_idx = 1
        for key, data in pairs(deadFishes) do
            if sortedFishes[sort_idx] == nil then sortedFishes[sort_idx] = {} end
            sortedFishes[sort_idx].key = key
            sortedFishes[sort_idx].data = data
            sort_idx = sort_idx + 1
        end
        for i = sort_idx, #sortedFishes do
            sortedFishes[i] = nil
        end
        table.sort(sortedFishes, function(a, b)
            local timeA = type(a.data) == "table" and a.data.time or a.data
            local timeB = type(b.data) == "table" and b.data.time or b.data
            return timeA < timeB
        end)
        
        for _, entry in ipairs(sortedFishes) do
            local key = entry.key
            local data = entry.data
            local deathTime = type(data) == "table" and data.time or data
            local marker = type(data) == "table" and data.marker or nil
            local elapsed = currentTime - deathTime
            local remaining = MARKED_FISH_TIMER - elapsed

            -- When Auto Mark (Enable Fish Markers 1-9) is enabled, automatically remove the Dead Fish Timer
            -- as soon as the fish's marker / entity disappears from the world (looted or despawned).
            if remaining > 0 and type(data) == "table" and data.unitId and (fish_tracker.enableCustomFishMarkers or data.autoMarked) then
                if data.autoMarked and not customMarkedFishes[data.unitId] then
                    remaining = 0
                else
                    local okName, uName = pcall(api.Unit.GetUnitNameById, api.Unit, data.unitId)
                    local okInfo, uInfo = pcall(api.Unit.GetUnitInfoById, api.Unit, data.unitId)
                    if (not okName or uName == nil or uName == "") or (data.hadUnitInfo and (not okInfo or uInfo == nil)) then
                        customMarkedFishes[data.unitId] = nil
                        remaining = 0
                    end
                end
            end
            
            if remaining <= 0 then
                deadFishes[key] = nil
                if markedFishUI[index] and markedFishUI[index].canvas then
                    markedFishUI[index].canvas:Show(false)
                end
            else
                local ui = markedFishUI[index]
                if ui then
                    if ui.canvas.deadFishKey ~= key then
                        ui.canvas.deleteState = false
                    end
                    ui.canvas.deadFishKey = key
                    local xOffset = (activeTimerCount * 55)
                    ui.canvas:RemoveAllAnchors()
                    local bx = fish_tracker.deadFishContainerPos[1] or 0
                    local by = fish_tracker.deadFishContainerPos[2] or 200
                    local apt = fish_tracker.deadFishContainerPos[3] or "CENTER"
                    ui.canvas:AddAnchor("TOPLEFT", "UIParent", apt, bx + xOffset, by)
                    ui.canvas:Show(true)
                        
                    if ui.canvas.deleteState then
                        if currentTime - (ui.canvas.deleteTime or currentTime) > 3000 then
                            ui.canvas.deleteState = false
                        end
                    end
                        
                    if ui.canvas.deleteState then
                        F_SLOT.SetIconBackGround(ui.icon, GetCachedIconPath(11487))
                        ui.timeLabel:SetText(string.format("%.0fs(X)", remaining / 1000))
                        ui.timeLabel.style:SetColor(1, 0, 0, 1)
                        ui.canvas:SetAlpha(0.5)
                    else
                        F_SLOT.SetIconBackGround(ui.icon, GetCachedIconPath(11487))
                        ui.timeLabel:SetText(string.format("%.0fs", remaining / 1000))
                        if remaining <= 5000 then
                            if math.floor(remaining / 250) % 2 == 0 then
                                ui.timeLabel.style:SetColor(1, 0, 0, 1)
                            else
                                ui.timeLabel.style:SetColor(1, 1, 1, 1)
                            end
                        elseif remaining <= 20000 then
                            ui.timeLabel.style:SetColor(1, 0, 0, 1)
                        else
                            ui.timeLabel.style:SetColor(1, 1, 1, 1)
                        end
                        ui.canvas:SetAlpha(1.0)
                    end
                        
                    if marker ~= nil then
                        ui.markerLabel:SetText(tostring(marker))
                        local color = markerColors[marker]
                        if color then
                            ui.markerLabel.style:SetColor(color[1], color[2], color[3], color[4])
                        else
                            ui.markerLabel.style:SetColor(1, 0.8, 0, 1)
                        end
                    else
                        ui.markerLabel:SetText("")
                    end
                        
                    activeTimerCount = activeTimerCount + 1
                    index = index + 1
                end
            end
            if index > 9 then break end
        end
        
        for i = index, 9 do
            if markedFishUI[i] and markedFishUI[i].canvas then
                markedFishUI[i].canvas:Show(false)
            end
        end
    else
        for i = 1, 9 do
            if markedFishUI[i] and markedFishUI[i].canvas then markedFishUI[i].canvas:Show(false) end
        end
    end

    -- 2. Owner Mark & Skill Indicators
    if currentTarget then
        local x, y, z = safeGetUnitScreenPosition("target")
        if prevX ~= x or prevY ~= y or prevZ ~= z then
            fishTrackerCanvas:AddAnchor("TOP", "UIParent", "TOPLEFT", (x or 0) - 42, (y or 0) - 100)
            prevX, prevY, prevZ = x, y, z
        end

        fish_tracker.buffCheckTimer = (fish_tracker.buffCheckTimer or 0) + dt
        if fish_tracker.buffCheckTimer > 100 then
            fish_tracker.buffCheckTimer = 0
            local buffCount = api.Unit:UnitBuffCount("target") or 0
            local ownersMarkBuff = nil
            local actionBuff = nil
            local strengthContestBuff = nil
    
            for i = 1, buffCount do
                local buff = api.Unit:UnitBuff("target", i)
                if buff ~= nil and buff.buff_id ~= nil then
                    local isOwner = ownersMarkCache[buff.buff_id]
                    if isOwner == nil and not nonOwnersMarkCache[buff.buff_id] then
                        local bInfoName = GetCachedBuffName(buff.buff_id)
                        if bInfo and bInfo.name and string.find(string.lower(bInfo.name), "owner's mark") then
                            ownersMarkCache[buff.buff_id] = true
                            isOwner = true
                        else
                            nonOwnersMarkCache[buff.buff_id] = true
                            isOwner = false
                        end
                    end
                    
                    if isOwner then
                        ownersMarkBuff = buff
                    elseif fishBuffIdsToAlert[buff.buff_id] ~= nil then
                        if actionBuffs[buff.buff_id] then
                            actionBuff = buff
                        elseif buff.buff_id == 5715 then
                            strengthContestBuff = buff
                        end
                    end
                end
            end
            
            fish_tracker.lastOwnersMarkBuff = ownersMarkBuff
            fish_tracker.lastActionBuff = actionBuff
            fish_tracker.lastStrengthContestBuff = strengthContestBuff
        end
        
        local ownersMarkBuff = fish_tracker.lastOwnersMarkBuff
        local actionBuff = fish_tracker.lastActionBuff
        local strengthContestBuff = fish_tracker.lastStrengthContestBuff

        if fish_tracker.enableOwnerMark and ownersMarkBuff ~= nil then
            if not fish_tracker.ownerMarkEndTime or currentTime > fish_tracker.ownerMarkEndTime or fish_tracker.ownerMarkUnitId == currentTarget then
                fish_tracker.ownerMarkEndTime = currentTime + ownersMarkBuff.timeLeft
                fish_tracker.ownerMarkIconPath = GetCachedIconPath(ownersMarkBuff.buff_id)
                fish_tracker.ownerMarkUnitId = currentTarget
            end
        end

        -- Fish Skill Indicators Logic
        local showSkillIndicators = fish_tracker.enableSkillIndicators
        if fish_tracker.enableOnlyMyFishes and not isTargetingMe then
            showSkillIndicators = false
        end
        local fishHealth = api.Unit:UnitHealth("target")
        if fishHealth ~= nil and fishHealth <= 0 and fish_tracker.enableSkillIndicators then
            showSkillIndicators = true
        end

        if showSkillIndicators then
            if (fishHealth ~= nil and fishHealth <= 0) or buffCount == 0 then
                strengthContestIcon:Show(false)
                strengthContestTimeLabel:SetText("")
                fishTrackerCanvas:AddAnchor("TOP", "UIParent", "TOPLEFT", (x or 0) - 42, (y or 0) - 100)
                if fishNamesToAlert[targetName] then
                    fishTrackerCanvas:Show(true)
                end
                targetFishIcon:Show(true)
                F_SLOT.SetIconBackGround(targetFishIcon, GetCachedIconPath(4053))
                fishBuffTimeLeftLabel:Show(false)
            else
                if actionBuff ~= nil then
                    fishTrackerCanvas:AddAnchor("TOP", "UIParent", "TOPLEFT", (x or 0) - 42, (y or 0) - 100)
                    fishTrackerCanvas:Show(true)
                    targetFishIcon:Show(true)
                    fishBuffTimeLeftLabel:Show(true)
                    F_SLOT.SetIconBackGround(targetFishIcon, actionBuff.path)
                    
                    local timeLeftSecs = math.max(0, actionBuff.timeLeft / 1000)
                    fishBuffTimeLeftLabel:SetText(string.format("%.0fs", timeLeftSecs))
                    
                    if currentTarget ~= previousFish or previousActionBuffId ~= actionBuff.buff_id then
                        previousActionBuffId = actionBuff.buff_id
                    end
                else
                    fishTrackerCanvas:AddAnchor("TOP", "UIParent", "TOPLEFT", (x or 0) - 42, (y or 0) - 100)
                    if fishNamesToAlert[targetName] then
                        fishTrackerCanvas:Show(true)
                    end
                    targetFishIcon:Show(true)
                    F_SLOT.SetIconBackGround(targetFishIcon, GetCachedIconPath(4622))
                    fishBuffTimeLeftLabel:Show(false)
                    previousActionBuffId = nil
                end

                if strengthContestBuff ~= nil then
                    strengthContestIcon:Show(true)
                    F_SLOT.SetIconBackGround(strengthContestIcon, GetCachedIconPath(5715))
                    -- SetIconBackGround appears to auto-size this icon to
                    -- buff 5715's own native texture, which renders bigger
                    -- than targetFishIcon's icons. Force it back to match
                    -- targetFishIcon's actual current size so both skill
                    -- indicators always look the same size.
                    strengthContestIcon:SetExtent(targetFishIcon:GetExtent())

                    local timeLeftSecs = math.max(0, strengthContestBuff.timeLeft / 1000)
                    strengthContestTimeLabel:SetText(string.format("%.0fs", timeLeftSecs))
                    
                    if currentTarget ~= previousFish or previousStrengthBuffId ~= strengthContestBuff.buff_id then
                        previousStrengthBuffId = strengthContestBuff.buff_id
                    end
                else
                    strengthContestIcon:Show(false)
                    strengthContestTimeLabel:SetText("")
                    previousStrengthBuffId = nil
                end
            end
        else
            if fishTrackerCanvas then fishTrackerCanvas:Show(false) end
            if strengthContestIcon then strengthContestIcon:Show(false) end
            if strengthContestTimeLabel then strengthContestTimeLabel:SetText("") end
        end

        previousFish = currentTarget
    else
        previousFish = nil
        previousActionBuffId = nil
        previousStrengthBuffId = nil
        if fishTrackerCanvas then fishTrackerCanvas:Show(false) end
    end

    -- 3. Update Custom Fish Markers (1-9)
    if fish_tracker.enableCustomFishMarkers then
        BuildCustomMarkerPool()
        local usedSlots = {}
        local pwx, pwy, pwz = api.Unit:UnitWorldPosition("player")

        for uid, entry in pairs(customMarkedFishes) do
            local expired = false
            local okName, uName = pcall(api.Unit.GetUnitNameById, api.Unit, uid)
            local okInfo, uInfo = pcall(api.Unit.GetUnitInfoById, api.Unit, uid)

            if (not okName or uName == nil or uName == "") or (entry.hadUnitInfo and (not okInfo or uInfo == nil)) then
                expired = true
            elseif entry.isDead and entry.deathTime and (currentTime - entry.deathTime) >= MARKED_FISH_TIMER then
                expired = true
            elseif not entry.isDead and entry.strengthContestEndTime and currentTime >= (entry.strengthContestEndTime + 500) then
                expired = true
            elseif not entry.isDead and currentTarget ~= uid and (currentTime - (entry.lastSeenTime or entry.createdTime)) >= 120000 then
                expired = true
            elseif isFiniteCoord(pwx) and isFiniteCoord(pwy) and isFiniteCoord(pwz) and isFiniteCoord(entry.wx) and isFiniteCoord(entry.wy) and isFiniteCoord(entry.wz) then
                local dx = entry.wx - pwx
                local dy = entry.wy - pwy
                local dz = entry.wz - pwz
                if (dx * dx + dy * dy + dz * dz) > 90000 then
                    expired = true
                end
            end

            if expired then
                customMarkedFishes[uid] = nil
                RemoveDeadFishByUnitId(uid)
            else
                local m = entry.marker
                local ui = customMarkerUI[m]
                if ui and ui.canvas then
                    local sx, sy, sz = nil, nil, nil
                    if currentTarget == uid then
                        local okT, tx, ty, tz = pcall(api.Unit.GetUnitScreenPosition, api.Unit, "target")
                        if okT and isFiniteCoord(tx) and isFiniteCoord(ty) then
                            sx, sy, sz = tx, ty, tz or 0
                            updateEntryWorldCalibration(entry, tx, ty, tz)
                        end
                    elseif entry.isDead then
                        -- Only project stationary world coordinates for DEAD fishes;
                        -- live fishes swim around and AAClassic's API blocks position reads on unselected units.
                        local pjx, pjy, pjz = projectEntryWorldToScreen(entry)
                        if pjx and pjy then
                            sx, sy, sz = pjx, pjy, pjz or 0
                        end
                    end

                    if sx and sy and (sz == nil or (sz >= 0 and sz <= 250)) and sx > -100 and sx < 4000 and sy > -100 and sy < 3000 then
                        usedSlots[m] = true
                        local ax = math.floor(sx + 0.5)
                        local ay = math.floor(sy - 55 + 0.5)
                        if ui.lastAx ~= ax or ui.lastAy ~= ay then
                            ui.canvas:RemoveAllAnchors()
                            ui.canvas:AddAnchor("CENTER", "UIParent", "TOPLEFT", ax, ay)
                            ui.lastAx = ax
                            ui.lastAy = ay
                        end
                        ui.canvas:Show(true)
                    end
                end
            end
        end

        for i = 1, 9 do
            if not usedSlots[i] and customMarkerUI[i] and customMarkerUI[i].canvas then
                customMarkerUI[i].canvas:Show(false)
            end
        end

        if targetBarMarkerUI and targetBarMarkerUI.canvas then
            local targetEntry = currentTarget and customMarkedFishes[currentTarget] or nil
            if targetEntry and targetEntry.marker then
                local okTf, targetFrame = pcall(function()
                    if ADDON and ADDON.GetContent and UIC and UIC.TARGET_UNITFRAME then
                        return ADDON:GetContent(UIC.TARGET_UNITFRAME)
                    end
                    return nil
                end)
                local hpBar = okTf and targetFrame and targetFrame.hpBar or nil
                if hpBar then
                    local m = targetEntry.marker
                    if targetBarMarkerUI.lastMarker ~= m then
                        targetBarMarkerUI.lastMarker = m
                        local mStr = tostring(m)
                        local color = markerColors[m] or {1, 0.8, 0, 1}
                        if targetBarMarkerUI.outlineLabels then
                            for _, ol in ipairs(targetBarMarkerUI.outlineLabels) do
                                ol:SetText(mStr)
                            end
                        end
                        if targetBarMarkerUI.coreLabels then
                            for _, cl in ipairs(targetBarMarkerUI.coreLabels) do
                                cl:SetText(mStr)
                                cl.style:SetColor(color[1], color[2], color[3], color[4])
                            end
                        end
                    end
                    if targetBarMarkerUI.anchoredBar ~= hpBar then
                        targetBarMarkerUI.anchoredBar = hpBar
                        targetBarMarkerUI.canvas:RemoveAllAnchors()
                        targetBarMarkerUI.canvas:AddAnchor("CENTER", hpBar, "BOTTOMLEFT", 18, -2)
                    end
                    if not targetBarMarkerUI.canvas:IsVisible() or targetBarMarkerUI.lastTargetId ~= currentTarget then
                        targetBarMarkerUI.lastTargetId = currentTarget
                        targetBarMarkerUI.canvas:Show(true)
                        pcall(function() targetBarMarkerUI.canvas:Raise() end)
                    end
                else
                    targetBarMarkerUI.canvas:Show(false)
                end
            else
                targetBarMarkerUI.canvas:Show(false)
            end
        end
    else
        HideAllCustomFishMarkers()
    end
end

function fish_tracker:OnUnload()
    if fish_tracker.masterCanvas then
        fish_tracker.masterCanvas:Show(false)
    end
    if fishTrackerCanvas ~= nil then
        fishTrackerCanvas:Show(false)
    end
    for i = 1, 9 do
        if markedFishUI[i] and markedFishUI[i].canvas then
            markedFishUI[i].canvas:Show(false)
        end
    end
    HideAllCustomFishMarkers()
    if fish_tracker.deadFishDragBox ~= nil then
        fish_tracker.deadFishDragBox:Show(false)
    end
    deadFishes = {}
    customMarkedFishes = {}
end

return fish_tracker













