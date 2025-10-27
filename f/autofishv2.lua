-- ===========================
-- AUTO FISH FEATURE - TEXT EFFECT TRIGGER WITH RETRY LOGIC + API DELAY
-- File: autofishv5_texteffect_retry.lua
-- ===========================

local AutoFishFeature = {}
AutoFishFeature.__index = AutoFishFeature

local logger = _G.Logger and _G.Logger.new("AutoFish") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")  
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- Network setup
local NetPath = nil
local EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted, FishObtainedNotification, BaitSpawned, CancelFishingEvent

local function initializeRemotes()
    local success = pcall(function()
        NetPath = ReplicatedStorage:WaitForChild("Packages", 5)
            :WaitForChild("_Index", 5)
            :WaitForChild("sleitnick_net@0.2.0", 5)
            :WaitForChild("net", 5)
        
        EquipTool = NetPath:WaitForChild("RE/EquipToolFromHotbar", 5)
        ChargeFishingRod = NetPath:WaitForChild("RF/ChargeFishingRod", 5)
        RequestFishing = NetPath:WaitForChild("RF/RequestFishingMinigameStarted", 5)
        FishingCompleted = NetPath:WaitForChild("RE/FishingCompleted", 5)
        FishObtainedNotification = NetPath:WaitForChild("RE/ObtainedNewFishNotification", 5)
        BaitSpawned = NetPath:WaitForChild("RE/BaitSpawned", 5)
        CancelFishingEvent = NetPath:WaitForChild("RF/CancelFishingInputs", 5)
        
        local ReplicateTextEffect = NetPath:FindFirstChild("RE/ReplicateTextEffect")
        if ReplicateTextEffect then
            _G.ReplicateTextEffect = ReplicateTextEffect
        end
        
        return true
    end)
    
    return success
end

-- Feature state
local isRunning = false
local currentMode = "Fast"
local connection = nil
local fishObtainedConnection = nil
local baitSpawnedConnection = nil
local textEffectConnection = nil
local controls = {}
local fishingInProgress = false
local lastFishTime = 0
local remotesInitialized = false
local currentCastCoroutine = nil

-- Tracking
local textEffectReceived = false
local fishCaughtFlag = false
local waitingForCompletion = false
local baitSpawnedFlag = false

-- Retry logic
local lastFishObtainedTime = 0
local cycleStartTime = 0

-- Rod-specific configs
local FISHING_CONFIGS = {
    ["Fast"] = {
        chargeTime = 1.0,
        waitBetweenCast = 0,
        rodSlot = 1,
        completionDelay = 1.5,  -- Delay setelah text effect (seconds)
        waitAfterFish = 1.5,    -- Delay setelah ikan tertangkap (seconds)
        stuckTimeout = 60       -- Timeout untuk retry (seconds)
    },
    ["Slow"] = {
        chargeTime = 1.0,
        waitBetweenCast = 1,
        rodSlot = 1,
        completionDelay = 2.0,
        waitAfterFish = 2.0,
        stuckTimeout = 35
    }
}

-- ===========================
-- PUBLIC API METHODS
-- ===========================

-- Set completion delay for specific mode
function AutoFishFeature:SetCompletionDelay(mode, delaySeconds)
    if not FISHING_CONFIGS[mode] then
        logger:warn("Invalid mode:", mode)
        return false
    end
    
    if type(delaySeconds) ~= "number" or delaySeconds < 0 then
        logger:warn("Invalid delay value:", delaySeconds)
        return false
    end
    
    FISHING_CONFIGS[mode].completionDelay = delaySeconds
    logger:info(mode, "completion delay set to:", delaySeconds, "seconds")
    return true
end

-- Set wait after fish delay for specific mode
function AutoFishFeature:SetWaitAfterFish(mode, delaySeconds)
    if not FISHING_CONFIGS[mode] then
        logger:warn("Invalid mode:", mode)
        return false
    end
    
    if type(delaySeconds) ~= "number" or delaySeconds < 0 then
        logger:warn("Invalid delay value:", delaySeconds)
        return false
    end
    
    FISHING_CONFIGS[mode].waitAfterFish = delaySeconds
    logger:info(mode, "wait after fish set to:", delaySeconds, "seconds")
    return true
end

-- Set stuck timeout for specific mode
function AutoFishFeature:SetStuckTimeout(mode, timeoutSeconds)
    if not FISHING_CONFIGS[mode] then
        logger:warn("Invalid mode:", mode)
        return false
    end
    
    if type(timeoutSeconds) ~= "number" or timeoutSeconds < 5 then
        logger:warn("Invalid timeout value (min 5s):", timeoutSeconds)
        return false
    end
    
    FISHING_CONFIGS[mode].stuckTimeout = timeoutSeconds
    logger:info(mode, "stuck timeout set to:", timeoutSeconds, "seconds")
    return true
