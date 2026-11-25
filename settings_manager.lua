local api = require("api")
local EluTrackerSettingsManager = {}

local ELU_TRACKER_SETTINGS_FILE = "elu_tracker_settings.lua"

EluTrackerSettingsManager.Settings = {
    tripPos = { x = 0, y = 0 },
    tripCount = { count = 0 },
    guildCheck = { showRank = true, showLevel = true },
    spotPos = { x = 0, y = 0 },
    spotTimers = {},
    stopwatchPos = { x = 0, y = 0 },
    zealSettings = { opacity = 50, sound = true, size = 1.0 },
    raidInvite = { moduleEnabled = true, giveleadCommand = "x givelead" },
    misc = { enableAltTracking = false, modifierKey = "SHIFT" },
    activeLootSession = {},
    lootOverlay = { x = 0, y = 0, visible = false },
    lossPornSettings = { chatMode = 2, sessionLogs = {} },
    rangeMeterSettings = { enabled = false, fontSize = 16, position = "Top", useDynamicColor = false, colorVariety = 3, threshold1 = 28, threshold2 = 33, c1 = {r=0, g=1, b=0}, c2 = {r=1, g=1, b=0}, c3 = {r=1, g=0, b=0}, staticColor = {r=1, g=1, b=1}, alpha = 1.0 },
    quickEquip = { enabled = false, x = 200, y = 400, gear_sets = {}, characters = {} },
    speedometer = { enabled = false, x = nil, y = nil, customPos = false },
    chatLanguage = { enabled = true, lang = "?", x = nil, y = nil, customPos = false, size = 18, alpha = 1.0, bgAlpha = 0.6, characters = {} }
}

function EluTrackerSettingsManager.LoadSettings()
    local data = api.File:Read(ELU_TRACKER_SETTINGS_FILE)
    if type(data) == "table" then
        for k, v in pairs(data) do
            if type(v) == "table" and type(EluTrackerSettingsManager.Settings[k]) == "table" then
                for subK, subV in pairs(v) do
                    EluTrackerSettingsManager.Settings[k][subK] = subV
                end
            else
                EluTrackerSettingsManager.Settings[k] = v
            end
        end
    end
end

function EluTrackerSettingsManager.SaveSettings()
    local lp = EluTrackerSettingsManager.Settings.lossPornSettings
    local logs = nil
    if type(lp) == "table" then
        logs = lp.sessionLogs
        lp.sessionLogs = nil
    end
    local qe = EluTrackerSettingsManager.Settings.quickEquip
    if type(qe) == "table" and qe.legacyClaimed then
        qe.gear_sets = nil
    end
    local ok, err = pcall(api.File.Write, api.File, ELU_TRACKER_SETTINGS_FILE, EluTrackerSettingsManager.Settings)
    if type(lp) == "table" then
        lp.sessionLogs = logs
    end
end

local function MigrateOldSettings()
    local migrated = false
    
    local function tryMigrate(oldFile, newKey)
        local data = api.File:Read(oldFile)
        if data and type(data) == "table" and next(data) ~= nil then
            EluTrackerSettingsManager.Settings[newKey] = data
            pcall(function() os.remove(oldFile) end)
            api.File:Write(oldFile, {}) 
            migrated = true
        end
    end

    tryMigrate("elu_trip_pos.txt", "tripPos")
    tryMigrate("elu_trip_count.txt", "tripCount")
    tryMigrate("elu_guild_check.txt", "guildCheck")
    tryMigrate("elu_spot_pos.txt", "spotPos")
    tryMigrate("elu_spot_timers.txt", "spotTimers")
    tryMigrate("elu_stopwatch_pos.txt", "stopwatchPos")
    tryMigrate("elu_zeal_settings.txt", "zealSettings")
    tryMigrate("elu_tracker_misc.txt", "misc")

    local currentQuickEquip = EluTrackerSettingsManager.Settings.quickEquip
    local hasOwnPresets = currentQuickEquip and type(currentQuickEquip.gear_sets) == "table" and #currentQuickEquip.gear_sets > 0
    if not hasOwnPresets then
        local ok, oldSetSwap = pcall(function()
            return api.GetSettings and api.GetSettings("set_swap") or nil
        end)
        if ok and type(oldSetSwap) == "table" and type(oldSetSwap.gear_sets) == "table" and #oldSetSwap.gear_sets > 0 then
            EluTrackerSettingsManager.Settings.quickEquip = {
                enabled = true,
                x = oldSetSwap.x or (currentQuickEquip and currentQuickEquip.x) or 200,
                y = oldSetSwap.y or (currentQuickEquip and currentQuickEquip.y) or 400,
                gear_sets = oldSetSwap.gear_sets
            }
            migrated = true
        end
    end

    pcall(function() os.remove("elu_commerce_prices.txt") end)
    api.File:Write("elu_commerce_prices.txt", {})

    if migrated then
        EluTrackerSettingsManager.SaveSettings()
    end
end

pcall(EluTrackerSettingsManager.LoadSettings)
pcall(MigrateOldSettings)

return EluTrackerSettingsManager
