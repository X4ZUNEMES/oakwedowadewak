-- ===========================
-- AUTO FISH BACKEND v6
-- Combines TextEffect, CancelInputs, Fast/Slow modes
-- ===========================

local AutoFish = {}
AutoFish.__index = AutoFish

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- Logger fallback
local logger = _G.Logger and _G.Logger.new("AutoFish") or {
    debug = function() end,
    info = function() print("[INFO]", ...) end,
    warn = function() print("[WARN]", ...) end,
    error = function() print("[ERROR]", ...) end
}

-- ========== NETWORK REMOTES ==========
local NetService = ReplicatedStorage:FindFirstChild("Packages", true)
    and ReplicatedStorage.Packages:FindFirstChild("_Index", true)
    and ReplicatedStorage.Packages._Index:FindFirstChild("sleitnick_net@0.2.0", true)
    and ReplicatedStorage.Packages._Index["sleitnick_net@0.2.0"]:FindFirstChild("net", true)

if not NetService then
    warn("NetService not found!")
    return
end

local EquipToolEvent = NetService:WaitForChild("RE/EquipToolFromHotbar")
local ChargeRodFunc = NetService:WaitForChild("RF/ChargeFishingRod")
local RequestMinigameFunc = NetService:WaitForChild("RF/RequestFishingMinigameStarted")
local FishingCompletedEvent = NetService:WaitForChild("RE/FishingCompleted")
local CancelInputsFunc = NetService:WaitForChild("RF/CancelFishingInputs")
local ReplicateTextEffect = NetService:FindFirstChild("RE/ReplicateTextEffect")
local FishObtainedNotification = NetService:FindFirstChild("RE/ObtainedNewFishNotification")

-- ========== CONFIG ==========
local FISHING_CONFIGS = {
    ["Fast"] = {chargeTime = 1.0, waitBetweenCast = 0, completionDelay = 1.0, waitAfterFish = 1.0, rodSlot = 1},
    ["Slow"] = {chargeTime = 1.0, waitBetweenCast = 1.0, completionDelay = 2.0, waitAfterFish = 2.0, rodSlot = 1}
}

local STUCK_TIMEOUT = 5.0

-- ========== STATE ==========
local isRunning = false
local currentMode = "Fast"
local fishingLoopTask = nil
local lastCastTime = 0
local fishCaughtFlag = false
local waitingForCompletion = false
local textEffectReceived = false

-- ========== UTILITY FUNCTIONS ==========
local function cancelFishing()
    pcall(function()
        CancelInputsFunc:InvokeServer()
    end)
end

local function equipRod(slot)
    pcall(function() EquipToolEvent:FireServer(slot) end)
    task.wait(0.01)
end

local function chargeRod()
    local ok = pcall(function()
        local serverTime = workspace:GetServerTimeNow()
        return ChargeRodFunc:InvokeServer(nil, nil, nil, serverTime)
    end)
    return ok
end

local function castRod()
    local x, z = -1.2331848144531, 0.99277655860847
    local serverTime = workspace:GetServerTimeNow()
    local success, result = pcall(function()
        return RequestMinigameFunc:InvokeServer(x, z, serverTime)
    end)
    return success and (result == true or type(result) == "table")
end

local function fireCompletion()
    local success = pcall(function() FishingCompletedEvent:FireServer() end)
    if success then
        cancelFishing()
        logger:info("✅ FishingCompleted fired")
    else
        logger:warn("⚠️ Failed to fire FishingCompleted")
    end
    return success
end

-- ========== LISTENERS ==========
local function setupFishObtainedListener()
    if not FishObtainedNotification then return end
    FishObtainedNotification.OnClientEvent:Connect(function()
        fishCaughtFlag = true
        waitingForCompletion = false
        textEffectReceived = false
        logger:info("🐟 Fish caught!")
        task.wait(FISHING_CONFIGS[currentMode].waitAfterFish)
        fishCaughtFlag = false
    end)
end

local function setupTextEffectListener()
    if not ReplicateTextEffect then return end
    ReplicateTextEffect.OnClientEvent:Connect(function(data)
        if not data or not data.TextData then return end
        if not LocalPlayer.Character or not LocalPlayer.Character.Head then return end
        if data.TextData.AttachTo ~= LocalPlayer.Character.Head then return end

        logger:info("📝 Text effect detected!")
        textEffectReceived = true
        waitingForCompletion = true

        task.spawn(function()
            task.wait(FISHING_CONFIGS[currentMode].completionDelay)
            if isRunning and not fishCaughtFlag then
                fireCompletion()
                waitingForCompletion = false
                textEffectReceived = false
            end
        end)
    end)
end

-- ========== CORE LOOP ==========
local function fishingLoop()
    while isRunning do
        -- Stuck detection
        if waitingForCompletion or fishCaughtFlag then
            if tick() - lastCastTime >= STUCK_TIMEOUT then
                logger:warn("⚠️ Stuck detected! Resetting...")
                waitingForCompletion = false
                textEffectReceived = false
                fishCaughtFlag = false
                cancelFishing()
            else
                task.wait(0.1)
                continue
            end
        end

        -- Start new cast
        local config = FISHING_CONFIGS[currentMode]
        lastCastTime = tick()
        equipRod(config.rodSlot)
        if chargeRod() and castRod() then
            waitingForCompletion = true
            -- Wait between casts
            task.wait(config.waitBetweenCast)
        else
            task.wait(0.05)
        end
    end
end

-- ========== PUBLIC API ==========
function AutoFish:Start(mode)
    if isRunning then return end
    currentMode = mode or "Fast"
    isRunning = true
    fishCaughtFlag = false
    waitingForCompletion = false
    textEffectReceived = false
    lastCastTime = 0

    setupFishObtainedListener()
    setupTextEffectListener()

    fishingLoopTask = task.spawn(fishingLoop)
    logger:info("🎣 AutoFish started - Mode:", currentMode)
end

function AutoFish:Stop()
    if not isRunning then return end
    isRunning = false
    cancelFishing()
    fishCaughtFlag = false
    waitingForCompletion = false
    textEffectReceived = false
    logger:info("🛑 AutoFish stopped")
end

function AutoFish:SetMode(mode)
    if FISHING_CONFIGS[mode] then
        currentMode = mode
        logger:info("Mode changed to:", mode)
        return true
    end
    return false
end

function AutoFish:SetDelays(completionDelay, waitAfterFish)
    local config = FISHING_CONFIGS[currentMode]
    if completionDelay then config.completionDelay = completionDelay end
    if waitAfterFish then config.waitAfterFish = waitAfterFish end
    logger:info("Delays updated - Completion:", config.completionDelay, "WaitAfterFish:", config.waitAfterFish)
end

function AutoFish:GetStatus()
    return {
        running = isRunning,
        mode = currentMode,
        waitingForCompletion = waitingForCompletion,
        textEffectReceived = textEffectReceived,
        fishCaughtFlag = fishCaughtFlag
    }
end

return AutoFish