end

-- Set both delays at once for a mode
function AutoFishFeature:SetDelays(mode, completionDelay, waitAfterFish, stuckTimeout)
    if not FISHING_CONFIGS[mode] then
        logger:warn("Invalid mode:", mode)
        return false
    end
    
    local success = true
    
    if completionDelay then
        success = success and self:SetCompletionDelay(mode, completionDelay)
    end
    
    if waitAfterFish then
        success = success and self:SetWaitAfterFish(mode, waitAfterFish)
    end
    
    if stuckTimeout then
        success = success and self:SetStuckTimeout(mode, stuckTimeout)
    end
    
    return success
end

-- Get current delay settings for a mode
function AutoFishFeature:GetDelays(mode)
    local config = FISHING_CONFIGS[mode or currentMode]
    if not config then return nil end
    
    return {
        completionDelay = config.completionDelay,
        waitAfterFish = config.waitAfterFish,
        stuckTimeout = config.stuckTimeout
    }
end

-- ===========================
-- CORE METHODS
-- ===========================

-- Initialize
function AutoFishFeature:Init(guiControls)
    controls = guiControls or {}
    remotesInitialized = initializeRemotes()
    
    if not remotesInitialized then
        logger:warn("Failed to initialize remotes")
        return false
    end
    
    logger:info("Initialized - Text effect trigger with retry logic + API delay")
    return true
end

-- Start fishing
function AutoFishFeature:Start(config)
    if isRunning then return end
    
    if not remotesInitialized then
        logger:warn("Cannot start - remotes not initialized")
        return
    end
    
    isRunning = true
    currentMode = config.mode or "Fast"
    fishingInProgress = false
    lastFishTime = 0
    fishCaughtFlag = false
    textEffectReceived = false
    waitingForCompletion = false
    baitSpawnedFlag = false
    lastFishObtainedTime = tick()
    cycleStartTime = 0
    
    local cfg = FISHING_CONFIGS[currentMode]
    logger:info("Started - Mode:", currentMode)
    logger:info("  - Completion delay:", cfg.completionDelay, "seconds")
    logger:info("  - Wait after fish:", cfg.waitAfterFish, "seconds")
    logger:info("  - Stuck timeout:", cfg.stuckTimeout, "seconds")
    
    self:SetupFishObtainedListener()
    self:SetupBaitSpawnedListener()
    self:SetupTextEffectListener()
    
    connection = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        self:FishingLoop()
        self:CheckStuckFishing()
    end)
end

-- Stop fishing
function AutoFishFeature:Stop()
    if not isRunning then return end
    
    isRunning = false
    fishingInProgress = false
    fishCaughtFlag = false
    textEffectReceived = false
    waitingForCompletion = false
    baitSpawnedFlag = false
    cycleStartTime = 0
    
    if currentCastCoroutine then
        pcall(function()
            coroutine.close(currentCastCoroutine)
        end)
        currentCastCoroutine = nil
    end
    
    if connection then
        connection:Disconnect()
        connection = nil
    end
    
    if fishObtainedConnection then
        fishObtainedConnection:Disconnect()
        fishObtainedConnection = nil
    end
    
    if baitSpawnedConnection then
        baitSpawnedConnection:Disconnect()
        baitSpawnedConnection = nil
    end
    
    if textEffectConnection then
        textEffectConnection:Disconnect()
        textEffectConnection = nil
    end
    
    logger:info("Stopped")
end

-- Setup bait spawned listener
function AutoFishFeature:SetupBaitSpawnedListener()
    if not BaitSpawned then
        logger:warn("BaitSpawned not available")
        return
    end
    
    if baitSpawnedConnection then
        baitSpawnedConnection:Disconnect()
    end
    
    baitSpawnedConnection = BaitSpawned.OnClientEvent:Connect(function(player, rodName, position)
        if player == LocalPlayer and isRunning then
            logger:info("🎣 Bait spawned! Rod:", rodName or "Unknown")
            baitSpawnedFlag = true
        end
    end)
    
    logger:info("Bait spawned listener ready")
end

