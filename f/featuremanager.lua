-- FeatureManager.lua
-- Synchronous feature loader with optimized wiring system

local FeatureManager = {}
FeatureManager.LoadedFeatures = {}
FeatureManager.InitializedFeatures = {}
FeatureManager.TotalFeatures = 0
FeatureManager.LoadedCount = 0
FeatureManager.IsReady = false

-- Global access point (optional, uncomment if needed)
-- _G.Features = FeatureManager.LoadedFeatures

local FEATURE_URLS = {
    AutoFish           = "https://raw.githubusercontent.com/X4ZUNEMES/oakwedowadewak/refs/heads/main/f/autofish.lua",
    AutoFishV2         = "https://raw.githubusercontent.com/X4ZUNEMES/oakwedowadewak/refs/heads/main/f/autofishv2.lua",
    AutoFishV3         = "https://raw.githubusercontent.com/X4ZUNEMES/oakwedowadewak/refs/heads/main/f/autofishv3.lua",
    FishWebhook        = "https://raw.githubusercontent.com/X4ZUNEMES/oakwedowadewak/refs/heads/main/f/fishwebhook.lua",
    AutoBuyWeather     = "https://raw.githubusercontent.com/X4ZUNEMES/oakwedowadewak/refs/heads/main/f/autobuyweather.lua",
    AutoBuyBait        = "https://raw.githubusercontent.com/X4ZUNEMES/oakwedowadewak/refs/heads/main/f/autobuybait.lua",
    AutoBuyRod         = "https://raw.githubusercontent.com/X4ZUNEMES/oakwedowadewak/refs/heads/main/f/autobuyrod.lua",
    AutoTeleportEvent  = "https://raw.githubusercontent.com/X4ZUNEMES/oakwedowadewak/refs/heads/main/f/autoteleportevent.lua",
    AutoTeleportPlayer = "https://raw.githubusercontent.com/X4ZUNEMES/oakwedowadewak/refs/heads/main/f/autoteleportplayer.lua",
    AutoGearOxyRadar   = "https://raw.githubusercontent.com/X4ZUNEMES/oakwedowadewak/refs/heads/main/f/autogearoxyradar.lua",
    AntiAfk            = "https://raw.githubusercontent.com/X4ZUNEMES/oakwedowadewak/refs/heads/main/f/antiafk.lua",
    AutoEnchantRod     = "https://raw.githubusercontent.com/X4ZUNEMES/oakwedowadewak/refs/heads/main/f/autoenchantrod.lua",
    AutoEnchantRod2    = "https://raw.githubusercontent.com/X4ZUNEMES/oakwedowadewak/refs/heads/main/f/autoenchantrod2.lua",
    BoostFPS           = "https://raw.githubusercontent.com/X4ZUNEMES/oakwedowadewak/refs/heads/main/f/boostfps.lua",
    AutoSendTrade      = "https://raw.githubusercontent.com/X4ZUNEMES/oakwedowadewak/refs/heads/main/f/autosendtrade.lua",
    AutoAcceptTrade    = "https://raw.githubusercontent.com/X4ZUNEMES/oakwedowadewak/refs/heads/main/f/autoaccepttrade.lua",
    SavePosition       = "https://raw.githubusercontent.com/X4ZUNEMES/oakwedowadewak/refs/heads/main/f/saveposition.lua",
    PositionManager    = "https://raw.githubusercontent.com/X4ZUNEMES/oakwedowadewak/refs/heads/main/f/positionmanager.lua",
    PlayerEsp          = "https://raw.githubusercontent.com/X4ZUNEMES/oakwedowadewak/refs/heads/main/f/playeresp.lua",
    AutoFixFishing     = "https://raw.githubusercontent.com/X4ZUNEMES/oakwedowadewak/refs/heads/main/f/autofixfishing.lua",
    PlayerModif        = "https://raw.githubusercontent.com/X4ZUNEMES/oakwedowadewak/refs/heads/main/f/playermodif.lua",
}

