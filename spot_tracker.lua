local settingsManager = require('Elu_Tracker/settings_manager')
local EluTrackerSettings = settingsManager.Settings
local SaveEluTrackerSettings = settingsManager.SaveSettings

local spot_tracker = {}

local MAX_TIMERS = 3
local spotOverlays = {}

local doodadListener = nil
local lastDoodadInfo = nil
local lastCaptureMs = 0

spot_tracker.enableAltTracking = false

local pendingReplacementInfo = nil
local replaceWarning = nil

local timersFilename = "elu_spot_timers.txt"

local function SaveSpotTimers()
    local timersToSave = {}
    for i = 1, MAX_TIMERS do
        local overlay = spotOverlays[i]
        if overlay and overlay:IsVisible() and overlay.timerEndMs and overlay.timerEndMs > api.Time:GetUiMsec() then
            table.insert(timersToSave, { 
                name = overlay.rawSpotName, 
                createdAtLocalTime = overlay.createdAtLocalTime,
                createdAtUiMsec = overlay.createdAtUiMsec,
                durationMs = overlay.durationMs
            })
        end
    end
    EluTrackerSettings.spotTimers = timersToSave
    SaveEluTrackerSettings()
end

local function LoadSpotTimers()
    local savedTimers = EluTrackerSettings.spotTimers
    if savedTimers and type(savedTimers) == "table" then
        local overlayIdx = 1
        for _, timer in ipairs(savedTimers) do
            if timer.createdAtLocalTime and timer.durationMs and overlayIdx <= MAX_TIMERS then
                local createdTimeStr = tostring(timer.createdAtLocalTime)
                local starttime = tonumber(string.sub(createdTimeStr, -6)) or 0
                local currtimeStr = tostring(api.Time:GetLocalTime())
                
                local currtime = tonumber(string.sub(currtimeStr, -6)) or 0
                
                if starttime > currtime then
                    currtime = currtime + 1000000
                end
                
                local elapsedOfflineMs = (currtime - starttime) * 1000
                local newCreatedAtUiMsec = api.Time:GetUiMsec() - elapsedOfflineMs
                
                local newTimerEndMs = newCreatedAtUiMsec + timer.durationMs
                
                if newTimerEndMs > api.Time:GetUiMsec() then
                    local overlay = spotOverlays[overlayIdx]
                    overlay.rawSpotName = timer.name or "Fishing Spot"
                    
                    overlay.createdAtLocalTime = timer.createdAtLocalTime
                    overlay.createdAtUiMsec = newCreatedAtUiMsec
                    overlay.durationMs = timer.durationMs
                    
                    overlay.timerEndMs = newTimerEndMs
                    overlay:Show(true)
                    overlayIdx = overlayIdx + 1
                end
            end
        end
    end
end

local function LoadMiscSettings()
    local data = EluTrackerSettings.misc
    if type(data) == "table" then
        if data.enableAltTracking ~= nil then spot_tracker.enableAltTracking = data.enableAltTracking end
    else
        spot_tracker.enableAltTracking = false
    end
    spot_tracker.modifierKey = "SHIFT"
end

local function SaveMiscSettings()
    EluTrackerSettings.misc = { enableAltTracking = spot_tracker.enableAltTracking, modifierKey = spot_tracker.modifierKey }
    SaveEluTrackerSettings()
end

