local api = require("api")
local settingsManager = require("Elu_Tracker/settings_manager")
local EluTrackerSettings = settingsManager.Settings
local SaveEluTrackerSettings = settingsManager.SaveSettings

local M = {}

local STATE_FILE = "elu_chat_language.lua"
local SANE_COORD_LIMIT = 10000

-- Default offset beside the chat input bar (bottom-left of screen)
local DEFAULT_X = 422
local DEFAULT_BOTTOM_OFFSET = 55

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
    width = 28,
    height = 20,
    autoResize = true,
    drawableType = "ninePart",
    coordsKey = "btn",
}

-- Default state: "?" until the player types /nuia or /haranya in chat (or if
-- a previous session already saved "H" or "N" on disk).
local state = {
    enabled = true,
    lang = "?",
    x = nil,
    y = nil,
    customPos = false,
    size = 18,
    alpha = 1.0,
    bgAlpha = 0.6,
}

local indicatorWnd = nil
local langLabel = nil
local bgBorder = nil
local dragOverlay = nil
local tooltipWnd = nil
local tooltipLabel = nil
local settingsPopupWnd = nil
local sizeStepper = nil
local alphaStepper = nil
local bgAlphaStepper = nil
local enableCheckWidget = nil
local eventWnd = nil
local _onLoadStarted = false
local lastScreenH = 0
local checkScreenTimer = 0
local shiftClickable = false
local hoverShown = false
local charCheckTimer = 0
local currentCharKey = nil
local savedCharacters = {}

local COLOR_HARANYA = { 1.0, 0.55, 0.0, 1.0 } -- Orange
local COLOR_NUIA    = { 0.2, 0.65, 1.0, 1.0 } -- Blue
local COLOR_UNKNOWN = { 0.85, 0.85, 0.85, 1.0 } -- Neutral gray/white for "?"

local function GetCurrentCharKey()
    local charName = nil
    pcall(function()
        local id = api.Unit:GetUnitId("player")
        if id then
            local name = api.Unit:GetUnitNameById(id)
            if type(name) == "string" then
                name = name:gsub("^%s*(.-)%s*$", "%1")
                if name ~= "" then
                    charName = string.lower(name)
                end
            end
        end
    end)
    return charName
end

local function ApplyLoadedFields(src, includeLang)
    if type(src) ~= "table" then return end
    if src.enabled ~= nil then
        state.enabled = (src.enabled == true)
    end
    if includeLang and (src.lang == "H" or src.lang == "N" or src.lang == "?") then
        state.lang = src.lang
    end
    if type(src.x) == "number" and src.x >= 0 and src.x <= SANE_COORD_LIMIT and
       type(src.y) == "number" and src.y >= 0 and src.y <= SANE_COORD_LIMIT then
        state.x = src.x
        state.y = src.y
    end
    if src.customPos ~= nil and state.x and state.y then
        state.customPos = (src.customPos == true)
    else
        state.customPos = false
    end
    if type(src.size) == "number" and src.size >= 10 and src.size <= 40 then
        state.size = math.floor(src.size + 0.5)
    end
    if type(src.alpha) == "number" and src.alpha >= 0.1 and src.alpha <= 1.0 then
        state.alpha = src.alpha
    end
    if type(src.bgAlpha) == "number" and src.bgAlpha >= 0.0 and src.bgAlpha <= 1.0 then
        state.bgAlpha = src.bgAlpha
    end
end

local function SaveState()
    local ck = currentCharKey or GetCurrentCharKey()
    if ck then
        currentCharKey = ck
        savedCharacters[ck] = {
            enabled = state.enabled,
            lang = state.lang,
            x = state.x,
            y = state.y,
            customPos = state.customPos,
            size = state.size,
            alpha = state.alpha,
            bgAlpha = state.bgAlpha,
        }
    end

    EluTrackerSettings.chatLanguage = {
        enabled = state.enabled,
        lang = state.lang,
        x = state.x,
        y = state.y,
        customPos = state.customPos,
        size = state.size,
        alpha = state.alpha,
        bgAlpha = state.bgAlpha,
        characters = savedCharacters,
    }
    pcall(SaveEluTrackerSettings)
    pcall(function()
        api.File:Write(STATE_FILE, EluTrackerSettings.chatLanguage)
    end)
end

local function LoadState()
    local loaded = nil
    local okFile, fileData = pcall(function()
        return api.File:Read(STATE_FILE)
    end)
    if okFile and type(fileData) == "table" and (fileData.lang == "H" or fileData.lang == "N" or fileData.customPos ~= nil or fileData.enabled ~= nil or type(fileData.characters) == "table") then
        loaded = fileData
    elseif type(EluTrackerSettings.chatLanguage) == "table" then
        loaded = EluTrackerSettings.chatLanguage
    end

    if type(loaded) == "table" then
        if type(loaded.characters) == "table" then
            for k, v in pairs(loaded.characters) do
                if type(v) == "table" then
                    savedCharacters[k] = v
                end
            end
        end
        if type(EluTrackerSettings.chatLanguage) == "table" and type(EluTrackerSettings.chatLanguage.characters) == "table" then
            for k, v in pairs(EluTrackerSettings.chatLanguage.characters) do
                if type(v) == "table" and not savedCharacters[k] then
                    savedCharacters[k] = v
                end
            end
        end

        -- Apply shared visual/layout defaults first (position, size, opacity, enabled)
        ApplyLoadedFields(loaded, false)

        local ck = GetCurrentCharKey()
        if ck then
            currentCharKey = ck
            local charData = savedCharacters[ck]
            if type(charData) == "table" then
                ApplyLoadedFields(charData, true)
            else
                -- New character profile: inherit visual/layout defaults, start lang at "?" until /nuia or /haranya is used on this character
                state.lang = "?"
                SaveState()
            end
        else
            state.lang = "?"
        end
    end
