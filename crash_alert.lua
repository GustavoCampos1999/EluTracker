local api = require("api")

local crash_age = {
	name = "Crash Alert",
	author = "Eludelu",
	version = "1.1.0",
	desc = "Memory tracker and crash warning system",
}

local settingsManager = require("Elu_Tracker/settings_manager")
local EluTrackerSettings = settingsManager.Settings
local SaveEluTrackerSettings = settingsManager.SaveSettings

local MAX_MEMORY = 3234

-- NOTE: this module used to keep its own private copy of these settings and
-- save/load them by directly reading and rewriting elu_tracker_settings.lua
-- itself (see the old SaveConfig/LoadConfig, since replaced below). That
-- was a real bug: this file and settings_manager.lua were BOTH
-- independently reading and fully rewriting the SAME shared settings file,
-- with no coordination between them. Every time ANY other Elu Tracker
-- module (Range Meter, Quick Equip, Guild Check, etc.) saved its own
-- settings via settingsManager.SaveSettings(), that call rewrites the
-- *entire* file from settingsManager's own in-memory table -- which only
-- ever held a stale snapshot of this module's config (captured once,
-- whenever this module's own LoadConfig() last ran), since this module
-- never wrote its changes into that shared table. So any Crash Alert
-- change was silently discarded the next time literally anything else in
-- the addon saved -- which is essentially "every time you touch the game",
-- given how often the other modules call SaveSettings(). Fixed by storing
-- this module's config the same way every other Elu Tracker module does
-- (see quick_equip.lua/range_meter.lua): as a key inside the ONE shared
-- settings table, saved through the shared SaveSettings() so there is only
-- ever a single writer for the whole file.
local config = {
    enabled = false,
	thresholds = { 2900, 3100 },
    critical = 3200,
	showLiveUsage = false,
	warnOffsetX = 400,
	warnOffsetY = 100,
	crashCommand = "/crash",
	liveOffsetX = 400,
	liveOffsetY = 170,
}

local timeSinceLastWarnCheck = 0
local warnCheckInterval = 5000 -- 5 seconds for checking warnings AND UI update

local triggeredThresholds = {}
local criticalTriggered = false
local moveMode = false

local configWnd = nil
local cornerWarningWnd = nil
local liveUsageWnd = nil
local cornerWarningHideTime = 0

local function SaveConfig()
    -- Single writer now: stash our config under the shared settings table
    -- and let settings_manager.lua do the one-and-only file write, exactly
    -- like every other Elu Tracker module.
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

-- Load immediately at require-time (not only from CreateUI/OnLoad). Other
-- modules' OnUpdate/HandleChatCommand can run before the Misc tab UI is
-- ever built, and used to see the hardcoded defaults (e.g. enabled=false)
-- until CreateUI() happened to run -- same class of desync bug that
-- quick_equip.lua's LoadQuickEquipSettings() comment explains in detail.
LoadConfig()

local function GetMemoryString(mb)
	local pct = math.floor((mb / MAX_MEMORY) * 100)
	return string.format("%d MB (%d%%)", mb, pct)
end

