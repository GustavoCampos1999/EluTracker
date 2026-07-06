local stopwatch_addon = {}

local swOverlay = nil
local swRunning = false
local swElapsedMs = 0
local startTimeMs = 0
local swPosFile = "elu_tracker/data/elu_stopwatch_pos.txt"

local BSCBTN = {
    path = "ui/common/default.dds",
    fontColor = {
        normal = { 0.407843, 0.266667, 0.0705882, 1 },
        pushed = { 0.407843, 0.266667, 0.0705882, 1 },
        highlight = { 0.603922, 0.376471, 0.0627451, 1 },
        disabled = { 0.360784, 0.360784, 0.360784, 1 },
    },
    coords = {
        normal = { 727, 247, 60, 25 },
        disable = { 788, 273, 60, 25 },
        over = { 727, 273, 60, 25 },
        click = { 788, 247, 60, 25 },
    },
    fontInset = { top = 0, right = 11, left = 11, bottom = 0 },
    width = 30,
    height = 24,
    autoResize = true,
    drawableType = "ninePart",
    coordsKey = "btn",
}

local function SavePosition()
    if swOverlay then
        local x, y = swOverlay:GetOffset()
        if x and y then
            api.File:Write(swPosFile, { x = x, y = y })
        end
    end
end

local function LoadPosition()
    local data = api.File:Read(swPosFile)
    if type(data) == "table" and data.x and data.y then
        swOverlay:RemoveAllAnchors()
        swOverlay:AddAnchor("TOPLEFT", "UIParent", data.x, data.y)
    end
end

function stopwatch_addon:OnLoad()
    swOverlay = api.Interface:CreateEmptyWindow("eluStopwatchOverlay", "UIParent")
    swOverlay:SetExtent(170, 95)
    swOverlay:AddAnchor("TOPLEFT", "UIParent", 500, 250)
    swOverlay:Show(false)
    swOverlay:EnableDrag(true)

    function swOverlay:OnDragStart() self:StartMoving() end
    swOverlay:SetHandler("OnDragStart", swOverlay.OnDragStart)

    function swOverlay:OnDragStop() 
        self:StopMovingOrSizing() 
        SavePosition()
    end
    swOverlay:SetHandler("OnDragStop", swOverlay.OnDragStop)

    local bg = swOverlay:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bg:SetTextureInfo("bg_quest")
    bg:SetColor(0, 0, 0, 0.6)
    bg:AddAnchor("TOPLEFT", swOverlay, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", swOverlay, 0, 0)
    
    local clockIcon = swOverlay:CreateChildWidget("label", "clockIcon", 0, true)  
    clockIcon:AddAnchor("TOPLEFT", swOverlay, 10, 2)
    local clockIconTexture = clockIcon:CreateImageDrawable(TEXTURE_PATH.HUD, "background")
    clockIconTexture:SetTextureInfo("clock")
    clockIconTexture:AddAnchor("TOPLEFT", clockIcon, 0, 0)

    local titleLabel = swOverlay:CreateChildWidget("label", "titleLabel", 0, true)
    titleLabel.style:SetShadow(true)
    titleLabel.style:SetAlign(ALIGN.CENTER)
    titleLabel:AddAnchor("TOP", swOverlay, "TOP", 0, 15)
    titleLabel.style:SetFontSize(FONT_SIZE.LARGE)
    titleLabel:SetText("Stopwatch")

    local clockLabel = swOverlay:CreateChildWidget("label", "clockLabel", 0, true)
    clockLabel.style:SetShadow(true)
    clockLabel.style:SetAlign(ALIGN.CENTER)
    clockLabel:AddAnchor("CENTER", swOverlay, -5, -3)
    clockLabel.style:SetFontSize(FONT_SIZE.XLARGE)
    clockLabel:SetText("00:00:00")
    swOverlay.clockLabel = clockLabel

    local startBtn = swOverlay:CreateChildWidget("button", "startBtn", 0, true)  
    startBtn:AddAnchor("BOTTOM", swOverlay, -50, -10)
    startBtn:SetText("Start")
    api.Interface:ApplyButtonSkin(startBtn, BSCBTN)
    
    local stopBtn = swOverlay:CreateChildWidget("button", "stopBtn", 0, true)  
    stopBtn:AddAnchor("BOTTOM", swOverlay, 0, -10)
    stopBtn:SetText("Stop")
    api.Interface:ApplyButtonSkin(stopBtn, BSCBTN)

    local restartBtn = swOverlay:CreateChildWidget("button", "restartBtn", 0, true)  
    restartBtn:AddAnchor("BOTTOM", swOverlay, 50, -10)
    restartBtn:SetText("Reset")
    api.Interface:ApplyButtonSkin(restartBtn, BSCBTN)

    function startBtn:OnClick()
        if not swRunning then
            swRunning = true
            startTimeMs = api.Time:GetUiMsec()
        end
    end
    startBtn:SetHandler("OnClick", startBtn.OnClick)

    function stopBtn:OnClick()
        if swRunning then
            swElapsedMs = swElapsedMs + (api.Time:GetUiMsec() - startTimeMs)
            swRunning = false
        end
    end
    stopBtn:SetHandler("OnClick", stopBtn.OnClick)

    function restartBtn:OnClick()
        swElapsedMs = 0
        swRunning = false
        swOverlay.clockLabel:SetText("00:00:00")
    end
    restartBtn:SetHandler("OnClick", restartBtn.OnClick)

    LoadPosition()
end

function stopwatch_addon.ToggleStopwatch()
    if swOverlay then
        local isVisible = not swOverlay:IsVisible()
        swOverlay:Show(isVisible)
    end
end

function stopwatch_addon:OnUpdate(dt)
    if swOverlay and swOverlay:IsVisible() then
        local currentElapsed = swElapsedMs
        if swRunning then
            currentElapsed = currentElapsed + (api.Time:GetUiMsec() - startTimeMs)
        end
        
        local totalSecs = math.floor(currentElapsed / 1000)
        local h = math.floor(totalSecs / 3600)
        local m = math.floor((totalSecs % 3600) / 60)
        local s = totalSecs % 60
        
        if h > 0 then
            swOverlay.clockLabel:SetText(string.format("%02d:%02d:%02d", h, m, s))
        else
            swOverlay.clockLabel:SetText(string.format("%02d:%02d", m, s))
        end
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
