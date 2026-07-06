local zeal_alert = {}

local zealOverlay = nil
local zealLabel = nil
local zealIcon = nil
local buffIdToTrack = 495
local trackedBuffInfo = {}
local zealSettingsFile = "elu_tracker/data_sessions/elu_zeal_settings.txt"

local settings = {
    enabled = true,
    scale = 1.0,
    x = 100,
    y = 100,
    moving = false
}

local function SaveSettings()
    if zealOverlay then
        local ox, oy = zealOverlay:GetOffset()
        if ox and oy then
            settings.x = ox
            settings.y = oy
        end
    end
    api.File:Write(zealSettingsFile, { 
        enabled = settings.enabled, 
        scale = settings.scale,
        x = settings.x,
        y = settings.y
    })
end

local function LoadSettings()
    local data = api.File:Read(zealSettingsFile)
    if type(data) == "table" then
        if data.enabled ~= nil then settings.enabled = data.enabled end
        if data.scale ~= nil then settings.scale = data.scale end
        if data.x ~= nil then settings.x = data.x end
        if data.y ~= nil then 
            settings.y = data.y
            if settings.y < 0 then settings.y = 100 end
        end
    end
end

local function ApplyScale()
    if zealOverlay then
        local scale = settings.scale or 1.0
        zealOverlay:RemoveAllAnchors()
        zealOverlay:AddAnchor("TOPLEFT", "UIParent", settings.x, settings.y)
        zealOverlay:SetExtent(math.floor(250 * scale), math.floor(140 * scale))
        if zealIcon then
            zealIcon:SetExtent(math.floor(48 * scale), math.floor(48 * scale))
        end
        if zealLabel then
            zealLabel.style:SetFontSize(math.floor(44 * scale))
            zealLabel:SetExtent(math.floor(250 * scale), math.floor(45 * scale))
        end
        if moveModeLabel then
            moveModeLabel.style:SetFontSize(math.floor(24 * scale))
            moveModeLabel:SetExtent(math.floor(200 * scale), math.floor(30 * scale))
        end
    end
end