end

-- Load immediately at require-time so CreateUI sees saved values
LoadState()

local IsBlockingWindowOpen

local function GetTooltipTextAndColor()
    if state.lang == "H" then
        return "Haranya", COLOR_HARANYA, 74
    elseif state.lang == "N" then
        return "Nuia", COLOR_NUIA, 56
    else
        return "Nuia / Haranya", COLOR_UNKNOWN, 110
    end
end

local function UpdateTooltipContent()
    if not tooltipWnd or not tooltipLabel then return end
    local text, col, width = GetTooltipTextAndColor()
    tooltipWnd:SetExtent(width, 26)
    tooltipLabel:SetExtent(width - 10, 20)
    tooltipLabel:SetText(text)
    pcall(function() ApplyTextColor(tooltipLabel, col) end)
    if tooltipLabel.style and tooltipLabel.style.SetColor then
        pcall(function() tooltipLabel.style:SetColor(col[1], col[2], col[3], 1.0) end)
    end
end

local function ApplyAlphaAndColors()
    local fontSize = state.size or 18
    local boxSize = math.max(28, fontSize + 12)
    local textAlpha = state.alpha or 1.0
    local boxAlpha = (state.bgAlpha or 0.6) * textAlpha

    if indicatorWnd then
        indicatorWnd:SetExtent(boxSize, boxSize)
        if indicatorWnd.SetAlpha then
            pcall(function() indicatorWnd:SetAlpha(textAlpha) end)
        end
    end
    if bgBorder then
        pcall(function() bgBorder:SetColor(0, 0, 0, boxAlpha) end)
    end

    if not langLabel then return end
    langLabel:SetExtent(boxSize, boxSize)
    if langLabel.style and langLabel.style.SetFontSize then
        pcall(function() langLabel.style:SetFontSize(fontSize) end)
    end

    local baseCol = COLOR_UNKNOWN
    if state.lang == "H" then
        langLabel:SetText("H")
        baseCol = COLOR_HARANYA
    elseif state.lang == "N" then
        langLabel:SetText("N")
        baseCol = COLOR_NUIA
    else
        langLabel:SetText("?")
        baseCol = COLOR_UNKNOWN
    end

    local colWithAlpha = { baseCol[1], baseCol[2], baseCol[3], textAlpha }
    pcall(function() ApplyTextColor(langLabel, colWithAlpha) end)
    if langLabel.style and langLabel.style.SetColor then
        pcall(function() langLabel.style:SetColor(baseCol[1], baseCol[2], baseCol[3], textAlpha) end)
    end
end

local function UpdateVisual()
    ApplyAlphaAndColors()
    UpdateTooltipContent()
end

local function SetLanguage(newLang)
    if newLang ~= "H" and newLang ~= "N" and newLang ~= "?" then
        return
    end
    local changed = (state.lang ~= newLang)
    state.lang = newLang
    UpdateVisual()
    if changed then
        SaveState()
    end
end

local function StripChatFormatting(text)
    if type(text) ~= "string" then return "" end
    local clean = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    clean = clean:gsub("^%s*(.-)%s*$", "%1")
    return string.lower(clean)
end

-- Checks for the exact red system message emitted by the client when
-- switching languages via /nuia or /haranya:
--   "Language changed to Nuia Continent Dialect."
--   "Language changed to Haranya Continent Dialect."
local function DetectExactSystemLanguageChange(rawText)
    if type(rawText) ~= "string" or rawText == "" then
        return nil
    end
    local msgLower = StripChatFormatting(rawText)
    if msgLower == "" then
        return nil
    end

    if msgLower:find("language changed to nuia", 1, true) or
       msgLower:find("nuia continent dialect", 1, true) then
        return "N"
    end

    if msgLower:find("language changed to haranya", 1, true) or
       msgLower:find("haranya continent dialect", 1, true) then
        return "H"
    end

    return nil
end

local function HasLanguageKeyword(msgLower)
    if msgLower:find("dialect", 1, true) then return true end
    if msgLower:find("language", 1, true) then return true end
    if msgLower:find("speaking", 1, true) then return true end
    if msgLower:find("switched", 1, true) then return true end
    if msgLower:find("changed", 1, true) then return true end
    if msgLower:find("linguagem", 1, true) then return true end
    if msgLower:find("idioma", 1, true) then return true end
    if msgLower:find("dialeto", 1, true) then return true end
    return false
end

