-- ===========================
-- AUTO FISH FEATURE - SIMPLE TEXT EFFECT TRIGGER
-- File: autofishv4_fixed.lua
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
local EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted, FishObtainedNotification

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

-- Rod-specific configs
local FISHING_CONFIGS = {
    ["Fast"] = {
        chargeTime = 1.0,
        waitBetween = 0,
        rodSlot = 1,
        completionDelay = 1.3  -- Delay setelah text effect (seconds)
    },
    ["Slow"] = {
        chargeTime = 1.0,
        waitBetween = 1,
        rodSlot = 1,
        completionDelay = 2.0  -- Delay setelah text effect (seconds)
    }
}

-- Initialize
function AutoFishFeature:Init(guiControls)
    controls = guiControls or {}
    remotesInitialized = initializeRemotes()
    
    if not remotesInitialized then
        logger:warn("Failed to initialize remotes")
        return false
    end
    
    logger:info("Initialized - Simple text effect trigger")
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
    
    logger:info("Started - Mode:", currentMode)
    
    self:SetupFishObtainedListener()
    self:SetupTextEffectListener()
    
    connection = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        self:FishingLoop()
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
    
    if textEffectConnection then
        textEffectConnection:Disconnect()
        textEffectConnection = nil
    end
    
    logger:info("Stopped")
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
            logger:info("Fish caught! Stopping current cycle...")
            fishCaughtFlag = true
            waitingForCompletion = false
            fishingInProgress = false
            
            -- Stop current cast coroutine if running
            if currentCastCoroutine then
                pcall(function()
                    coroutine.close(currentCastCoroutine)
                end)
                currentCastCoroutine = nil
            end
            
            spawn(function()
                task.wait(1.3)
                
                if not isRunning then return end
                
                fishCaughtFlag = false
                textEffectReceived = false
                waitingForCompletion = false
                fishingInProgress = false
                logger:info("Starting next cycle after cooldown...")
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
        
        logger:info("Text effect detected!")
        textEffectReceived = true
        
        -- Trigger completion after delay
        local config = FISHING_CONFIGS[currentMode]
        spawn(function()
            logger:info("Waiting", config.completionDelay, "seconds before firing completion...")
            task.wait(config.completionDelay)
            
            if not isRunning or fishCaughtFlag then
                logger:info("Cancelled - fish already caught or stopped")
                return
            end
            
            logger:info("Firing completion NOW!")
            self:FireCompletion()
        end)
    end)
    
    logger:info("Text effect listener ready")
end

-- Main fishing loop
function AutoFishFeature:FishingLoop()
    if fishingInProgress or waitingForCompletion or fishCaughtFlag then return end
    
    local currentTime = tick()
    local config = FISHING_CONFIGS[currentMode]
    
    if currentTime - lastFishTime < config.waitBetween then
        return
    end
    
    fishingInProgress = true
    lastFishTime = currentTime
    
    currentCastCoroutine = coroutine.create(function()
        local success = self:ExecuteFishingSequence()
        
        if not fishCaughtFlag then
            fishingInProgress = false
        end
        
        if success then
            logger:info("Waiting for text effect...")
        end
    end)
    
    coroutine.resume(currentCastCoroutine)
end

-- Execute fishing sequence
function AutoFishFeature:ExecuteFishingSequence()
    if fishCaughtFlag then return false end
    
    local config = FISHING_CONFIGS[currentMode]
    
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
    
    -- Mark as waiting for text effect
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
        local x = -1.2331848144531
        local z = 0.99277655860847
        local serverTime = workspace:GetServerTimeNow()
        return RequestFishing:InvokeServer(x, z, serverTime)
    end)
    
    return success
end

-- Fire FishingCompleted (only once!)
function AutoFishFeature:FireCompletion()
    if not FishingCompleted then return false end
    
    local success = pcall(function()
        FishingCompleted:FireServer()
    end)
    
    if success then
        logger:info("FishingCompleted fired successfully!")
    else
        logger:warn("Failed to fire FishingCompleted")
    end
    
    return success
end

-- Get status
function AutoFishFeature:GetStatus()
    return {
        running = isRunning,
        mode = currentMode,
        inProgress = fishingInProgress,
        waitingForCompletion = waitingForCompletion,
        textEffectReceived = textEffectReceived,
        fishCaughtFlag = fishCaughtFlag,
        lastCatch = lastFishTime,
        remotesReady = remotesInitialized,
        fishListenerReady = fishObtainedConnection ~= nil,
        textEffectListenerReady = textEffectConnection ~= nil
    }
end

-- Update mode
function AutoFishFeature:SetMode(mode)
    if FISHING_CONFIGS[mode] then
        currentMode = mode
        logger:info("Mode changed to:", mode)
        logger:info("  - Completion delay:", FISHING_CONFIGS[mode].completionDelay, "seconds")
        return true
    end
    return false
end

-- Get notification listener info for debugging
function AutoFishFeature:GetNotificationInfo()
    return {
        hasNotificationRemote = FishObtainedNotification ~= nil,
        hasTextEffectRemote = _G.ReplicateTextEffect ~= nil,
        fishListenerConnected = fishObtainedConnection ~= nil,
        textEffectListenerConnected = textEffectConnection ~= nil,
        fishCaughtFlag = fishCaughtFlag,
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
