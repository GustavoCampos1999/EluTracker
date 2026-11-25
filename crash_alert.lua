local api = require("api")

local crash_age = {
	name = "Crash Me",
	author = "Eludelu",
	version = "1.1.0",
	desc = "Memory tracker and crash warning system",
}

local settingsManager = require("Elu_Tracker/settings_manager")
local EluTrackerSettings = settingsManager.Settings
local SaveEluTrackerSettings = settingsManager.SaveSettings

local MAX_MEMORY = 3288

local config = {
    enabled = false,
	thresholds = { 3100, 3150 },
    critical = 3200,
	showLiveUsage = false,
	warnOffsetX = 400,
	warnOffsetY = 100,
	crashCommand = "/crash",
	liveOffsetX = 400,
	liveOffsetY = 170,
}

local timeSinceLastWarnCheck = 0
local warnCheckInterval = 5000

local triggeredThresholds = {}
local criticalTriggered = false
local moveMode = false

local configWnd = nil
local cornerWarningWnd = nil
local liveUsageWnd = nil
local cornerWarningHideTime = 0

local function SaveConfig()
    EluTrackerSettings.crash_alert = config
    SaveEluTrackerSettings()
end

local function LoadConfig()
	pcall(function()
		local data = EluTrackerSettings.crash_alert
			if type(data) == "table" then
				if data.thresholds then
					config.thresholds = data.thresholds
				end
				if data.critical then
					config.critical = data.critical
				end
				if data.enabled ~= nil then
					config.enabled = data.enabled
				end
				if data.showLiveUsage ~= nil then
					config.showLiveUsage = data.showLiveUsage
				end
				if data.warnOffsetX ~= nil then
					config.warnOffsetX = data.warnOffsetX
				end
				if data.warnOffsetY ~= nil then
					config.warnOffsetY = data.warnOffsetY
				end
				if data.crashCommand ~= nil then
					config.crashCommand = data.crashCommand
				end
				if data.liveOffsetX ~= nil then
					config.liveOffsetX = data.liveOffsetX
				end
				if data.liveOffsetY ~= nil then
					config.liveOffsetY = data.liveOffsetY
				end
			end
	end)
	table.sort(config.thresholds)
end

local LEARN_FILE = "elu_crash_learn.lua"
local LEARN_SAVE_INTERVAL = 30000
local MIN_LEARN_SAMPLES = 3
local CEILING_MARGIN = 100
local MAX_LEARN_HISTORY = 8
local LEARN_CRITICAL_MAX = 3800
local BASELINE_MAX_MEMORY = 3288

local CRITICAL_PERCENT = 0.9732

local LEARN_CRASH_FILTER_MB = 3000

local learnState = {
    cleanExit = true,
    lastMB = nil,
    sessionMaxMB = nil,
    crashFloor = {},
    safeCeiling = {},
    deliberateCrash = false,
}
local timeSinceLastLearnSave = 0

local function LoadLearnState()
    local ok, data = pcall(function() return api.File:Read(LEARN_FILE) end)
    if ok and type(data) == "table" then
        if data.cleanExit ~= nil then learnState.cleanExit = data.cleanExit end
        if data.lastMB ~= nil then learnState.lastMB = data.lastMB end
        if type(data.crashFloor) == "table" then learnState.crashFloor = data.crashFloor end
        if type(data.safeCeiling) == "table" then learnState.safeCeiling = data.safeCeiling end
        if data.deliberateCrash ~= nil then learnState.deliberateCrash = data.deliberateCrash end
    end
end

local function SaveLearnState()
    pcall(function() api.File:Write(LEARN_FILE, learnState) end)
end

local function MarkDeliberateCrash()
    learnState.deliberateCrash = true
    SaveLearnState()
end

