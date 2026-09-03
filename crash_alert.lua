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

-- Calibrated 2026-09-03 from a real historical crash study (24 confirmed
-- "*** Memory allocation for N bytes failed ****" engine crashes matched
-- against ArcheAge.log across Aug/Sep, cross-referenced with each session's
-- own "[ADDONS] Current memory usage" readings). Findings:
--   - the tightest-correlated readings (crash within seconds/minutes of the
--     last known reading) cluster at 3055-3206 MB
--   - the lowest EVER confirmed pre-crash reading was 2802 MB
--   - the highest EVER confirmed CLEAN session (no crash) reached 3199 MB
-- These numbers (3000/3100/3200) are the shipped default/fallback -- see
-- the self-calibration section below for how they shift per-PC from there.
local MAX_MEMORY = 3200 -- ties the % readout to "critical" itself: 100% = act now

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
	thresholds = { 3000, 3100 }, -- [1] = yellow starts, [2] = orange starts (see MAX_MEMORY comment above)
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

-- ===== Self-calibrating thresholds ("learning") =====
-- Keeps a tiny file OF ITS OWN (not the shared settings file) tracking the
-- most recent memory reading and whether the last session closed cleanly.
-- Kept separate from elu_tracker_settings.lua on purpose: this gets written
-- periodically while playing (every ~30s), and that file is shared with
-- every other Elu Tracker module and already tens of KB -- rewriting THAT
-- on a timer would be real, avoidable overhead. This file only ever holds a
-- handful of numbers, so writing it periodically costs nothing (same idea,
-- same cost, as mem_log.lua's own periodic save).
--
-- How a crash is inferred: OnUnload only runs on a clean close (quit,
-- reload, relog). So if the game starts back up and this file's cleanExit
-- flag is still false from last time, the addon never got there -- it
-- crashed (or the power went out) sometime after the last saved reading.
-- That reading is treated as roughly where it crashed, but ONLY if it was
-- already at least at the yellow line -- that's what keeps a network drop
-- or a power cut at 1800MB from being mistaken for a memory crash and
-- polluting the learned data, without needing to read ArcheAge.log at all.
--
-- What it learns:
--   crashFloor  -- MB readings from inferred crashes on THIS pc. If this
--                  builds up, critical moves DOWN toward (lowest - margin),
--                  since this pc apparently can't be trusted past that.
--   safeCeiling -- the highest MB reached in sessions that closed cleanly,
--                  but only kept when that peak was already >= critical.
--                  If THIS builds up with no crash ever recorded, critical
--                  moves UP toward (highest + margin) -- this pc evidently
--                  tolerates more than the shipped default, so warning at
--                  the old number would just be nagging too early.
-- Either way it always starts from the shipped numbers above until there's
-- enough local evidence (3+ samples) to move away from them, and crash
-- evidence always wins over ceiling evidence if a pc somehow has both.
local LEARN_FILE = "elu_crash_learn.lua"
local LEARN_SAVE_INTERVAL = 30000 -- 30s -- deliberately much slower than the 5s UI tick
local MIN_LEARN_SAMPLES = 3
local CRASH_MARGIN = 50
local CEILING_MARGIN = 100
local MAX_LEARN_HISTORY = 8
local LEARN_CRITICAL_MAX = 3800 -- sanity ceiling: never stop warning entirely
local DEFAULT_CRITICAL = 3200   -- shipped default, also RecalibrateFromLearning's fallback

-- The bar an inferred crash's last-known MB has to clear to be believed as
-- a MEMORY crash at all (otherwise: network drop, alt-F4, power cut, task
-- kill -- something else, not counted). Deliberately a FIXED number, not
-- config.thresholds[1] -- that one is learned and can itself drift down
-- over time, and using a moving target here would let a downward drift
-- feed on itself (a crash counted in because the bar had already dropped
-- last time would drag the bar down further, counting in even lower crashes
-- next time, with nothing to anchor it). No PC is expected to ever crash
-- from Elu Tracker's addon memory alone below this, no matter how far
-- critical itself has been learned down for that PC.
local LEARN_CRASH_FILTER_MB = 3000

-- Sanity floor for a LEARNED critical value. Derived from the filter above
-- (rather than an independent magic number) so it can never silently drift
-- out of sync with it: every value that actually reaches crashFloor is
-- already >= LEARN_CRASH_FILTER_MB by construction, so the lowest possible
-- learned critical is always exactly LEARN_CRASH_FILTER_MB - CRASH_MARGIN.
local LEARN_CRITICAL_MIN = LEARN_CRASH_FILTER_MB - CRASH_MARGIN

local learnState = {
    cleanExit = true, -- true so a first-ever run isn't mistaken for a crash
    lastMB = nil,
    sessionMaxMB = nil,
    crashFloor = {},
    safeCeiling = {},
    -- Set right before the "Crash NOW" test button or the /crash chat
    -- command deliberately hangs the client -- that's a self-inflicted
    -- test crash, not a real out-of-memory one, so it must never be
    -- learned as a genuine crash floor even if memory happened to be high
    -- when it was triggered (e.g. testing the alert while already playing
    -- at high memory). See MarkDeliberateCrash() below.
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

-- Called immediately before either deliberate-crash trigger (the "Crash
-- NOW" button and the /crash chat command below) actually hangs the
-- client. Must be saved to disk BEFORE that happens, synchronously -- once
-- the infinite loop starts there's no more OnUpdate, no more ticks, no
-- second chance to flag this one.
local function MarkDeliberateCrash()
    learnState.deliberateCrash = true
    SaveLearnState()
end

local function AddCapped(list, value)
    table.insert(list, value)
    if #list > MAX_LEARN_HISTORY then
        table.remove(list, 1)
    end
end

-- Recomputes config.critical/config.thresholds/MAX_MEMORY from whatever's
-- been learned so far, always falling back to the shipped default when
-- there isn't enough local evidence yet. thresholds keep the same spacing
-- below critical the shipped defaults use (100 and 200 MB below), so the
-- whole gradient shifts together as critical is learned.
local function RecalibrateFromLearning()
    local newCritical = DEFAULT_CRITICAL

    if #learnState.crashFloor >= MIN_LEARN_SAMPLES then
        local lowest = math.huge
        for _, v in ipairs(learnState.crashFloor) do
            if v < lowest then lowest = v end
        end
        newCritical = math.max(LEARN_CRITICAL_MIN, lowest - CRASH_MARGIN)
    elseif #learnState.crashFloor == 0 and #learnState.safeCeiling >= MIN_LEARN_SAMPLES then
        -- Only ever raise critical when there is NO recorded crash evidence
        -- at all on this pc, not merely "fewer than MIN_LEARN_SAMPLES of
        -- it" -- even one real inferred crash is a real data point, and
        -- should block a raise rather than being outvoted by unrelated
        -- clean-session evidence just because it hasn't hit 3 yet.
        local highest = 0
        for _, v in ipairs(learnState.safeCeiling) do
            if v > highest then highest = v end
        end
        if highest + CEILING_MARGIN > newCritical then
            newCritical = math.min(LEARN_CRITICAL_MAX, highest + CEILING_MARGIN)
        end
    end

    config.critical = newCritical
    config.thresholds = { newCritical - 200, newCritical - 100 }
    MAX_MEMORY = newCritical
    -- pcall'd like every other I/O call in this section: this now runs from
    -- OnUnload (before window cleanup and SaveLearnState below it) and from
    -- require-time. If SaveEluTrackerSettings ever threw here unprotected,
    -- OnUnload would stop right here -- skipping its own cleanup and,
    -- worse, skipping SaveLearnState(), so cleanExit=true would never be
    -- persisted and next session would wrongly infer a crash that didn't
    -- happen.
    pcall(SaveConfig)
end

-- Runs once, at load: check whether last session's shutdown was clean; if
-- not, and the last known reading was already elevated, learn from it as
-- an inferred crash. Then reset the tracking state for this new session.
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

-- Load immediately at require-time (not only from CreateUI/OnLoad). Other
-- modules' OnUpdate/HandleChatCommand can run before the Misc tab UI is
-- ever built, and used to see the hardcoded defaults (e.g. enabled=false)
-- until CreateUI() happened to run -- same class of desync bug that
-- quick_equip.lua's LoadQuickEquipSettings() comment explains in detail.
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

    -- Same orange used by the normal (non-critical) warning popup -- critical
    -- no longer gets its own red styling. It now also auto-hides just like
    -- the orange one, just with a longer window (20s instead of 10s) since
    -- it's the more urgent message. Note: this is a one-shot popup per
    -- continuous stretch above its own line (critical, or each yellow/orange
    -- threshold) -- it won't re-appear on its own while memory keeps
    -- climbing past that point; it only re-arms once memory drops back
    -- below that line minus 100 and crosses it again (see criticalTriggered
    -- reset below, and the matching triggeredThresholds reset above it).
    cornerWarningWnd.warnLabel.style:SetColor(1, 0.6, 0, 1)
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

    -- Four-tier gradient, both configured thresholds now actually drive a
    -- color step (thresholds[2]/"orange" used to be dead code for this
    -- purpose -- it only fired a popup, never changed the live color).
    --   green   < thresholds[1]  : comfortably safe
    --   yellow  >= thresholds[1] : early heads-up, not urgent
    --   orange  >= thresholds[2] : real risk zone, start wrapping up
    --   red     >= critical      : relog now
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

    -- Was two SetHandler("OnClick", ...) calls back to back -- the second
    -- overwrites the first as far as the game is concerned, so the first
    -- one never actually ran. The one that DID run also had one dead inner
    -- block (an `if liveUsageWidget then` referencing a variable that was
    -- never declared anywhere in this file, always nil, so that Show() call
    -- never fired) -- harmless only because the UpdateLiveUsage(currentMB)
    -- call right after it already shows/hides liveUsageWnd correctly on its
    -- own based on config.showLiveUsage. Collapsed to the one handler that
    -- was actually active, with that dead inner block removed -- behavior
    -- is unchanged either way, this only removes code that never ran.
    toggleLiveBtn:SetHandler("OnClick", function()
        config.showLiveUsage = not config.showLiveUsage
        local text = config.showLiveUsage and "[X] Show Live Usage" or "[ ] Show Live Usage"
        toggleLiveBtn:SetText(text)
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
        MarkDeliberateCrash()
        local s = "CRASH"
        while true do
            s = s .. s
        end
    end)

    return configWnd
end

local function OnUpdate(dt)
	if not config.enabled then return end
	if cornerWarningWnd and cornerWarningWnd:IsVisible() and not moveMode then
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

		-- Learning bookkeeping: cheap, in-memory every 5s tick; only
		-- actually hits disk every LEARN_SAVE_INTERVAL (see comment above
		-- LEARN_FILE for why that's throttled separately from everything
		-- else in this function).
		learnState.lastMB = currentMB
		if not learnState.sessionMaxMB or currentMB > learnState.sessionMaxMB then
			learnState.sessionMaxMB = currentMB
		end
		timeSinceLastLearnSave = timeSinceLastLearnSave + warnCheckInterval
		if timeSinceLastLearnSave >= LEARN_SAVE_INTERVAL then
			timeSinceLastLearnSave = 0
			SaveLearnState()
		end

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
				elseif currentMB < t - 100 and triggeredThresholds[t] then
					-- Same hysteresis margin as criticalTriggered below: re-arms
					-- once memory drops a real 100MB under this threshold, not
					-- right at the boundary, so it can't flicker/re-fire on
					-- small readings jitter around the line.
					triggeredThresholds[t] = false
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
		MarkDeliberateCrash()
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

	-- This is a clean shutdown (quit / reload / relog) -- record it as such
	-- so next load's CheckForInferredCrashAndReset() doesn't mistake this
	-- session for a crash. If this session's peak reached the current
	-- critical line without ever actually crashing, that's a data point
	-- this pc can apparently handle more than the shipped default --
	-- see RecalibrateFromLearning for what happens with that.
	if learnState.sessionMaxMB and learnState.sessionMaxMB >= config.critical then
		AddCapped(learnState.safeCeiling, learnState.sessionMaxMB)
	end
	learnState.cleanExit = true
	RecalibrateFromLearning()
	SaveLearnState()

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
