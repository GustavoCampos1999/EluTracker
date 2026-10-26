local api = require("api")
local settingsManager = require("Elu_Tracker/settings_manager")
local settings = settingsManager.Settings.rangeMeterSettings
local SaveSettings = settingsManager.SaveSettings

local range_meter = {}

-- Same fix as guild_check.lua's stepper buttons and the same root cause:
-- BUTTON_BASIC.DEFAULT's native skin has a fixed minimum render size well
-- beyond a 20x20 box, so a tiny stepper button using it renders visually
-- oversized regardless of :SetExtent(). Swapped in the addon's own smaller
-- nine-slice skin (copied verbatim from stopwatch.lua's proven-working BSCBTN).
local SMALL_BTN_SKIN = {
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
    drawableType = "ninePart",
    coordsKey = "btn",
}

local canvas = nil
local rangeLabel = nil
local dynWnd = nil
local dynChk = nil
local varietyCombo = nil
local t1Edit, t2Edit = nil, nil
local t1PreLbl, t1PostLbl = nil, nil
local t2PreLbl, t2PostLbl = nil, nil
local t3Lbl = nil
local swatch1, swatch2, swatch3 = nil, nil, nil
local paletteButtons1, paletteButtons2, paletteButtons3 = {}, {}, {}
local r1Row, r2Row, r3Row = nil, nil, nil
local alphaGrp = nil

local POSITIONS = { "Top", "Bottom", "Left", "Right" }

local cachedTargetId = nil
local cachedTargetValid = true
local targetInfoRetryTimer = 0
local lastRoundedDist10 = nil
local lastR, lastG, lastB, lastA = nil, nil, nil, nil
local lateHookRegistered = false
local raiseTimer = 0

-- Exact original 8 colors from upstream
local PALETTE_COLORS = {
    { r = 1, g = 1,   b = 1   }, -- White
    { r = 1, g = 0,   b = 0   }, -- Red
    { r = 0, g = 1,   b = 0   }, -- Green
    { r = 0, g = 0,   b = 1   }, -- Blue
    { r = 1, g = 1,   b = 0   }, -- Yellow
    { r = 1, g = 0.5, b = 0   }, -- Orange
    { r = 0, g = 1,   b = 1   }, -- Cyan
    { r = 1, g = 0,   b = 1   }, -- Magenta
}

local function GetColorIndex(color)
    if not color then return 1 end
    for i, col in ipairs(PALETTE_COLORS) do
        if math.abs(col.r - (color.r or 1)) < 0.05 and
           math.abs(col.g - (color.g or 1)) < 0.05 and
           math.abs(col.b - (color.b or 1)) < 0.05 then
            return i
        end
    end
    return 1
end

local function GetPositionIndex(posStr)
    for i, v in ipairs(POSITIONS) do
        if v == posStr then return i end
    end
    return 1
end

local function ForceUpdateRangeLabel()
    lastRoundedDist10 = nil
    lastR, lastG, lastB, lastA = nil, nil, nil, nil
    if canvas and canvas:IsVisible() and range_meter.OnUpdate then
        range_meter.OnUpdate(0)
    end
end

local function UpdateRangeLabels()
    local t1 = tonumber(settings.threshold1) or 28
    local t2 = tonumber(settings.threshold2) or 33
    local variety = settings.colorVariety or 3
    if t2PreLbl then
        if variety == 2 then
            t2PreLbl:SetText(string.format("> %dm:", t1))
        else
            t2PreLbl:SetText(string.format("%dm to", t1))
        end
    end
    if t3Lbl then
        t3Lbl:SetText(string.format("> %dm:", t2))
    end
end

local function UpdateVarietyDisplay()
    local variety = settings.colorVariety or 3
    if variety == 2 then
        if t2Edit then t2Edit:Show(false) end
        if t2PostLbl then t2PostLbl:Show(false) end
        if t2PreLbl then
            t2PreLbl:SetText(string.format("> %dm:", tonumber(settings.threshold1) or 28))
        end
        if r3Row then r3Row:Show(false) end
    else
        if t2Edit then t2Edit:Show(true) end
        if t2PostLbl then t2PostLbl:Show(true) end
        if t2PreLbl then
            t2PreLbl:SetText(string.format("%dm to", tonumber(settings.threshold1) or 28))
        end
        if r3Row then r3Row:Show(true) end
        if t3Lbl then
            t3Lbl:SetText(string.format("> %dm:", tonumber(settings.threshold2) or 33))
        end
    end
    UpdateRangeLabels()
end

local function RefreshAllColorDisplays()
    local c1 = settings.c1 or {r=0, g=1, b=0}
    local c2 = settings.c2 or {r=1, g=1, b=0}
    local c3 = settings.c3 or {r=1, g=0, b=0}
    if swatch1 then swatch1:SetColor(c1.r, c1.g, c1.b) end
    if swatch2 then swatch2:SetColor(c2.r, c2.g, c2.b) end
    if swatch3 then swatch3:SetColor(c3.r, c3.g, c3.b) end
end

local function RefreshDynWnd()
    if not dynWnd then return end
    if dynChk then dynChk:SetChecked(settings.useDynamicColor or false) end
    if varietyCombo then
        local variety = settings.colorVariety or 3
        varietyCombo:Select(variety == 2 and 1 or 2)
    end
    if alphaGrp then alphaGrp:SetValue(math.floor((settings.alpha or 1.0) * 10)) end
    if t1Edit then t1Edit:SetText(tostring(settings.threshold1 or 28)) end
    if t2Edit then t2Edit:SetText(tostring(settings.threshold2 or 33)) end
    UpdateVarietyDisplay()
    UpdateRangeLabels()
    RefreshAllColorDisplays()
end

function range_meter.OnUpdate(dt)
    if not settings.enabled then
        if canvas then canvas:Show(false) end
        return
    end

    if not canvas then return end

    local targetId = api.Unit:GetUnitId("target")
    local playerId = api.Unit:GetUnitId("player")
    
    if targetId == nil or targetId == playerId then
        if canvas then canvas:Show(false) end
        return
    end

    -- Cache target type validity per targetId (avoid per-frame unit info lookups)
    if targetId ~= cachedTargetId then
        cachedTargetId = targetId
        cachedTargetValid = true
        targetInfoRetryTimer = 0
        lastRoundedDist10 = nil
        lastR, lastG, lastB, lastA = nil, nil, nil, nil
        local info = nil
        if api.Unit.UnitInfo then info = api.Unit:UnitInfo("target") end
        if not info and api.Unit.GetUnitInfoById then info = api.Unit:GetUnitInfoById(targetId) end
        if info and info.type ~= "character" and info.type ~= "npc" and info.type ~= "monster" then
            cachedTargetValid = false
        end
        -- Keep range HUD placed strictly on top of target buff icons (TTP)
        if canvas then
            pcall(function() canvas:Raise() end)
        end
    end
    if not cachedTargetValid then
        canvas:Show(false)
        return
    end

    -- Periodically re-raise canvas above TTP (TrackThatPlease creates/shows buff icon frames dynamically)
    raiseTimer = raiseTimer + (dt or 0.016)
    if raiseTimer >= 0.5 then
        raiseTimer = 0
        if canvas and canvas:IsVisible() then
            pcall(function() canvas:Raise() end)
        end
    end
    
    local sX, sY, sZ = api.Unit:GetUnitScreenPosition("target")
    if sX == nil or sZ < 0 or sZ > 120 then
        canvas:Show(false)
        return
    end

    local dist = api.Unit:UnitDistance("target")
    if dist == nil then
        canvas:Show(false)
        return
    end

    if dist < 0 then dist = 0 end

    local r, g, b = 1, 1, 1
    if settings.useDynamicColor then
        local variety = settings.colorVariety or 3
        local t1 = tonumber(settings.threshold1) or 28
        local t2 = tonumber(settings.threshold2) or 33
        if variety == 2 then
            if dist <= t1 then
                local c1 = settings.c1 or {r=0, g=1, b=0}
                r, g, b = c1.r or 0, c1.g or 1, c1.b or 0
            else
                local c2 = settings.c2 or {r=1, g=0, b=0}
                r, g, b = c2.r or 1, c2.g or 0, c2.b or 0
            end
        else -- 3 colors
            if dist <= t1 then
                local c1 = settings.c1 or {r=0, g=1, b=0}
                r, g, b = c1.r or 0, c1.g or 1, c1.b or 0
            elseif dist <= t2 then
                local c2 = settings.c2 or {r=1, g=1, b=0}
                r, g, b = c2.r or 1, c2.g or 1, c2.b or 0
            else
                local c3 = settings.c3 or {r=1, g=0, b=0}
                r, g, b = c3.r or 1, c3.g or 0, c3.b or 0
            end
        end
    else
        local sc = settings.staticColor or {r=1, g=1, b=1}
        r, g, b = sc.r or 1, sc.g or 1, sc.b or 1
    end
    local a = settings.alpha or 1.0

    local dist10 = math.floor(dist * 10 + 0.5)
    if dist10 ~= lastRoundedDist10 or r ~= lastR or g ~= lastG or b ~= lastB or a ~= lastA then
        lastRoundedDist10 = dist10
        lastR, lastG, lastB, lastA = r, g, b, a
        rangeLabel.style:SetColor(r, g, b, a)
        rangeLabel:SetText(string.format("%.1fm", dist))
    end

    canvas:RemoveAllAnchors()

    local pos = settings.position or "Top"
    
    if pos == "Top" then
        canvas:AddAnchor("CENTER", "UIParent", "TOPLEFT", sX, sY - 46)
    elseif pos == "Bottom" then
        canvas:AddAnchor("CENTER", "UIParent", "TOPLEFT", sX, sY + 6)
    elseif pos == "Left" then
        canvas:AddAnchor("CENTER", "UIParent", "TOPLEFT", sX - 72, sY - 17)
    elseif pos == "Right" then
        canvas:AddAnchor("CENTER", "UIParent", "TOPLEFT", sX + 72, sY - 17)
    else
        canvas:AddAnchor("CENTER", "UIParent", "TOPLEFT", sX, sY - 46)
    end
    
    canvas:Show(true)
end


function range_meter.CreateUI(wndParent)
    local function ApplyCheckSkin(chk)
        chk:SetExtent(18, 17)
        local bg1 = chk:CreateImageDrawable("ui/button/check_button.dds", "background")
        bg1:SetExtent(18, 17)
        bg1:AddAnchor("CENTER", chk, 0, 0)
        bg1:SetCoords(0, 0, 18, 17)
        chk:SetNormalBackground(bg1)

        local bg2 = chk:CreateImageDrawable("ui/button/check_button.dds", "background")
        bg2:SetExtent(18, 17)
        bg2:AddAnchor("CENTER", chk, 0, 0)
        bg2:SetCoords(18, 0, 18, 17)
        chk:SetCheckedBackground(bg2)

        local bg3 = chk:CreateImageDrawable("ui/button/check_button.dds", "background")
        bg3:SetExtent(18, 17)
        bg3:AddAnchor("CENTER", chk, 0, 0)
        bg3:SetCoords(0, 0, 18, 17)
        chk:SetPushedBackground(bg3)

        local bg4 = chk:CreateImageDrawable("ui/button/check_button.dds", "background")
        bg4:SetExtent(18, 17)
        bg4:AddAnchor("CENTER", chk, 0, 0)
        bg4:SetCoords(18, 0, 18, 17)
        chk:SetHighlightBackground(bg4)
    end

    local function CreateSliderStepper(parent, name, lblText, initVal, minVal, maxVal, onChange)
        local grp = parent:CreateChildWidget("emptywidget", name.."Grp", 0, true)
        grp:SetExtent(145, 25)
        local lbl = grp:CreateChildWidget("label", name.."Lbl", 0, true)
        lbl:SetAutoResize(true)
        lbl:SetText(lblText)
        lbl:AddAnchor("LEFT", grp, 0, 0)
        lbl.style:SetColor(0.2, 0.2, 0.2, 1)

        local btnMinus = grp:CreateChildWidget("button", name.."Minus", 0, true)
        btnMinus:AddAnchor("LEFT", lbl, "RIGHT", 5, 0)
        btnMinus:SetText("-")
        api.Interface:ApplyButtonSkin(btnMinus, SMALL_BTN_SKIN)

        local valLbl = grp:CreateChildWidget("label", name.."Val", 0, true)
        valLbl:SetAutoResize(true)
        valLbl:SetText(tostring(initVal))
        valLbl:AddAnchor("LEFT", btnMinus, "RIGHT", 5, 0)
        valLbl.style:SetColor(0.2, 0.2, 0.2, 1)

        local btnPlus = grp:CreateChildWidget("button", name.."Plus", 0, true)
        btnPlus:AddAnchor("LEFT", valLbl, "RIGHT", 5, 0)
        btnPlus:SetText("+")
        api.Interface:ApplyButtonSkin(btnPlus, SMALL_BTN_SKIN)

        local curVal = initVal

        btnMinus:SetHandler("OnClick", function()
            if curVal > minVal then
                curVal = curVal - 1
                valLbl:SetText(tostring(curVal))
                onChange(curVal)
            end
        end)

        btnPlus:SetHandler("OnClick", function()
            if curVal < maxVal then
                curVal = curVal + 1
                valLbl:SetText(tostring(curVal))
                onChange(curVal)
            end
        end)

        function grp:SetValue(val)
            curVal = val
            valLbl:SetText(tostring(curVal))
        end

        return grp
    end

    local wnd = wndParent:CreateChildWidget("emptywidget", "rangeMeterSettingsWnd", 0, true)
    wnd:SetExtent(350, 145)
    wnd:AddAnchor("TOP", wndParent, 0, 480)

    -- Header
    local title = wnd:CreateChildWidget("label", "title", 0, true)
    title:SetText("Range Meter Settings")
    title:SetExtent(300, 25)
    title:AddAnchor("TOP", wnd, 0, 0)
    title.style:SetAlign(ALIGN.CENTER)
    title.style:SetFontSize(20)
    title.style:SetColor(0.4, 0.3, 0.1, 1)

    -- Row 1 Container (Centered)
    local r1 = wnd:CreateChildWidget("emptywidget", "r1", 0, true)
    r1:SetExtent(330, 25)
    r1:AddAnchor("TOP", title, "BOTTOM", 0, 10)

    local toggleBtn = r1:CreateChildWidget("button", "toggleBtn", 0, true)
    api.Interface:ApplyButtonSkin(toggleBtn, BUTTON_BASIC.DEFAULT)
    toggleBtn:SetExtent(75, 25)
    toggleBtn:AddAnchor("LEFT", r1, 0, 0)

    local function UpdateBtnText()
        if settings.enabled then toggleBtn:SetText("Turn OFF") else toggleBtn:SetText("Turn ON") end
    end
    UpdateBtnText()

    toggleBtn:SetHandler("OnClick", function()
        settings.enabled = not settings.enabled
        UpdateBtnText()
        SaveSettings()
    end)

    local fontGrp = CreateSliderStepper(r1, "fontGrp", "Font Size:", settings.fontSize or 16, 10, 40, function(val)
        settings.fontSize = val
        if rangeLabel then 
            rangeLabel.style:SetFontSize(settings.fontSize)
            rangeLabel:SetText(rangeLabel:GetText())
        end
        SaveSettings()
    end)
    fontGrp:AddAnchor("LEFT", toggleBtn, "RIGHT", 8, 0)

    -- Static Color Swatch beside Font Size (cycles on click, moved slightly right to avoid overlapping with fontGrp)
    local colorLbl = r1:CreateChildWidget("label", "colorLbl", 0, true)
    colorLbl:SetText("Color:")
    colorLbl:SetExtent(36, 25)
    colorLbl:AddAnchor("LEFT", fontGrp, "RIGHT", 16, 0)
    colorLbl.style:SetColor(0.2, 0.2, 0.2, 1)

    local staticColorBtn = r1:CreateChildWidget("button", "staticColorBtn", 0, true)
    staticColorBtn:SetExtent(20, 20)
    staticColorBtn:AddAnchor("LEFT", colorLbl, "RIGHT", 5, 0)
    
    local scBorder = staticColorBtn:CreateColorDrawable(0.2, 0.2, 0.2, 1, "background")
    scBorder:AddAnchor("TOPLEFT", staticColorBtn, 0, 0)
    scBorder:AddAnchor("BOTTOMRIGHT", staticColorBtn, 0, 0)

    local scFill = staticColorBtn:CreateChildWidget("emptywidget", "scFill", 0, true)
    scFill:SetExtent(16, 16)
    scFill:AddAnchor("CENTER", staticColorBtn, 0, 0)
    scFill:Clickable(false)
    local curSc = settings.staticColor or {r=1, g=1, b=1}
    local scFillBg = scFill:CreateColorDrawable(curSc.r, curSc.g, curSc.b, 1, "background")
    scFillBg:AddAnchor("TOPLEFT", scFill, 0, 0)
    scFillBg:AddAnchor("BOTTOMRIGHT", scFill, 0, 0)

    local function ApplyStaticColor(col)
        settings.staticColor = {r=col.r, g=col.g, b=col.b}
        scFillBg:SetColor(col.r, col.g, col.b, 1)
        SaveSettings()
        ForceUpdateRangeLabel()
    end

    staticColorBtn:SetHandler("OnClick", function()
        local curIdx = GetColorIndex(settings.staticColor)
        local nextIdx = (curIdx % #PALETTE_COLORS) + 1
        local col = PALETTE_COLORS[nextIdx]
        ApplyStaticColor(col)
    end)

    -- Row 2 Container (Centered)
    local r2 = wnd:CreateChildWidget("emptywidget", "r2", 0, true)
    r2:SetExtent(290, 25)
    r2:AddAnchor("TOP", r1, "BOTTOM", 0, 10)

    local posLbl = r2:CreateChildWidget("label", "posLbl", 0, true)
    posLbl:SetText("Position:")
    posLbl:SetExtent(60, 25)
    posLbl:AddAnchor("LEFT", r2, 0, 0)
    posLbl.style:SetColor(0.2, 0.2, 0.2, 1)

    local posCombo = W_CTRL.CreateComboBox(r2)
    posCombo:SetExtent(90, 25)
    posCombo:AddAnchor("LEFT", posLbl, "RIGHT", 5, 0)
    posCombo.dropdownItem = POSITIONS
    posCombo:Select(GetPositionIndex(settings.position or "Top"))

    function posCombo:SelectedProc(index)
        settings.position = POSITIONS[index] or "Top"
        SaveSettings()
    end
    
    local dynBtn = r2:CreateChildWidget("button", "dynBtn", 0, true)
    api.Interface:ApplyButtonSkin(dynBtn, BUTTON_BASIC.DEFAULT)
    dynBtn:SetText("Dynamic Colors")
    dynBtn:SetExtent(120, 25)
    dynBtn:AddAnchor("RIGHT", r2, 0, 0)

    -- Reset Defaults (Centered Below Row 2)
    local r3 = wnd:CreateChildWidget("emptywidget", "r3", 0, true)
    r3:SetExtent(120, 25)
    r3:AddAnchor("TOP", r2, "BOTTOM", 0, 15)
    
    local resetBtn = r3:CreateChildWidget("button", "resetBtn", 0, true)
    api.Interface:ApplyButtonSkin(resetBtn, BUTTON_BASIC.DEFAULT)
    resetBtn:SetText("Reset Defaults")
    resetBtn:SetExtent(120, 25)
    resetBtn:AddAnchor("TOP", r3, 0, 0)

    resetBtn:SetHandler("OnClick", function()
        settings.enabled = false
        settings.fontSize = 16
        settings.position = "Top"
        settings.useDynamicColor = false
        settings.colorVariety = 3
        settings.threshold1 = 28
        settings.threshold2 = 33
        settings.c1 = {r=0, g=1, b=0}
        settings.c2 = {r=1, g=1, b=0}
        settings.c3 = {r=1, g=0, b=0}
        settings.staticColor = {r=1, g=1, b=1}
        settings.alpha = 1.0
        SaveSettings()
        if rangeLabel then 
            rangeLabel.style:SetFontSize(16)
            rangeLabel.style:SetColor(1, 1, 1, 1)
            rangeLabel:SetText("0.0m")
        end
        if dynChk then dynChk:SetChecked(false) end
        if posCombo then posCombo:Select(GetPositionIndex("Top")) end
        if fontGrp then fontGrp:SetValue(16) end
        if toggleBtn then toggleBtn:SetText("Turn ON") end
        if t1Edit then t1Edit:SetText("28") end
        if t2Edit then t2Edit:SetText("33") end
        if alphaGrp then alphaGrp:SetValue(10) end
        if varietyCombo then varietyCombo:Select(2) end
        if scFillBg then scFillBg:SetColor(1, 1, 1, 1) end
        UpdateVarietyDisplay()
        UpdateRangeLabels()
        RefreshAllColorDisplays()
        ForceUpdateRangeLabel()
        api.Log:Info("Range Meter reset! Settings applied.")
    end)
    
    -- Popup Window for Colors (Using EXACT model from raid_invite.lua whitelist/blacklist manager)
    if not dynWnd then
        dynWnd = api.Interface:CreateWindow("eluRangeDynWnd", "Color Settings", 0, 0)
        dynWnd:SetExtent(300, 210)
        dynWnd:AddAnchor("CENTER", "UIParent", 0, 0)
        dynWnd:Show(false)
        pcall(function() dynWnd:SetCloseOnEscape(true) end)

        local ConvertColor = function(c) return c / 255 end
        if dynWnd.titleBar and dynWnd.titleBar.bg then
            dynWnd.titleBar.bg:SetColor(ConvertColor(40), ConvertColor(44), ConvertColor(52), 1.0)
        end
        if dynWnd.bg then
            dynWnd.bg:SetColor(ConvertColor(24), ConvertColor(26), ConvertColor(31), 0.95)
        end
        if dynWnd.titleBar and dynWnd.titleBar.closeButton then
            dynWnd.titleBar.closeButton:SetHandler("OnClick", function()
                dynWnd:Show(false)
            end)
        end

        local function CreateColorSwatchBtn(parent, name, initialColor, onCycleColor)
            local btn = parent:CreateChildWidget("button", name, 0, true)
            btn:SetExtent(18, 18)
            
            local border = btn:CreateColorDrawable(0.2, 0.2, 0.2, 1, "background")
            border:AddAnchor("TOPLEFT", btn, 0, 0)
            border:AddAnchor("BOTTOMRIGHT", btn, 0, 0)

            local fill = btn:CreateChildWidget("emptywidget", name.."Fill", 0, true)
            fill:SetExtent(14, 14)
            fill:AddAnchor("CENTER", btn, 0, 0)
            fill:Clickable(false)
            local fillBg = fill:CreateColorDrawable(initialColor.r or 1, initialColor.g or 1, initialColor.b or 1, 1, "background")
            fillBg:AddAnchor("TOPLEFT", fill, 0, 0)
            fillBg:AddAnchor("BOTTOMRIGHT", fill, 0, 0)

            function btn:SetColor(r, g, b)
                fillBg:SetColor(r, g, b, 1)
            end

            if onCycleColor then
                btn:SetHandler("OnClick", onCycleColor)
            end

            return btn
        end

        local function CreateColorPicker(parent, name, startX, startY, onColorSelect)
            local buttons = {}
            local btnX = startX
            for i, col in ipairs(PALETTE_COLORS) do
                local btn = parent:CreateChildWidget("button", name.."Btn"..i, 0, true)
                btn:SetExtent(15, 15)
                btn:AddAnchor("TOPLEFT", parent, btnX, startY)
                
                local border = btn:CreateColorDrawable(0.3, 0.3, 0.3, 1, "background")
                border:AddAnchor("TOPLEFT", btn, 0, 0)
                border:AddAnchor("BOTTOMRIGHT", btn, 0, 0)
                
                local inner = btn:CreateChildWidget("emptywidget", name.."Inner"..i, 0, true)
                inner:SetExtent(13, 13)
                inner:AddAnchor("CENTER", btn, 0, 0)
                inner:Clickable(false)
                local bg = inner:CreateColorDrawable(col.r, col.g, col.b, 1, "background")
                bg:AddAnchor("TOPLEFT", inner, 0, 0)
                bg:AddAnchor("BOTTOMRIGHT", inner, 0, 0)

                function btn:OnClick()
                    onColorSelect(col.r, col.g, col.b)
                end
                btn:SetHandler("OnClick", btn.OnClick)
                btnX = btnX + 17
                table.insert(buttons, btn)
            end
            return buttons
        end

        -- Row 1: Checkbox on left, Variety dropdown on right
        local topRow = dynWnd:CreateChildWidget("emptywidget", "topRow", 0, true)
        topRow:SetExtent(270, 22)
        topRow:AddAnchor("TOP", dynWnd, 0, 46)

        dynChk = topRow:CreateChildWidget("checkbutton", "dynChk", 0, true)
        dynChk:AddAnchor("LEFT", topRow, 0, 0)
        ApplyCheckSkin(dynChk)
        dynChk:SetChecked(settings.useDynamicColor or false)
        
        local dynLbl = topRow:CreateChildWidget("label", "dynLbl", 0, true)
        dynLbl:SetText("Use Dynamic Colors")
        dynLbl:SetExtent(125, 20)
        dynLbl:AddAnchor("LEFT", dynChk, "RIGHT", 5, 0)
        dynLbl.style:SetColor(0.2, 0.2, 0.2, 1)
        
        dynChk:SetHandler("OnCheckChanged", function()
            settings.useDynamicColor = dynChk:GetChecked()
            SaveSettings()
            ForceUpdateRangeLabel()
        end)

        -- Variety Selector (2 Colors vs 3 Colors)
        local varietyLbl = topRow:CreateChildWidget("label", "varietyLbl", 0, true)
        varietyLbl:SetText("Colors:")
        varietyLbl:SetExtent(40, 20)
        varietyLbl:AddAnchor("RIGHT", topRow, -72, 0)
        varietyLbl.style:SetColor(0.2, 0.2, 0.2, 1)

        varietyCombo = W_CTRL.CreateComboBox(topRow)
        varietyCombo:SetExtent(70, 22)
        varietyCombo:AddAnchor("LEFT", varietyLbl, "RIGHT", 2, 0)
        varietyCombo.dropdownItem = { "2 Colors", "3 Colors" }
        varietyCombo:Select((settings.colorVariety or 3) == 2 and 1 or 2)

        function varietyCombo:SelectedProc(index)
            settings.colorVariety = (index == 1) and 2 or 3
            SaveSettings()
            UpdateVarietyDisplay()
            ForceUpdateRangeLabel()
        end

        -- Row 2: Opacity Control
        local opacityRow = dynWnd:CreateChildWidget("emptywidget", "opacityRow", 0, true)
        opacityRow:SetExtent(270, 20)
        opacityRow:AddAnchor("TOP", dynWnd, 0, 74)

        alphaGrp = CreateSliderStepper(opacityRow, "alphaGrp", "Opacity:", math.floor((settings.alpha or 1.0) * 10), 1, 10, function(val)
            settings.alpha = val / 10.0
            SaveSettings()
            ForceUpdateRangeLabel()
        end)
        alphaGrp:AddAnchor("LEFT", opacityRow, 0, 0)

        -- Threshold editing logic with re-entrancy protection
        local isUpdatingThresholds = false
        local function SafeThreshold1Changed()
            if isUpdatingThresholds then return end
            isUpdatingThresholds = true
            local val = tonumber(t1Edit:GetText())
            if val and val >= 0 and val <= 99 then
                settings.threshold1 = val
                local t2 = tonumber(settings.threshold2) or (val + 5)
                if val >= t2 then
                    settings.threshold2 = math.min(99, val + 1)
                    if t2Edit then t2Edit:SetText(tostring(settings.threshold2)) end
                end
                SaveSettings()
                UpdateRangeLabels()
                ForceUpdateRangeLabel()
            end
            isUpdatingThresholds = false
        end

        local function FinalizeThreshold1()
            if isUpdatingThresholds then return end
            isUpdatingThresholds = true
            local val = tonumber(t1Edit:GetText())
            if not val or val < 0 then
                val = 0
                t1Edit:SetText(tostring(val))
                settings.threshold1 = val
            end
            local t2 = tonumber(settings.threshold2) or (val + 5)
            if val >= t2 then
                settings.threshold2 = math.min(99, val + 1)
                if t2Edit then t2Edit:SetText(tostring(settings.threshold2)) end
            end
            SaveSettings()
            UpdateRangeLabels()
            ForceUpdateRangeLabel()
            isUpdatingThresholds = false
        end

        local function SafeThreshold2Changed()
            if isUpdatingThresholds then return end
            isUpdatingThresholds = true
            local val = tonumber(t2Edit:GetText())
            local t1 = tonumber(settings.threshold1) or 0
            -- Only update live if the user typed a valid number strictly greater than t1.
            -- Do NOT force t2Edit:SetText here while typing, so the user can freely backspace and type!
            if val and val > t1 and val <= 99 then
                settings.threshold2 = val
                SaveSettings()
                UpdateRangeLabels()
                ForceUpdateRangeLabel()
            end
            isUpdatingThresholds = false
        end

        local function FinalizeThreshold2()
            if isUpdatingThresholds then return end
            isUpdatingThresholds = true
            local val = tonumber(t2Edit:GetText())
            local t1 = tonumber(settings.threshold1) or 0
            if not val or val <= t1 then
                val = math.min(99, t1 + 1)
                t2Edit:SetText(tostring(val))
            end
            settings.threshold2 = val
            SaveSettings()
            UpdateRangeLabels()
            ForceUpdateRangeLabel()
            isUpdatingThresholds = false
        end

        -- Row 3: Range 1 [ Swatch 1 ] 0m to [ X ] m: [Palette 1]
        r1Row = dynWnd:CreateChildWidget("emptywidget", "r1Row", 0, true)
        r1Row:SetExtent(270, 22)
        r1Row:AddAnchor("TOP", dynWnd, 0, 104)

        swatch1 = CreateColorSwatchBtn(r1Row, "swatch1", settings.c1 or {r=0, g=1, b=0}, function()
            local curIdx = GetColorIndex(settings.c1)
            local nextIdx = (curIdx % #PALETTE_COLORS) + 1
            local col = PALETTE_COLORS[nextIdx]
            settings.c1 = {r=col.r, g=col.g, b=col.b}
            swatch1:SetColor(col.r, col.g, col.b)
            SaveSettings()
            ForceUpdateRangeLabel()
        end)
        swatch1:AddAnchor("LEFT", r1Row, 0, 2)

        t1PreLbl = r1Row:CreateChildWidget("label", "t1PreLbl", 0, true)
        t1PreLbl:SetAutoResize(true)
        t1PreLbl:SetText("0m to")
        t1PreLbl:AddAnchor("LEFT", swatch1, "RIGHT", 5, 0)
        t1PreLbl.style:SetColor(0.2, 0.2, 0.2, 1)

        t1Edit = W_CTRL.CreateEdit("t1Edit", r1Row)
        t1Edit:SetExtent(26, 20)
        t1Edit:AddAnchor("LEFT", t1PreLbl, "RIGHT", 4, 0)
        t1Edit.style:SetAlign(ALIGN.CENTER)
        pcall(function() t1Edit:SetMaxTextLength(2) end)
        t1Edit:SetText(tostring(settings.threshold1 or 28))
        
        t1PostLbl = r1Row:CreateChildWidget("label", "t1PostLbl", 0, true)
        t1PostLbl:SetAutoResize(true)
        t1PostLbl:SetText("m:")
        t1PostLbl:AddAnchor("LEFT", t1Edit, "RIGHT", 3, 0)
        t1PostLbl.style:SetColor(0.2, 0.2, 0.2, 1)

        paletteButtons1 = CreateColorPicker(r1Row, "c1", 136, 3, function(r, g, b)
            settings.c1 = {r=r, g=g, b=b}
            swatch1:SetColor(r, g, b)
            SaveSettings()
            ForceUpdateRangeLabel()
        end)

        t1Edit:SetHandler("OnTextChanged", SafeThreshold1Changed)
        t1Edit:SetHandler("OnKillFocus", FinalizeThreshold1)
        t1Edit:SetHandler("OnEnterPressed", FinalizeThreshold1)

        -- Row 4: Range 2 [ Swatch 2 ] [ X ]m to [ Y ] m: [Palette 2] (or > [ X ]m: if 2 Colors)
        r2Row = dynWnd:CreateChildWidget("emptywidget", "r2Row", 0, true)
        r2Row:SetExtent(270, 22)
        r2Row:AddAnchor("TOP", dynWnd, 0, 134)

        swatch2 = CreateColorSwatchBtn(r2Row, "swatch2", settings.c2 or {r=1, g=1, b=0}, function()
            local curIdx = GetColorIndex(settings.c2)
            local nextIdx = (curIdx % #PALETTE_COLORS) + 1
            local col = PALETTE_COLORS[nextIdx]
            settings.c2 = {r=col.r, g=col.g, b=col.b}
            swatch2:SetColor(col.r, col.g, col.b)
            SaveSettings()
            ForceUpdateRangeLabel()
        end)
        swatch2:AddAnchor("LEFT", r2Row, 0, 2)

        t2PreLbl = r2Row:CreateChildWidget("label", "t2PreLbl", 0, true)
        t2PreLbl:SetAutoResize(true)
        t2PreLbl:SetText(string.format("%dm to", tonumber(settings.threshold1) or 28))
        t2PreLbl:AddAnchor("LEFT", swatch2, "RIGHT", 5, 0)
        t2PreLbl.style:SetColor(0.2, 0.2, 0.2, 1)

        t2Edit = W_CTRL.CreateEdit("t2Edit", r2Row)
        t2Edit:SetExtent(26, 20)
        t2Edit:AddAnchor("LEFT", t2PreLbl, "RIGHT", 4, 0)
        t2Edit.style:SetAlign(ALIGN.CENTER)
        pcall(function() t2Edit:SetMaxTextLength(2) end)
        t2Edit:SetText(tostring(settings.threshold2 or 33))
        
        t2PostLbl = r2Row:CreateChildWidget("label", "t2PostLbl", 0, true)
        t2PostLbl:SetAutoResize(true)
        t2PostLbl:SetText("m:")
        t2PostLbl:AddAnchor("LEFT", t2Edit, "RIGHT", 3, 0)
        t2PostLbl.style:SetColor(0.2, 0.2, 0.2, 1)

        paletteButtons2 = CreateColorPicker(r2Row, "c2", 136, 3, function(r, g, b)
            settings.c2 = {r=r, g=g, b=b}
            swatch2:SetColor(r, g, b)
            SaveSettings()
            ForceUpdateRangeLabel()
        end)

        t2Edit:SetHandler("OnTextChanged", SafeThreshold2Changed)
        t2Edit:SetHandler("OnKillFocus", FinalizeThreshold2)
        t2Edit:SetHandler("OnEnterPressed", FinalizeThreshold2)

        -- Row 5: Range 3 [ Swatch 3 ] > [ Y ]m: [Palette 3]
        r3Row = dynWnd:CreateChildWidget("emptywidget", "r3Row", 0, true)
        r3Row:SetExtent(270, 22)
        r3Row:AddAnchor("TOP", dynWnd, 0, 164)

        swatch3 = CreateColorSwatchBtn(r3Row, "swatch3", settings.c3 or {r=1, g=0, b=0}, function()
            local curIdx = GetColorIndex(settings.c3)
            local nextIdx = (curIdx % #PALETTE_COLORS) + 1
            local col = PALETTE_COLORS[nextIdx]
            settings.c3 = {r=col.r, g=col.g, b=col.b}
            swatch3:SetColor(col.r, col.g, col.b)
            SaveSettings()
            ForceUpdateRangeLabel()
        end)
        swatch3:AddAnchor("LEFT", r3Row, 0, 2)

        t3Lbl = r3Row:CreateChildWidget("label", "t3Lbl", 0, true)
        t3Lbl:SetAutoResize(true)
        t3Lbl:SetText(string.format("> %dm:", tonumber(settings.threshold2) or 33))
        t3Lbl:AddAnchor("LEFT", swatch3, "RIGHT", 5, 0)
        t3Lbl.style:SetColor(0.2, 0.2, 0.2, 1)

        paletteButtons3 = CreateColorPicker(r3Row, "c3", 136, 3, function(r, g, b)
            settings.c3 = {r=r, g=g, b=b}
            swatch3:SetColor(r, g, b)
            SaveSettings()
            ForceUpdateRangeLabel()
        end)
    else
        -- Re-opening this tab: refresh the cached controls to reflect current settings
        RefreshDynWnd()
    end

    dynBtn:SetHandler("OnClick", function()
        if not dynWnd then return end
        local willShow = not dynWnd:IsVisible()
        if willShow then
            RefreshDynWnd()
            dynWnd:Show(true)
            dynWnd:Raise()
        else
            dynWnd:Show(false)
        end
    end)

    return wnd
end


function range_meter.OnLoad()
    if not canvas then
        canvas = api.Interface:CreateEmptyWindow("eluRangeMeter")
        canvas:SetExtent(150, 40)
        canvas:Show(false)
        canvas:Clickable(false)
        
        rangeLabel = canvas:CreateChildWidget("label", "rLabel", 0, true)
        pcall(function() rangeLabel:Clickable(false) end)
        rangeLabel:Show(true)
        rangeLabel:SetAutoResize(true)
        rangeLabel:AddAnchor("CENTER", canvas, 0, 0)
        rangeLabel:SetText("0.0m")
        rangeLabel.style:SetFontSize(settings.fontSize or 16)
        local initialCol = settings.staticColor or {r=1, g=1, b=1}
        rangeLabel.style:SetColor(initialCol.r or 1, initialCol.g or 1, initialCol.b or 1, settings.alpha or 1.0)
        rangeLabel.style:SetOutline(true)
        
        if rangeLabel.style.SetShadow then
            rangeLabel.style:SetShadow(true)
        end
    end

    cachedTargetId = nil
    cachedTargetValid = true
    lastRoundedDist10 = nil
    lastR, lastG, lastB, lastA = nil, nil, nil, nil
    raiseTimer = 0

    if not lateHookRegistered then
        lateHookRegistered = true
        api:DoIn(1500, function()
            if canvas then
                pcall(function() canvas:Raise() end)
            end
        end)
    end
end


function range_meter.OnUnload()
    if canvas then
        canvas:Show(false)
    end
    if dynWnd then
        dynWnd:Show(false)
    end
end

return range_meter
