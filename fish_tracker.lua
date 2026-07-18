local api = require("api")

local fish_tracker = {}

fish_tracker.enableDeadFishTimers = true
fish_tracker.enableSkillIndicators = true
fish_tracker.enableDebugMode = true
fish_tracker.enableOnlyMyFishes = true

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
	["Marlin"] = true, ["Blue Marlin"] = true, ["Tuna"] = true, ["Blue Tuna"] = true, ["Bluefin Tuna"] = true, ["Sunfish"] = true,
	["Sailfish"] = true, ["Sturgeon"] = true, ["Pink Pufferfish"] = true,
	["Carp"] = true, ["Arowana"] = true, ["Pufferfish"] = true, ["Eel"] = true,
	["Pink Marlin"] = true, ["Treasure Mimic"] = true,
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

local function LoadMiscSettings()
    local data = api.File:Read("elu_tracker_misc.txt")
    if type(data) == "table" then
        if data.enableDeadFishTimers ~= nil then fish_tracker.enableDeadFishTimers = data.enableDeadFishTimers end
        if data.enableSkillIndicators ~= nil then fish_tracker.enableSkillIndicators = data.enableSkillIndicators end
        api.Log:Info(string.format("[Fish Tracker Debug] Settings Loaded - DeadFish:%s, SkillInd:%s", 
            tostring(fish_tracker.enableDeadFishTimers), tostring(fish_tracker.enableSkillIndicators)))
    else
        api.Log:Info("[Fish Tracker Debug] No settings file found, using defaults.")
        fish_tracker.enableDeadFishTimers = true
        fish_tracker.enableSkillIndicators = true
    end
end

local function SaveMiscSettings()
    local data = api.File:Read("elu_tracker_misc.txt")
    if type(data) ~= "table" then data = {} end
    data.enableDeadFishTimers = fish_tracker.enableDeadFishTimers
    data.enableSkillIndicators = fish_tracker.enableSkillIndicators
    api.File:Write("elu_tracker_misc.txt", data)
end

function fish_tracker.CreateUI(wndParent)
    LoadMiscSettings()
    local anchorWidget = wndParent.eluAltToggleContainer or wndParent
    local yOffset = anchorWidget == wndParent and 300 or 10
    
    local container = wndParent:CreateChildWidget("emptywidget", "eluFishTrackerToggles", 0, true)
    container:SetExtent(300, 60)
    if anchorWidget == wndParent then
        container:AddAnchor("TOP", anchorWidget, 0, yOffset)
    else
        container:AddAnchor("TOP", anchorWidget, "BOTTOM", 0, yOffset)
    end
    
    -- Dead Fish Timers Toggle
    local deadFishToggle = container:CreateChildWidget("checkbutton", "deadFishToggle", 0, true)
    deadFishToggle:SetExtent(18, 17)
    deadFishToggle:AddAnchor("TOPLEFT", container, "TOPLEFT", 15, 0)
    
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
    dfLbl:SetText("Enable Dead Fish Timers (Beta)")
    dfLbl:AddAnchor("LEFT", deadFishToggle, "RIGHT", 5, 0)
    ApplyTextColor(dfLbl, FONT_COLOR.DEFAULT)

    deadFishToggle:SetChecked(fish_tracker.enableDeadFishTimers, false)
    function deadFishToggle:OnCheckChanged()
        fish_tracker.enableDeadFishTimers = self:GetChecked()
        SaveMiscSettings()
        if not fish_tracker.enableDeadFishTimers then
            for i = 1, 9 do
                if markedFishUI[i] and markedFishUI[i].canvas then
                    markedFishUI[i].canvas:Show(false)
                end
            end
        end
    end
    deadFishToggle:SetHandler("OnCheckChanged", deadFishToggle.OnCheckChanged)

    -- Skill Indicators Toggle
    local skillIndToggle = container:CreateChildWidget("checkbutton", "skillIndToggle", 0, true)
    skillIndToggle:SetExtent(18, 17)
    skillIndToggle:AddAnchor("TOPLEFT", deadFishToggle, "BOTTOMLEFT", 0, 10)
    
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
    siLbl:SetText("Enable Fish Skill Indicators (Beta)")
    siLbl:AddAnchor("LEFT", skillIndToggle, "RIGHT", 5, 0)
    ApplyTextColor(siLbl, FONT_COLOR.DEFAULT)

    skillIndToggle:SetChecked(fish_tracker.enableSkillIndicators, false)
    function skillIndToggle:OnCheckChanged()
        fish_tracker.enableSkillIndicators = self:GetChecked()
        SaveMiscSettings()
        if not fish_tracker.enableSkillIndicators and fishTrackerCanvas then
            fishTrackerCanvas:Show(false)
        end
    end
    skillIndToggle:SetHandler("OnCheckChanged", skillIndToggle.OnCheckChanged)