function spot_tracker.CreateUI(wndParent)
    LoadMiscSettings()
    if not spot_tracker.modifierKey then spot_tracker.modifierKey = "ALT" end
    
    local desc = wndParent:CreateChildWidget("textbox", "descSpot", 0, true)
    desc:SetExtent(260, 40)
    desc.style:SetAlign(ALIGN.CENTER)
    ApplyTextColor(desc, FONT_COLOR.DEFAULT)
    desc:SetText("Hover over a fishing spot\nand press " .. spot_tracker.modifierKey .. " to track.")
    
    if wndParent.eluFishTrackerToggles then
        desc:AddAnchor("TOP", wndParent.eluFishTrackerToggles, "BOTTOM", 0, 15)
    else
        desc:AddAnchor("TOP", wndParent, "TOP", 0, 50)
    end
    
    local container = wndParent:CreateChildWidget("emptywidget", "eluAltToggleContainer", 0, true)
    container:SetExtent(300, 30)
    container:AddAnchor("TOP", desc, "BOTTOM", 0, 5)
    wndParent.eluAltToggleContainer = container
    
    local altToggle = container:CreateChildWidget("checkbutton", "eluAltToggleCheck", 0, true)
    altToggle:SetExtent(18, 17)
    altToggle:AddAnchor("LEFT", container, 45, 0)
    
    local bg1 = altToggle:CreateImageDrawable("ui/button/check_button.dds", "background")
    bg1:SetExtent(18, 17)
    bg1:AddAnchor("CENTER", altToggle, 0, 0)
    bg1:SetCoords(0, 0, 18, 17)
    altToggle:SetNormalBackground(bg1)
    
    local bg2 = altToggle:CreateImageDrawable("ui/button/check_button.dds", "background")
    bg2:SetExtent(18, 17)
    bg2:AddAnchor("CENTER", altToggle, 0, 0)
    bg2:SetCoords(18, 0, 18, 17)
    altToggle:SetCheckedBackground(bg2)
    
    local altLbl = container:CreateChildWidget("label", "eluAltToggleLbl", 0, true)
    altLbl:SetAutoResize(true)
    altLbl:SetText("Enable Spot Tracking")
    altLbl:AddAnchor("LEFT", altToggle, "RIGHT", 5, 0)
    ApplyTextColor(altLbl, FONT_COLOR.DEFAULT)
    
    altToggle:SetChecked(spot_tracker.enableAltTracking)
    function altToggle:OnCheckChanged()
        spot_tracker.enableAltTracking = self:GetChecked()
        SaveMiscSettings()
    end
    altToggle:SetHandler("OnCheckChanged", altToggle.OnCheckChanged)

    local modifierBtn = container:CreateChildWidget("button", "modifierBtn", 0, true)
    modifierBtn:SetText(spot_tracker.modifierKey)
    api.Interface:ApplyButtonSkin(modifierBtn, BUTTON_BASIC.DEFAULT)
    modifierBtn:AddAnchor("LEFT", altLbl, "RIGHT", 10, 0)
    modifierBtn:SetExtent(60, 25)
    function modifierBtn:OnClick()
        if spot_tracker.modifierKey == "ALT" then
            spot_tracker.modifierKey = "SHIFT"
        elseif spot_tracker.modifierKey == "SHIFT" then
            spot_tracker.modifierKey = "CTRL"
        else
            spot_tracker.modifierKey = "ALT"
        end
        self:SetText(spot_tracker.modifierKey)
        desc:SetText("Hover over a fishing spot\nand press " .. spot_tracker.modifierKey .. " to track.")
        SaveMiscSettings()
    end
    modifierBtn:SetHandler("OnClick", modifierBtn.OnClick)
end

function spot_tracker.CaptureHoveredSpot()
    if not lastDoodadInfo then return false end
    
    local nowMs = api.Time:GetUiMsec()
    if nowMs - lastCaptureMs < 300 then return false end 
    lastCaptureMs = nowMs
    
    local info = lastDoodadInfo
    local spotNameStr = info.name or "Fishing Spot"
    local exactTimeSeconds = info.displayTime or 0 
    if exactTimeSeconds <= 0 then exactTimeSeconds = 45 * 60 end
    
    local newTimerEndMs = nowMs + (exactTimeSeconds * 1000)
    
    local targetOverlay = nil
    local oldestOverlay = spotOverlays[1]
    
    for i = 1, MAX_TIMERS do
        local overlay = spotOverlays[i]
        if not overlay:IsVisible() then
            targetOverlay = overlay
            break
        end
        if overlay.createdAtUiMsec < oldestOverlay.createdAtUiMsec then
            oldestOverlay = overlay
        end
    end
    
    if not targetOverlay then
        if not pendingReplacementInfo then
            pendingReplacementInfo = { name = spotNameStr, endMs = newTimerEndMs, target = oldestOverlay, time = nowMs }
            local modKey = spot_tracker.modifierKey or "ALT"
            if replaceWarning then 
                if replaceWarning.rwLbl then
                    replaceWarning.rwLbl:SetText(string.format("Press %s again to replace oldest timer! (Move/Wait 5s to cancel)", modKey))
                end
                replaceWarning:Show(true) 
            end
            return true
        else
            if nowMs - pendingReplacementInfo.time > 500 then
                targetOverlay = pendingReplacementInfo.target
                newTimerEndMs = pendingReplacementInfo.endMs
                spotNameStr = pendingReplacementInfo.name
                pendingReplacementInfo = nil
                if replaceWarning then replaceWarning:Show(false) end
            else
                return true
            end
        end
    end
    
    if targetOverlay then
        targetOverlay.createdAtLocalTime = api.Time:GetLocalTime()
        targetOverlay.createdAtUiMsec = nowMs
        targetOverlay.durationMs = exactTimeSeconds * 1000
        
        targetOverlay.timerEndMs = newTimerEndMs
        targetOverlay.rawSpotName = spotNameStr
        
        local mins = math.floor(exactTimeSeconds / 60)
        targetOverlay:Show(true)
        SaveSpotTimers()
    end
    return true