local function ShowCornerWarning(text, isCritical)
    if cornerWarningWnd == nil then
        cornerWarningWnd = api.Interface:CreateEmptyWindow("crashAgeTopWarning", "UIParent")
        cornerWarningWnd:SetExtent(500, 50)
        
        -- Use a color drawable to ensure the background catches clicks
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
        cornerWarningWnd.warnLabel.style:SetColor(1, 0, 0, 1)
        cornerWarningHideTime = 0
    else
        cornerWarningWnd.warnLabel.style:SetColor(1, 0.6, 0, 1)
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
    elseif currentMB >= config.thresholds[1] then
        r, g, b = 1.0, 0.5, 0.0
    elseif currentMB >= (config.thresholds[1] - 200) then
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

    configWnd = parentWnd:CreateChildWidget("emptywidget", "crashAgeSettingsWnd", 0, true)
    configWnd:SetExtent(500, 220)
    configWnd:AddAnchor("TOP", parentWnd, "TOP", 0, 175) -- fallback position; main.lua re-anchors this under the previous Misc section
    configWnd:Show(true)
    
    local title = configWnd:CreateChildWidget("label", "title", 0, true)
    title:SetAutoResize(true)
    title.style:SetFontSize(FONT_SIZE.XXLARGE)
    if FONT_COLOR and FONT_COLOR.TITLE then
        ApplyTextColor(title, FONT_COLOR.TITLE)
    else
        title.style:SetColor(1, 1, 1, 1)
    end
    title:SetText("Crash Alert Settings")
    title:AddAnchor("TOP", configWnd, "TOP", 0, 10)

    
    
    
    
    local r1 = configWnd:CreateChildWidget("emptywidget", "r1", 0, true)
    r1:SetExtent(265, 30)
    r1:AddAnchor("TOP", title, "BOTTOM", 0, 15)

    local toggleMainBtn = r1:CreateChildWidget("button", "toggleMainBtn", 0, true)
    if api and api.Interface and api.Interface.ApplyButtonSkin then
        api.Interface:ApplyButtonSkin(toggleMainBtn, BUTTON_BASIC.DEFAULT)
    end
    local mainText = config.enabled and "Turn OFF" or "Turn ON"
    toggleMainBtn:SetText(mainText)
    toggleMainBtn:SetExtent(100, 30)
    toggleMainBtn:AddAnchor("LEFT", r1, 0, 0)

    local toggleLiveBtn = r1:CreateChildWidget("button", "toggleLiveBtn", 0, true)
    local btnText = config.showLiveUsage and "[X] Show Live Usage" or "[ ] Show Live Usage"
    toggleLiveBtn:SetText(btnText)
    toggleLiveBtn:SetExtent(160, 30)
    toggleLiveBtn:AddAnchor("RIGHT", r1, 0, 0)
    if api and api.Interface and api.Interface.ApplyButtonSkin then
        api.Interface:ApplyButtonSkin(toggleLiveBtn, BUTTON_BASIC.DEFAULT)
    end
    toggleLiveBtn:Show(config.enabled)

    toggleMainBtn:SetHandler("OnClick", function()
        config.enabled = not config.enabled
        local text = config.enabled and "Turn OFF" or "Turn ON"
        toggleMainBtn:SetText(text)
        toggleLiveBtn:Show(config.enabled)
        
        if not config.enabled then
            if liveUsageWnd then liveUsageWnd:Show(false) end
            if cornerWarningWnd then cornerWarningWnd:Show(false) end
        else
            if config.showLiveUsage and liveUsageWnd then liveUsageWnd:Show(true) end
        end
        SaveConfig()
    end)

    toggleLiveBtn:SetHandler("OnClick", function()
        config.showLiveUsage = not config.showLiveUsage
        local text = config.showLiveUsage and "[X] Show Live Usage" or "[ ] Show Live Usage"
        toggleLiveBtn:SetText(text)
        if liveUsageWnd then
            liveUsageWnd:Show(config.showLiveUsage)
        end
        SaveConfig()
    end)

    toggleLiveBtn:SetHandler("OnClick", function()
        config.showLiveUsage = not config.showLiveUsage
        local text = config.showLiveUsage and "[X] Show Live Usage" or "[ ] Show Live Usage"
        toggleLiveBtn:SetText(text)
        if liveUsageWidget then
            liveUsageWidget:Show(config.showLiveUsage)
        end
        SaveConfig()


        local mem = api.GetMemoryUsage()
        if mem then
            local currentMB = math.floor(mem < 100000 and mem or (mem / 1024 / 1024))
            UpdateLiveUsage(currentMB)
        end
    end)
    
    local sEdit = W_CTRL.CreateEdit("crashAgeSlashEdit", configWnd)
    sEdit:SetExtent(320, 30)
    sEdit:AddAnchor("TOP", r1, "BOTTOM", 0, 35)
    sEdit:SetText(tostring(config.crashCommand))
    configWnd.sEdit = sEdit
    
    local sLabel = configWnd:CreateChildWidget("label", "sLabel", 0, true)
    sLabel:SetText("Manual Crash Command:")
    sLabel:SetExtent(320, 20)
    sLabel:AddAnchor("BOTTOM", sEdit, "TOP", 0, -5)
    sLabel.style:SetAlign(ALIGN.CENTER)
    sLabel.style:SetColor(0, 0, 0, 1)
    
    sEdit:SetHandler("OnKillFocus", function()
        local sCmd = configWnd.sEdit:GetText()
        if sCmd and sCmd ~= "" then 
            config.crashCommand = sCmd 
            SaveConfig()
        end
    end)

    local resetPosBtn = configWnd:CreateChildWidget("button", "resetPosBtn", 0, true)
    resetPosBtn:SetText("Reset Position")
    resetPosBtn:SetExtent(100, 30)
    resetPosBtn:AddAnchor("TOP", sEdit, "BOTTOM", 0, 20)
    if api and api.Interface and api.Interface.ApplyButtonSkin then
        api.Interface:ApplyButtonSkin(resetPosBtn, BUTTON_BASIC.DEFAULT)
    end

    local toggleMoveBtn = configWnd:CreateChildWidget("button", "toggleMoveBtn", 0, true)
    toggleMoveBtn:SetText("Move UI")
    toggleMoveBtn:SetExtent(100, 30)
    toggleMoveBtn:AddAnchor("RIGHT", resetPosBtn, "LEFT", -10, 0)
    if api and api.Interface and api.Interface.ApplyButtonSkin then
        api.Interface:ApplyButtonSkin(toggleMoveBtn, BUTTON_BASIC.DEFAULT)
    end
    configWnd.toggleMoveBtn = toggleMoveBtn

    local forceCrashBtn = configWnd:CreateChildWidget("button", "forceCrashBtn", 0, true)
    forceCrashBtn:SetText("Crash NOW")
    forceCrashBtn:SetExtent(100, 30)
    forceCrashBtn:AddAnchor("LEFT", resetPosBtn, "RIGHT", 10, 0)
    if api and api.Interface and api.Interface.ApplyButtonSkin then
        api.Interface:ApplyButtonSkin(forceCrashBtn, BUTTON_BASIC.DEFAULT)
    end

    toggleMoveBtn:SetHandler("OnClick", function()
        moveMode = not moveMode
        if moveMode then
            toggleMoveBtn:SetText("Save UI")
            ShowCornerWarning("Test Warning Position", false)
            local mem = api.GetMemoryUsage()
            if mem then
                local currentMB = math.floor(mem < 100000 and mem or (mem / 1024 / 1024))
                UpdateLiveUsage(currentMB)
            end
        else
            toggleMoveBtn:SetText("Move UI")
            if cornerWarningWnd then cornerWarningWnd:Show(false) end
            local mem = api.GetMemoryUsage()
            if mem then
                local currentMB = math.floor(mem < 100000 and mem or (mem / 1024 / 1024))
                UpdateLiveUsage(currentMB)
            end
            SaveConfig()
        end
    end)

    resetPosBtn:SetHandler("OnClick", function()
        -- NOTE: this used to call UIParent:GetExtent(), but "UIParent" is
        -- only valid as the anchor-target STRING elsewhere in this addon --
        -- it is not a real Lua global here, so this line always threw
        -- "attempt to index global 'UIParent' (a nil value)" and the whole
        -- handler aborted before ever reaching SaveConfig() below. Same bug,
        -- same fix, as quick_equip.lua's context menu positioning.
        local okSize, screenW = pcall(function() return api.Interface:GetScreenWidth() end)
        if not okSize or not screenW then screenW = 2560 end
        config.warnOffsetX = screenW / 2
        config.warnOffsetY = 100
        config.liveOffsetX = screenW / 2
        config.liveOffsetY = 50
        
        if cornerWarningWnd then
            cornerWarningWnd:RemoveAllAnchors()
            cornerWarningWnd:AddAnchor("TOPLEFT", "UIParent", "TOPLEFT", config.warnOffsetX, config.warnOffsetY)
        end
        if liveUsageWnd then
            liveUsageWnd:RemoveAllAnchors()
            liveUsageWnd:AddAnchor("TOPLEFT", "UIParent", "TOPLEFT", config.liveOffsetX, config.liveOffsetY)
        end
        SaveConfig()
    end)

    forceCrashBtn:SetHandler("OnClick", function()
        local s = "CRASH"
        while true do
            s = s .. s
        end
    end)

    return configWnd
