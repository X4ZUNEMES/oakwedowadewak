-- ===========================
-- AUTO FISH BACKEND with ReplicateTextEffect Trigger + Dual-Cast & Spam Mode
-- Improved: preserves all original functions and adds features (no removals)
-- File: autofishv5_texteffect.lua
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
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

-- Network setup (placeholders, initialized later)
local NetPath = nil
local EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted, FishObtainedNotification, ReplicateTextEffect, CancelFishingInputs

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
        ReplicateTextEffect = NetPath:WaitForChild("RE/ReplicateTextEffect", 5)
        CancelFishingInputs = NetPath:FindFirstChild("RF/CancelFishingInputs") or nil

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
local lastCastTime = 0 -- for stuck detection

-- Stuck detection timeout (seconds)
local STUCK_TIMEOUT = 5.0

-- Rod-specific configs (kept original keys, added toggleState for new features)
local FISHING_CONFIGS = {
    ["Fast"] = {
        chargeTime = 1.0,
        waitBetweenCast = 0,
        rodSlot = 1,
        completionDelay = 1.3,  -- Delay after text effect appears
        waitAfterFish = 1.3,    -- Delay after fish caught
        toggleState = {         -- new extra options (non-breaking: optional)
            castStyle = "Normal", -- "Perfect"|"Amazing"|"Normal"
            animate = "Spam",    -- "Normal"|"Spam"
            spamDelay = 0.2,
            loopDelay = 0.3,
        },
    },
    ["Slow"] = {
        chargeTime = 1.0,
        waitBetweenCast = 1,
        rodSlot = 1,
        completionDelay = 2.0,
        waitAfterFish = 2.0,
        toggleState = {
            castStyle = "Normal",
            animate = "Normal",
            spamDelay = 0.25,
            loopDelay = 0.4,
        },
    }
}

-- Helper: safe pcall invoke / fire wrappers (avoid breaking if remote missing)
local function safeFire(remote, ...)
    if not remote then return false end
    local ok, res = pcall(function() return remote:FireServer(...) end)
    return ok, res
end
local function safeInvoke(remote, ...)
    if not remote then return false end
    local ok, res = pcall(function() return remote:InvokeServer(...) end)
    return ok, res
end

-- ===========================
-- PUBLIC API METHODS
-- ===========================

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

function AutoFishFeature:SetDelays(mode, completionDelay, waitAfterFish)
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
    return success
end

function AutoFishFeature:GetDelays(mode)
    local config = FISHING_CONFIGS[mode or currentMode]
    if not config then return nil end
    return {
        completionDelay = config.completionDelay,
        waitAfterFish = config.waitAfterFish
    }
end

-- Expose configs (safe copy)
function AutoFishFeature:GetConfig(mode)
    return FISHING_CONFIGS[mode or currentMode]
end

function AutoFishFeature:GetAllConfigs()
    return FISHING_CONFIGS
end

-- Add a safe method to update toggleState for a mode
function AutoFishFeature:SetToggleState(mode, newToggleState)
    if not FISHING_CONFIGS[mode] then return false end
    FISHING_CONFIGS[mode].toggleState = FISHING_CONFIGS[mode].toggleState or {}
    for k,v in pairs(newToggleState) do
        FISHING_CONFIGS[mode].toggleState[k] = v
    end
    logger:info("ToggleState updated for mode:", mode)
    return true
end

-- ===========================
-- CORE METHODS (Init / Start / Stop)
-- ===========================

function AutoFishFeature:Init(guiControls)
    controls = guiControls or {}
    remotesInitialized = initializeRemotes()
    if not remotesInitialized then
        logger:warn("Failed to initialize remotes")
        return false
    end
    logger:info("Initialized - ReplicateTextEffect trigger ready")
    return true
end

function AutoFishFeature:Start(config)
    if isRunning then return end
    if not remotesInitialized then
        logger:warn("Cannot start - remotes not initialized")
        return
    end
    isRunning = true
    currentMode = config and config.mode or "Fast"
    fishingInProgress = false
    lastFishTime = 0
    fishCaughtFlag = false
    textEffectReceived = false
    waitingForCompletion = false
    lastCastTime = tick()

    logger:info("Started - Mode:", currentMode)
    logger:info("  - Completion delay:", FISHING_CONFIGS[currentMode].completionDelay, "seconds")
    logger:info("  - Wait after fish:", FISHING_CONFIGS[currentMode].waitAfterFish, "seconds")

    self:SetupFishObtainedListener()
    self:SetupTextEffectListener()

    connection = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        self:FishingLoop()
    end)
end