local function DetectLanguageFromText(rawText, requireKeyword)
    if type(rawText) ~= "string" or rawText == "" then
        return nil
    end

    local exact = DetectExactSystemLanguageChange(rawText)
    if exact then
        return exact
    end

    local msgLower = StripChatFormatting(rawText)
    if msgLower == "" then
        return nil
    end

    if msgLower == "/haranya" or msgLower == "!haranya" then
        return "H"
    end
    if msgLower == "/nuia" or msgLower == "!nuia" then
        return "N"
    end

    local hasKeyword = HasLanguageKeyword(msgLower)
    if requireKeyword and not hasKeyword then
        return nil
    end

    -- Avoid false positives on "Nuia Alliance" / "Haranya Alliance" channel join notices
    if not hasKeyword and msgLower:find("alliance", 1, true) then
        return nil
    end
    if msgLower:find("entering chat", 1, true) then
        return nil
    end

    local posH = msgLower:find("haranya", 1, true) or msgLower:find("harani", 1, true)
    local posN = msgLower:find("nuia", 1, true)

    if posH and posN then
        return (posH > posN) and "H" or "N"
    elseif posH then
        return "H"
    elseif posN then
        return "N"
    end

    return nil
end

local function GetMyPlayerNameLower()
    local myName = ""
    pcall(function()
        local id = api.Unit:GetUnitId("player")
        if id then
            myName = api.Unit:GetUnitNameById(id) or ""
        end
    end)
    return string.lower(myName or "")
end

local function IsSystemChannel(channelId)
    if type(channelId) ~= "number" then return true end
    if channelId <= 0 or channelId == 2 or channelId == 10 or channelId == 11 then
        return true
    end
    if CHAT_MESSAGE_FILTERS then
        if channelId == CHAT_MESSAGE_FILTERS.SYSTEM or
           channelId == CHAT_MESSAGE_FILTERS.NOTICE or
           channelId == CHAT_MESSAGE_FILTERS.CHANNEL_INFO then
            return true
        end
    end
    return false
end

local function ScanAllArgsForExactMatch(...)
    for i = 1, 9 do
        local v = select(i, ...)
        if type(v) == "string" and v ~= "" then
            local exact = DetectExactSystemLanguageChange(v)
            if exact then
                SetLanguage(exact)
                return true
            end
        elseif type(v) == "table" then
            for _, subV in pairs(v) do
                if type(subV) == "string" and subV ~= "" then
                    local exact = DetectExactSystemLanguageChange(subV)
                    if exact then
                        SetLanguage(exact)
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function OnChatMessage(channel, unit, isHostile, name, message, speakerInChatBound, specifyName, factionName, trialPosition)
    -- 1. Always check all arguments for the exact system dialect change message first
    if ScanAllArgsForExactMatch(channel, unit, isHostile, name, message, speakerInChatBound, specifyName, factionName, trialPosition) then
        return
    end

    local speakerLower = type(name) == "string" and string.lower(name:gsub("^%s*(.-)%s*$", "%1")) or ""
    local myNameLower = GetMyPlayerNameLower()

    local isSystemSpeaker = (speakerLower == "" or speakerLower == "system" or speakerLower == "server" or speakerLower == "notice")
    local isSelfSpeaker = (myNameLower ~= "" and speakerLower == myNameLower)

    if not isSystemSpeaker and not isSelfSpeaker and not IsSystemChannel(channel) then
        return
    end

    if type(message) == "string" and message ~= "" then
        local detected = DetectLanguageFromText(message, true)
        if detected then
            SetLanguage(detected)
            return
        end
    end
end

local function HandleRawEvent(event, a1, a2, a3, a4, a5, a6, a7, a8, a9)
    if event == "CHAT_MESSAGE" then
        OnChatMessage(a1, a2, a3, a4, a5, a6, a7, a8, a9)
        return
    end

    -- Check all arguments for the exact "Language changed to ... Continent Dialect." string
    if ScanAllArgsForExactMatch(a1, a2, a3, a4, a5, a6, a7, a8, a9) then
        return
    end

    if event == "NOTICE_MESSAGE" and type(a5) == "string" and a5 ~= "" then
        local myNameLower = GetMyPlayerNameLower()
        local speakerLower = string.lower(a5)
        if myNameLower ~= "" and speakerLower ~= myNameLower and speakerLower ~= "system" and speakerLower ~= "server" then
            return
        end
    end

    for i = 1, 9 do
        local v = select(i, a1, a2, a3, a4, a5, a6, a7, a8, a9)
        if type(v) == "string" and v ~= "" then
            local detected = DetectLanguageFromText(v, true)
            if detected then
                SetLanguage(detected)
                return
            end
        end
    end
end

local function GetDefaultTopLeftPos()
    local okH, screenH = pcall(function() return api.Interface:GetScreenHeight() end)
    if not okH or type(screenH) ~= "number" or screenH < 200 then
        screenH = 1080
    end
    lastScreenH = screenH
    return DEFAULT_X, screenH - DEFAULT_BOTTOM_OFFSET
end

-- Returns a clearly visible spot right near the center of the screen so when
-- the player clicks the Reset Position arrow button, the indicator is
-- immediately obvious and easy to Shift+drag to the desired spot.
local function GetVisibleResetPos()
    local okW, screenW = pcall(function() return api.Interface:GetScreenWidth() end)
    local okH, screenH = pcall(function() return api.Interface:GetScreenHeight() end)
    if not okW or type(screenW) ~= "number" or screenW < 300 then screenW = 1920 end
    if not okH or type(screenH) ~= "number" or screenH < 200 then screenH = 1080 end
    return math.floor(screenW * 0.35), math.floor(screenH * 0.5)
