local api = require("api")
local settingsManager = require("Elu_Tracker/settings_manager")
local settings = settingsManager.Settings.rangeMeterSettings
local SaveSettings = settingsManager.SaveSettings

local range_meter = {}
local canvas = nil
local rangeLabel = nil

local POSITIONS = { "Top", "Bottom", "Left", "Right" }

local function GetPositionIndex(posStr)
    for i, v in ipairs(POSITIONS) do
        if v == posStr then return i end
    end
    return 1
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



    local info = nil
    if api.Unit.UnitInfo then info = api.Unit:UnitInfo("target") end
    if not info and api.Unit.GetUnitInfoById then info = api.Unit:GetUnitInfoById(targetId) end

    if info then
        local isPlayer = (info.type == "character")
        local isHostileMob = (info.type == "monster" or info.isAggressive == true)
        if not isPlayer and not isHostileMob then
            canvas:Show(false)
            return
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




    rangeLabel:SetText(string.format("%.1fm", dist))

    if settings.useDynamicColor then
        if dist <= (settings.threshold1 or 28) then
            local c1 = settings.c1 or {r=0, g=1, b=0}
            rangeLabel.style:SetColor(c1.r, c1.g, c1.b, settings.alpha or 1.0)
        elseif dist <= (settings.threshold2 or 33) then
            local c2 = settings.c2 or {r=1, g=1, b=0}
            rangeLabel.style:SetColor(c2.r, c2.g, c2.b, settings.alpha or 1.0)
        else
            local c3 = settings.c3 or {r=1, g=0, b=0}
            rangeLabel.style:SetColor(c3.r, c3.g, c3.b, settings.alpha or 1.0)
        end
    else
        rangeLabel.style:SetColor(1, 1, 1, settings.alpha or 1.0)
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
        grp:SetExtent(130, 20)
        local lbl = grp:CreateChildWidget("label", name.."Lbl", 0, true)
        lbl:SetAutoResize(true)
        lbl:SetText(lblText)
        lbl:AddAnchor("LEFT", grp, 0, 0)
        lbl.style:SetColor(0.2, 0.2, 0.2, 1)

        local btnMinus = grp:CreateChildWidget("button", name.."Minus", 0, true)
        btnMinus:SetExtent(20, 20)
        btnMinus:AddAnchor("LEFT", lbl, "RIGHT", 5, 0)
        btnMinus:SetText("-")
        api.Interface:ApplyButtonSkin(btnMinus, BUTTON_BASIC.DEFAULT)

        local valLbl = grp:CreateChildWidget("label", name.."Val", 0, true)
        valLbl:SetAutoResize(true)
        valLbl:SetText(tostring(initVal))
        valLbl:AddAnchor("LEFT", btnMinus, "RIGHT", 5, 0)
        valLbl.style:SetColor(0.2, 0.2, 0.2, 1)

        local btnPlus = grp:CreateChildWidget("button", name.."Plus", 0, true)
        btnPlus:SetExtent(20, 20)
        btnPlus:AddAnchor("LEFT", valLbl, "RIGHT", 5, 0)
        btnPlus:SetText("+")
        api.Interface:ApplyButtonSkin(btnPlus, BUTTON_BASIC.DEFAULT)

        local currentVal = initVal
        local function UpdateValue(newVal)
            if newVal >= minVal and newVal <= maxVal then
                currentVal = newVal
                valLbl:SetText(tostring(currentVal))
                onChange(currentVal)
            end
        end

        grp.SetValue = function(self, v)
            currentVal = v
            valLbl:SetText(tostring(currentVal))
        end

        function btnMinus:OnClick() UpdateValue(currentVal - 1) end
        btnMinus:SetHandler("OnClick", btnMinus.OnClick)

        function btnPlus:OnClick() UpdateValue(currentVal + 1) end
        btnPlus:SetHandler("OnClick", btnPlus.OnClick)
        
        return grp
    end

    local wnd = wndParent:CreateChildWidget("emptywidget", "rangeMeterSettingsWnd", 0, true)
    wnd:SetExtent(350, 160)
    wnd:AddAnchor("TOP", wndParent, 0, 480)

    -- Header
    local title = wnd:CreateChildWidget("label", "title", 0, true)
    title:SetText("Range Meter Settings")
    title:SetExtent(200, 30)
    title:AddAnchor("TOP", wnd, 0, 0)
    title.style:SetAlign(ALIGN.CENTER)
    title.style:SetFontSize(20)
    title.style:SetColor(0.4, 0.3, 0.1, 1)

    
    
    -- Row 1 Container (Centered)
    local r1 = wnd:CreateChildWidget("emptywidget", "r1", 0, true)
    r1:SetExtent(260, 25)
    r1:AddAnchor("TOP", title, "BOTTOM", 0, 10)

    local toggleBtn = r1:CreateChildWidget("button", "toggleBtn", 0, true)
    api.Interface:ApplyButtonSkin(toggleBtn, BUTTON_BASIC.DEFAULT)
    toggleBtn:SetExtent(100, 25)
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
    fontGrp:AddAnchor("RIGHT", r1, 0, 0)

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
        settings.threshold1 = 28
        settings.threshold2 = 33
        settings.c1 = {r=1, g=1, b=1}
        settings.c2 = {r=1, g=1, b=1}
        
        settings.c3 = {r=1, g=1, b=1}
        settings.alpha = 1.0
        SaveSettings()
        if rangeLabel then 
            rangeLabel.style:SetFontSize(16)
            rangeLabel.style:SetColor(1, 1, 1, 1)
        end
        if dynChk then dynChk:SetChecked(false) end
        if posCombo then posCombo:Select(GetPositionIndex("Top")) end
        if fontGrp then fontGrp:SetValue(16) end
        if toggleBtn then toggleBtn:SetText("Turn ON") end
        if t1Edit then t1Edit:SetText("28") end
        if t2Edit then t2Edit:SetText("33") end
        if alphaGrp then alphaGrp:SetValue(10) end
        api.Log:Info("Range Meter reset! Settings applied.")

    end)
    
    -- Popup Window for Colors (Using EXACT model from Fishing Settings)
    local dynWnd = api.Interface:CreateWindow("eluRangeDynWnd", "Color Settings", 300, 250)
    dynWnd:AddAnchor("CENTER", "UIParent", 0, 0)
    dynWnd:Show(false)
    pcall(function() dynWnd:SetCloseOnEscape(true) end)

    if dynWnd.titleBar and dynWnd.titleBar.bg then
        local ConvertColor = function(c) return c/255 end
        dynWnd.titleBar.bg:SetColor(ConvertColor(40), ConvertColor(44), ConvertColor(52), 1.0)
    end
    if dynWnd.bg then
        local ConvertColor = function(c) return c/255 end
        dynWnd.bg:SetColor(ConvertColor(24), ConvertColor(26), ConvertColor(31), 0.95)
    end
    
    dynBtn:SetHandler("OnClick", function()
        dynWnd:Show(not dynWnd:IsVisible())
    end)

    local function CreateColorPicker(parent, name, startX, startY, onColorSelect)
        local colors = {
            {r=1, g=1, b=1}, {r=1, g=0, b=0}, {r=0, g=1, b=0},
            {r=0, g=0, b=1}, {r=1, g=1, b=0}, {r=1, g=0.5, b=0},
            {r=0, g=1, b=1}, {r=1, g=0, b=1}
        }
        local btnX = startX
        for i, col in ipairs(colors) do
            local btn = parent:CreateChildWidget("button", name.."Btn"..i, 0, true)
            btn:SetExtent(16, 16)
            btn:AddAnchor("TOPLEFT", parent, btnX, startY)
            local bg = btn:CreateColorDrawable(col.r, col.g, col.b, 1, "background")
            bg:AddAnchor("TOPLEFT", btn, 0, 0)
            bg:AddAnchor("BOTTOMRIGHT", btn, 0, 0)
            function btn:OnClick() onColorSelect(col.r, col.g, col.b) end
            btn:SetHandler("OnClick", btn.OnClick)
            btnX = btnX + 18
        end
    end

    local dynChk = dynWnd:CreateChildWidget("checkbutton", "dynChk", 0, true)
    dynChk:AddAnchor("TOPLEFT", dynWnd, 20, 50)
    ApplyCheckSkin(dynChk)
    dynChk:SetChecked(settings.useDynamicColor)
    
    local dynLbl = dynWnd:CreateChildWidget("label", "dynLbl", 0, true)
    dynLbl:SetText("Use Dynamic Colors")
    dynLbl:SetExtent(150, 20)
    dynLbl:AddAnchor("LEFT", dynChk, "RIGHT", 5, 0)
    dynLbl.style:SetColor(0.2, 0.2, 0.2, 1)
    
    dynChk:SetHandler("OnCheckChanged", function()
        settings.useDynamicColor = dynChk:GetChecked()
        SaveSettings()
    end)

    -- Opacity Control
    local alphaGrp = CreateSliderStepper(dynWnd, "alphaGrp", "Opacity:", math.floor((settings.alpha or 1.0) * 10), 1, 10, function(val)
        settings.alpha = val / 10.0
        SaveSettings()
    end)
    alphaGrp:AddAnchor("TOPLEFT", dynChk, "BOTTOMLEFT", 0, 10)

    -- Stage 1
    local t1Lbl = dynWnd:CreateChildWidget("label", "t1Lbl", 0, true)
    t1Lbl:SetText("0 to")
    t1Lbl:SetExtent(35, 20)
    t1Lbl:AddAnchor("TOPLEFT", alphaGrp, "BOTTOMLEFT", 0, 15)
    t1Lbl.style:SetColor(0.2, 0.2, 0.2, 1)

    local t1Edit = W_CTRL.CreateEdit("t1Edit", dynWnd)
    t1Edit:SetExtent(35, 20)
    t1Edit:AddAnchor("LEFT", t1Lbl, "RIGHT", 0, 0)
    if not settings.threshold1 then settings.threshold1 = 28; SaveSettings() end
    t1Edit:SetText(tostring(settings.threshold1))
    
    local t1Lbl2 = dynWnd:CreateChildWidget("label", "t1Lbl2", 0, true)
    t1Lbl2:SetText("m:")
    t1Lbl2:SetExtent(20, 20)
    t1Lbl2:AddAnchor("LEFT", t1Edit, "RIGHT", 0, 0)
    t1Lbl2.style:SetColor(0.2, 0.2, 0.2, 1)

    t1Edit:SetHandler("OnKillFocus", function()
        local val = tonumber(t1Edit:GetText())
        if val then settings.threshold1 = val; SaveSettings() else t1Edit:SetText(tostring(settings.threshold1)) end
    end)
    
    if not settings.c1 then settings.c1 = {r=1, g=1, b=1}; SaveSettings() end
    CreateColorPicker(dynWnd, "c1", 125, 122, function(r, g, b)
        settings.c1 = {r=r, g=g, b=b}; SaveSettings()
    end)

    -- Stage 2
    local t2Lbl = dynWnd:CreateChildWidget("label", "t2Lbl", 0, true)
    t2Lbl:SetText("<=")
    t2Lbl:SetExtent(35, 20)
    t2Lbl:AddAnchor("TOPLEFT", t1Lbl, "BOTTOMLEFT", 0, 15)
    t2Lbl.style:SetColor(0.2, 0.2, 0.2, 1)

    local t2Edit = W_CTRL.CreateEdit("t2Edit", dynWnd)
    t2Edit:SetExtent(35, 20)
    t2Edit:AddAnchor("LEFT", t2Lbl, "RIGHT", 0, 0)
    if not settings.threshold2 then settings.threshold2 = 33; SaveSettings() end
    t2Edit:SetText(tostring(settings.threshold2))
    
    local t2Lbl2 = dynWnd:CreateChildWidget("label", "t2Lbl2", 0, true)
    t2Lbl2:SetText("m:")
    t2Lbl2:SetExtent(20, 20)
    t2Lbl2:AddAnchor("LEFT", t2Edit, "RIGHT", 0, 0)
    t2Lbl2.style:SetColor(0.2, 0.2, 0.2, 1)

    t2Edit:SetHandler("OnKillFocus", function()
        local val = tonumber(t2Edit:GetText())
        if val then settings.threshold2 = val; SaveSettings() else t2Edit:SetText(tostring(settings.threshold2)) end
    end)
    
    if not settings.c2 then settings.c2 = {r=1, g=1, b=1}; SaveSettings() end
    CreateColorPicker(dynWnd, "c2", 125, 157, function(r, g, b)
        settings.c2 = {r=r, g=g, b=b}; SaveSettings()
    end)

    -- Stage 3
    local t3Lbl = dynWnd:CreateChildWidget("label", "t3Lbl", 0, true)
    t3Lbl:SetText("Max:")
    t3Lbl:SetExtent(90, 20)
    t3Lbl:AddAnchor("TOPLEFT", t2Lbl, "BOTTOMLEFT", 0, 15)
    t3Lbl.style:SetColor(0.2, 0.2, 0.2, 1)
    
    if not settings.c3 then settings.c3 = {r=1, g=1, b=1}; SaveSettings() end
    CreateColorPicker(dynWnd, "c3", 125, 192, function(r, g, b)
        settings.c3 = {r=r, g=g, b=b}; SaveSettings()
    end)

    return wnd
end



function range_meter.OnLoad()
    -- Use layer "overlay" to ensure it draws on top of almost everything
    canvas = api.Interface:CreateEmptyWindow("eluRangeMeter", "UIParent")
    canvas:SetUILayer("tooltip")
    canvas:SetExtent(150, 40)
    canvas:Show(false)
    canvas:Clickable(false)
    
    
    rangeLabel = canvas:CreateChildWidget("label", "rLabel", 0, true)
    rangeLabel:Show(true)
        rangeLabel:SetAutoResize(true)
    rangeLabel:AddAnchor("CENTER", canvas, 0, 0)
    rangeLabel:SetText("0.0m")
    rangeLabel.style:SetFontSize(settings.fontSize or 16)
    rangeLabel.style:SetColor(1, 1, 1, settings.alpha or 1.0) -- White text
    rangeLabel.style:SetOutline(true) -- Black outline
    
    if rangeLabel.style.SetShadow then
        rangeLabel.style:SetShadow(true)
    end
end

function range_meter.OnUnload()
    if canvas then
        canvas:Show(false)
        canvas = nil
    end
end

return range_meter