function AutoFishFeature:Stop()
    if not isRunning then return end
    isRunning = false
    fishingInProgress = false
    fishCaughtFlag = false
    textEffectReceived = false
    waitingForCompletion = false

    if currentCastCoroutine then
        pcall(function() coroutine.close(currentCastCoroutine) end)
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

-- ===========================
-- LISTENERS (Fish obtained & Text effect)
-- ===========================

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
            logger:info("🐟 Fish caught! Stopping current cycle...")
            fishCaughtFlag = true
            waitingForCompletion = false
            fishingInProgress = false
            textEffectReceived = false

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
                logger:info("✨ Starting next cycle after cooldown...")
            end)
        end
    end)

    logger:info("Fish obtained listener ready")
end

function AutoFishFeature:SetupTextEffectListener()
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
        if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("Head") then return end
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

-- ===========================
-- FISHING LOOP & STUCK HANDLING
-- ===========================

function AutoFishFeature:FishingLoop()
    -- Stuck detection: if already in a state that should wait, but timed out -> reset
    if fishingInProgress or waitingForCompletion or fishCaughtFlag then
        if tick() - lastCastTime >= STUCK_TIMEOUT then
            logger:warn("⚠️ Stuck detected! Resetting fishing cycle...")
            fishingInProgress = false
            waitingForCompletion = false
            textEffectReceived = false
            if currentCastCoroutine then
                pcall(function() coroutine.close(currentCastCoroutine) end)
                currentCastCoroutine = nil
            end
            lastCastTime = tick()
        else
            return
        end
    end

    local currentTime = tick()
    local config = FISHING_CONFIGS[currentMode]
    if currentTime - lastFishTime < config.waitBetweenCast then
        return
    end

    fishingInProgress = true
    lastFishTime = currentTime
    lastCastTime = tick()

    currentCastCoroutine = coroutine.create(function()
        local success = self:ExecuteFishingSequence()
        if not fishCaughtFlag then
            fishingInProgress = false
        end
        if success then
            logger:info("⏰ Waiting for text effect trigger...")
        end
    end)
    coroutine.resume(currentCastCoroutine)
end

-- ===========================
-- Execution sequence (preserves original functions, adds enhanced behavior)
-- - This function integrates startFishing & startFishingDua logic as optional behavior
-- - Does NOT remove or reduce any original functionality
-- ===========================

-- Legacy-compatible Equip/Charge/Cast functions (kept in case other code calls them)
function AutoFishFeature:EquipRod(slot)
    if not EquipTool then return false end
    local success = pcall(function() EquipTool:FireServer(slot) end)
    return success
end

function AutoFishFeature:ChargeRod(chargeTime)
    if not ChargeFishingRod then return false end
    local success = pcall(function()
        local serverTime = workspace:GetServerTimeNow()
        return ChargeFishingRod:InvokeServer(nil, nil, nil, serverTime)
    end)
    return success
end

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

-- New: safe wrappers for the remotes used in startFishing variants
local function safeRemoteInvoke(name, ...)
    local ok, res
    pcall(function()
        if name == "ChargeFishingRod" and ChargeFishingRod then
            ok, res = ChargeFishingRod:InvokeServer(...)
        elseif name == "RequestFishing" and RequestFishing then
            ok, res = RequestFishing:InvokeServer(...)
        elseif name == "EquipTool" and EquipTool then
            ok, res = EquipTool:FireServer(...)
        elseif name == "CancelFishing" and CancelFishingInputs then
            ok, res = CancelFishingInputs:InvokeServer(...)
        end
    end)
    return ok, res
end