-- Load single feature synchronously
function FeatureManager:LoadSingleFeature(featureName, url, logger)
    local success, result = pcall(function()
        local code = game:HttpGet(url)
        if not code or code == "" then
            error("Empty response from URL")
        end
        
        local module = loadstring(code)()
        if type(module) ~= "table" then
            error("Module did not return a table")
        end
        
        return module
    end)
    
    if success and result then
        result.__featureName = featureName
        result.__initialized = false
        self.LoadedFeatures[featureName] = result
        self.LoadedCount = self.LoadedCount + 1
        
        if logger then
            logger:info(string.format("✓ %s loaded (%d/%d)", 
                featureName, self.LoadedCount, self.TotalFeatures))
        end
        return true
    else
        if logger then
            logger:warn(string.format("✗ Failed to load %s: %s", featureName, result or "Unknown error"))
        end
        return false
    end
end

-- Initialize all features synchronously
function FeatureManager:InitializeAllFeatures(notifyLib, logger)
    if logger then
        logger:info("Starting synchronous feature loading...")
    end
    
    if notifyLib then
        game.StarterGui:SetCore(
        "SendNotification",
        {
            Title = "Nemesis",
            Text = "Loading Script...",
            Icon = "rbxassetid://134005923087938",
            Duration = 10
        })
    end
    
    self.TotalFeatures = 0
    for _ in pairs(FEATURE_URLS) do
        self.TotalFeatures = self.TotalFeatures + 1
    end
    
    -- local loadOrder = {
    --     "AntiAfk", "SavePosition", "PositionManager", "BoostFPS", 
    --     "AutoFish", "AutoFishV2", "AutoFishV3", "AutoSellFish", "AutoTeleportIsland", "AutoTeleportPlayer", 
    --     "AutoTeleportEvent", "AutoEnchantRod", "AutoFavorite", --"AutoFavoriteFishV2", "AutoFavoriteFishV3",
    --     "AutoSendTrade", "AutoAcceptTrade", "FishWebhook", "AutoBuyWeather", 
    --     "AutoBuyBait", "AutoBuyRod", "AutoGearOxyRadar", "CopyJoinServer", "PlayerEsp", "AutoFixFishing", "UnfavoriteAllFish", "PlayerModif", "AutoSubmitSecret", "AutoEnchantRod2",
    --     "AutoBuyMerchant",
    -- }
    
        local loadOrder = {
        "AntiAfk", "SavePosition", "PositionManager", "BoostFPS", 
        "AutoFish", "AutoFishV2", "AutoFishV3", "AutoSellFish", "AutoTeleportIsland", "AutoTeleportPlayer", 
        "AutoTeleportEvent", "AutoEnchantRod", "AutoFavorite",
        "AutoSendTrade", "AutoAcceptTrade", "FishWebhook", "AutoBuyWeather", 
        "AutoBuyBait", "AutoBuyRod", "AutoGearOxyRadar", "CopyJoinServer", "PlayerEsp", "AutoFixFishing", "UnfavoriteAllFish", "PlayerModif", "AutoSubmitSecret", "AutoEnchantRod2", "AutoBuyMerchant"
    }
    local successCount = 0
    
    for _, featureName in ipairs(loadOrder) do
        local url = FEATURE_URLS[featureName]
        if url and self:LoadSingleFeature(featureName, url, logger) then
            successCount = successCount + 1
        end
        wait(0.02)
    end
    
    self.IsReady = true
    
    if logger then
        logger:info(string.format("Loading completed: %d/%d features ready", 
            successCount, self.TotalFeatures))
    end
    
    if notifyLib then
        game.StarterGui:SetCore(
        "SendNotification",
        {
            Title = "Nemesis",
            Text = string.format("%d/%d features loaded successfully", successCount, self.TotalFeatures),
            Icon = "rbxassetid://134005923087938",
            Duration = 5
        }
    )
    end
    
    return successCount, self.TotalFeatures
