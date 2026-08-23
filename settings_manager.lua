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
    misc = { enableAltTracking = false, modifierKey = "SHIFT" },
    activeLootSession = {}
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
    api.File:Write(ELU_TRACKER_SETTINGS_FILE, EluTrackerSettingsManager.Settings)
end

local function MigrateOldSettings()
    local migrated = false
    
    local function tryMigrate(oldFile, newKey)
        local data = api.File:Read(oldFile)
        if data and type(data) == "table" and next(data) ~= nil then
            EluTrackerSettingsManager.Settings[newKey] = data -- Old file left intentionally untouched since Delete is forbidden
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
    
    -- Old price file left intentionally untouched
    pcall(function() os.remove("elu_commerce_prices.txt") end)
    api.File:Write("elu_commerce_prices.txt", {})

    if migrated then
        EluTrackerSettingsManager.SaveSettings()
    end
end

pcall(EluTrackerSettingsManager.LoadSettings)
pcall(MigrateOldSettings)

return EluTrackerSettingsManager
