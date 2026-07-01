local spot_tracker = {}

local MAX_TIMERS = 3
local spotOverlays = {}

local doodadListener = nil
local lastDoodadInfo = nil
local lastCaptureMs = 0

spot_tracker.enableAltTracking = false

local pendingReplacementInfo = nil
local replaceWarning = nil

local function LoadMiscSettings()
    local data = api.File:Read("elu_tracker_misc.txt")
    if type(data) == "table" then
        if data.enableAltTracking ~= nil then spot_tracker.enableAltTracking = data.enableAltTracking end
        if data.modifierKey ~= nil then spot_tracker.modifierKey = data.modifierKey else spot_tracker.modifierKey = "ALT" end
    else
        spot_tracker.enableAltTracking = false
        spot_tracker.modifierKey = "ALT"
    end
end

local function SaveMiscSettings()
    api.File:Write("elu_tracker_misc.txt", { enableAltTracking = spot_tracker.enableAltTracking, modifierKey = spot_tracker.modifierKey })
end

function spot_tracker.CreateUI(wndParent)
    local anchorWidget = wndParent.resetBtn or wndParent
    local yOffset = wndParent.resetBtn and 40 or 250

    if wndParent.altToggle then wndParent.altToggle:Show(false) end
    if wndParent.altLbl then wndParent.altLbl:Show(false) end

    local titleSpot = wndParent:CreateChildWidget("label", "titleSpot", 0, true)
    titleSpot:SetAutoResize(true)
    titleSpot.style:SetFontSize(FONT_SIZE.XXLARGE)
    ApplyTextColor(titleSpot, FONT_COLOR.TITLE)
    titleSpot:SetText("Fishing Spot")
    if anchorWidget == wndParent then
        titleSpot:AddAnchor("TOP", anchorWidget, 0, yOffset)
    else
        titleSpot:AddAnchor("TOP", anchorWidget, "BOTTOM", 0, yOffset)
    end

    local desc = wndParent:CreateChildWidget("label", "descSpot", 0, true)
    ApplyTextColor(desc, FONT_COLOR.DEFAULT)
    desc:SetText("Hover over a Fishing Spot or Pack and press ALT to track.")
    desc:AddAnchor("TOP", titleSpot, "BOTTOM", 0, 30)

    if eluAltToggleContainer then eluAltToggleContainer:Show(false) end
    if eluAltToggleCheck then eluAltToggleCheck:Show(false) end
    if eluAltToggleLbl then eluAltToggleLbl:Show(false) end

    if altToggle then altToggle:Show(false) end
    if altLbl then altLbl:Show(false) end

    local container = wndParent:CreateChildWidget("emptywidget", "eluAltToggleContainer", 0, true)
    container:SetExtent(200, 30)
    container:AddAnchor("TOP", desc, "BOTTOM", 0, 10)

    local altToggle = container:CreateChildWidget("checkbutton", "eluAltToggleCheck", 0, true)
    altToggle:SetExtent(18, 17)
    altToggle:AddAnchor("LEFT", container, 15, 6)
    
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

    LoadMiscSettings()
    altToggle:SetChecked(spot_tracker.enableAltTracking)
    
    local modBtn = container:CreateChildWidget("button", "eluTrackerModBtn", 0, true)
    modBtn:SetExtent(60, 25)
    modBtn:AddAnchor("LEFT", altLbl, "RIGHT", 10, 0)
    ApplyButtonSkin(modBtn, BUTTON_BASIC.DEFAULT)
    
    if not spot_tracker.modifierKey then spot_tracker.modifierKey = "ALT" end
    modBtn:SetText(spot_tracker.modifierKey)
    
    function modBtn:OnClick()
        if spot_tracker.modifierKey == "ALT" then spot_tracker.modifierKey = "SHIFT"
        elseif spot_tracker.modifierKey == "SHIFT" then spot_tracker.modifierKey = "CTRL"
        else spot_tracker.modifierKey = "ALT" end
        self:SetText(spot_tracker.modifierKey)
        SaveMiscSettings()
    end
    modBtn:SetHandler("OnClick", modBtn.OnClick)

    function altToggle:OnCheckChanged()
        spot_tracker.enableAltTracking = self:GetChecked()
        SaveMiscSettings()
    end
    altToggle:SetHandler("OnCheckChanged", altToggle.OnCheckChanged)
end

