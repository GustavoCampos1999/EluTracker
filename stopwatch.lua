local stopwatch_addon = {}

local swOverlay = nil
local swRunning = false
local swElapsedMs = 0

local function ConvertColor(color) return color / 255 end 

function stopwatch_addon:OnLoad()
    swOverlay = api.Interface:CreateEmptyWindow("eluStopwatchOverlay", "UIParent")
    swOverlay:SetExtent(180, 100)
    swOverlay:AddAnchor("TOPLEFT", "UIParent", 500, 250)
    swOverlay:Show(false)
    swOverlay:EnableDrag(true)

    function swOverlay:OnDragStart() self:StartMoving() end
    swOverlay:SetHandler("OnDragStart", swOverlay.OnDragStart)

    function swOverlay:OnDragStop() self:StopMovingOrSizing() end
    swOverlay:SetHandler("OnDragStop", swOverlay.OnDragStop)

    local bg = swOverlay:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bg:SetTextureInfo("bg_quest")
    bg:SetColor(0, 0, 0, 0.7)
    bg:AddAnchor("TOPLEFT", swOverlay, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", swOverlay, 0, 0)

    local closeBtn = swOverlay:CreateChildWidget("button", "closeBtn", 0, true)
    closeBtn:SetText("X")
    closeBtn:SetExtent(16, 16)
    closeBtn:AddAnchor("TOPRIGHT", swOverlay, -5, 5)
    closeBtn.style:SetAlign(ALIGN.CENTER)
    ApplyTextColor(closeBtn, FONT_COLOR.RED)
    function closeBtn:OnClick() swOverlay:Show(false) end
    closeBtn:SetHandler("OnClick", closeBtn.OnClick)

    local timeLabel = swOverlay:CreateChildWidget("label", "timeLabel", 0, true)
    timeLabel:AddAnchor("TOP", swOverlay, 0, 20)
    timeLabel.style:SetFontSize(FONT_SIZE.XXLARGE)
    timeLabel:SetText("00:00:00")
    ApplyTextColor(timeLabel, FONT_COLOR.WHITE)
    swOverlay.timeLabel = timeLabel

    local playBtn = swOverlay:CreateChildWidget("button", "playBtn", 0, true)
    playBtn:SetText("Start")
    playBtn:SetExtent(60, 25)
    playBtn:AddAnchor("BOTTOMLEFT", swOverlay, 20, -15)
    ApplyButtonSkin(playBtn, BUTTON_BASIC.DEFAULT)
    swOverlay.playBtn = playBtn

    function playBtn:OnClick()
        swRunning = not swRunning
        if swRunning then
            swOverlay.playBtn:SetText("Pause")
        else
            swOverlay.playBtn:SetText("Start")
        end
    end
    playBtn:SetHandler("OnClick", playBtn.OnClick)

    local resetBtn = swOverlay:CreateChildWidget("button", "resetBtn", 0, true)
    resetBtn:SetText("Reset")
    resetBtn:SetExtent(60, 25)
    resetBtn:AddAnchor("BOTTOMRIGHT", swOverlay, -20, -15)
    ApplyButtonSkin(resetBtn, BUTTON_BASIC.DEFAULT)
    function resetBtn:OnClick()
        swRunning = false
        swElapsedMs = 0
        swOverlay.timeLabel:SetText("00:00:00")
        swOverlay.playBtn:SetText("Start")
    end
    resetBtn:SetHandler("OnClick", resetBtn.OnClick)
end

function stopwatch_addon.ToggleStopwatch()
    if swOverlay then
        local isVisible = not swOverlay:IsVisible()
        swOverlay:Show(isVisible)
    end
end

function stopwatch_addon:OnUpdate(dt)
    if swRunning and swOverlay and swOverlay:IsVisible() then
        swElapsedMs = swElapsedMs + dt
        
        local totalSecs = math.floor(swElapsedMs / 1000)
        local h = math.floor(totalSecs / 3600)
        local m = math.floor((totalSecs % 3600) / 60)
        local s = totalSecs % 60
        
        swOverlay.timeLabel:SetText(string.format("%02d:%02d:%02d", h, m, s))
    end
end

function stopwatch_addon:OnUnload()
    if swOverlay then
        swOverlay:Show(false)
        api.Interface:Free(swOverlay)
        swOverlay = nil
    end
end

return stopwatch_addon