end

function fish_tracker:OnLoad()
    LoadMiscSettings()

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

    for i = 1, 9 do
        local canvas = api.Interface:CreateEmptyWindow("eluMarkedFishTarget" .. i)
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



    deadFishes = {}
    
    api.Log:Info("[Fish Tracker] OnLoad complete. OwnerMark enabled: " .. tostring(fish_tracker.enableOwnerMark))
end

function fish_tracker:OnUpdate(dt)
    if not fishTrackerCanvas or not boatOwnerMarkUI then return end
    
    local currentTime = api.Time:GetUiMsec()
    local currentTarget = api.Unit:GetUnitId("target")
    local targetName = nil

    local hp = nil
    if currentTarget then
        local tInfo = api.Unit:GetUnitInfoById(currentTarget)
        if tInfo then targetName = tInfo.name end
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
            for k, v in pairs(deadFishes) do
                if v.unitId == currentTarget then
                    deadFishes[k] = nil
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
                    for i = 1, 9 do
                        local mUnit = api.Unit:GetOverHeadMarkerUnitId(i)
                        if mUnit and mUnit == currentTarget then
                            mIdx = i
                            break
                        end
                    end
                    
                    fish_tracker.nextDeadFishId = (fish_tracker.nextDeadFishId or 0) + 1
                    local uniqueKey = currentTarget .. "_" .. tostring(fish_tracker.nextDeadFishId)
                    
                    deadFishes[uniqueKey] = { time = currentTime, marker = mIdx, unitId = currentTarget }
                end
            end
        end
        fish_tracker.lastTargetHp = hp
    else
        fish_tracker.lastTargetHp = nil
    end
    


    -- Update Dead Fish Timers UI
    if fish_tracker.enableDeadFishTimers then
        local activeTimerCount = 0
        local index = 1
        for key, data in pairs(deadFishes) do
            local deathTime = type(data) == "table" and data.time or data
            local marker = type(data) == "table" and data.marker or nil
            local elapsed = currentTime - deathTime
            local remaining = MARKED_FISH_TIMER - elapsed
            
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
                    local xOffset = (activeTimerCount * 50) - 125
                        ui.canvas:RemoveAllAnchors()
                        ui.canvas:AddAnchor("TOP", "UIParent", "CENTER", xOffset, 200)
                        ui.canvas:Show(true)
                        
                        if ui.canvas.deleteState then
                            if currentTime - (ui.canvas.deleteTime or currentTime) > 3000 then
                                ui.canvas.deleteState = false
                            end
                        end
                        
                        if ui.canvas.deleteState then
                            F_SLOT.SetIconBackGround(ui.icon, api.Ability:GetBuffTooltip(11487, 1).path)
                            ui.timeLabel:SetText(string.format("%.0fs(X)", remaining / 1000))
                            ui.timeLabel.style:SetColor(1, 0, 0, 1)
                            ui.canvas:SetAlpha(0.5)
                        else
                            F_SLOT.SetIconBackGround(ui.icon, api.Ability:GetBuffTooltip(11487, 1).path)
                            ui.timeLabel:SetText(string.format("%.0fs", remaining / 1000))
                            ui.timeLabel.style:SetColor(1, 1, 1, 1)
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
        local x, y, z = api.Unit:GetUnitScreenPosition("target")
        local currentXYZ = tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
        if previousXYZ ~= currentXYZ then
            fishTrackerCanvas:AddAnchor("TOP", "UIParent", "TOPLEFT", (x or 0) - 42, (y or 0) + 5)
            previousXYZ = currentXYZ
        end

        local buffCount = api.Unit:UnitBuffCount("target") or 0
        local ownersMarkBuff = nil
        local actionBuff = nil
        local strengthContestBuff = nil

        for i = 1, buffCount do
            local buff = api.Unit:UnitBuff("target", i)
            if buff ~= nil then
                local bInfo = api.Ability:GetBuffTooltip(buff.buff_id, 1)
                if buff.buff_id == 4867 or buff.buff_id == 5748 or buff.buff_id == 14470 or 
                   (bInfo and bInfo.name and string.find(string.lower(bInfo.name), "owner's mark")) then
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

        if fish_tracker.enableOwnerMark and ownersMarkBuff ~= nil then
            if not fish_tracker.ownerMarkEndTime or currentTime > fish_tracker.ownerMarkEndTime or fish_tracker.ownerMarkUnitId == currentTarget then
                fish_tracker.ownerMarkEndTime = currentTime + ownersMarkBuff.timeLeft
                fish_tracker.ownerMarkIconPath = api.Ability:GetBuffTooltip(ownersMarkBuff.buff_id, 1).path
                fish_tracker.ownerMarkUnitId = currentTarget
            end
        end

        -- Fish Skill Indicators Logic
        local showSkillIndicators = fish_tracker.enableSkillIndicators
        if fish_tracker.enableOnlyMyFishes and not isTargetingMe then
            showSkillIndicators = false
        end

        if showSkillIndicators then
            local fishHealth = api.Unit:UnitHealth("target")
            if (fishHealth ~= nil and fishHealth <= 0) or buffCount == 0 then
                strengthContestIcon:Show(false)
                strengthContestTimeLabel:SetText("")
                fishTrackerCanvas:AddAnchor("TOP", "UIParent", "TOPLEFT", (x or 0) - 42, (y or 0) + 5)
                if fishNamesToAlert[targetName] then
                    fishTrackerCanvas:Show(true)
                end
                targetFishIcon:Show(true)
                F_SLOT.SetIconBackGround(targetFishIcon, api.Ability:GetBuffTooltip(4622, 1).path)
                fishBuffTimeLeftLabel:Show(false)
            else
                if actionBuff ~= nil then
                    fishTrackerCanvas:AddAnchor("TOP", "UIParent", "TOPLEFT", (x or 0) - 42, (y or 0) + 5)
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
                    fishTrackerCanvas:AddAnchor("TOP", "UIParent", "TOPLEFT", (x or 0) - 42, (y or 0) + 5)
                    if fishNamesToAlert[targetName] then
                        fishTrackerCanvas:Show(true)
                    end
                    targetFishIcon:Show(true)
                    F_SLOT.SetIconBackGround(targetFishIcon, api.Ability:GetBuffTooltip(4622, 1).path)
                    fishBuffTimeLeftLabel:Show(false)
                    previousActionBuffId = nil
                end

                if strengthContestBuff ~= nil then
                    strengthContestIcon:Show(true)
                    F_SLOT.SetIconBackGround(strengthContestIcon, api.Ability:GetBuffTooltip(5715, 1).path)
                    
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
end

function fish_tracker:OnUnload()
    if fishTrackerCanvas ~= nil then
        fishTrackerCanvas:Show(false)
        api.Interface:Free(fishTrackerCanvas)
        fishTrackerCanvas = nil
    end
    for i = 1, 9 do
        if markedFishUI[i] ~= nil and markedFishUI[i].canvas ~= nil then
            markedFishUI[i].canvas:Show(false)
            api.Interface:Free(markedFishUI[i].canvas)
            markedFishUI[i] = nil
        end
    end
    markedFishUI = {}
    deadFishes = {}
end

return fish_tracker