function spot_tracker.CaptureHoveredSpot()
    if not lastDoodadInfo then return false end
    
    local nowMs = api.Time:GetUiMsec()
    if nowMs - lastCaptureMs < 1000 then return false end 
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
        if overlay.createMs < oldestOverlay.createMs then
            oldestOverlay = overlay
        end
    end
    
    if not targetOverlay then
        if not pendingReplacementInfo then
            pendingReplacementInfo = { name = spotNameStr, endMs = newTimerEndMs, target = oldestOverlay, time = nowMs }
            if replaceWarning then replaceWarning:Show(true) end
            api.Log:Info("[Elu Tracker] Spot limit reached. Press ALT again to replace oldest.")
            return true
        else
            if nowMs - pendingReplacementInfo.time > 500 then
                targetOverlay = pendingReplacementInfo.target
                newTimerEndMs = pendingReplacementInfo.endMs
                spotNameStr = pendingReplacementInfo.name
                pendingReplacementInfo = nil
                if replaceWarning then replaceWarning:Show(false) end
                api.Log:Info("[Elu Tracker] Replaced oldest tracker with new one!")
            else
                return true
            end
        end
    end
    
    if targetOverlay then
        targetOverlay.createMs = nowMs
        targetOverlay.timerEndMs = newTimerEndMs
        targetOverlay.rawSpotName = spotNameStr
        
        local mins = math.floor(exactTimeSeconds / 60)
        api.Log:Info(string.format("[Elu Tracker] '%s' marked with %d mins timer!", spotNameStr, mins))
        targetOverlay:Show(true)
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
    rwLbl:SetText("Press ALT again to replace oldest timer! (Move/Wait 5s to cancel)")
    rwLbl.style:SetFontSize(FONT_SIZE.LARGE)
    ApplyTextColor(rwLbl, FONT_COLOR.RED)
    rwLbl:AddAnchor("CENTER", replaceWarning, 0, 0)
    replaceWarning:Show(false)

    for i = 1, MAX_TIMERS do
        local overlay = api.Interface:CreateEmptyWindow("eluSpotOverlay"..i, "UIParent")
        overlay:SetExtent(200, 100)
        overlay:AddAnchor("TOPLEFT", "UIParent", 500, 100 + ((i-1)*110))
        overlay:Show(false)
        overlay:EnableDrag(true)

        function overlay:OnDragStart() self:StartMoving() end
        overlay:SetHandler("OnDragStart", overlay.OnDragStart)

        function overlay:OnDragStop() self:StopMovingOrSizing() end
        overlay:SetHandler("OnDragStop", overlay.OnDragStop)
        
        local bg = overlay:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
        bg:SetTextureInfo("bg_quest")
        bg:SetColor(0, 0, 0, 0.8)
        bg:AddAnchor("TOPLEFT", overlay, 0, 0)
        bg:AddAnchor("BOTTOMRIGHT", overlay, 0, 0)
        
        local nameLabel = overlay:CreateChildWidget("textbox", "nameLabel", 0, true)
        nameLabel:SetExtent(180, 40)
        nameLabel:AddAnchor("TOP", overlay, 0, 10)
        nameLabel.style:SetAlign(ALIGN.CENTER)
        nameLabel.style:SetFontSize(FONT_SIZE.LARGE)
        nameLabel:SetText("Spot")
        overlay.nameLabel = nameLabel
        
        local timerLabel = overlay:CreateChildWidget("label", "timerLabel", 0, true)
        timerLabel:AddAnchor("TOP", nameLabel, "BOTTOM", 0, 5)
        timerLabel.style:SetFontSize(FONT_SIZE.XXLARGE)
        timerLabel:SetText("00:00")
        overlay.timerLabel = timerLabel

        local closeBtn = overlay:CreateChildWidget("button", "closeBtn", 0, true)
        closeBtn:SetText("X")
        closeBtn:SetExtent(16, 16)
        closeBtn:AddAnchor("TOPRIGHT", overlay, -5, 5)
        closeBtn.style:SetAlign(ALIGN.CENTER)
        ApplyTextColor(closeBtn, FONT_COLOR.RED)
        function closeBtn:OnClick() overlay:Show(false) end
        closeBtn:SetHandler("OnClick", closeBtn.OnClick)
        
        overlay.timerEndMs = 0
        overlay.createMs = 0
        spotOverlays[i] = overlay
    end
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
            local spotName = string.lower(overlay.rawSpotName or overlay.nameLabel:GetText() or "")
            spotName = spotName:gsub("<[^>]+>", "")
            local hexColor = "#FFFFFF"
            
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
                
                local labelColor = {1.0, 0.8, 0.2, 1.0} 
                if string.find(spotName, "schooling") then
                    labelColor = {0.2, 0.8, 1.0, 1.0} 
                    if totalSecs <= 300 then ApplyTextColor(overlay.timerLabel, FONT_COLOR.RED) else ApplyTextColor(overlay.timerLabel, FONT_COLOR.WHITE) end
                elseif string.find(spotName, "frenzy") then
                    labelColor = {0.6, 0.2, 1.0, 1.0} 
                    if totalSecs <= 300 then ApplyTextColor(overlay.timerLabel, FONT_COLOR.RED) else ApplyTextColor(overlay.timerLabel, FONT_COLOR.WHITE) end
                else
                    ApplyTextColor(overlay.timerLabel, FONT_COLOR.WHITE)
                end
                
                overlay.nameLabel:SetText(overlay.rawSpotName or spotName)
                ApplyTextColor(overlay.nameLabel, labelColor)
                
                if not overlay:IsVisible() then overlay:Show(true) end
            else
                overlay.timerLabel:SetText("00:00:00")
                local expireElapsed = -remaining
                if expireElapsed > 5000 then
                    overlay:Show(false)
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
    if doodadListener then
        api.Interface:Free(doodadListener)
        doodadListener = nil
    end

    if replaceWarning then
        replaceWarning:Show(false)
        api.Interface:Free(replaceWarning)
        replaceWarning = nil
    end

    for i = 1, MAX_TIMERS do
        if spotOverlays[i] then
            spotOverlays[i]:Show(false)
            api.Interface:Free(spotOverlays[i])
            spotOverlays[i] = nil
        end
    end
end

return spot_tracker