end

local function OnUpdate(dt)
	if not config.enabled then return end
	if cornerWarningWnd and cornerWarningWnd:IsVisible() and not criticalTriggered and not moveMode then
		if cornerWarningHideTime > 0 then
			local timeLeft = cornerWarningHideTime - api.Time:GetUiMsec()
			if timeLeft <= 0 then
				cornerWarningWnd:Show(false)
			elseif timeLeft < 2000 then
				if cornerWarningWnd.SetAlpha then
					cornerWarningWnd:SetAlpha(timeLeft / 2000.0)
				end
			end
		end
	end

	timeSinceLastWarnCheck = timeSinceLastWarnCheck + (dt or 1000)

	if timeSinceLastWarnCheck >= warnCheckInterval then
		timeSinceLastWarnCheck = 0

		local mem = api.GetMemoryUsage()
		if mem == nil then
			return
		end
		local isMB = (mem < 100000)
		local currentMB = math.floor(isMB and mem or (mem / 1024 / 1024))
		
		-- Merge Live usage update into this 5s tick
		UpdateLiveUsage(currentMB)

		if currentMB >= config.critical then
			if not criticalTriggered then
				criticalTriggered = true
				ShowCornerWarning("CRITICAL WARNING! " .. GetMemoryString(currentMB), true)
			else
				-- Keep updating text with current memory
				if cornerWarningWnd and cornerWarningWnd.warnLabel then
					cornerWarningWnd.warnLabel:SetText("CRITICAL WARNING! " .. GetMemoryString(currentMB))
				end
			end
		else
			for _, t in ipairs(config.thresholds) do
				if currentMB >= t and not triggeredThresholds[t] then
					triggeredThresholds[t] = true
					ShowCornerWarning("Memory Warning: " .. GetMemoryString(currentMB), false)
				end
			end

			if criticalTriggered and currentMB < config.critical - 100 then
				criticalTriggered = false
				if cornerWarningWnd and not moveMode then
					cornerWarningWnd:Show(false)
				end
			end
		end
	end
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
    if not config.enabled then return end
	if channel == 2 then
		return
	end -- ignore system messages or non-user chat

	local playerName = api.Unit:GetUnitNameById(api.Unit:GetUnitId("player"))
	if playerName == name and message == config.crashCommand then
		local s = "CRASH"
		while true do
			s = s .. s
		end
	end
end

local function OnLoad()
	-- LoadConfig() now runs at require-time (see bottom of the config
	-- section above), so config is already correct by the time OnLoad runs.

	-- api.On("UPDATE" removed for monolithic integration
	-- CHAT_MESSAGE is now dispatched centrally from main.lua (see HandleChatCommand export below)



	if config.enabled and config.showLiveUsage then
		local mem = api.GetMemoryUsage()
		if mem then
			local isMB = (mem < 100000)
			UpdateLiveUsage(math.floor(isMB and mem or (mem / 1024 / 1024)))
		end
	end
end

local function OnUnload()
	-- api.On("UPDATE" removed for monolithic integration end)
	-- CHAT_MESSAGE is owned centrally by main.lua now; nothing to unregister here.

	if configWnd then
		
		api.Interface:Free(configWnd)
		configWnd = nil
	end

	if cornerWarningWnd then
		cornerWarningWnd:Show(false)
		api.Interface:Free(cornerWarningWnd)
		cornerWarningWnd = nil
	end

	if liveUsageWnd then
		liveUsageWnd:Show(false)
		api.Interface:Free(liveUsageWnd)
		liveUsageWnd = nil
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