end

local function ApplyPosition()
    if not indicatorWnd then return end
    indicatorWnd:RemoveAllAnchors()
    if state.customPos and type(state.x) == "number" and type(state.y) == "number" then
        indicatorWnd:AddAnchor("TOPLEFT", "UIParent", state.x, state.y)
    else
        local defX, defY = GetDefaultTopLeftPos()
        indicatorWnd:AddAnchor("TOPLEFT", "UIParent", defX, defY)
    end
end

local function ShowHoverTooltip()
    if not state.enabled or not tooltipWnd or not indicatorWnd then return end
    if IsBlockingWindowOpen and IsBlockingWindowOpen() then return end
    UpdateTooltipContent()
    tooltipWnd:Show(true)
    pcall(function() tooltipWnd:Raise() end)
end

local function HideHoverTooltip()
    if not tooltipWnd then return end
    tooltipWnd:Show(false)
end

local function SetEnabled(enabled)
    state.enabled = enabled and true or false
    SaveState()
    if enableCheckWidget then
        pcall(function() enableCheckWidget:SetChecked(state.enabled, false) end)
    end
    if indicatorWnd then
        indicatorWnd:Show(state.enabled)
        if not state.enabled then
            HideHoverTooltip()
            if settingsPopupWnd then settingsPopupWnd:Show(false) end
        end
    end
end

local function StartMoving()
    if not indicatorWnd then return end
    if not api.Input:IsShiftKeyDown() then return end
    HideHoverTooltip()
    indicatorWnd:StartMoving()
    api.Cursor:ClearCursor()
    api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
end

local function StopMoving()
    if not indicatorWnd then return end
    indicatorWnd:StopMovingOrSizing()
    api.Cursor:ClearCursor()
    local x, y = indicatorWnd:GetOffset()
    if type(x) == "number" and type(y) == "number" and
       x >= 0 and x <= SANE_COORD_LIMIT and y >= 0 and y <= SANE_COORD_LIMIT then
        state.x = x
        state.y = y
        state.customPos = true
        SaveState()
    end
end

local function WireShiftDragAndTooltip(widget)
    if not widget then return end
    pcall(function() widget:EnableDrag(true) end)
    function widget:OnDragStart() StartMoving() end
    widget:SetHandler("OnDragStart", widget.OnDragStart)
    function widget:OnDragStop() StopMoving() end
    widget:SetHandler("OnDragStop", widget.OnDragStop)
    function widget:OnEnter() ShowHoverTooltip() end
    widget:SetHandler("OnEnter", widget.OnEnter)
    function widget:OnLeave() HideHoverTooltip() end
    widget:SetHandler("OnLeave", widget.OnLeave)
end

local function CreateSliderStepper(parent, name, lblText, initVal, minVal, maxVal, onChange)
    local grp = parent:CreateChildWidget("emptywidget", name .. "Grp", 0, true)
    grp:SetExtent(220, 22)

    local lbl = grp:CreateChildWidget("label", name .. "Lbl", 0, true)
    lbl:SetAutoResize(true)
    lbl:SetText(lblText)
    lbl:AddAnchor("LEFT", grp, 0, 0)
    ApplyTextColor(lbl, FONT_COLOR.DEFAULT)

    local btnPlus = grp:CreateChildWidget("button", name .. "Plus", 0, true)
    btnPlus:AddAnchor("RIGHT", grp, 0, 0)
    btnPlus:SetText("+")
    api.Interface:ApplyButtonSkin(btnPlus, SMALL_BTN_SKIN)

    local valLbl = grp:CreateChildWidget("label", name .. "Val", 0, true)
    valLbl:SetExtent(28, 20)
    valLbl.style:SetAlign(ALIGN.CENTER)
    valLbl:SetText(tostring(initVal))
    valLbl:AddAnchor("RIGHT", btnPlus, "LEFT", -5, 0)
    ApplyTextColor(valLbl, FONT_COLOR.DEFAULT)

    local btnMinus = grp:CreateChildWidget("button", name .. "Minus", 0, true)
    btnMinus:AddAnchor("RIGHT", valLbl, "LEFT", -5, 0)
    btnMinus:SetText("-")
    api.Interface:ApplyButtonSkin(btnMinus, SMALL_BTN_SKIN)

    local currentVal = initVal
    local function UpdateValue(newVal)
        if newVal >= minVal and newVal <= maxVal then
            currentVal = newVal
            valLbl:SetText(tostring(currentVal))
            onChange(currentVal)
        end
    end

    grp.SetValue = function(_, v)
        currentVal = v
        valLbl:SetText(tostring(currentVal))
    end

    function btnMinus:OnClick() UpdateValue(currentVal - 1) end
    btnMinus:SetHandler("OnClick", btnMinus.OnClick)

    function btnPlus:OnClick() UpdateValue(currentVal + 1) end
    btnPlus:SetHandler("OnClick", btnPlus.OnClick)

    return grp
end