end

function spot_tracker:OnLoad()
    doodadListener = api.Interface:CreateEmptyWindow("eluSpotDoodadListener", "UIParent")
    doodadListener:Show(false)
    function doodadListener:OnEvent(event, ...)
        local arg = arg or {...}
        if event == "DRAW_DOODAD_TOOLTIP" then
            local info = unpack(arg)
            if type(info) == "table" then lastDoodadInfo = info end
        elseif event == "DRAW_DOODAD_SIGN_TAG" then
            local tag = unpack(arg)
            if tag == nil or tag == "" then 
                lastDoodadInfo = nil 
            end
        end
    end
    doodadListener:SetHandler("OnEvent", doodadListener.OnEvent)
    doodadListener:RegisterEvent("DRAW_DOODAD_TOOLTIP")
    doodadListener:RegisterEvent("DRAW_DOODAD_SIGN_TAG")

    replaceWarning = api.Interface:CreateWidget("emptywidget", "eluSpotWarningBg", "UIParent")
    replaceWarning:SetExtent(500, 40)
    replaceWarning:AddAnchor("TOP", "UIParent", 0, 150)
    
    local rwBg = replaceWarning:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    rwBg:SetTextureInfo("bg_quest")
    rwBg:SetColor(0, 0, 0, 0.9)
    rwBg:AddAnchor("TOPLEFT", replaceWarning, 0, 0)
    rwBg:AddAnchor("BOTTOMRIGHT", replaceWarning, 0, 0)
    
    local rwLbl = replaceWarning:CreateChildWidget("label", "rwLbl", 0, true)
    rwLbl:SetText("Press SHIFT again to replace oldest timer! (Move/Wait 5s to cancel)")
    rwLbl.style:SetFontSize(FONT_SIZE.LARGE)
    ApplyTextColor(rwLbl, FONT_COLOR.RED)
    rwLbl:AddAnchor("CENTER", replaceWarning, 0, 0)
    replaceWarning.rwLbl = rwLbl
    replaceWarning:Show(false)

    spot_tracker.masterOverlay = api.Interface:CreateEmptyWindow("eluSpotMasterOverlay", "UIParent")
    local masterOverlay = spot_tracker.masterOverlay
    --("eluSpotMasterOverlay", "UIParent")
    masterOverlay:Show(true)
    masterOverlay:SetExtent(0, 0)
    masterOverlay:AddAnchor("TOPLEFT", "UIParent", 0, 0)

    for i = 1, MAX_TIMERS do
        local overlay = masterOverlay:CreateChildWidget("emptywidget", "eluSpotOverlay"..i, 0, true)
        overlay:SetExtent(145, 65)
        overlay:AddAnchor("TOPLEFT", "UIParent", 500, 100 + ((i-1)*75))
        overlay:Show(false)
        overlay:EnableDrag(true)

        function overlay:OnDragStart() self:StartMoving() end
        overlay:SetHandler("OnDragStart", overlay.OnDragStart)

        function overlay:OnDragStop() 
            self:StopMovingOrSizing() 
            if spot_tracker.SaveSpotPositions then
                spot_tracker.SaveSpotPositions()
            end
        end
        overlay:SetHandler("OnDragStop", overlay.OnDragStop)
        
        local bg = overlay:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
        bg:SetTextureInfo("bg_quest")
        bg:SetColor(0, 0, 0, 0.4)
        bg:AddAnchor("TOPLEFT", overlay, 0, 0)
        bg:AddAnchor("BOTTOMRIGHT", overlay, 0, 0)
        
        local nameLabel = overlay:CreateChildWidget("textbox", "nameLabel", 0, true)
        nameLabel:SetExtent(145, 40)
        nameLabel:AddAnchor("TOP", overlay, "TOP", 0, 2)
        nameLabel.style:SetAlign(ALIGN.CENTER)
        nameLabel.style:SetFontSize(FONT_SIZE.LARGE)
        nameLabel.style:SetShadow(true)
        nameLabel:SetLineSpace(0)
        nameLabel:SetText("Spot")
        if nameLabel.EnableHitTest then nameLabel:EnableHitTest(false) end
        if nameLabel.Clickable then nameLabel:Clickable(false) end
        overlay.nameLabel = nameLabel
        
        local timerLabel = overlay:CreateChildWidget("label", "timerLabel", 0, true)
        timerLabel:SetExtent(145, 20)
        timerLabel:AddAnchor("TOP", nameLabel, "BOTTOM", 0, -2)
        timerLabel.style:SetAlign(ALIGN.CENTER)
        timerLabel.style:SetFontSize(FONT_SIZE.LARGE)
        timerLabel.style:SetShadow(true)
        timerLabel.style:SetOutline(true)
        timerLabel:SetText("00:00")
        if timerLabel.EnableHitTest then timerLabel:EnableHitTest(false) end
        if timerLabel.Clickable then timerLabel:Clickable(false) end
        overlay.timerLabel = timerLabel

        local closeBtn = overlay:CreateChildWidget("button", "closeBtn", 0, true)
        closeBtn:SetText("X")
        closeBtn:SetExtent(16, 16)
        closeBtn:AddAnchor("TOPRIGHT", overlay, -5, 5)
        closeBtn.style:SetAlign(ALIGN.CENTER)
        ApplyTextColor(closeBtn, FONT_COLOR.RED)
        function closeBtn:OnClick() 
            overlay:Show(false)
            SaveSpotTimers() 
        end
        closeBtn:SetHandler("OnClick", closeBtn.OnClick)
        
        overlay.timerEndMs = 0
        overlay.createMs = 0
        spotOverlays[i] = overlay
    end
    LoadSpotTimers()
    
    local spotPosFile = "elu_spot_pos.txt"
    function spot_tracker.SaveSpotPositions()
        local posData = {}
        for i = 1, MAX_TIMERS do
            if spotOverlays[i] then
                local x, y = spotOverlays[i]:GetOffset()
                posData[i] = { x = x, y = y }
            end
        end
        EluTrackerSettings.spotPos = posData
        SaveEluTrackerSettings()
    end
    
    local function LoadSpotPositions()
        local data = EluTrackerSettings.spotPos
        if type(data) == "table" then
            for i = 1, MAX_TIMERS do
                if data[i] and data[i].x and data[i].y and spotOverlays[i] then
                    spotOverlays[i]:RemoveAllAnchors()
                    spotOverlays[i]:AddAnchor("TOPLEFT", "UIParent", data[i].x, data[i].y)
                end
            end
        end
    end
    LoadSpotPositions()
