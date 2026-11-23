--[[
  SINGLE-BOT script: one main, one bot, no formations / groups.
  Run it on the BOT account only, with the loader (the names live in the loader, not in this file):
      getgenv().CONFIG = { main = "YourMain", bot = "YourBot" }
      loadstring(game:HttpGet("<raw link to THIS file>", true))()
  Optional CONFIG keys:
      mains = {"another"}           -- extra mains
      afk = false                   -- start with the focus spoof off
      summonRadius = {4, 10}        -- .summon lands this many studs from the player
      boombox = "boombox"           -- tool name to look for in the bot's hand
  Prefixes: . ? ! ;      Commands: .cmds
]]

local CONFIG = getgenv().CONFIG
if not CONFIG or not CONFIG.main then
    warn("CONFIG not set! do getgenv().CONFIG = { main = 'yourmain', bot = 'yourbot' } before loading!")
    return
end
if getgenv().BOT_STOP then pcall(getgenv().BOT_STOP) end -- re-running replaces the old copy

local Players  = game:GetService("Players")
local RS       = game:GetService("RunService")
local TCS      = game:GetService("TextChatService")
local SG       = game:GetService("StarterGui")
local UIS      = game:GetService("UserInputService")
local RepStore = game:GetService("ReplicatedStorage")
local lp  = Players.LocalPlayer
local TAU = math.pi * 2