local function EnsureSettingsPopup()
    if settingsPopupWnd then
        if sizeStepper then
            sizeStepper:SetValue(state.size or 18)
        end
        if alphaStepper then
            alphaStepper:SetValue(math.floor((state.alpha or 1.0) * 10 + 0.5))
        end
        if bgAlphaStepper then
            bgAlphaStepper:SetValue(math.floor((state.bgAlpha or 0.6) * 10 + 0.5))
        end
        return settingsPopupWnd
    end

    -- Exact same popup window model as Range Meter (dynWnd) and Fishing Settings (_fishingSettingsWnd)
    settingsPopupWnd = api.Interface:CreateWindow("eluChatLangSettingsWnd", "Chat Language Settings", 300, 225)
    settingsPopupWnd:AddAnchor("CENTER", "UIParent", 0, 0)
    settingsPopupWnd:Show(false)
    pcall(function() settingsPopupWnd:SetCloseOnEscape(true) end)

    if settingsPopupWnd.titleBar and settingsPopupWnd.titleBar.bg then
        settingsPopupWnd.titleBar.bg:SetColor(40 / 255, 44 / 255, 52 / 255, 1.0)
    end
    if settingsPopupWnd.bg then
        settingsPopupWnd.bg:SetColor(24 / 255, 26 / 255, 31 / 255, 0.95)
    end

    sizeStepper = CreateSliderStepper(
        settingsPopupWnd,
        "chatLangSize",
        "Font Size:",
        state.size or 18,
        10,
        40,
        function(val)
            state.size = val
            ApplyAlphaAndColors()
            SaveState()
        end
    )
    sizeStepper:AddAnchor("TOP", settingsPopupWnd, 0, 55)

    alphaStepper = CreateSliderStepper(
        settingsPopupWnd,
        "chatLangAlpha",
        "Letter Opacity:",
        math.floor((state.alpha or 1.0) * 10 + 0.5),
        1,
        10,
        function(val)
            state.alpha = val / 10.0
            ApplyAlphaAndColors()
            SaveState()
        end
    )
    alphaStepper:AddAnchor("TOP", sizeStepper, "BOTTOM", 0, 12)

    bgAlphaStepper = CreateSliderStepper(
        settingsPopupWnd,
        "chatLangBgAlpha",
        "Box Opacity:",
        math.floor((state.bgAlpha or 0.6) * 10 + 0.5),
        0,
        10,
        function(val)
            state.bgAlpha = val / 10.0
            ApplyAlphaAndColors()
            SaveState()
        end
    )
    bgAlphaStepper:AddAnchor("TOP", alphaStepper, "BOTTOM", 0, 12)

    local resetDefBtn = settingsPopupWnd:CreateChildWidget("button", "chatLangResetDefBtn", 0, true)
    api.Interface:ApplyButtonSkin(resetDefBtn, BUTTON_BASIC.DEFAULT)
    resetDefBtn:SetText("Reset Defaults")
    resetDefBtn:SetExtent(120, 25)
    resetDefBtn:AddAnchor("TOP", bgAlphaStepper, "BOTTOM", 0, 18)

    function resetDefBtn:OnClick()
        state.size = 18
        state.alpha = 1.0
        state.bgAlpha = 0.6
        if sizeStepper then sizeStepper:SetValue(18) end
        if alphaStepper then alphaStepper:SetValue(10) end
        if bgAlphaStepper then bgAlphaStepper:SetValue(6) end
        ApplyAlphaAndColors()
        SaveState()
    end
    resetDefBtn:SetHandler("OnClick", resetDefBtn.OnClick)

    return settingsPopupWnd
end