function zeal_alert.CreateUI(wndParent)
    local container = wndParent:CreateChildWidget("emptywidget", "zealAlertContainer", 0, true)
    container:SetExtent(500, 150)
    container:AddAnchor("TOP", wndParent, 0, 360)
    
    local title = container:CreateChildWidget("label", "title", 0, true)
    title:SetAutoResize(true)
    title.style:SetFontSize(FONT_SIZE.XXLARGE)
    ApplyTextColor(title, FONT_COLOR.TITLE)
    title:SetText("Zeal Alert Settings")
    title:AddAnchor("TOP", container, 0, 0)
    
    local enableCheck = container:CreateChildWidget("checkbutton", "enableCheck", 0, true)
    enableCheck:SetExtent(18, 17)
    enableCheck:AddAnchor("TOP", title, "BOTTOM", -90, 20)
    local bg1 = enableCheck:CreateImageDrawable("ui/button/check_button.dds", "background")
    bg1:SetExtent(18, 17)
    bg1:AddAnchor("CENTER", enableCheck, 0, 0)
    bg1:SetCoords(0, 0, 18, 17)
    enableCheck:SetNormalBackground(bg1)
    
    local bg2 = enableCheck:CreateImageDrawable("ui/button/check_button.dds", "background")
    bg2:SetExtent(18, 17)
    bg2:AddAnchor("CENTER", enableCheck, 0, 0)
    bg2:SetCoords(18, 0, 18, 17)
    enableCheck:SetCheckedBackground(bg2)
    
    local bg3 = enableCheck:CreateImageDrawable("ui/button/check_button.dds", "background")
    bg3:SetExtent(18, 17)
    bg3:AddAnchor("CENTER", enableCheck, 0, 0)
    bg3:SetCoords(0, 0, 18, 17)
    enableCheck:SetPushedBackground(bg3)
    
    local bg4 = enableCheck:CreateImageDrawable("ui/button/check_button.dds", "background")
    bg4:SetExtent(18, 17)
    bg4:AddAnchor("CENTER", enableCheck, 0, 0)
    bg4:SetCoords(0, 0, 18, 17)
    enableCheck:SetHighlightBackground(bg4)
    
    local enableLbl = container:CreateChildWidget("label", "enableLbl", 0, true)
    enableLbl:SetAutoResize(true)
    enableLbl:SetText("Enable Zeal Alert")
    enableLbl:AddAnchor("LEFT", enableCheck, "RIGHT", 5, 0)
    ApplyTextColor(enableLbl, FONT_COLOR.DEFAULT)
    
    enableCheck:SetChecked(settings.enabled)
    
    local scaleLbl = container:CreateChildWidget("label", "scaleLbl", 0, true)
    scaleLbl:SetAutoResize(true)
    scaleLbl:SetText("Scale (0.5 to 2.0):")
    scaleLbl:AddAnchor("TOP", enableCheck, "BOTTOM", -50, 20)
    ApplyTextColor(scaleLbl, FONT_COLOR.DEFAULT)
    
    local scaleInput = W_CTRL.CreateEdit("scaleInput", container)
    scaleInput:SetExtent(50, 25)
    scaleInput:AddAnchor("LEFT", scaleLbl, "RIGHT", 10, 0)
    scaleInput.style:SetAlign(ALIGN.CENTER)
    scaleInput:SetText(tostring(settings.scale))
    
    local applyScaleBtn = container:CreateChildWidget("button", "applyScaleBtn", 0, true)
    applyScaleBtn:SetText("Apply Scale")
    applyScaleBtn:SetExtent(90, 25)
    applyScaleBtn:AddAnchor("LEFT", scaleInput, "RIGHT", 10, 0)
    ApplyButtonSkin(applyScaleBtn, BUTTON_BASIC.DEFAULT)
    
    function applyScaleBtn:OnClick()
        local newScale = tonumber(scaleInput:GetText())
        if newScale and newScale >= 0.1 and newScale <= 5.0 then
            settings.scale = newScale
            SaveSettings()
            ApplyScale()
        else
            scaleInput:SetText(tostring(settings.scale))
        end
    end
    applyScaleBtn:SetHandler("OnClick", applyScaleBtn.OnClick)
    
    local moveBtn = container:CreateChildWidget("button", "moveBtn", 0, true)
    moveBtn:SetText("Toggle Move Mode")
    moveBtn:SetExtent(130, 25)
    moveBtn:AddAnchor("LEFT", applyScaleBtn, "RIGHT", 10, 0)
    ApplyButtonSkin(moveBtn, BUTTON_BASIC.DEFAULT)
    
    local function UpdateVisibility()
        local isVis = settings.enabled
        scaleLbl:Show(isVis)
        scaleInput:Show(isVis)
        applyScaleBtn:Show(isVis)
        moveBtn:Show(isVis)
    end
    UpdateVisibility()
    
    function enableCheck:OnCheckChanged()
        settings.enabled = self:GetChecked()
        SaveSettings()
        UpdateVisibility()
        if not settings.enabled and zealOverlay then
            zealOverlay:Show(false)
            settings.moving = false
            if zealBg then zealBg:Show(false) end
        end
    end
    enableCheck:SetHandler("OnCheckChanged", enableCheck.OnCheckChanged)
    
    function moveBtn:OnClick()
        settings.moving = not settings.moving
        api.Log:Info("[ZealAlert] Move Mode toggled: " .. tostring(settings.moving))
        if settings.moving then
            zealOverlay:Show(true)
            if moveModeLabel then moveModeLabel:Show(true) end
            if zealLabel then 
                zealLabel:SetText("ZEAL IS UP")
            end
        else
            if moveModeLabel then moveModeLabel:Show(false) end
            if zealLabel then 
                zealLabel:SetText(string.format("%s IS UP", (trackedBuffInfo and trackedBuffInfo.name) or "ZEAL")) 
            end
            zealOverlay:Show(false)
        end
    end
    moveBtn:SetHandler("OnClick", moveBtn.OnClick)

    container:Show(true)