end

function spot_tracker:OnUpdate(dt)
    local nowMs = api.Time:GetUiMsec()

    local isModDown = false
    if spot_tracker.modifierKey == "SHIFT" then isModDown = api.Input:IsShiftKeyDown()
    elseif spot_tracker.modifierKey == "CTRL" then isModDown = api.Input:IsControlKeyDown()
    else isModDown = api.Input:IsAltKeyDown() end

    if spot_tracker.enableAltTracking and isModDown and lastDoodadInfo then
        local valid = false
        local spotName = string.lower(lastDoodadInfo.name or "")
        if string.find(spotName, "schooling") or string.find(spotName, "frenzy") then
            valid = true
        end
        if valid then
            spot_tracker.CaptureHoveredSpot()
        end
    end

    if pendingReplacementInfo then
        if not lastDoodadInfo or (nowMs - pendingReplacementInfo.time > 10000) then
            pendingReplacementInfo = nil
            if replaceWarning then replaceWarning:Show(false) end
        end
    end

    for i = 1, MAX_TIMERS do
        local overlay = spotOverlays[i]
        if overlay and overlay:IsVisible() then
            local remaining = overlay.timerEndMs - nowMs
            if not overlay.cachedDisplayName or overlay.cachedRawName ~= overlay.rawSpotName then
                local spotName = string.lower(overlay.rawSpotName or overlay.nameLabel:GetText() or "")
                spotName = spotName:gsub("<[^>]+>", "")
                
                local displayName = overlay.rawSpotName or "Spot"
                local labelColor = {1.0, 0.8, 0.2, 1.0} 
                
                local s_idx = string.find(spotName, " schooling")
                local f_idx = string.find(spotName, " feeding frenzy")
                
                if s_idx then
                    displayName = string.sub(displayName, 1, s_idx-1) .. "\nSchooling"
                    labelColor = {0.2, 0.8, 1.0, 1.0} 
                elseif f_idx then
                    displayName = string.sub(displayName, 1, f_idx-1) .. "\nFeeding Frenzy"
                    labelColor = {0.6, 0.2, 1.0, 1.0} 
                end
                
                overlay.cachedDisplayName = displayName
                overlay.cachedLabelColor = labelColor
                overlay.cachedRawName = overlay.rawSpotName
            end
            
            local displayName = overlay.cachedDisplayName
            local labelColor = overlay.cachedLabelColor
            
            if remaining > 0 then
                local totalSecs = math.ceil(remaining / 1000)
                local m = math.floor(totalSecs / 60)
                local s = totalSecs % 60
                
                if m > 59 then
                    local h = math.floor(m / 60)
                    m = m % 60
                    overlay.timerLabel:SetText(string.format("%02d:%02d:%02d", h, m, s))
                else
                    overlay.timerLabel:SetText(string.format("%02d:%02d", m, s))
                end
                
                if labelColor[1] == 0.2 then
                    if totalSecs <= 300 then ApplyTextColor(overlay.timerLabel, FONT_COLOR.RED) else ApplyTextColor(overlay.timerLabel, FONT_COLOR.WHITE) end
                elseif labelColor[1] == 0.6 then
                    if totalSecs <= 300 then ApplyTextColor(overlay.timerLabel, FONT_COLOR.RED) else ApplyTextColor(overlay.timerLabel, FONT_COLOR.WHITE) end
                else
                    ApplyTextColor(overlay.timerLabel, FONT_COLOR.WHITE)
                end
                
                overlay.nameLabel:SetText(displayName)
                ApplyTextColor(overlay.nameLabel, labelColor)
                
                if not overlay:IsVisible() then overlay:Show(true) end
            else
                overlay.timerLabel:SetText("00:00:00")
                local expireElapsed = -remaining
                if expireElapsed > 5000 then
                    overlay:Show(false)
                    SaveSpotTimers()
                else
                    if math.floor(expireElapsed / 500) % 2 == 0 then
                        ApplyTextColor(overlay.timerLabel, FONT_COLOR.RED)
                    else
                        ApplyTextColor(overlay.timerLabel, FONT_COLOR.WHITE)
                    end
                end
            end
        end
    end
end

function spot_tracker:OnUnload()
    if spot_tracker.masterOverlay then
        spot_tracker.masterOverlay:Show(false)
        spot_tracker.masterOverlay = nil
    end
    if doodadListener then
        doodadListener:Show(false)
        doodadListener = nil
    end

    if replaceWarning then
        replaceWarning:Show(false)
        replaceWarning = nil
    end

    for i = 1, MAX_TIMERS do
        if spotOverlays[i] then
            spotOverlays[i]:Show(false)
            spotOverlays[i] = nil
        end
    end
end

return spot_tracker