function M.CreateUI(wndParent)
    LoadState()

    local container = wndParent:CreateChildWidget("emptywidget", "chatLanguageMiscSection", 0, true)
    container:SetExtent(500, 25)

    local enableCheck = container:CreateChildWidget("checkbutton", "chatLangEnableCheck", 0, true)
    enableCheck:SetExtent(18, 17)
    enableCheck:AddAnchor("TOPLEFT", container, 0, 4)
    enableCheckWidget = enableCheck

    local cbg1 = enableCheck:CreateImageDrawable("ui/button/check_button.dds", "background")
    cbg1:SetExtent(18, 17)
    cbg1:AddAnchor("CENTER", enableCheck, 0, 0)
    cbg1:SetCoords(0, 0, 18, 17)
    enableCheck:SetNormalBackground(cbg1)

    local cbg2 = enableCheck:CreateImageDrawable("ui/button/check_button.dds", "background")
    cbg2:SetExtent(18, 17)
    cbg2:AddAnchor("CENTER", enableCheck, 0, 0)
    cbg2:SetCoords(18, 0, 18, 17)
    enableCheck:SetCheckedBackground(cbg2)

    local cbg3 = enableCheck:CreateImageDrawable("ui/button/check_button.dds", "background")
    cbg3:SetExtent(18, 17)
    cbg3:AddAnchor("CENTER", enableCheck, 0, 0)
    cbg3:SetCoords(0, 0, 18, 17)
    enableCheck:SetPushedBackground(cbg3)

    local cbg4 = enableCheck:CreateImageDrawable("ui/button/check_button.dds", "background")
    cbg4:SetExtent(18, 17)
    cbg4:AddAnchor("CENTER", enableCheck, 0, 0)
    cbg4:SetCoords(18, 0, 18, 17)
    enableCheck:SetHighlightBackground(cbg4)

    local enableLbl = container:CreateChildWidget("label", "chatLangEnableLbl", 0, true)
    enableLbl:SetAutoResize(true)
    enableLbl:SetText("Chat Language: Enable H / N indicator")
    enableLbl:AddAnchor("LEFT", enableCheck, "RIGHT", 6, 0)
    ApplyTextColor(enableLbl, FONT_COLOR.DEFAULT)

    local checkboxGap = 6
    local labelWidth = enableLbl:GetWidth() or 220
    local totalWidth = 18 + checkboxGap + labelWidth
    local containerWidth = container:GetWidth() or 500
    local startX = math.floor((containerWidth - totalWidth) / 2)
    enableCheck:RemoveAllAnchors()
    enableCheck:AddAnchor("TOPLEFT", container, startX, 4)

    enableCheck:SetChecked(state.enabled, false)

    function enableCheck:OnCheckChanged()
        SetEnabled(self:GetChecked())
    end
    enableCheck:SetHandler("OnCheckChanged", enableCheck.OnCheckChanged)

    -- Reset Position arrow button (moves indicator to a very visible center-screen spot)
    local resetPosBtn = container:CreateChildWidget("button", "chatLangResetPosBtn", 0, true)
    resetPosBtn:AddAnchor("LEFT", enableLbl, "RIGHT", 10, 0)
    api.Interface:ApplyButtonSkin(resetPosBtn, BUTTON_BASIC.RESET)

    function resetPosBtn:OnEnter()
        local x, y = self:GetOffset()
        api.Interface:SetTooltipOnPos("Moves the H / N indicator to a visible spot in the middle of the screen.\nHold Shift + drag the letter to move it anywhere.", container, x, y + 25)
    end
    function resetPosBtn:OnLeave()
        local x, y = self:GetOffset()
        api.Interface:SetTooltipOnPos(nil, container, x, y + 25)
    end
    resetPosBtn:SetHandler("OnEnter", resetPosBtn.OnEnter)
    resetPosBtn:SetHandler("OnLeave", resetPosBtn.OnLeave)

    function resetPosBtn:OnClick()
        local visX, visY = GetVisibleResetPos()
        state.x = visX
        state.y = visY
        state.customPos = true
        state.enabled = true
        if enableCheckWidget then
            pcall(function() enableCheckWidget:SetChecked(true, false) end)
        end
        SaveState()
        if indicatorWnd then
            ApplyPosition()
            indicatorWnd:Show(true)
        end
    end
    resetPosBtn:SetHandler("OnClick", resetPosBtn.OnClick)

    -- Gear button to open size & transparency settings
    local gearBtn = container:CreateChildWidget("button", "chatLangGearBtn", 0, true)
    gearBtn:SetExtent(20, 20)
    gearBtn:AddAnchor("LEFT", resetPosBtn, "RIGHT", 6, 0)

    local blankBg = gearBtn:CreateColorDrawable(0, 0, 0, 0, "background")
    gearBtn:SetNormalBackground(blankBg)
    gearBtn:SetPushedBackground(blankBg)
    gearBtn:SetHighlightBackground(blankBg)
    gearBtn:SetDisabledBackground(blankBg)

    local gearImg = gearBtn:CreateImageDrawable("Addon/Elu_Tracker/gear.png", "background")
    gearImg:AddAnchor("TOPLEFT", gearBtn, 0, 0)
    gearImg:AddAnchor("BOTTOMRIGHT", gearBtn, 0, 0)

    function gearBtn:OnEnter()
        gearImg:RemoveAllAnchors()
        gearImg:AddAnchor("TOPLEFT", gearBtn, -2, -2)
        gearImg:AddAnchor("BOTTOMRIGHT", gearBtn, 2, 2)
        local x, y = self:GetOffset()
        api.Interface:SetTooltipOnPos("Adjust H / N indicator size and transparency (opacity).", container, x, y + 25)
    end
    function gearBtn:OnLeave()
        gearImg:RemoveAllAnchors()
        gearImg:AddAnchor("TOPLEFT", gearBtn, 0, 0)
        gearImg:AddAnchor("BOTTOMRIGHT", gearBtn, 0, 0)
        local x, y = self:GetOffset()
        api.Interface:SetTooltipOnPos(nil, container, x, y + 25)
    end
    gearBtn:SetHandler("OnEnter", gearBtn.OnEnter)
    gearBtn:SetHandler("OnLeave", gearBtn.OnLeave)

    function gearBtn:OnClick()
        local popup = EnsureSettingsPopup()
        local nextVis = not popup:IsVisible()
        popup:Show(nextVis)
        if nextVis then
            pcall(function() popup:Raise() end)
        end
    end
    gearBtn:SetHandler("OnClick", gearBtn.OnClick)

    return container
end