end

function zeal_alert:OnLoad()
    LoadSettings()
    trackedBuffInfo = api.Ability:GetBuffTooltip(buffIdToTrack)

    zealOverlay = api.Interface:CreateEmptyWindow("eluZealOverlay", "UIParent")
    zealOverlay:SetExtent(300, 60)
    zealOverlay:Show(false)
    zealOverlay:EnableDrag(true)

    function zealOverlay:OnDragStart() 
        if settings.moving then self:StartMoving() end 
    end
    zealOverlay:SetHandler("OnDragStart", zealOverlay.OnDragStart)

    function zealOverlay:OnDragStop() 
        self:StopMovingOrSizing() 
        SaveSettings()
    end
    zealOverlay:SetHandler("OnDragStop", zealOverlay.OnDragStop)

    zealIcon = CreateItemIconButton("zealIcon", zealOverlay)
    zealIcon:Show(true)
    F_SLOT.ApplySlotSkin(zealIcon, zealIcon.back, SLOT_STYLE.BUFF)
    zealIcon:AddAnchor("TOP", zealOverlay, "TOP", 0, 5)

    zealLabel = zealOverlay:CreateChildWidget("label", "label", 0, true)
    zealLabel:SetExtent(250, 45)
    zealLabel:SetText(string.format("%s IS UP", (trackedBuffInfo and trackedBuffInfo.name) or "ZEAL"))
    zealLabel:AddAnchor("TOP", zealIcon, "BOTTOM", 0, 5)
    zealLabel.style:SetFontSize(44)
    zealLabel.style:SetShadow(true)
    zealLabel.style:SetAlign(ALIGN.CENTER)
    
    moveModeLabel = zealOverlay:CreateChildWidget("button", "moveModeLabel", 0, true)
    moveModeLabel:SetExtent(200, 30)
    moveModeLabel:SetText("(MOVE MODE)")
    moveModeLabel:AddAnchor("TOP", zealLabel, "BOTTOM", 0, 2)
    moveModeLabel.style:SetFontSize(24)
    moveModeLabel.style:SetAlign(ALIGN.CENTER)
    ApplyTextColor(moveModeLabel, FONT_COLOR.BLACK)
    moveModeLabel:Show(false)
    
    zealBg = moveModeLabel:CreateColorDrawable(1, 1, 1, 0.9, "background")
    zealBg:AddAnchor("TOPLEFT", moveModeLabel, -5, -2)
    zealBg:AddAnchor("BOTTOMRIGHT", moveModeLabel, 5, 2)
    
    moveModeLabel:EnableDrag(true)
    function moveModeLabel:OnDragStart() if settings.moving then zealOverlay:StartMoving() end end
    moveModeLabel:SetHandler("OnDragStart", moveModeLabel.OnDragStart)
    function moveModeLabel:OnDragStop() zealOverlay:StopMovingOrSizing() SaveSettings() end
    moveModeLabel:SetHandler("OnDragStop", moveModeLabel.OnDragStop)

    if trackedBuffInfo and trackedBuffInfo.path then
        F_SLOT.SetIconBackGround(zealIcon, trackedBuffInfo.path)
    end

    ApplyScale()
end

function zeal_alert:OnUpdate(dt)
    if not settings.enabled then return end
    if settings.moving then return end
    
    if trackedBuffInfo == nil then return end
    
    local buffCount = api.Unit:UnitBuffCount("player")
    for i = 1, buffCount, 1 do
        local buff = api.Unit:UnitBuff("player", i)
        if buff and buff.buff_id == trackedBuffInfo.buff_id then
            if not zealOverlay:IsVisible() then
                zealOverlay:Show(true)
            end
            return
        end
    end

    if zealOverlay:IsVisible() then
        zealOverlay:Show(false)
    end
end

function zeal_alert:OnUnload()
    if zealOverlay then
        zealOverlay:Show(false)
        api.Interface:Free(zealOverlay)
        zealOverlay = nil
    end
end

return zeal_alert
