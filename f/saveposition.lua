-- module/f/saveposition.lua  (v3.0 - NO JSON: Direct file storage)
local SavePosition = {}
SavePosition.__index = SavePosition

local logger = _G.Logger and _G.Logger.new("SavePosition") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local FOLDER = "Noctis/FishIt/SavePosition"
local FILE_ENABLED = FOLDER .. "/enabled.txt"
local FILE_POSITION = FOLDER .. "/position.txt"

-- state
local _enabled  = false
local _savedCF  = nil
local _cons     = {}
local _controls = {}
local _initialTeleportDone = false

-- ===== FILE HELPERS (SIMPLE & DIRECT) =====
local function ensureFolder()
    if not isfolder or not makefolder then return false end
    
    local parts = {"Noctis", "Noctis/FishIt", FOLDER}
    for _, path in ipairs(parts) do
        if not isfolder(path) then
            pcall(makefolder, path)
        end
    end
    return true
end

local function saveEnabled(enabled)
    if not writefile then return end
    ensureFolder()
    pcall(writefile, FILE_ENABLED, enabled and "true" or "false")
end

local function loadEnabled()
    if not isfile or not readfile then return false end
    if not isfile(FILE_ENABLED) then return false end
    
    local ok, content = pcall(readfile, FILE_ENABLED)
    return ok and content == "true"
end

local function savePosition(cf)
    if not cf or not writefile then return end
    ensureFolder()
    
    local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
    local data = string.format(
        "%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f",
        x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22
    )
    
    pcall(writefile, FILE_POSITION, data)
    
    if logger and logger.info then
        logger:info("SavePosition: Saved to file:", Vector3.new(x, y, z))
    end
end

local function loadPosition()
    if not isfile or not readfile then return nil end
    if not isfile(FILE_POSITION) then return nil end
    
    local ok, content = pcall(readfile, FILE_POSITION)
    if not ok or not content then return nil end
    
    local parts = {}
    for num in content:gmatch("[^,]+") do
        table.insert(parts, tonumber(num))
    end
    
    if #parts ~= 12 then return nil end
    
    local cf = CFrame.new(
        parts[1], parts[2], parts[3],
        parts[4], parts[5], parts[6],
        parts[7], parts[8], parts[9],
        parts[10], parts[11], parts[12]
    )
    
    if logger and logger.info then
        logger:info("SavePosition: Loaded from file:", cf.Position)
    end
    
    return cf
end

local function clearFiles()
    if not delfile then return end
    if isfile and isfile(FILE_ENABLED) then pcall(delfile, FILE_ENABLED) end
    if isfile and isfile(FILE_POSITION) then pcall(delfile, FILE_POSITION) end
end

-- ===== TELEPORT HELPERS =====
local function waitHRP(timeout)
    local deadline = tick() + (timeout or 10)
    repeat
        local char = LocalPlayer.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then 
                return hrp 
            end
        end
        task.wait(0.1)
    until tick() > deadline
    return nil
end

local function teleportCF(cf)
    if not cf then return false end
    
    local hrp = waitHRP(8)
    if not hrp then return false end
    
    local success = pcall(function()
        hrp.CFrame = cf + Vector3.new(0, 6, 0)
    end)
    
    if success and logger and logger.info then
        logger:info("SavePosition: Teleported to:", cf.Position)
    end
    
    return success
end

local function scheduleTeleport(delaySec, reason)
    task.delay(delaySec or 5, function()
        if _enabled and _savedCF then
            if logger and logger.info then
                logger:info("SavePosition: Teleporting (" .. (reason or "scheduled") .. ")...")
            end
            teleportCF(_savedCF)
        end
    end)
end

-- ===== CHARACTER RESPAWN HANDLER =====
local function bindCharacterAdded()
    -- Disconnect old connections
    for _, c in ipairs(_cons) do 
        pcall(function() c:Disconnect() end) 
    end
    _cons = {}
    
    -- Bind respawn handler
    table.insert(_cons, LocalPlayer.CharacterAdded:Connect(function()
        if logger and logger.info then
            logger:info("SavePosition: Character respawned, waiting for teleport...")
        end
        
        -- Re-load position from file (case: user changed it while alive)
        local freshCF = loadPosition()
        if freshCF then
            _savedCF = freshCF
        end
        
        scheduleTeleport(5, "respawn")
    end))
end

local function captureNow()
    local hrp = waitHRP(3)
    if not hrp then return false end
    _savedCF = hrp.CFrame
    
    if logger and logger.info then
        logger:info("SavePosition: Captured current position:", _savedCF.Position)
    end
    
    return true
end

-- ===== PUBLIC API =====
function SavePosition:Init(a, b)
    _controls = (type(a) == "table" and a ~= self and a) or b or {}
    
    -- DON'T auto-enable on init - let the Toggle control it
    -- Just load the saved position for later use
    local savedCF = loadPosition()
    
    if savedCF then
        _savedCF = savedCF
        if logger and logger.info then
            logger:info("SavePosition: Init - Loaded position:", _savedCF.Position)
        end
    end
    
    -- Always start disabled - wait for Toggle to enable
    _enabled = false
    _initialTeleportDone = true
    bindCharacterAdded()
    
    if logger and logger.info then
        logger:info("SavePosition: Init complete - Waiting for toggle activation")
    end
    
    return true
end

function SavePosition:Start()
    _enabled = true
    _initialTeleportDone = true
    
    -- Try to load existing position first
    local existing = loadPosition()
    if existing then
        _savedCF = existing
        if logger and logger.info then
            logger:info("SavePosition: Started with existing position:", _savedCF.Position)
        end
    else
        -- Capture current position
        if not captureNow() then
            if logger and logger.warn then
                logger:warn("SavePosition: Failed to capture position")
            end
            return false
        end
    end
    
    -- Save to files
    saveEnabled(true)
    savePosition(_savedCF)
    
    -- Setup respawn handler
    bindCharacterAdded()
    scheduleTeleport(3, "start")  -- Quick teleport saat toggle ON
    
    return true
end

function SavePosition:Stop()
    _enabled = false
    _savedCF = nil
    
    -- Clear files
    clearFiles()
    
    if logger and logger.info then
        logger:info("SavePosition: Stopped and cleared")
    end
    
    return true
end

function SavePosition:SaveHere()
    if not captureNow() then 
        return false 
    end
    
    -- Save to files
    saveEnabled(_enabled)
    savePosition(_savedCF)
    
    return true
end

function SavePosition:GetStatus()
    return {
        enabled = _enabled,
        saved   = _savedCF and Vector3.new(_savedCF.X, _savedCF.Y, _savedCF.Z) or nil,
        files_exist = (isfile and isfile(FILE_POSITION)) or false
    }
end

function SavePosition:Cleanup()
    for _, c in ipairs(_cons) do 
        pcall(function() c:Disconnect() end) 
    end
    _cons, _controls = {}, {}
end

-- Debug helper
function SavePosition:Debug()
    print("=== SavePosition Debug ===")
    print("Enabled:", _enabled)
    print("Saved Position:", _savedCF and _savedCF.Position or "none")
    print("File Enabled:", loadEnabled())
    print("File Position:", loadPosition() and "exists" or "missing")
    print("Initial Teleport Done:", _initialTeleportDone)
    print("========================")
end

return SavePosition