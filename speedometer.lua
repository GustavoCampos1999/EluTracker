local api = require("api")
local settingsManager = require("Elu_Tracker/settings_manager")
local EluTrackerSettings = settingsManager.Settings
local SaveEluTrackerSettings = settingsManager.SaveSettings

local speedometer_addon = {
    name = "Speedometer",
    author = "Aguru / Eludelu",
    version = "1.0.0",
    desc = "Siege weapon / vehicle speedometer"
}

local SANE_COORD_LIMIT = 10000

local canvas = nil
local speedBar = nil
local speedLabel = nil
local dragOverlay = nil
local maxSpeedValue = 50
local lastRoundedSpeed10 = nil

local settings = {
    enabled = false,
    x = nil,
    y = nil,
    customPos = false
}

local function ConvertColor(color)
    return color / 255
end

local function LoadSpeedometerSettings()
    local data = EluTrackerSettings.speedometer
    if type(data) == "table" then
        if data.enabled ~= nil then
            settings.enabled = data.enabled and true or false
        end
        if type(data.x) == "number" and math.abs(data.x) <= SANE_COORD_LIMIT and
           type(data.y) == "number" and math.abs(data.y) <= SANE_COORD_LIMIT then
            settings.x = data.x
            settings.y = data.y
        end
        if data.customPos ~= nil then
            settings.customPos = (data.customPos == true)
        end
    end
end

local function SaveSpeedometerSettings()
    EluTrackerSettings.speedometer = {
        enabled = settings.enabled,
        x = settings.x,
        y = settings.y,
        customPos = settings.customPos
    }
    pcall(SaveEluTrackerSettings)
end