local function SyncCharacterStateIfNeeded()
    local ck = GetCurrentCharKey()
    if ck and ck ~= currentCharKey then
        LoadState()
        if enableCheckWidget then
            pcall(function() enableCheckWidget:SetChecked(state.enabled, false) end)
        end
        if sizeStepper then sizeStepper:SetValue(state.size or 18) end
        if alphaStepper then alphaStepper:SetValue(math.floor((state.alpha or 1.0) * 10 + 0.5)) end
        if bgAlphaStepper then bgAlphaStepper:SetValue(math.floor((state.bgAlpha or 0.6) * 10 + 0.5)) end
        ApplyPosition()
        UpdateVisual()
        if indicatorWnd then
            indicatorWnd:Show(state.enabled)
        end
    end
end

-- Windows/frames that must always stay in front of the indicator.
local BLOCKING_UIC_NAMES = {
    "BAG", "BANK", "COFFER", "CHARACTER_INFO", "OPTION_FRAME", "SYSTEM_CONFIG_FRAME",
    "GAME_EXIT_FRAME", "SLAVE_EQUIPMENT", "RAID_MANAGER", "COMMUNITY_WINDOW",
    "ENCHANT_WINDOW", "ABILITY_CHANGE", "MAIL_BOX", "MAIL", "AUCTION", "AUCTION_WINDOW",
    "TRADE", "STORE", "CRAFT", "WORLD_MAP", "QUEST_LIST", "SKILL_WINDOW", "ABILITY_WINDOW",
}

local function IsBlockingWindowOpen()
    if type(UIC) == "table" and ADDON and ADDON.GetContent then
        for i = 1, #BLOCKING_UIC_NAMES do
            local id = UIC[BLOCKING_UIC_NAMES[i]]
            if id ~= nil then
                local ok, vis = pcall(function()
                    local w = ADDON:GetContent(id)
                    return w and w.IsVisible and w:IsVisible()
                end)
                if ok and vis then return true end
            end
        end
    end
    local okE, eluVis = pcall(function()
        return eluDisplayWindow and eluDisplayWindow:IsVisible()
    end)
    if okE and eluVis then return true end
    if settingsPopupWnd and settingsPopupWnd:IsVisible() then return true end
    return false
end

local function OnUpdate(dt)
    if currentCharKey == nil then
        charCheckTimer = charCheckTimer + (type(dt) == "number" and dt or 0)
        if charCheckTimer >= 500 then
            charCheckTimer = 0
            SyncCharacterStateIfNeeded()
        end
    end

    if not indicatorWnd then return end

    if not state.enabled then
        if indicatorWnd:IsVisible() then
            indicatorWnd:Show(false)
        end
        return
    end

    if not indicatorWnd:IsVisible() then
        indicatorWnd:Show(true)
    end

    -- Click-through: only clickable while Shift is held (Shift + drag to move).
    local shift = api.Input:IsShiftKeyDown() and true or false
    if shift ~= shiftClickable then
        shiftClickable = shift
        pcall(function() indicatorWnd:Clickable(shift) end)
        if dragOverlay then pcall(function() dragOverlay:Clickable(shift) end) end
    end

    -- Hover tooltip driven by mouse position (works while click-through).
    if not shift then
        local mx, my = api.Input:GetMousePos()
        local ox, oy = indicatorWnd:GetOffset()
        local w, h = indicatorWnd:GetExtent()
        local inside = false
        if mx and my and ox and oy and w and h then
            inside = mx >= ox and mx <= ox + w and my >= oy and my <= oy + h
        end
        if inside ~= hoverShown then
            hoverShown = inside
            if inside then ShowHoverTooltip() else HideHoverTooltip() end
        end
    end

    if not state.customPos then
        checkScreenTimer = checkScreenTimer + (type(dt) == "number" and dt or 0)
        if checkScreenTimer >= 1000 then
            checkScreenTimer = 0
            local okH, screenH = pcall(function() return api.Interface:GetScreenHeight() end)
            if okH and type(screenH) == "number" and screenH >= 200 and screenH ~= lastScreenH then
                ApplyPosition()
            end
        end
    end
end