local function TriggerDeliberateCrash()
    MarkDeliberateCrash()

    if type(os) == "table" and type(os.exit) == "function" then
        os.exit(0)
    end
    if type(System) == "table" and type(System.Quit) == "function" then
        System.Quit()
    end

    local chunks = {}
    local block = "CRASH_BLOCK_16B_"
    for _ = 1, 25 do
        block = block .. block
    end
    while true do
        pcall(function()
            chunks[#chunks + 1] = block .. tostring(#chunks)
        end)
    end
end

local function AddCapped(list, value)
    table.insert(list, value)
    if #list > MAX_LEARN_HISTORY then
        table.remove(list, 1)
    end
end

local function RecalibrateFromLearning()
    local ceiling = BASELINE_MAX_MEMORY

    if #learnState.safeCeiling >= MIN_LEARN_SAMPLES then
        local highest = 0
        for _, v in ipairs(learnState.safeCeiling) do
            if v > highest then highest = v end
        end
        if highest + CEILING_MARGIN > ceiling then
            ceiling = math.min(LEARN_CRITICAL_MAX, highest + CEILING_MARGIN)
        end
    end

    MAX_MEMORY = ceiling
    config.critical = math.floor(ceiling * CRITICAL_PERCENT + 0.5)
    config.thresholds = { config.critical - 100, config.critical - 50 }
    pcall(SaveConfig)
end

local function CheckForInferredCrashAndReset()
    LoadLearnState()

    if not learnState.cleanExit and not learnState.deliberateCrash and learnState.lastMB
        and learnState.lastMB >= LEARN_CRASH_FILTER_MB then
        AddCapped(learnState.crashFloor, learnState.lastMB)
    end

    learnState.cleanExit = false
    learnState.deliberateCrash = false
    learnState.lastMB = nil
    learnState.sessionMaxMB = nil
    RecalibrateFromLearning()
    SaveLearnState()
end

LoadConfig()
CheckForInferredCrashAndReset()

local function GetMemoryString(mb)
	local pct = math.floor((mb / MAX_MEMORY) * 100)
	return string.format("%d MB (%d%%)", mb, pct)
end

local function ShowCornerWarning(text, isCritical)
    if cornerWarningWnd == nil then
        cornerWarningWnd = api.Interface:CreateEmptyWindow("crashAgeTopWarning", "UIParent")
        cornerWarningWnd:SetExtent(500, 50)
        
        cornerWarningWnd.bgCol = cornerWarningWnd:CreateColorDrawable(0, 0, 0, 0.5, "background")
        cornerWarningWnd.bgCol:AddAnchor("TOPLEFT", cornerWarningWnd, 0, 0)
        cornerWarningWnd.bgCol:AddAnchor("BOTTOMRIGHT", cornerWarningWnd, 0, 0)
        
        cornerWarningWnd.bg = cornerWarningWnd:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
        cornerWarningWnd.bg:SetTextureInfo("bg_quest")
        cornerWarningWnd.bg:SetColor(0, 0, 0, 0.5)
        cornerWarningWnd.bg:AddAnchor("TOPLEFT", cornerWarningWnd, "TOPLEFT", 0, 0)
        cornerWarningWnd.bg:AddAnchor("BOTTOMRIGHT", cornerWarningWnd, "BOTTOMRIGHT", 0, 0)

        local label = cornerWarningWnd:CreateChildWidget("label", "warnLabel", 0, true)
        label:AddAnchor("CENTER", cornerWarningWnd, "CENTER", 0, 0)
        label.style:SetFontSize(24)
        label.style:SetShadow(true)

        function cornerWarningWnd:OnClick()
            if not criticalTriggered and not moveMode then
                cornerWarningWnd:Show(false)
                cornerWarningHideTime = 0
            end
        end
        cornerWarningWnd:SetHandler("OnClick", cornerWarningWnd.OnClick)

        function cornerWarningWnd:OnDragStart()
            if moveMode then self:StartMoving() end
        end
        cornerWarningWnd:SetHandler("OnDragStart", cornerWarningWnd.OnDragStart)

        function cornerWarningWnd:OnDragStop()
            self:StopMovingOrSizing()
            local x, y = self:GetOffset()
            if x and y then
                config.warnOffsetX = x
                config.warnOffsetY = y
                SaveConfig()
            end
        end
        cornerWarningWnd:SetHandler("OnDragStop", cornerWarningWnd.OnDragStop)
    end

    cornerWarningWnd.warnLabel:SetText(text)

    if isCritical then
        cornerWarningWnd.warnLabel.style:SetColor(1, 0.1, 0.1, 1)
    else
        cornerWarningWnd.warnLabel.style:SetColor(1, 0.6, 0, 1)
    end
    if isCritical then
        cornerWarningHideTime = api.Time:GetUiMsec() + 20000
    else
        cornerWarningHideTime = api.Time:GetUiMsec() + 10000
    end

    cornerWarningWnd:RemoveAllAnchors()
    cornerWarningWnd:AddAnchor("TOPLEFT", "UIParent", "TOPLEFT", config.warnOffsetX, config.warnOffsetY)
    
    cornerWarningWnd:EnableDrag(moveMode)
    
    if cornerWarningWnd.SetAlpha then
        cornerWarningWnd:SetAlpha(1.0)
    end

    cornerWarningWnd:Show(true)
        if cornerWarningWnd.bgCol then cornerWarningWnd.bgCol:SetColor(0, 0, 0, moveMode and 0.7 or 0.01) end
end

local function UpdateLiveUsage(currentMB)
    if not config.enabled or not config.showLiveUsage then
        if liveUsageWnd then
            liveUsageWnd:Show(false)
        end
        return
    end

    if liveUsageWnd == nil then
        liveUsageWnd = api.Interface:CreateEmptyWindow("crashAgeLiveUsage", "UIParent")
        liveUsageWnd:SetExtent(200, 30)

        local bgCol = liveUsageWnd:CreateColorDrawable(0, 0, 0, 0, "background")
        bgCol:AddAnchor("TOPLEFT", liveUsageWnd, "TOPLEFT", 0, 0)
        bgCol:AddAnchor("BOTTOMRIGHT", liveUsageWnd, "BOTTOMRIGHT", 0, 0)
        liveUsageWnd.bgCol = bgCol

        local label = liveUsageWnd:CreateChildWidget("label", "memLabel", 0, true)
        label:AddAnchor("LEFT", liveUsageWnd, "LEFT", 5, 0)
        label.style:SetFontSize(15)
        label.style:SetAlign(ALIGN.LEFT)
        label.style:SetOutline(true)
        label.style:SetShadow(true)

        function liveUsageWnd:OnDragStart()
            if moveMode then self:StartMoving() end
        end
        liveUsageWnd:SetHandler("OnDragStart", liveUsageWnd.OnDragStart)

        function liveUsageWnd:OnDragStop()
            self:StopMovingOrSizing()
            local x, y = self:GetOffset()
            if x and y then
                config.liveOffsetX = x
                config.liveOffsetY = y
                SaveConfig()
            end
        end
        liveUsageWnd:SetHandler("OnDragStop", liveUsageWnd.OnDragStop)
    end

    if moveMode then
        liveUsageWnd.bgCol:SetColor(0, 0, 0, 0.7)
    else
        liveUsageWnd.bgCol:SetColor(0, 0, 0, 0)
    end
    liveUsageWnd:EnableDrag(moveMode)

    liveUsageWnd:RemoveAllAnchors()
    liveUsageWnd:AddAnchor("TOPLEFT", "UIParent", "TOPLEFT", config.liveOffsetX, config.liveOffsetY)
    liveUsageWnd:Show(true)

    local r, g, b = 0, 0.7, 0
    if currentMB >= config.critical then
        r, g, b = 1.0, 0.1, 0.1
    elseif currentMB >= config.thresholds[2] then
        r, g, b = 1.0, 0.5, 0.0
    elseif currentMB >= config.thresholds[1] then
        r, g, b = 1.0, 1.0, 0.0
    end

    if liveUsageWnd.memLabel then
        liveUsageWnd.memLabel:SetText("Mem: " .. GetMemoryString(currentMB))
        liveUsageWnd.memLabel.style:SetColor(r, g, b, 1)
    end
end

function crash_age.CreateUI(parentWnd)
    LoadConfig()
    if configWnd then
        return configWnd
    end

    if not config.crashCommand or config.crashCommand == "" then
        config.crashCommand = "/crash"
    end

    configWnd = parentWnd:CreateChildWidget("emptywidget", "crashAgeSettingsWnd", 0, true)
    configWnd:SetExtent(500, 92)
    configWnd:AddAnchor("TOP", parentWnd, "TOP", 0, 175)
    configWnd:Show(true)

    local title = configWnd:CreateChildWidget("label", "title", 0, true)
    title:SetAutoResize(false)
    title:SetExtent(300, 26)
    title.style:SetAlign(ALIGN.CENTER)
    title.style:SetFontSize(FONT_SIZE.XXLARGE)
    if FONT_COLOR and FONT_COLOR.TITLE then
        ApplyTextColor(title, FONT_COLOR.TITLE)
    else
        title.style:SetColor(1, 1, 1, 1)
    end
    title:SetText("Crash Me")
    title:AddAnchor("TOP", configWnd, "TOP", 0, 0)

    local sLabel = configWnd:CreateChildWidget("label", "sLabel", 0, true)
    sLabel:SetText("Crash Command:")
    sLabel:SetExtent(320, 20)
    sLabel:AddAnchor("TOP", configWnd, "TOP", 0, 32)
    sLabel.style:SetAlign(ALIGN.CENTER)
    if FONT_COLOR and FONT_COLOR.DEFAULT then
        ApplyTextColor(sLabel, FONT_COLOR.DEFAULT)
    else
        sLabel.style:SetColor(0.85, 0.85, 0.85, 1)
    end

    local row = configWnd:CreateChildWidget("emptywidget", "crashMeRow", 0, true)
    row:SetExtent(310, 30)
    row:AddAnchor("TOP", configWnd, "TOP", 0, 56)

    local sEdit = W_CTRL.CreateEdit("crashAgeSlashEdit", row)
    sEdit:SetExtent(195, 30)
    sEdit:AddAnchor("LEFT", row, 0, 0)
    sEdit:SetText(tostring(config.crashCommand or "/crash"))
    configWnd.sEdit = sEdit

    local function syncCommandFromInput(allowFallback)
        if not configWnd or not configWnd.sEdit then return end
        local sCmd = configWnd.sEdit:GetText()
        sCmd = type(sCmd) == "string" and (sCmd:match("^%s*(.-)%s*$") or sCmd) or ""
        if sCmd ~= "" then
            config.crashCommand = sCmd
            SaveConfig()
        elseif allowFallback then
            config.crashCommand = "/crash"
            configWnd.sEdit:SetText("/crash")
            SaveConfig()
        end
    end

    sEdit:SetHandler("OnTextChanged", function()
        syncCommandFromInput(false)
    end)
    sEdit:SetHandler("OnEnterPressed", function()
        syncCommandFromInput(true)
    end)
    sEdit:SetHandler("OnKillFocus", function()
        syncCommandFromInput(true)
    end)

    local forceCrashBtn = row:CreateChildWidget("button", "forceCrashBtn", 0, true)
    forceCrashBtn:SetText("Crash")
    if api and api.Interface and api.Interface.ApplyButtonSkin then
        api.Interface:ApplyButtonSkin(forceCrashBtn, BUTTON_BASIC.DEFAULT)
    end
    forceCrashBtn:SetExtent(105, 30)
    forceCrashBtn:AddAnchor("RIGHT", row, 0, 0)

    forceCrashBtn:SetHandler("OnClick", function()
        syncCommandFromInput(true)
        TriggerDeliberateCrash()
    end)

    return configWnd
end

local function OnUpdate(dt)
end

local function HandleChatCommand(
	channel,
	unit,
	isHostile,
	name,
	message,
	speakerInChatBound,
	specifyName,
	factionName,
	trialPosition
)
	if channel == 2 then
		return
	end
	if type(message) ~= "string" or type(config.crashCommand) ~= "string" or config.crashCommand == "" then
		return
	end

	local trimmedMsg = message:match("^%s*(.-)%s*$") or message
	local targetCmd = config.crashCommand:match("^%s*(.-)%s*$") or config.crashCommand
	if string.lower(trimmedMsg) ~= string.lower(targetCmd) then
		return
	end

	local playerName = api.Unit:GetUnitNameById(api.Unit:GetUnitId("player"))
	local isSelf = (playerName == name)
		or (type(playerName) == "string" and type(name) == "string" and string.lower(playerName) == string.lower(name))
	if isSelf then
		TriggerDeliberateCrash()
	end
end

local function OnLoad()

	CheckForInferredCrashAndReset()

	if cornerWarningWnd then
		cornerWarningWnd:Show(false)
	end
	if liveUsageWnd then
		liveUsageWnd:Show(false)
	end
end

local function OnUnload()

	if learnState.sessionMaxMB and learnState.sessionMaxMB >= config.critical then
		AddCapped(learnState.safeCeiling, learnState.sessionMaxMB)
	end
	learnState.cleanExit = true
	RecalibrateFromLearning()
	SaveLearnState()

	if configWnd then
		configWnd:Show(false)
		configWnd = nil
	end

	if cornerWarningWnd then
		cornerWarningWnd:Show(false)
	end

	if liveUsageWnd then
		liveUsageWnd:Show(false)
	end
end

local function OnSettingToggle()
	if configWnd then
		configWnd:Show(not configWnd:IsVisible())
	end
end

crash_age.OnLoad = OnLoad
crash_age.OnUnload = OnUnload
crash_age.HandleChatCommand = HandleChatCommand

crash_age.OnUpdate = OnUpdate

return crash_age