local conns, threads = {}, {}
local function on(sig, fn) conns[#conns + 1] = sig:Connect(fn) end
local function bg(fn) local t = task.spawn(fn); threads[#threads + 1] = t; return t end

local function notify(t, x)
    pcall(function() SG:SetCore("SendNotification", { Title = t, Text = tostring(x), Duration = 5 }) end)
end

local function say(msg)
    pcall(function()
        local chans = TCS:FindFirstChild("TextChannels")
        local chan = chans and chans:FindFirstChild("RBXGeneral")
        if chan then chan:SendAsync(msg) return end
        local ev = RepStore:FindFirstChild("DefaultChatSystemChatEvents")
        if ev then ev.SayMessageRequest:FireServer(msg, "All") end
    end)
end

-- ===== WHO IS WHO (exact usernames only, never display names) =====
local me = lp.Name:lower()
local MAINS = { [tostring(CONFIG.main):lower()] = true }
for _, n in ipairs(CONFIG.mains or {}) do MAINS[tostring(n):lower()] = true end
local TRUSTED = getgenv().TRUSTED or {}
getgenv().TRUSTED = TRUSTED

if MAINS[me] then
    warn("[bot] " .. lp.Name .. " is a MAIN account, so the bot script was not started here")
    notify("Bot script", "This is a main account, not running the bot here")
    return
end
if CONFIG.bot and me ~= tostring(CONFIG.bot):lower() then
    warn("[bot] this account (" .. lp.Name .. ") is not the bot (" .. tostring(CONFIG.bot) .. "), not starting")
    notify("Bot script", "Wrong account, expected " .. tostring(CONFIG.bot))
    return
end

local PREFIX = { ["."] = true, ["?"] = true, ["!"] = true, [";"] = true }

local function mainName()
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name:lower() == tostring(CONFIG.main):lower() then return p.Name end
    end
    return CONFIG.main
end

local function findPlayer(q)
    if not q or q == "" then return nil end
    q = q:lower()
    for _, p in ipairs(Players:GetPlayers()) do if p.Name:lower() == q then return p end end
    for _, p in ipairs(Players:GetPlayers()) do if (p.DisplayName or ""):lower() == q then return p end end
    for _, p in ipairs(Players:GetPlayers()) do if p.Name:lower():find(q, 1, true) then return p end end
    for _, p in ipairs(Players:GetPlayers()) do if (p.DisplayName or ""):lower():find(q, 1, true) then return p end end
    return nil
end

local function flat(v)
    local f = Vector3.new(v.X, 0, v.Z)
    return f.Magnitude > .01 and f.Unit or nil
end

-- ===== DONATE / HIDE / SUMMON / FLING =====
local function getTime()
    local ls = lp:FindFirstChild("leaderstats")
    if ls then
        local t = ls:FindFirstChild("Time")
        if t and (t:IsA("IntValue") or t:IsA("NumberValue")) then return math.max(0, math.floor(t.Value)) end
    end
    return 0
end

local function dn(n) return (tostring(n):gsub("_", ".")) end -- the game doesn't allow "_" in names

local function donate(amount, to)
    if amount <= 0 then return notify("Donate Fail", "0 time") end
    say(';donate "' .. dn(to) .. '" "' .. amount .. '"')
    notify("Donated", amount .. " to " .. to)
end

local autoOn, autoThread = false, nil
local function toggleAuto(enable, interval, to, silent)
    if autoThread then pcall(task.cancel, autoThread); autoThread = nil end
    autoOn = enable
    if enable then
        local iv = interval or 60
        autoThread = bg(function()
            while autoOn do donate(getTime(), to) task.wait(iv) end
        end)
        notify("Auto Donate", "ON every " .. iv .. "s")
    elseif not silent then
        notify("Auto Donate", "OFF")
    end
end

local hideConn
local function toggleHide(enable, silent)
    if hideConn then hideConn:Disconnect(); hideConn = nil end
    if enable then
        hideConn = RS.Stepped:Connect(function()
            local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.CFrame = CFrame.new(9999, 9999, 9999) end
        end)
    end
    if not silent then notify("Hide", enable and "ON" or "OFF") end
end

local flingConn
local function toggleFling(enable, targetName, silent)
    if flingConn then flingConn:Disconnect(); flingConn = nil end
    if not enable then
        local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.AssemblyLinearVelocity = Vector3.zero; hrp.AssemblyAngularVelocity = Vector3.zero end
        if not silent then notify("Fling", "Stopped") end
        return
    end
    local target = findPlayer(targetName)
    if not target then notify("Fling Error", "No player: " .. tostring(targetName)) return end
    flingConn = RS.Heartbeat:Connect(function()
        local tHrp  = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        local myHrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        local hum   = lp.Character and lp.Character:FindFirstChild("Humanoid")
        if not (myHrp and tHrp) then return end
        myHrp.CFrame = tHrp.CFrame * CFrame.new(math.random(-2, 2), math.random(0, 1), math.random(-2, 2))
        myHrp.AssemblyAngularVelocity = Vector3.new(math.random(-900, 900), math.random(-1800, 1800), math.random(-900, 900))
        local dir = tHrp.Position - myHrp.Position
        local fl = Vector3.new(dir.X, 0, dir.Z)
        local pushDir = (fl.Magnitude > 0.01) and fl.Unit or Vector3.new(1, 0, 0)
        tHrp.AssemblyLinearVelocity = pushDir * 2800 + Vector3.new(math.random(-200, 200), math.random(600, 1000), math.random(-200, 200))
        if hum and hum:GetState() ~= Enum.HumanoidStateType.Jumping then hum.Jump = true end
    end)
    notify("Fling", "Flinging " .. target.Name)
end

local function stopHF() -- drop out of hide/fling (used when a movement command takes over)
    if hideConn then toggleHide(false, true) end
    if flingConn then toggleFling(false, nil, true) end
end

local SR = type(CONFIG.summonRadius) == "table" and CONFIG.summonRadius or { 4, 10 }
local function summonCF(th) -- random spot around the player, facing them
    local a, r = math.random() * TAU, SR[1] + math.random() * (SR[2] - SR[1])
    local c = th.Position
    local p = Vector3.new(c.X + math.cos(a) * r, c.Y, c.Z + math.sin(a) * r)
    return CFrame.lookAt(p, Vector3.new(c.X, p.Y, c.Z))
end

-- ===== ANTI-AFK =====
local VU = game:GetService("VirtualUser")
local function nudge()
    pcall(function() VU:CaptureController() end)
    pcall(function() VU:ClickButton2(Vector2.new(math.random(1, 8), math.random(1, 8))) end)
end
on(lp.Idled, nudge)
bg(function() while true do nudge() task.wait(45) end end)

-- "always tabbed in" spoof: kills the game's focus-lost handlers, fires its focus handlers,
-- and makes IsWindowFocused() return true. Needs getconnections / hookmetamethod in the executor.
local afk, afkOff = false, {}
local function conList(sig)
    if typeof(getconnections) ~= "function" then return {} end
    local ok, r = pcall(getconnections, sig)
    return ok and r or {}
end
pcall(function()
    if hookmetamethod and newcclosure and getnamecallmethod and checkcaller then
        local old
        old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            if afk and self == UIS and not checkcaller() and getnamecallmethod() == "IsWindowFocused" then
                return true
            end
            return old(self, ...)
        end))
    end
end)
local afkThread
local function setAfk(enable, silent)
    if afkThread then pcall(task.cancel, afkThread); afkThread = nil end
    afk = enable
    if not enable then
        for c in pairs(afkOff) do pcall(function() c:Enable() end) end
        afkOff = {}
        if not silent then notify("AFK Spoof", "OFF") end
        return
    end
    if not silent then
        notify("AFK Spoof", typeof(getconnections) == "function" and "ON" or "ON (limited: no getconnections)")
    end
    afkThread = bg(function()
        while afk do
            for _, c in ipairs(conList(UIS.WindowFocusReleased)) do
                if not afkOff[c] and pcall(function() c:Disable() end) then afkOff[c] = true end
            end
            for _, c in ipairs(conList(UIS.WindowFocused)) do pcall(function() c:Fire() end) end
            task.wait(10)
        end
    end)