-- Integrated ExecuteFishingSequence:
-- Uses existing sequence but extends with castStyle, animation, spam dual-cast (startFishing + startFishingDua logic).
-- Preserves original behavior when toggleState is default/unchanged.
function AutoFishFeature:ExecuteFishingSequence()
    if fishCaughtFlag then return false end
    local config = FISHING_CONFIGS[currentMode]
    if not config then return false end
    local toggleState = config.toggleState or {}

    -- Pre-cancel any existing fishing attempt (like startFishing did)
    pcall(function()
        if CancelFishingInputs then
            pcall(function() CancelFishingInputs:InvokeServer() end)
        end
        if FishingController and FishingController.RequestClientStopFishing then
            FishingController:RequestClientStopFishing(true)
        end
    end)

    -- Optional: attempt to bypass cooldown (best-effort; original code used hookfunction)
    -- We don't reimplement hookfunction here to avoid altering environment, but if user had that hook
    -- in their environment it's fine — this preserves original non-destructive behavior.

    -- Equip rod (legacy-compatible)
    if EquipTool then
        pcall(function() EquipTool:FireServer(config.rodSlot) end)
    end
    task.wait(0.1)
    if fishCaughtFlag then return false end

    -- Use improved charging sequence (prefer server time from workspace)
    local serverTime = Workspace:GetServerTimeNow()
    if ChargeFishingRod then
        pcall(function() ChargeFishingRod:InvokeServer(serverTime) end)
    end
    if fishCaughtFlag then return false end

    -- Animations: call playWithDuration if available (best-effort)
    -- We keep this optional so absence doesn't break anything
    pcall(function()
        if toggleState.animate == "Normal" and type(playWithDuration) == "function" then
            -- try to play charge & throw / reeling animations if those functions are present in environment
            pcall(function()
                if tostring(equippedRodId) == "245" then
                    pcall(function() playWithDuration(StartRodChargeAnimHT, 1) end)
                else
                    pcall(function() playWithDuration(StartRodChargeAnim, 1) end)
                end
            end)
        end
    end)

    -- Determine cast coordinates based on castStyle (this mirrors startFishing variants)
    local x, y
    if toggleState.castStyle == "Perfect" then
        x, y = -139.6379, 1
    elseif toggleState.castStyle == "Amazing" then
        x, y = -139.6379, 0.99
    else
        x, y = -139.6379, 0.99
    end

    -- Wait small time to simulate charge animation / original behavior
    task.wait(config.chargeTime and config.chargeTime or 0.2)

    -- Fire RequestFishingMinigameStarted (if available)
    if RequestFishing then
        pcall(function() RequestFishing:InvokeServer(x, y, Workspace:GetServerTimeNow()) end)
    end

    -- If animate == "Normal" and animations exist, try to play throw & reel
    pcall(function()
        if toggleState.animate == "Normal" and type(playWithDuration) == "function" then
            pcall(function()
                if tostring(equippedRodId) == "245" then
                    playWithDuration(RodThrowAnimHT, 2)
                    playWithDuration(ReelingIdleAnimHT, 25)
                else
                    playWithDuration(RodThrowAnim, 2)
                    playWithDuration(ReelingIdleAnim, 25)
                end
            end)
        end
    end)

    -- Spam Mode (dual-cast) — replicate startFishingDua behavior safely and optionally
    if toggleState.animate == "Spam" then
        -- spawn secondary cast as in startFishingDua
        task.spawn(function()
            task.wait(toggleState.spamDelay or 0.2)
            -- attempt to cancel previous and re-charge & recast
            if CancelFishingInputs then
                pcall(function() CancelFishingInputs:InvokeServer() end)
            else
                -- fallback to original Cancel remote name if present in NetPath
                pcall(function()
                    local alt = NetPath and NetPath:FindFirstChild("RF/CancelFishingInputs")
                    if alt and alt.InvokeServer then pcall(function() alt:InvokeServer() end) end
                end)
            end

            -- small flag reset similar to original
            pcall(function() if FishingController and FishingController.RequestClientStopFishing then FishingController:RequestClientStopFishing(true) end end)

            -- re-charge and recast
            pcall(function() if ChargeFishingRod then ChargeFishingRod:InvokeServer(Workspace:GetServerTimeNow()) end end)
            local sx, sy
            if toggleState.castStyle == "Perfect" then
                sx, sy = -139.6379, 1
            elseif toggleState.castStyle == "Amazing" then
                sx, sy = -139.6379, 0.99
            else
                sx, sy = -139.6379, 0.99
            end
            task.wait(0.15)
            pcall(function() if RequestFishing then RequestFishing:InvokeServer(sx, sy, Workspace:GetServerTimeNow()) end end)
        end)
    end

    -- Mark waiting for completion (original behavior relied on text effect)
    textEffectReceived = false
    waitingForCompletion = true

    return true
end

-- Keep original FireCompletion which fires the FishingCompleted remote
function AutoFishFeature:FireCompletion()
    if not FishingCompleted then return false end
    local success = pcall(function() FishingCompleted:FireServer() end)
    if success then
        logger:info("✅ FishingCompleted fired successfully!")
    else
        logger:warn("⚠️ Failed to fire FishingCompleted")
    end
    return success
end

-- ===========================
-- Utility / Status / Cleanup
-- ===========================

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

function AutoFishFeature:SetMode(mode)
    if FISHING_CONFIGS[mode] then
        currentMode = mode
        logger:info("Mode changed to:", mode)
        logger:info("  - Completion delay:", FISHING_CONFIGS[mode].completionDelay, "seconds")
        logger:info("  - Wait after fish:", FISHING_CONFIGS[mode].waitAfterFish, "seconds")
        return true
    end
    return false
end

function AutoFishFeature:Cleanup()
    logger:info("Cleaning up...")
    self:Stop()
    controls = {}
    remotesInitialized = false
end

-- Keep file return as before
return AutoFishFeature