-- Setup fish obtained notification listener
function AutoFishFeature:SetupFishObtainedListener()
    if not FishObtainedNotification then
        logger:warn("FishObtainedNotification not available")
        return
    end
    
    if fishObtainedConnection then
        fishObtainedConnection:Disconnect()
    end
    
    fishObtainedConnection = FishObtainedNotification.OnClientEvent:Connect(function(...)
        if isRunning then
            logger:info("🐟 Fish caught! Timer reset")
            fishCaughtFlag = true
            waitingForCompletion = false
            fishingInProgress = false
            baitSpawnedFlag = false
            lastFishObtainedTime = tick()
            cycleStartTime = 0
            
            if currentCastCoroutine then
                pcall(function()
                    coroutine.close(currentCastCoroutine)
                end)
                currentCastCoroutine = nil
            end
            
            local config = FISHING_CONFIGS[currentMode]
            spawn(function()
                task.wait(config.waitAfterFish)
                
                if not isRunning then return end
                
                fishCaughtFlag = false
                textEffectReceived = false
                waitingForCompletion = false
                fishingInProgress = false
                baitSpawnedFlag = false
                logger:info("✨ Starting next cycle after cooldown...")
            end)
        end
    end)
    
    logger:info("Fish obtained listener ready")
end

-- Setup text effect listener
function AutoFishFeature:SetupTextEffectListener()
    local ReplicateTextEffect = _G.ReplicateTextEffect
    if not ReplicateTextEffect then
        logger:warn("ReplicateTextEffect not available")
        return
    end
    
    if textEffectConnection then
        textEffectConnection:Disconnect()
    end
    
    textEffectConnection = ReplicateTextEffect.OnClientEvent:Connect(function(data)
        if not isRunning or not waitingForCompletion then return end
        
        if not data or not data.TextData then return end
        if not LocalPlayer.Character or not LocalPlayer.Character.Head then return end
        if data.TextData.AttachTo ~= LocalPlayer.Character.Head then return end
        
        logger:info("📝 Text effect detected!")
        textEffectReceived = true
        
        local config = FISHING_CONFIGS[currentMode]
        spawn(function()
            logger:info("⏳ Waiting", config.completionDelay, "seconds before firing completion...")
            task.wait(config.completionDelay)
            
            if not isRunning or fishCaughtFlag then
                logger:info("❌ Cancelled - fish already caught or stopped")
                return
            end
            
            logger:info("🎣 Firing completion NOW!")
            self:FireCompletion()
        end)
    end)
    
    logger:info("Text effect listener ready")
end

-- Check if fishing is stuck (retry logic)
function AutoFishFeature:CheckStuckFishing()
    if not fishingInProgress and not waitingForCompletion then return end
    if cycleStartTime == 0 then return end
    
    local currentTime = tick()
    local cycleElapsed = currentTime - cycleStartTime
    local config = FISHING_CONFIGS[currentMode]
    
    if cycleElapsed >= config.stuckTimeout then
        logger:warn("⚠️ Fishing stuck! No fish for", math.floor(cycleElapsed), "seconds - CANCELLING & RETRYING")
        self:CancelAndRetry()
    end
end

-- Cancel stuck fishing and retry
function AutoFishFeature:CancelAndRetry()
    if not CancelFishingEvent then
        logger:error("CancelFishingEvent not available")
        return
    end
    
    local success = pcall(function()
        CancelFishingEvent:InvokeServer()
    end)
    
    if success then
        logger:info("✅ Successfully cancelled stuck fishing")
    else
        logger:error("❌ Failed to cancel fishing")
    end
    
    fishingInProgress = false
    waitingForCompletion = false
    textEffectReceived = false
    baitSpawnedFlag = false
    cycleStartTime = 0
    
    if currentCastCoroutine then
        pcall(function()
            coroutine.close(currentCastCoroutine)
        end)
        currentCastCoroutine = nil
    end
    
    spawn(function()
        task.wait(1)
        logger:info("🔄 Retrying fishing cycle...")
    end)
end

-- Main fishing loop
function AutoFishFeature:FishingLoop()
    if fishingInProgress or waitingForCompletion or fishCaughtFlag then return end
    
    local currentTime = tick()
    local config = FISHING_CONFIGS[currentMode]
    
    if currentTime - lastFishTime < config.waitBetweenCast then
        return
    end
    
    fishingInProgress = true
    lastFishTime = currentTime
    cycleStartTime = currentTime
    
    currentCastCoroutine = coroutine.create(function()
        local success = self:ExecuteFishingSequence()
        
        if not fishCaughtFlag then
            fishingInProgress = false
        end
        
        if success then
            logger:info("⏰ Waiting for text effect...")
        else
            cycleStartTime = 0
        end
    end)
    
    coroutine.resume(currentCastCoroutine)
end

-- Execute fishing sequence
function AutoFishFeature:ExecuteFishingSequence()
    if fishCaughtFlag then return false end
    
    local config = FISHING_CONFIGS[currentMode]
    
    baitSpawnedFlag = false
    
    if not self:EquipRod(config.rodSlot) then
        return false
    end
    
    task.wait(0.1)
    if fishCaughtFlag then return false end

    if not self:ChargeRod(config.chargeTime) then
        return false
    end
    
    if fishCaughtFlag then return false end
    
    if not self:CastRod() then
        return false
    end

    if fishCaughtFlag then return false end
    
    textEffectReceived = false
    waitingForCompletion = true
    
    return true