end

-- OPTIMIZED WIRING METHODS

-- Method 1: Batch initialize multiple features at once
function FeatureManager:BatchInit(featureNames, controls, logger)
    if not self.IsReady then
        if logger then logger:warn("Features not ready yet!") end
        return {}
    end
    
    local initialized = {}
    for _, name in ipairs(featureNames) do
        local feature = self:GetFeature(name, controls, logger)
        if feature then
            initialized[name] = feature
        end
    end
    return initialized
end

-- Method 2: Wire feature directly to toggle (most practical for GUI)
function FeatureManager:Wire(featureName, toggle, controls, logger)
    if not self.IsReady then
        if logger then logger:warn("Features not ready yet!") end
        return false
    end
    
    local feature = self:GetFeature(featureName, controls, logger)
    if not feature then return false end
    
    -- Auto-wire Toggle/Start/Stop methods
    if toggle then
        toggle:OnChanged(function()
            local state = toggle:GetState()
            if state and feature.Start then
                pcall(feature.Start, feature)
            elseif not state and feature.Stop then
                pcall(feature.Stop, feature)
            end
        end)
    end
    
    return true
end

-- Method 3: Bulk wire multiple features at once (saves lots of code)
function FeatureManager:BulkWire(wireConfig, controls, logger)
    if not self.IsReady then
        if logger then logger:warn("Features not ready yet!") end
        return
    end
    
    for featureName, toggle in pairs(wireConfig) do
        self:Wire(featureName, toggle, controls, logger)
    end
end

-- Method 4: Create proxy object for direct access (cleanest syntax)
function FeatureManager:CreateProxy(controls, logger)
    if not self.IsReady then
        if logger then logger:warn("Features not ready yet!") end
        return {}
    end
    
    local proxy = {}
    setmetatable(proxy, {
        __index = function(_, key)
            return self:GetFeature(key, controls, logger)
        end
    })
    return proxy
end

-- Method 5: Initialize ALL features immediately (eager initialization)
function FeatureManager:InitAll(controls, logger)
    if not self.IsReady then
        if logger then logger:warn("Features not ready yet!") end
        return 0
    end
    
    local count = 0
    for featureName, _ in pairs(self.LoadedFeatures) do
        local feature = self:GetFeature(featureName, controls, logger)
        if feature and feature.__initialized then
            count = count + 1
        end
    end
    
    if logger then
        logger:info(string.format("✓ Initialized %d/%d features", count, self.TotalFeatures))
    end
    
    return count
end

-- Original methods (kept for compatibility)
function FeatureManager:GetFeature(featureName, controls, logger)
    if not self.IsReady then
        if logger then logger:warn("Features not ready yet!") end
        return nil
    end
    
    local feature = self.LoadedFeatures[featureName]
    if not feature then
        if logger then logger:warn(string.format("Feature %s not found", featureName)) end
        return nil
    end
    
    if controls and not feature.__controlsAttached then
        feature.__controls = controls
        feature.__controlsAttached = true
        
        if feature.Init and not feature.__initialized then
            local success, err = pcall(feature.Init, feature, controls)
            if success then 
                feature.__initialized = true
                if logger then
                    logger:info(string.format("✓ %s initialized", featureName))
                end
            else
                if logger then
                    logger:warn(string.format("✗ Init failed for %s: %s", featureName, err))
                end
            end
        end
    end
    
    return feature
end

function FeatureManager:Get(featureName)
    return self.LoadedFeatures[featureName]
end

function FeatureManager:IsLoaded()
    return self.IsReady
end

function FeatureManager:GetStatus()
    return {
        isReady = self.IsReady,
        loaded = self.LoadedCount,
        total = self.TotalFeatures,
        features = {}
    }
end

return FeatureManager