end

-- ===== MOVEMENT: orbit / line / stare =====
local MOVE, stare, moving = nil, nil, false -- MOVE = { kind, target, radius, speed, gap }
local TRAIL = {}

local function orbitCF(P, th)
    local a = os.clock() * P.speed
    local c = th.Position
    return CFrame.lookAt(c + Vector3.new(math.cos(a) * P.radius, 0, math.sin(a) * P.radius), c) -- facing the middle
end

-- line: the bot follows the player's real path, `gap` studs behind
local function lineCF(P, th)
    local head = th.Position
    local name = P.target:lower()
    local t = TRAIL[name]
    if not t then t = {}; TRAIL[name] = t end
    local last = t[#t]
    if last and (head - last).Magnitude > 40 then -- teleported: fresh trail
        t = {}
        TRAIL[name] = t
        last = nil
    end
    if not last or (head - last).Magnitude > .75 then
        t[#t + 1] = head
        if #t > 900 then t = table.move(t, #t - 599, #t, 1, {}); TRAIL[name] = t end
    end
    local look = flat(th.CFrame.LookVector) or Vector3.new(0, 0, -1)
    local function at(dist)
        local prev, rem = head, dist
        for i = #t, 1, -1 do
            local seg = (prev - t[i]).Magnitude
            if seg > 0 and seg >= rem then return prev:Lerp(t[i], rem / seg) end
            rem = rem - seg
            prev = t[i]
        end
        return prev - look * rem
    end
    local pos, ahead = at(P.gap), at(P.gap * .5)
    local face = flat(ahead - pos) or look
    return CFrame.lookAt(pos, pos + face)
end

on(RS.Heartbeat, function()
    local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    if MOVE then
        local anchor = Players:FindFirstChild(MOVE.target)
        if not anchor then
            notify("Movement", MOVE.target .. " left, stopped")
            MOVE = nil
        else
            local th = anchor.Character and anchor.Character:FindFirstChild("HumanoidRootPart")
            if th then
                hrp.CFrame = (MOVE.kind == "orbit") and orbitCF(MOVE, th) or lineCF(MOVE, th)
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                moving = true
            end
        end
    elseif moving then
        moving = false
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end
    if stare then -- keep turning to face them (works on top of orbit / line)
        local t = Players:FindFirstChild(stare)
        local th = t and t.Character and t.Character:FindFirstChild("HumanoidRootPart")
        if th then
            local p = hrp.Position
            local d = flat(th.Position - p)
            if d then hrp.CFrame = CFrame.lookAt(p, p + d) end
        end
    end
end)

-- ===== BOOMBOX =====
local BOOM = tostring(CONFIG.boombox or "boombox"):lower()
local function boomTool()
    local ch = lp.Character
    for _, t in ipairs(ch and ch:GetChildren() or {}) do
        if t:IsA("Tool") and t.Name:lower():find(BOOM, 1, true) then return t end
    end
end
local function boombox(arg)
    local tool = boomTool()
    if not tool then return notify("Boombox", "no boombox in hand") end
    local id = tonumber(arg)
    local stop = (arg or ""):lower() == "stop"
    if not id and not stop then return notify("Boombox", "usage: .play <id> | .play stop") end
    local n = 0
    for _, d in ipairs(tool:GetDescendants()) do
        local ev, fn = d:IsA("RemoteEvent"), d:IsA("RemoteFunction")
        if ev or fn then
            local nm, args = d.Name:lower(), nil
            if nm == "remote" then
                args = stop and { "StopSong" } or { "PlaySong", id } -- the classic Roblox boombox
            elseif nm:find("play") or nm:find("song") or nm:find("music") or nm:find("sound") or nm:find("track") or nm:find("audio") then
                args = stop and {} or { id }
            end
            if args then
                n = n + 1
                task.spawn(function()
                    pcall(function()
                        if ev then d:FireServer(unpack(args)) else d:InvokeServer(unpack(args)) end
                    end)
                end)
            end
        end
    end
    notify("Boombox", n > 0 and ((stop and "stop" or ("play " .. id)) .. " sent to " .. n .. " remote(s)")
        or "no matching remote, try .boominfo")
end
local function boominfo()
    local tool = boomTool()
    if not tool then return notify("Boombox", "no boombox in hand") end
    local names = {}
    for _, d in ipairs(tool:GetDescendants()) do
        if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
            names[#names + 1] = d.ClassName .. " " .. d:GetFullName()
        end
    end
    print("[Boombox] " .. tool.Name .. ":\n" .. table.concat(names, "\n"))
    notify("Boombox", tool.Name .. ": " .. #names .. " remote(s), see console (F9)")
end

-- ===== COMMANDS =====
local seen = {}
local function handle(msg, plr)
    local sp = plr.Name
    local isMain = MAINS[sp:lower()] == true
    if not (isMain or TRUSTED[sp:lower()]) then return end -- exact username only
    if not PREFIX[msg:sub(1, 1)] then return end

    local now = os.clock()
    if now - (seen.__t or 0) > 60 then seen = { __t = now } end
    local dk = sp .. "|" .. msg
    if seen[dk] and now - seen[dk] < .5 then return end
    seen[dk] = now

    local w = {}
    for x in msg:gmatch("%S+") do w[#w + 1] = x end
    if #w == 0 then return end
    local cmd = w[1]:sub(2):lower()
    local to = isMain and sp or mainName() -- who donations go to

    if cmd == "dall" or cmd == "donateall" then
        donate(getTime(), to)

    elseif cmd == "adall" then
        local n = tonumber(w[2])
        if n and n > 0 then toggleAuto(true, n, to) else toggleAuto(false) end

    elseif cmd == "stopauto" then
        toggleAuto(false)

    elseif cmd == "hide" then
        MOVE = nil
        stopHF()
        toggleHide(true)

    elseif cmd == "unhide" or cmd == "show" then
        toggleHide(false)

    elseif cmd == "summon" then
        local th = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
        local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        if th and hrp then
            MOVE = nil
            stopHF()
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.CFrame = summonCF(th)
            notify("Summon", "Teleported to " .. sp)
        else
            notify("Summon", "Can't see " .. sp)
        end

    elseif cmd == "f" then
        if not w[2] then return notify("Fling", "Usage: .f [player]") end
        MOVE = nil
        toggleFling(true, w[2])

    elseif cmd == "stopfling" or cmd == "unfling" then
        toggleFling(false)

    elseif cmd == "say" then
        local text = table.concat(w, " ", 2)
        if text ~= "" then say(text) end

    elseif cmd == "enlighten" then
        task.delay(.3, say, ";enlighten " .. dn(sp))

    elseif cmd == "play" or cmd == "boombox" then
        boombox(w[2])
    elseif cmd == "boominfo" then
        boominfo()

    elseif cmd == "follow" or cmd == "stare" then
        local t = w[2] and findPlayer(w[2]) or plr
        if not t then return notify("Follow", "Player not found") end
        if t == lp then return notify("Follow", "Can't watch myself") end
        stare = t.Name
        notify("Follow", "Watching " .. t.Name)
    elseif cmd == "unfollow" or cmd == "unstare" then
        stare = nil
        notify("Follow", "Stopped")

    elseif cmd == "orbit" then -- .orbit [radius] [speed] [player|me]
        local nums, name = {}, nil
        for i = 2, #w do
            local n = tonumber(w[i])
            if n and #nums < 2 then nums[#nums + 1] = n else name = w[i] end
        end
        local t = (not name or name:lower() == "me") and plr or findPlayer(name)
        if not t then return notify("Orbit", "Player not found") end
        if t == lp then return notify("Orbit", "Can't orbit myself") end
        local old = MOVE and MOVE.kind == "orbit" and MOVE or {}
        stopHF()
        MOVE = {
            kind = "orbit", target = t.Name,
            radius = math.clamp(nums[1] or old.radius or 6, 2, 50),
            speed = math.clamp(nums[2] or old.speed or 3, 0, 20), -- 0 holds still
        }
        notify("Orbit", "Orbiting " .. t.Name)

    elseif cmd == "unorbit" then
        if MOVE and MOVE.kind == "orbit" then MOVE = nil; notify("Orbit", "Stopped") end

    elseif cmd == "line" or cmd == "train" then -- .line [gap] | .line off
        local a2 = (w[2] or ""):lower()
        if a2 == "off" or a2 == "stop" then
            if MOVE and MOVE.kind == "line" then MOVE = nil; notify("Line", "Stopped") end
            return
        end
        if plr == lp then return end
        stopHF()
        MOVE = { kind = "line", target = sp, gap = math.clamp(tonumber(w[2]) or 4, 2, 20) }
        notify("Line", "Following " .. sp)

    elseif cmd == "unline" then
        if MOVE and MOVE.kind == "line" then MOVE = nil; notify("Line", "Stopped") end

    elseif cmd == "afk" or cmd == "antiafk" then
        local a2 = (w[2] or ""):lower()
        local state
        if a2 == "on" then state = true elseif a2 == "off" then state = false else state = not afk end
        setAfk(state)

    elseif cmd == "r" then
        MOVE, stare = nil, nil
        toggleAuto(false, nil, nil, true)
        stopHF()
        local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.Health = 0 elseif lp.Character then lp.Character:BreakJoints() end
        notify("Reset", "Stopped everything + reset")

    elseif cmd == "clear" or cmd == "perish" then
        MOVE = nil
        toggleAuto(false, nil, nil, true)
        stopHF()
        setAfk(false, true)
        notify("Perish", "Closing Roblox...")
        task.wait(.3)
        pcall(function() game:Shutdown() end)
        task.wait(1)
        pcall(function() lp:Kick("Closed") end)
        task.wait(1)
        pcall(function() game:Shutdown() end)

    elseif cmd == "trust" or cmd == "untrust" then -- mains only
        if not isMain then return end
        local t = findPlayer(w[2])
        if not t then return notify("Trust", "Player not found: " .. tostring(w[2])) end
        if MAINS[t.Name:lower()] or t == lp then return end
        TRUSTED[t.Name:lower()] = (cmd == "trust") or nil
        notify("Trust", (cmd == "trust" and "Trusted " or "Untrusted ") .. t.Name)

    elseif cmd == "cmds" or cmd == "help" then
        notify("Commands", "dall adall stopauto hide unhide summon f stopfling say enlighten play follow unfollow orbit unorbit line afk r clear trust untrust")
    end
end

-- ===== LISTENERS =====
local function safe(m, p)
    local ok, e = pcall(handle, m, p)
    if not ok then warn("[bot] " .. tostring(e)) end
end
local function hook(p) on(p.Chatted, function(m) safe(m, p) end) end
for _, p in ipairs(Players:GetPlayers()) do hook(p) end
on(Players.PlayerAdded, hook)
pcall(function()
    on(TCS.MessageReceived, function(m)
        local src = m.TextSource
        local p = src and Players:GetPlayerByUserId(src.UserId)
        if p then
            local t = m.Text:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&#39;", "'"):gsub("&amp;", "&")
            safe(t, p)
        end
    end)
end)

getgenv().BOT_STOP = function()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for _, t in ipairs(threads) do pcall(task.cancel, t) end
    afk = false
    autoOn = false
    pcall(toggleHide, false, true)
    pcall(toggleFling, false, nil, true)
end

if CONFIG.afk ~= false then setAfk(true, true) end
notify("Script Loaded", "Prefixes: . ? ! ;  |  .cmds for the list  |  Anti-AFK: ON")