local function OnLoad()
    if indicatorWnd or _onLoadStarted then return end
    _onLoadStarted = true

    LoadState()

    local fontSize = state.size or 18
    local boxSize = math.max(28, fontSize + 12)

    indicatorWnd = api.Interface:CreateEmptyWindow("eluChatLanguageWnd")
    pcall(function() indicatorWnd:Clickable(false) end)
    indicatorWnd:SetExtent(boxSize, boxSize)
    ApplyPosition()

    -- Same single-drawable HUD box style as Stopwatch, Quick Equip, Loot Overlay, and Trip Counter
    bgBorder = indicatorWnd:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bgBorder:SetTextureInfo("bg_quest")
    bgBorder:SetColor(0, 0, 0, 0.6)
    bgBorder:AddAnchor("TOPLEFT", indicatorWnd, 0, 0)
    bgBorder:AddAnchor("BOTTOMRIGHT", indicatorWnd, 0, 0)

    langLabel = indicatorWnd:CreateChildWidget("label", "langLabel", 0, true)
    langLabel:SetExtent(boxSize, boxSize)
    langLabel:AddAnchor("CENTER", indicatorWnd, 0, 0)
    langLabel.style:SetAlign(ALIGN.CENTER)
    langLabel.style:SetFontSize(fontSize)
    if langLabel.style.SetShadow then langLabel.style:SetShadow(true) end
    if langLabel.style.SetOutline then langLabel.style:SetOutline(true) end
    if langLabel.Clickable then
        pcall(function() langLabel:Clickable(false) end)
    end

    dragOverlay = indicatorWnd:CreateChildWidget("emptywidget", "chatLangDragOverlay", 0, true)
    dragOverlay:AddAnchor("TOPLEFT", indicatorWnd, 0, 0)
    dragOverlay:AddAnchor("BOTTOMRIGHT", indicatorWnd, 0, 0)
    dragOverlay:Show(true)
    pcall(function() dragOverlay:Clickable(false) end)
    shiftClickable = false

    -- Hover tooltip displaying "Nuia" or "Haranya" right above the indicator
    tooltipWnd = api.Interface:CreateEmptyWindow("eluChatLangTooltip")
    tooltipWnd:SetExtent(74, 26)
    tooltipWnd:AddAnchor("BOTTOM", indicatorWnd, "TOP", 0, -4)
    tooltipWnd:Show(false)
    if tooltipWnd.Clickable then
        pcall(function() tooltipWnd:Clickable(false) end)
    end

    pcall(function()
        local tBg = tooltipWnd:CreateNinePartDrawable("ui/common_new/default.dds", "background")
        tBg:SetTextureInfo("tooltip")
        tBg:AddAnchor("TOPLEFT", tooltipWnd, 0, 0)
        tBg:AddAnchor("BOTTOMRIGHT", tooltipWnd, 0, 0)
        tBg:SetColor(1, 1, 1, 0.95)
    end)

    tooltipLabel = tooltipWnd:CreateChildWidget("label", "tooltipLabel", 0, true)
    tooltipLabel:SetExtent(64, 20)
    tooltipLabel:AddAnchor("CENTER", tooltipWnd, 0, 0)
    tooltipLabel.style:SetAlign(ALIGN.CENTER)
    tooltipLabel.style:SetFontSize(FONT_SIZE.MIDDLE or 13)
    if tooltipLabel.style.SetShadow then tooltipLabel.style:SetShadow(true) end
    if tooltipLabel.Clickable then
        pcall(function() tooltipLabel:Clickable(false) end)
    end

    WireShiftDragAndTooltip(indicatorWnd)
    WireShiftDragAndTooltip(langLabel)
    WireShiftDragAndTooltip(dragOverlay)

    UpdateVisual()
    indicatorWnd:Show(state.enabled)
    if state.enabled then
        pcall(function() indicatorWnd:Raise() end)
    end

    eventWnd = api.Interface:CreateEmptyWindow("eluChatLanguageEventWnd", "UIParent")
    function eventWnd:OnEvent(event, a1, a2, a3, a4, a5, a6, a7, a8, a9)
        if arg ~= nil and a1 == nil then
            HandleRawEvent(event, arg[1], arg[2], arg[3], arg[4], arg[5], arg[6], arg[7], arg[8], arg[9])
        else
            HandleRawEvent(event, a1, a2, a3, a4, a5, a6, a7, a8, a9)
        end
    end
    eventWnd:SetHandler("OnEvent", eventWnd.OnEvent)

    local eventsToWatch = {
        -- CHAT_MESSAGE is dispatched centrally by main.lua; CHAT_MSG_SYSTEM
        -- is not a valid event (logged a warning on every load).
        "SYS_MSG",
        "SYSTEM_MESSAGE",
        "NOTICE_MESSAGE",
        "WORLD_MESSAGE",
        "CHAT_FAILED",
        "CHAT_MSG_ALARM",
        "SET_UI_MESSAGE",
        "ERROR_MESSAGE",
        "UI_ERROR_MESSAGE",
        "CHAT_JOINED_CHANNEL",
        "CHAT_LEAVED_CHANNEL",
    }
    for _, ev in ipairs(eventsToWatch) do
        pcall(function() eventWnd:RegisterEvent(ev) end)
    end
    eventWnd:Show(true)
end

local function OnUnload()
    _onLoadStarted = false
    SaveState()
    currentCharKey = nil
    hoverShown = false

    enableCheckWidget = nil
    sizeStepper = nil
    alphaStepper = nil
    bgAlphaStepper = nil

    if settingsPopupWnd ~= nil then
        settingsPopupWnd:Show(false)
        pcall(function() api.Interface:Free(settingsPopupWnd) end)
        settingsPopupWnd = nil
    end

    if eventWnd ~= nil then
        pcall(function() eventWnd:ReleaseHandler("OnEvent") end)
        eventWnd:Show(false)
        pcall(function() api.Interface:Free(eventWnd) end)
        eventWnd = nil
    end

    if tooltipWnd ~= nil then
        tooltipWnd:Show(false)
        pcall(function() api.Interface:Free(tooltipWnd) end)
        tooltipWnd = nil
        tooltipLabel = nil
    end

    if indicatorWnd ~= nil then
        indicatorWnd:Show(false)
        pcall(function() api.Interface:Free(indicatorWnd) end)
        indicatorWnd = nil
        langLabel = nil
        bgBorder = nil
        dragOverlay = nil
    end
end

M.OnLoad = OnLoad
M.OnUnload = OnUnload
M.OnUpdate = OnUpdate
M.OnChatMessage = OnChatMessage

return M