end

-- Equip rod
function AutoFishFeature:EquipRod(slot)
    if not EquipTool then return false end
    
    local success = pcall(function()
        EquipTool:FireServer(slot)
    end)
    
    return success
end

-- Charge rod
function AutoFishFeature:ChargeRod(chargeTime)
    if not ChargeFishingRod then return false end
    
    local success = pcall(function()
        local serverTime = workspace:GetServerTimeNow()
        return ChargeFishingRod:InvokeServer(nil, nil, nil, serverTime)
    end)
    
    return success
end

-- Cast rod
function AutoFishFeature:CastRod()
    if not RequestFishing then return false end
    
    local success = pcall(function()
        local x = -1.233184814453125
        local z = 0.9999120558411321
        local serverTime = workspace:GetServerTimeNow()
        return RequestFishing:InvokeServer(x, z, serverTime)
    end)
    
    return success
end

-- Fire FishingCompleted
function AutoFishFeature:FireCompletion()
    if not FishingCompleted then return false end
    
    local success = pcall(function()
        FishingCompleted:FireServer()
    end)
    
    if success then
        logger:info("✅ FishingCompleted fired successfully!")
    else
        logger:warn("⚠️ Failed to fire FishingCompleted")
    end
    
    return success
end

-- Get status
function AutoFishFeature:GetStatus()
    local timeSinceCycleStart = cycleStartTime > 0 and (tick() - cycleStartTime) or 0
    local config = FISHING_CONFIGS[currentMode]
    
    return {
        running = isRunning,
        mode = currentMode,
        inProgress = fishingInProgress,
        waitingForCompletion = waitingForCompletion,
        textEffectReceived = textEffectReceived,
        fishCaughtFlag = fishCaughtFlag,
        baitSpawnedFlag = baitSpawnedFlag,
        lastCatch = lastFishTime,
        lastFishObtained = lastFishObtainedTime,
        cycleElapsed = math.floor(timeSinceCycleStart),
        timeoutThreshold = config.stuckTimeout,
        timeRemaining = math.max(0, config.stuckTimeout - timeSinceCycleStart),
        remotesReady = remotesInitialized,
        fishListenerReady = fishObtainedConnection ~= nil,
        baitListenerReady = baitSpawnedConnection ~= nil,
        textEffectListenerReady = textEffectConnection ~= nil
    }
end

-- Update mode
function AutoFishFeature:SetMode(mode)
    if FISHING_CONFIGS[mode] then
        currentMode = mode
        local cfg = FISHING_CONFIGS[mode]
        logger:info("Mode changed to:", mode)
        logger:info("  - Completion delay:", cfg.completionDelay, "seconds")
        logger:info("  - Wait after fish:", cfg.waitAfterFish, "seconds")
        logger:info("  - Stuck timeout:", cfg.stuckTimeout, "seconds")
        return true
    end
    return false
end

-- Legacy timeout setter (backwards compatibility)
function AutoFishFeature:SetTimeout(seconds)
    return self:SetStuckTimeout(currentMode, seconds)
end

-- Manual cancel & retry
function AutoFishFeature:ManualRetry()
    logger:info("Manual retry triggered")
    self:CancelAndRetry()
    return true
end

-- Get current config
function AutoFishFeature:GetConfig(mode)
    return FISHING_CONFIGS[mode or currentMode]
end

-- Get all configs
function AutoFishFeature:GetAllConfigs()
    return FISHING_CONFIGS
end

-- Get notification listener info for debugging
function AutoFishFeature:GetNotificationInfo()
    return {
        hasNotificationRemote = FishObtainedNotification ~= nil,
        hasBaitSpawnedRemote = BaitSpawned ~= nil,
        hasTextEffectRemote = _G.ReplicateTextEffect ~= nil,
        hasCancelRemote = CancelFishingEvent ~= nil,
        fishListenerConnected = fishObtainedConnection ~= nil,
        baitListenerConnected = baitSpawnedConnection ~= nil,
        textEffectListenerConnected = textEffectConnection ~= nil,
        fishCaughtFlag = fishCaughtFlag,
        baitSpawnedFlag = baitSpawnedFlag,
        textEffectReceived = textEffectReceived,
        waitingForCompletion = waitingForCompletion
    }
end

-- Cleanup
function AutoFishFeature:Cleanup()
    logger:info("Cleaning up...")
    self:Stop()
    controls = {}
    remotesInitialized = false
end

return AutoFishFeature