-- Load immediately at require-time so CreateUI (which runs inside
-- CreateWindow's subWindowConstructor before module OnLoad) sees the
-- saved state instead of the default false.
LoadSpeedometerSettings()

local function ApplyPosition()
    if not canvas then return end
    canvas:RemoveAllAnchors()
    if settings.customPos and type(settings.x) == "number" and type(settings.y) == "number" then
        canvas:AddAnchor("TOPLEFT", "UIParent", settings.x, settings.y)
    else
        canvas:AddAnchor("TOP", "UIParent", "TOP", 10, 44)
    end
end

local function StartMoving()
    if not canvas then return end
    if not api.Input:IsShiftKeyDown() then return end
    canvas:StartMoving()
    api.Cursor:ClearCursor()
    api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
end

local function StopMoving()
    if not canvas then return end
    canvas:StopMovingOrSizing()
    api.Cursor:ClearCursor()
    local x, y = canvas:GetOffset()
    if type(x) == "number" and type(y) == "number" and
       math.abs(x) <= SANE_COORD_LIMIT and math.abs(y) <= SANE_COORD_LIMIT then
        settings.x = x
        settings.y = y
        settings.customPos = true
        SaveSpeedometerSettings()
    end
end

local function WireShiftDrag(widget)
    if not widget then return end
    pcall(function() widget:EnableDrag(true) end)
    function widget:OnDragStart()
        StartMoving()
    end
    widget:SetHandler("OnDragStart", widget.OnDragStart)
    function widget:OnDragStop()
        StopMoving()
    end
    widget:SetHandler("OnDragStop", widget.OnDragStop)
end

local function destroySpeedometerUI()
    if canvas then
        canvas:Show(false)
        pcall(function() api.Interface:Free(canvas) end)
        canvas = nil
    end
    speedBar = nil
    speedLabel = nil
    dragOverlay = nil
end

local function createSpeedometerUI()
    destroySpeedometerUI()
    maxSpeedValue = 50

    canvas = api.Interface:CreateEmptyWindow("speedometer")
    canvas:Show(false)
    canvas:SetExtent(255, 20)

    speedBar = api.Interface:CreateStatusBar("speedo", canvas, "item_evolving_material")
    speedBar:SetBarColor({ ConvertColor(222), ConvertColor(177), ConvertColor(102), 1 })
    if speedBar.bg then
        speedBar.bg:SetColor(ConvertColor(76), ConvertColor(45), ConvertColor(8), 0.4)
    end
    speedBar:SetMinMaxValues(0, maxSpeedValue)
    speedBar:AddAnchor("TOPLEFT", canvas, 25, 1)
    speedBar:AddAnchor("BOTTOMRIGHT", canvas, -1, 1)

    speedLabel = canvas:CreateChildWidget("label", "speedLabel", 0, true)
    speedLabel:AddAnchor("TOPLEFT", speedBar, 110, 10)
    speedLabel:SetText("SPEED")
    if speedLabel.Clickable then
        pcall(function() speedLabel:Clickable(false) end)
    end

    -- Transparent top overlay so Shift + drag works across the entire
    -- status bar surface as well as the window frame.
    dragOverlay = canvas:CreateChildWidget("emptywidget", "speedoDragOverlay", 0, true)
    dragOverlay:AddAnchor("TOPLEFT", canvas, 0, 0)
    dragOverlay:AddAnchor("BOTTOMRIGHT", canvas, 0, 0)
    dragOverlay:Show(true)

    WireShiftDrag(canvas)
    WireShiftDrag(speedBar)
    WireShiftDrag(dragOverlay)

    ApplyPosition()
end

local function setEnabled(enabled)
    settings.enabled = enabled and true or false
    SaveSpeedometerSettings()
    if settings.enabled then
        createSpeedometerUI()
    else
        destroySpeedometerUI()
    end
end

function speedometer_addon.CreateUI(wndParent)
    LoadSpeedometerSettings()

    local container = wndParent:CreateChildWidget("emptywidget", "speedometerMiscSection", 0, true)
    container:SetExtent(500, 26)

    local enableCheck = container:CreateChildWidget("checkbutton", "speedometerEnableCheck", 0, true)
    enableCheck:SetExtent(18, 17)
    enableCheck:AddAnchor("TOPLEFT", container, 0, 4)

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
    bg4:SetCoords(18, 0, 18, 17)
    enableCheck:SetHighlightBackground(bg4)

    local enableLbl = container:CreateChildWidget("label", "speedometerEnableLbl", 0, true)
    enableLbl:SetAutoResize(true)
    enableLbl:SetText("Speedometer: Enable speed bar")
    enableLbl:AddAnchor("LEFT", enableCheck, "RIGHT", 6, 0)
    ApplyTextColor(enableLbl, FONT_COLOR.DEFAULT)

    local checkboxGap = 6
    local labelWidth = enableLbl:GetWidth() or 200
    local totalWidth = 18 + checkboxGap + labelWidth
    local containerWidth = container:GetWidth() or 500
    local startX = math.floor((containerWidth - totalWidth) / 2)
    enableCheck:RemoveAllAnchors()
    enableCheck:AddAnchor("TOPLEFT", container, startX, 4)

    enableCheck:SetChecked(settings.enabled, false)

    function enableCheck:OnCheckChanged()
        setEnabled(self:GetChecked())
    end
    enableCheck:SetHandler("OnCheckChanged", enableCheck.OnCheckChanged)

    -- Small native reset arrow button to the right of the label, matching Quick Equip
    local resetPosBtn = container:CreateChildWidget("button", "speedometerResetPosBtn", 0, true)
    resetPosBtn:AddAnchor("LEFT", enableLbl, "RIGHT", 12, 0)
    api.Interface:ApplyButtonSkin(resetPosBtn, BUTTON_BASIC.RESET)

    function resetPosBtn:OnEnter()
        local x, y = self:GetOffset()
        api.Interface:SetTooltipOnPos("Resets the Speedometer to its default position.\nHold Shift + drag the bar to move it.", container, x, y + 25)
    end
    function resetPosBtn:OnLeave()
        local x, y = self:GetOffset()
        api.Interface:SetTooltipOnPos(nil, container, x, y + 25)
    end
    resetPosBtn:SetHandler("OnEnter", resetPosBtn.OnEnter)
    resetPosBtn:SetHandler("OnLeave", resetPosBtn.OnLeave)

    function resetPosBtn:OnClick()
        settings.x = nil
        settings.y = nil
        settings.customPos = false
        SaveSpeedometerSettings()
        if settings.enabled and canvas then
            ApplyPosition()
        elseif settings.enabled then
            createSpeedometerUI()
        end
    end
    resetPosBtn:SetHandler("OnClick", resetPosBtn.OnClick)

    return container
end

function speedometer_addon.OnUpdate(dt)
    if not settings.enabled then
        if canvas and canvas:IsVisible() then
            canvas:Show(false)
        end
        return
    end

    if not canvas then
        createSpeedometerUI()
    end

    if not api.SiegeWeapon or not api.SiegeWeapon.GetSiegeWeaponSpeed then
        return
    end

    local speed = api.SiegeWeapon:GetSiegeWeaponSpeed()
    if not speed or speed == 0 then
        if canvas:IsVisible() then
            canvas:Show(false)
        end
        return
    end

    local absSpeed10 = math.abs(speed * 10)
    if absSpeed10 > maxSpeedValue then
        maxSpeedValue = absSpeed10
        speedBar:SetMinMaxValues(0, maxSpeedValue)
    end

    if not canvas:IsVisible() then
        canvas:Show(true)
        lastRoundedSpeed10 = nil
    end
    local rounded = math.floor(absSpeed10 + 0.5)
    if rounded ~= lastRoundedSpeed10 then
        lastRoundedSpeed10 = rounded
        speedBar:SetValue(absSpeed10)
        speedLabel:SetText(string.format("%.1fm/s", speed))
    end
end

function speedometer_addon.OnLoad()
    LoadSpeedometerSettings()
    if settings.enabled then
        createSpeedometerUI()
    end
end

function speedometer_addon.OnUnload()
    SaveSpeedometerSettings()
    destroySpeedometerUI()
end

return speedometer_addon
