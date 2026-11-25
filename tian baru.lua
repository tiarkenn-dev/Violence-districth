local originalPrint = print
local function logQuiet(...) end
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local LocalPlayer = Players.LocalPlayer

local TianHubState = getgenv().TianHubState or {}
getgenv().TianHubState = TianHubState
TianHubState.AutoCrouch = TianHubState.AutoCrouch == true

_G.TianMotionUpdate = function(tr, pos, now, eng)
    local buf = tr.buf
    if not buf then buf = {}; tr.buf = buf end
    buf[#buf + 1] = { t = now, p = Vector3.new(pos.X, 0, pos.Z) }
    while #buf > 2 and now - buf[1].t > 0.4 do table.remove(buf, 1) end
    local n = #buf
    local newest = buf[n]
    local function sampleAt(age)
        local best = buf[1]
        for i = 1, n do
            if now - buf[i].t >= age then best = buf[i] else break end
        end
        return best
    end
    local function velOver(age)
        local sm = sampleAt(age)
        local dt = newest.t - sm.t
        if dt < 0.015 then return nil end
        return (newest.p - sm.p) / dt
    end

    local vRecent = velOver(0.06)
    local vMid = velOver(0.15)
    local sOld, sMid = sampleAt(0.20), sampleAt(0.06)
    local vPrev
    if sMid.t - sOld.t > 0.04 then vPrev = (sMid.p - sOld.p) / (sMid.t - sOld.t) end

    if (not vRecent or vRecent.Magnitude < 2) and eng and eng.Magnitude >= 4 then vRecent = eng end
    if not vRecent then return tr.ema or Vector3.zero, 0.5 end

    local oldest = buf[1]
    if newest.t - oldest.t > 0.25 and (newest.p - oldest.p).Magnitude < 1.2 then
        tr.moving = false
        tr.ema = Vector3.zero
        return Vector3.zero, 1
    end

    local spd = vRecent.Magnitude
    if tr.moving then
        if spd < 2 then tr.moving = false end
    elseif spd > 4 then
        tr.moving = true
    end
    if not tr.moving then
        tr.ema = Vector3.zero
        return Vector3.zero, 1
    end

    local target = vMid or vRecent
    if not tr.ema or tr.ema.Magnitude < 1 then tr.ema = target end
    local dtm = math.clamp(now - (tr.emaT or now), 0, 0.1)
    tr.emaT = now

    if vPrev and vPrev.Magnitude > 3 and vRecent.Magnitude > 3
        and vRecent.Unit:Dot(vPrev.Unit) < 0.75
        and now - (tr.changeAt or -10) > 0.5 then
        tr.changeAt = now
        tr.ema = vRecent
    else
        tr.ema = tr.ema:Lerp(target, 1 - math.exp(-dtm * 10))
    end

    local since = now - (tr.changeAt or -10)
    local conf = since < 0.3 and (0.4 + 0.6 * (since / 0.3)) or 1
    return tr.ema, conf
end

pcall(function() if cleardrawcache then cleardrawcache() end end)

pcall(function()
    if _G.TianConns then
        for _, c in pairs(_G.TianConns) do pcall(function() c:Disconnect() end) end
    end
    _G.TianConns = {}
end)
pcall(function()
    for _, plr in ipairs(game:GetService("Players"):GetPlayers()) do
        local ch = plr.Character
        if ch then
            for _, n in ipairs({ "TianHub_PlayerESP", "TianHub_PlayerTag", "TianHub_ItemESP" }) do
                local o = ch:FindFirstChild(n)
                if o then o:Destroy() end
            end
        end
    end
end)

if CoreGui:FindFirstChild("TianHubUI") then
    CoreGui.TianHubUI:Destroy()
end

local Splash = { Set = function() end, Close = function() end }

local UI = {}
do
local player = LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local ContentProvider = game:GetService("ContentProvider")
local function getGuiParent()
    local ok, h = pcall(function() return gethui and gethui() end)
    if ok and h then return h end
    local ok2, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok2 and cg then
        local okT = pcall(function() local t = Instance.new("Folder"); t.Parent = cg; t:Destroy() end)
        if okT then return cg end
    end
    return playerGui
end
local GUI_PARENT = getGuiParent()

for _, container in ipairs({GUI_PARENT, playerGui, CoreGui}) do
    for _, n in ipairs({"TianHub", "TianHubUI"}) do
        local old = container:FindFirstChild(n)
        if old then old:Destroy() end
    end
end

local C = {
    -- Unified black menu shell; purple is reserved for accent/active indicators.
    bg = Color3.fromRGB(9, 9, 15),             -- #09090F
    sidebar = Color3.fromRGB(9, 9, 15),         -- black sidebar base
    panel = Color3.fromRGB(5, 5, 5),            -- #050505 GroupBox/tab base
    panel2 = Color3.fromRGB(5, 5, 5),            -- keep secondary surfaces black
    hover = Color3.fromRGB(5, 5, 5),             -- no purple/gray tab fill on hover/active
    line = Color3.fromRGB(24, 54, 92),
    text = Color3.fromRGB(245, 243, 255),
    muted = Color3.fromRGB(145, 166, 194),
    sub = Color3.fromRGB(174, 207, 244),
    off = Color3.fromRGB(24, 38, 58),
    red = Color3.fromRGB(235, 80, 120),
}
local DEFAULT_ACCENT = Color3.fromRGB(35, 139, 255) -- TianHub ice blue

local HUB_NAME = "TianHub"
local HUB_SUB = "SURVIVOR • ESP • UTILITY"
local HUB_VERSION = "v88888888888"

-- TianHub winged blue-silver identity asset supplied by the user.
local TIANHUB_ASSET = "rbxassetid://80369014097246"
local LOGO_ASSETS = {
    TIANHUB_ASSET,
}

-- Reuse the supplied TianHub image as the menu background artwork.
local BG_ASSET = TIANHUB_ASSET
local CUSTOM_BG_ASSET = "rbxassetid://74361815952925"
local BG_DEFAULT_OPACITY = 90
local LOGO_BG = Color3.fromRGB(5, 12, 24)

local LOGO_URL = ""
local LOGO_BASE64 = ""

local CONFIG_FOLDER = "TianHub"

local TABS = {
    {Name = "Main",     Icon = "house",    Desc = "Movement, camera and utilities"},
    {Name = "Survivor", Icon = "user",     Desc = "Generator, parry and survivor abilities"},
    {Name = "Killer",   Icon = "swords",   Desc = "Combat, spear and killer abilities"},
    {Name = "ESP",      Icon = "eye",      Desc = "Players, map, information and world effects"},
    {Name = "Music",    Icon = "music",    Desc = "Song library, playback and mini player"},
    {Name = "Settings", Icon = "settings", Desc = "Interface, configs and session info"},
}

local DESIGN_W, DESIGN_H = 900, 550
local SIDE_X, SIDE_W = 8, 184
-- Sidebar and content touch edge-to-edge so the menu reads as one unified surface.
local CONTENT_X = SIDE_X + SIDE_W

local animationsEnabled = true
local keptConnections = {}
local accent = DEFAULT_ACCENT
local accentListeners = {}

local function keep(conn)
    table.insert(keptConnections, conn)
    return conn
end

local function onAccent(fn)
    table.insert(accentListeners, fn)
    pcall(fn)
end

local function accentText()
    return accent:Lerp(C.text, 0.3)
end

local function setAccent(color)
    accent = color
    for _, fn in ipairs(accentListeners) do
        pcall(fn)
    end
end

local function create(className, props, parent)
    local obj = Instance.new(className)
    props = props or {}

    -- TIANHUB: samakan transparansi seluruh panel/menu GUI menjadi 20%.
    -- Hanya berlaku untuk GuiObject di dalam ScreenGui, tidak menyentuh ESP/world objects.
    local insideScreenGui = false
    local ancestor = parent
    while ancestor do
        if ancestor:IsA("ScreenGui") then
            insideScreenGui = true
            break
        end
        ancestor = ancestor.Parent
    end

    if insideScreenGui
        and obj:IsA("GuiObject")
        and props.BackgroundColor3 ~= nil
        and props.BackgroundTransparency == nil then
        -- Apply the menu's default glass tint only when a component has no
        -- explicit transparency. Intentional transparent feature rows stay clear.
        props.BackgroundTransparency = 0.20
    end

    for k, v in pairs(props) do
        obj[k] = v
    end
    obj.Parent = parent
    return obj
end

local function round(parent, radius)
    return create("UICorner", {CornerRadius = UDim.new(0, radius or 8)}, parent)
end

local function outline(parent, thickness, transparency, color)
    return create("UIStroke", {
        Color = color or C.line,
        Thickness = thickness or 1,
        Transparency = transparency or 0.85,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, parent)
end

local function tween(obj, duration, props)
    local d = animationsEnabled and (duration or 0.12) or 0
    local t = TweenService:Create(obj, TweenInfo.new(d, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    t:Play()
    return t
end

local function canHover()
    return UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch
end

local function bar(parent, w, h, x, y, rot, color)
    local f = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(w, h),
        Position = UDim2.fromOffset(x, y),
        Rotation = rot or 0,
        BackgroundColor3 = color,
        BorderSizePixel = 0,
    }, parent)
    round(f, math.max(1, h / 2))
    return f
end

local function makeChevron(parent, color, position, anchor)
    local holder = create("Frame", {
        Size = UDim2.fromOffset(14, 14),
        Position = position,
        AnchorPoint = anchor or Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
    }, parent)
    local a = bar(holder, 6.5, 2, 4.8, 6.2, 45, color)
    local b = bar(holder, 6.5, 2, 9.2, 6.2, -45, color)
    return {
        Holder = holder,
        SetColor = function(c)
            a.BackgroundColor3 = c
            b.BackgroundColor3 = c
        end,
    }
end

local function makeSearchIcon(parent, color, position)
    local holder = create("Frame", {
        Size = UDim2.fromOffset(16, 16),
        Position = position,
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
    }, parent)
    local ring = create("Frame", {
        Size = UDim2.fromOffset(10, 10),
        Position = UDim2.fromOffset(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, holder)
    round(ring, 5)
    outline(ring, 1.6, 0, color)
    bar(holder, 5, 1.8, 12.4, 12.4, 45, color)
    return holder
end

local ICON_PROVIDER_URL = "https://raw.githubusercontent.com/deividcomsono/lucide-roblox-direct/refs/heads/main/source.lua"
local IconProvider = nil
local iconObjects = {}

local function resolveIcon(name)
    if not IconProvider then return nil end
    local ok, asset = pcall(function()
        return IconProvider.GetAsset(name)
    end)
    if ok and type(asset) == "table" and asset.Url then
        return asset
    end
    return nil
end

local function makeIcon(parent, iconName, size, color, position, anchor, noLetter)
    local holder = create("Frame", {
        Size = UDim2.fromOffset(size, size),
        Position = position or UDim2.new(),
        AnchorPoint = anchor or Vector2.new(0, 0),
        BackgroundTransparency = 1,
    }, parent)

    local img = create("ImageLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ImageColor3 = color,
        ScaleType = Enum.ScaleType.Fit,
        Image = "",
        Visible = false,
    }, holder)

    local letter = create("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = color,
        TextSize = math.max(8, math.floor(size * 0.7)),
        Font = Enum.Font.GothamBold,
        Visible = not noLetter,
    }, holder)

    local currentName = iconName
    local obj = {Holder = holder}
    local curColor = color
    local drawn = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
    }, holder)
    local parts = {}

    local function clearDrawn()
        for _, p in ipairs(parts) do pcall(function() p.inst:Destroy() end) end
        parts = {}
    end
    local function rect(w, h, cx, cy, rot, cr)
        local f = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(cx, cy),
            Size = UDim2.fromOffset(math.max(1, w * size), math.max(1, h * size)),
            Rotation = rot or 0,
            BackgroundColor3 = curColor,
            BorderSizePixel = 0,
        }, drawn)
        create("UICorner", {CornerRadius = UDim.new(cr or 0, 0)}, f)
        if cr and cr > 0 and cr < 1 then
            f:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, math.max(1, cr * size))
        end
        parts[#parts + 1] = {inst = f, kind = "bg"}
        return f
    end
    local function disc(d, cx, cy)
        local f = rect(d, d, cx, cy, 0, 0)
        f:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)
        return f
    end
    local function ring(d, cx, cy, th)
        local f = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(cx, cy),
            Size = UDim2.fromOffset(d * size, d * size),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
        }, drawn)
        create("UICorner", {CornerRadius = UDim.new(1, 0)}, f)
        local st = create("UIStroke", {Color = curColor, Thickness = th}, f)
        parts[#parts + 1] = {inst = st, kind = "stroke"}
        return f
    end
    local function drawIcon(name)
        clearDrawn()
        if name == "check" then
            rect(0.4, 0.2, 0.33, 0.6, 45, 0.5)
            rect(0.78, 0.2, 0.6, 0.5, -52, 0.5)
        elseif name == "house" then
            rect(0.52, 0.52, 0.5, 0.36, 45, 0.06)
            rect(0.58, 0.36, 0.5, 0.72, 0, 0.06)
        elseif name == "user" then
            disc(0.36, 0.5, 0.3)
            rect(0.66, 0.36, 0.5, 0.78, 0, 0.18)
        elseif name == "swords" then
            rect(1, 0.17, 0.5, 0.5, 45, 0.5)
            rect(1, 0.17, 0.5, 0.5, -45, 0.5)
        elseif name == "eye" then
            local e = ring(0.9, 0.5, 0.5, 2)
            e.Size = UDim2.fromOffset(0.95 * size, 0.58 * size)
            disc(0.3, 0.5, 0.5)
        elseif name == "settings" then
            ring(0.62, 0.5, 0.5, 2.4)
            disc(0.22, 0.5, 0.5)
            rect(0.16, 0.26, 0.5, 0.09, 0, 0.3)
            rect(0.16, 0.26, 0.5, 0.91, 0, 0.3)
            rect(0.26, 0.16, 0.09, 0.5, 0, 0.3)
            rect(0.26, 0.16, 0.91, 0.5, 0, 0.3)
        else
            return false
        end
        return true
    end

    function obj.Set(name)
        currentName = name
        -- Prefer remote image assets for every icon. Do not render icons
        -- from primitive Frames; keep the frame-based drawing only as unused
        -- legacy code so existing callers remain compatible.
        local info = resolveIcon(name)
        if info then
            clearDrawn()
            drawn.Visible = false
            letter.Visible = false
            img.Visible = true
            img.Image = info.Url
            img.ImageRectSize = info.ImageRectSize or Vector2.new(0, 0)
            img.ImageRectOffset = info.ImageRectOffset or Vector2.new(0, 0)
        else
            img.Visible = false
            drawn.Visible = false
            letter.Visible = not noLetter
            letter.Text = string.upper(string.sub(tostring(name), 1, 1))
        end
    end

    function obj.Refresh()
        if holder.Parent then
            obj.Set(currentName)
        end
    end

    function obj.SetColor(c, animated)
        if animated then
            tween(img, 0.1, {ImageColor3 = c})
            tween(letter, 0.1, {TextColor3 = c})
        else
            img.ImageColor3 = c
            letter.TextColor3 = c
        end
        curColor = c
        for _, p in ipairs(parts) do
            if p.kind == "bg" then
                p.inst.BackgroundColor3 = c
            elseif p.kind == "stroke" then
                p.inst.Color = c
            end
        end
    end

    table.insert(iconObjects, obj)
    obj.Set(iconName)
    return obj
end

local ICON_PROVIDER_URLS = {
    ICON_PROVIDER_URL,
    "https://raw.githubusercontent.com/deividcomsono/lucide-roblox-direct/main/source.lua",
    "https://cdn.jsdelivr.net/gh/deividcomsono/lucide-roblox-direct@main/source.lua",
}
local ICON_PROVIDER_CACHE = "TianHub_Lucide.lua"

task.spawn(function()
    local function tryLoad(src)
        if type(src) ~= "string" or #src < 500 then return nil end
        local fn = loadstring(src)
        if type(fn) ~= "function" then return nil end
        local ok, lib = pcall(fn)
        if ok and type(lib) == "table" and lib.GetAsset then return lib end
        return nil
    end

    local lib
    -- 1) Cache lokal terlebih dahulu agar ikon tetap tersedia saat sumber remote tidak dapat diakses.
    if type(readfile) == "function" and type(isfile) == "function" then
        local okF, has = pcall(isfile, ICON_PROVIDER_CACHE)
        if okF and has then
            local okR, src = pcall(readfile, ICON_PROVIDER_CACHE)
            if okR then lib = tryLoad(src) end
        end
    end

    -- 2) Unduh dengan beberapa mirror dan ulangi sampai berhasil.
    local attempt = 0
    while not lib and attempt < 12 do
        attempt = attempt + 1
        for _, url in ipairs(ICON_PROVIDER_URLS) do
            local src
            local okGet = pcall(function() src = game:HttpGet(url) end)
            if not okGet or not src then pcall(function() src = game:HttpGetAsync(url) end) end
            lib = tryLoad(src)
            if lib then
                if type(writefile) == "function" then pcall(writefile, ICON_PROVIDER_CACHE, src) end
                break
            end
        end
        if not lib then task.wait(math.min(2 + attempt, 8)) end
    end

    if lib then
        IconProvider = lib
        for _ = 1, 3 do
            for _, o in ipairs(iconObjects) do pcall(o.Refresh) end
            task.wait(1) -- ikon yang dibuat belakangan ikut terpasang
        end
        logQuiet("[TianHub] aset ikon dimuat")
    else
        logQuiet("[TianHub] aset ikon gagal dimuat setelah beberapa percobaan")
    end
end)

local logoTargets = {}

local function registerLogo(img, fallback)
    table.insert(logoTargets, {img = img, fallback = fallback})
    img.Image = LOGO_ASSETS[1]

    task.spawn(function()
        for _ = 1, 120 do
            if not img.Parent then return end
            if img.IsLoaded then
                fallback.Visible = false
                return
            end
            task.wait(0.25)
        end
    end)
end

local B64CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64decode(data)
    data = string.gsub(data, "[^%w%+/=]", "")
    local out, buffer, bits = {}, 0, 0
    for i = 1, #data do
        local c = string.sub(data, i, i)
        if c == "=" then break end
        local v = string.find(B64CHARS, c, 1, true)
        if v then
            buffer = buffer * 64 + (v - 1)
            bits += 6
            if bits >= 8 then
                bits -= 8
                local div = 2 ^ bits
                local byte = math.floor(buffer / div)
                buffer = buffer - byte * div
                table.insert(out, string.char(byte))
            end
        end
    end
    return table.concat(out)
end

local function prepareLocalLogo()
    if LOGO_URL == "" and LOGO_BASE64 == "" then return nil end
    if type(writefile) ~= "function" or type(getcustomasset) ~= "function" then
        logQuiet("[TianHub] executor tidak mendukung writefile/getcustomasset, logo lokal dilewati")
        return nil
    end
    local ok, result = pcall(function()
        local data
        if LOGO_BASE64 ~= "" then
            data = b64decode(LOGO_BASE64)
        else
            local okGet = pcall(function()
                data = game:HttpGet(LOGO_URL)
            end)
            if not okGet or not data then
                data = game:HttpGetAsync(LOGO_URL)
            end
        end
        if type(isfolder) == "function" and type(makefolder) == "function" and not isfolder(CONFIG_FOLDER) then
            makefolder(CONFIG_FOLDER)
        end
        local path = CONFIG_FOLDER .. "/logo.png"
        writefile(path, data)
        return getcustomasset(path)
    end)
    if ok and result then
        return result
    end
    logQuiet("[TianHub] logo lokal gagal dibuat: " .. tostring(result))
    return nil
end

local function startLogoResolver(parentGui)
    task.spawn(function()
        local localAsset = prepareLocalLogo()
        if localAsset then
            for _, t in ipairs(logoTargets) do
                if t.img.Parent then
                    t.img.Image = localAsset
                    if t.img.Name == "FloatingLogoImage" then
                        t.img.ImageTransparency = 0
                    end

                    task.spawn(function()
                        for _ = 1, 40 do
                            if not t.img.Parent then return end
                            if t.img.IsLoaded then
                                t.fallback.Visible = false
                                return
                            end
                            task.wait(0.25)
                        end
                    end)
                end
            end
            logQuiet("[TianHub] logo lokal dimuat")
            return
        end
        local function probeImage(content)
            local probe = create("ImageLabel", {
                Size = UDim2.fromOffset(4, 4),
                BackgroundTransparency = 1,
                ImageTransparency = 0.98,
                Image = content,
            }, parentGui)
            pcall(function()
                ContentProvider:PreloadAsync({probe})
            end)
            local t0 = os.clock()
            while not probe.IsLoaded and os.clock() - t0 < 5 do
                task.wait(0.2)
            end
            local good = probe.IsLoaded
            probe:Destroy()
            return good
        end

        local function applyLogo(content)
            for _, t in ipairs(logoTargets) do
                if t.img.Parent then
                    t.img.Image = content
                    if t.img.Name == "FloatingLogoImage" then
                        t.img.ImageTransparency = 0
                    end
                end
            end
        end

        local function decalToImage(content)
            local ok, objs = pcall(function()
                return game:GetObjects(content)
            end)
            if not ok or type(objs) ~= "table" or not objs[1] then return nil end
            local obj = objs[1]
            local tex
            if obj:IsA("Decal") or obj:IsA("Texture") then
                tex = obj.Texture
            else
                local d = obj:FindFirstChildWhichIsA("Decal", true) or obj:FindFirstChildWhichIsA("Texture", true)
                tex = d and d.Texture
            end
            pcall(function() obj:Destroy() end)
            if type(tex) == "string" and tex ~= "" then
                return tex
            end
            return nil
        end

        for index, id in ipairs(LOGO_ASSETS) do
            if probeImage(id) then
                if index ~= 1 then applyLogo(id) end
                logQuiet("[TianHub] logo dimuat: " .. id)
                return
            end
            local converted = decalToImage(id)
            if converted and probeImage(converted) then
                applyLogo(converted)
                logQuiet("[TianHub] logo dimuat (dari Decal): " .. converted)
                return
            end
        end
        logQuiet("[TianHub] logo belum tersedia; mempertahankan gambar asset tanpa fallback teks")
    end)
end

local function makeLogo(parent, size, radius)
    local holder = create("Frame", {
        Size = UDim2.fromOffset(size, size),
        BackgroundColor3 = LOGO_BG,
        BorderSizePixel = 0,
    }, parent)
    round(holder, radius)
    outline(holder, 1, 0.3)

    local fallback = create("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = C.text,
        TextSize = math.floor(size * 0.55),
        Font = Enum.Font.GothamBold,
        Visible = false,
    }, holder)

    local image = create("ImageLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = 2,
    }, holder)
    round(image, radius)
    registerLogo(image, fallback)

    return holder
end

local TianHubBackgroundSync
local setTianHubBackgroundVisibility
local applyTianHubBackgroundImage
local restoreTianHubBackgrounds

local gui = create("ScreenGui", {
    Name = "TianHub",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 100,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    Enabled = false,
}, GUI_PARENT)
pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)

keep(gui.Destroying:Connect(function()
    pcall(restoreTianHubBackgrounds)
    for _, c in ipairs(keptConnections) do
        c:Disconnect()
    end
end))

local isOpen = false
local dragging = false

local FLOAT_SIZE = 48
local FLOAT_RADIUS = 24
local openButton = create("TextButton", {
    Name = "FloatingOpen",
    Size = UDim2.fromOffset(FLOAT_SIZE, FLOAT_SIZE),
    Position = UDim2.new(0, 14, 0.42, 0),
    BackgroundColor3 = LOGO_BG,
    Text = "",
    AutoButtonColor = false,
    ZIndex = 20,
}, gui)
round(openButton, FLOAT_RADIUS)
local openStroke = outline(openButton, 1.5, 0.35)

local openFallback = create("TextLabel", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Text = "",
    TextColor3 = C.text,
    TextSize = 24,
    Font = Enum.Font.GothamBold,
    Visible = false,
    ZIndex = 21,
}, openButton)
local openImage = create("ImageLabel", {
    Name = "FloatingLogoImage",
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    -- Fill the whole floating menu button with the TIANHUB artwork.
    ScaleType = Enum.ScaleType.Crop,
    -- Wait for the resolved banner texture so the floating button never shows
    -- the raw decal/placeholder while the banner already shows the final image.
    ImageTransparency = 1,
    ZIndex = 22,
}, openButton)
round(openImage, FLOAT_RADIUS)
registerLogo(openImage, openFallback)

openButton.MouseEnter:Connect(function()
    tween(openButton, 0.1, {BackgroundColor3 = C.panel2})
end)
openButton.MouseLeave:Connect(function()
    tween(openButton, 0.1, {BackgroundColor3 = LOGO_BG})
end)

local statusPill = create("Frame", {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -12, 0, 10),
    Size = UDim2.fromOffset(150, 26),
    BackgroundColor3 = C.panel,
    BackgroundTransparency = 0.22,
    BorderSizePixel = 0,
    ZIndex = 15,
}, gui)
round(statusPill, 13)
outline(statusPill, 1, 0.3)
local statusLabel = create("TextLabel", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Text = "FPS --  |  -- ms",
    TextColor3 = C.text,
    TextSize = 11,
    Font = Enum.Font.GothamMedium,
    ZIndex = 16,
}, statusPill)

local currentFps, currentPing = 60, 0
do
    local acc, frames = 0, 0
    keep(RunService.Heartbeat:Connect(function(dt)
        acc += dt
        frames += 1
        if acc >= 0.5 then
            currentFps = math.floor(frames / acc + 0.5)
            acc, frames = 0, 0
            local okp, ping = pcall(function()
                return player:GetNetworkPing()
            end)
            currentPing = okp and math.floor(ping * 1000) or 0
            statusLabel.Text = string.format("FPS %d  |  %d ms", currentFps, currentPing)
        end
    end))
end

local shell = create("Frame", {
    Name = "Shell",
    Size = UDim2.fromOffset(DESIGN_W, DESIGN_H),
    Position = UDim2.fromScale(0.5, 0.5),
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundTransparency = 1,
}, gui)

local scale = create("UIScale", {Scale = 1}, shell)
local userScale = 1
local popValue = create("NumberValue", {Value = 1}, gui)

local MIN_W, MIN_H = 560, 350
local curW, curH = DESIGN_W, DESIGN_H
local baseScale = 1

local function setSize(w, h)
    local gs = gui.AbsoluteSize
    local sc = math.max(baseScale, 0.05)
    local maxW = math.max(MIN_W, math.floor(gs.X * 0.98 / sc))
    local maxH = math.max(MIN_H, math.floor(gs.Y * 0.98 / sc))
    curW = math.clamp(w, MIN_W, maxW)
    curH = math.clamp(h, MIN_H, maxH)
    shell.Size = UDim2.fromOffset(curW, curH)
end

local function updateScale()
    local fit = 1
    local size = gui.AbsoluteSize
    if size.X > 0 and size.Y > 0 then
        fit = math.min((size.X * 0.94) / DESIGN_W, (size.Y * 0.94) / DESIGN_H)
    end
    fit = math.clamp(fit, 0.4, 1.4)
    local s = fit * math.min(userScale, 1)
    baseScale = s
    scale.Scale = math.max(s * popValue.Value, 0.05)
    setSize(curW, curH)
end
updateScale()
popValue.Changed:Connect(updateScale)
keep(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScale))

local main = create("CanvasGroup", {
    Name = "Main",
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = C.panel,
    BackgroundTransparency = 1, -- let the artwork show through the whole menu shell
    BorderSizePixel = 0,
    GroupTransparency = 0,
}, shell)
round(main, 14)
-- Static thin outline: decorative outer glow and animated edge are disabled.
local mainStroke = outline(main, 1, 0.35, C.line)

local baseTransparency = 0

local bgImage = create("ImageLabel", {
    Name = "Background",
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Image = BG_ASSET,
    ImageTransparency = 0,
    ScaleType = Enum.ScaleType.Crop,
    ZIndex = 0,
}, main)
round(bgImage, 14)
local customBackgroundApplied = false

-- Shared background state lets the gallery (declared earlier) and the real
-- music mini-player (built later) use the same original-image references.

task.spawn(function()
    local ok, objs = pcall(function()
        return game:GetObjects(BG_ASSET)
    end)
    if not ok or type(objs) ~= "table" or not objs[1] then return end
    local obj = objs[1]
    local tex
    if obj:IsA("Decal") or obj:IsA("Texture") then
        tex = obj.Texture
    else
        local d = obj:FindFirstChildWhichIsA("Decal", true) or obj:FindFirstChildWhichIsA("Texture", true)
        tex = d and d.Texture
    end
    pcall(function() obj:Destroy() end)
    if type(tex) == "string" and tex ~= "" and bgImage.Parent then
        if TianHubBackgroundSync then TianHubBackgroundSync.MainOriginal = tex end
        if not customBackgroundApplied then
            bgImage.Image = tex
        end
        logQuiet("[TianHub] background dimuat (dari Decal): " .. tex)
    end
end)

local sidebar = create("Frame", {
    Name = "Sidebar",
    Position = UDim2.fromOffset(SIDE_X, 8),
    Size = UDim2.new(0, SIDE_W, 1, -16),
    BackgroundColor3 = C.panel,
    BackgroundTransparency = 0.16,
    BorderSizePixel = 0,
}, main)
round(sidebar, 12)
outline(sidebar, 1, 0.18, C.line)

local brandCard = create("Frame", {
    Name = "BrandCard",
    Position = UDim2.fromOffset(8, 8),
    Size = UDim2.new(1, -16, 0, 68),
    BackgroundColor3 = C.panel2,
    BackgroundTransparency = 1, -- match transparent navigation tabs
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, sidebar)
round(brandCard, 10)

-- Banner artwork tetap memakai asset identitas asli TianHub.
-- Hanya layout yang dibuat full-cover seperti referensi; tanpa logo/teks overlay.
local bannerImage = create("ImageLabel", {
    Name = "TianHubBannerImage",
    Position = UDim2.fromScale(0, 0),
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Image = TIANHUB_ASSET,
    ImageTransparency = 0,
    -- Crop fills the entire banner rectangle; no empty/black letterbox bars.
    ScaleType = Enum.ScaleType.Crop,
    BorderSizePixel = 0,
}, brandCard)
round(bannerImage, 10)

TianHubBackgroundSync = {
    Main = bgImage,
    Banner = bannerImage,
    MainOriginal = bgImage.Image,
    BannerOriginal = bannerImage.Image,
    MiniBackground = nil,
    MiniOriginal = nil,
    MiniAlbumArt = nil,
    MiniAlbumArtOriginal = nil,
    Visibility = 500,
    AppliedImage = nil,
    Active = true,
}

setTianHubBackgroundVisibility = function(value)
    local visibility = math.clamp(tonumber(value) or 500, 0, 500)
    TianHubBackgroundSync.Visibility = visibility
    local transparency = 1 - visibility / 500
    for _, image in ipairs({
        TianHubBackgroundSync.Main,
        TianHubBackgroundSync.Banner,
        TianHubBackgroundSync.MiniBackground,
    }) do
        if image and image.Parent then
            pcall(function() image.ImageTransparency = transparency end)
        end
    end
end

applyTianHubBackgroundImage = function(image)
    if type(image) ~= "string" or image == "" then return end
    TianHubBackgroundSync.AppliedImage = image
    for _, target in ipairs({
        TianHubBackgroundSync.Main,
        TianHubBackgroundSync.Banner,
        TianHubBackgroundSync.MiniBackground,
        TianHubBackgroundSync.MiniAlbumArt,
    }) do
        if target and target.Parent then
            pcall(function() target.Image = image end)
        end
    end
    setTianHubBackgroundVisibility(TianHubBackgroundSync.Visibility)
end

restoreTianHubBackgrounds = function()
    if not TianHubBackgroundSync.Active then return end
    TianHubBackgroundSync.Active = false
    local restoreTargets = {
        {TianHubBackgroundSync.Main, TianHubBackgroundSync.MainOriginal},
        {TianHubBackgroundSync.Banner, TianHubBackgroundSync.BannerOriginal},
        {TianHubBackgroundSync.MiniBackground, TianHubBackgroundSync.MiniOriginal},
        {TianHubBackgroundSync.MiniAlbumArt, TianHubBackgroundSync.MiniAlbumArtOriginal},
    }
    for _, entry in ipairs(restoreTargets) do
        local target, original = entry[1], entry[2]
        if target and target.Parent and type(original) == "string" then
            pcall(function() target.Image = original end)
        end
        if target and target.Parent then
            pcall(function()
                if target == TianHubBackgroundSync.Main then
                    target.ImageTransparency = 0
                elseif target == TianHubBackgroundSync.Banner then
                    target.ImageTransparency = 0
                elseif target == TianHubBackgroundSync.MiniBackground then
                    target.ImageTransparency = 0.44
                end
            end)
        end
    end
    TianHubBackgroundSync.AppliedImage = nil
end

_G.TianHubBackgroundSync = TianHubBackgroundSync


outline(brandCard, 1, 0.55)

-- Lightweight banner shimmer: one UIGradient tween, no per-frame loop.
-- The overlay is clipped to the banner and does not intercept input.
local bannerShimmer = create("Frame", {
    Name = "TianHubBannerShimmer",
    Position = UDim2.fromScale(0, 0),
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
    BackgroundTransparency = 0,
    BorderSizePixel = 0,
    ZIndex = bannerImage.ZIndex + 1,
    Active = false,
    Selectable = false,
}, brandCard)
round(bannerShimmer, 10)

local shimmerGradient = Instance.new("UIGradient")
shimmerGradient.Name = "TianHubShimmerGradient"
shimmerGradient.Rotation = 18
shimmerGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0.00, C.line),
    ColorSequenceKeypoint.new(0.50, accent),
    ColorSequenceKeypoint.new(1.00, C.text),
})
shimmerGradient.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0.00, 1.00),
    NumberSequenceKeypoint.new(0.40, 1.00),
    NumberSequenceKeypoint.new(0.50, 0.48),
    NumberSequenceKeypoint.new(0.60, 1.00),
    NumberSequenceKeypoint.new(1.00, 1.00),
})
shimmerGradient.Offset = Vector2.new(-1.25, 0)
shimmerGradient.Parent = bannerShimmer

-- Slow sweep with a pause between passes keeps the effect subtle and cheap.
local shimmerTween = TweenService:Create(
    shimmerGradient,
    TweenInfo.new(2.6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false, 1.8),
    { Offset = Vector2.new(1.25, 0) }
)
shimmerTween:Play()

-- Resolve the original TianHub decal into its actual texture URL.
-- ImageLabel.Image may show blank when given a Decal asset ID directly.
task.spawn(function()
    local ok, objs = pcall(function()
        return game:GetObjects(TIANHUB_ASSET)
    end)
    if not ok or type(objs) ~= "table" or not objs[1] then return end
    local obj = objs[1]
    local tex
    if obj:IsA("Decal") or obj:IsA("Texture") then
        tex = obj.Texture
    else
        local d = obj:FindFirstChildWhichIsA("Decal", true) or obj:FindFirstChildWhichIsA("Texture", true)
        tex = d and d.Texture
    end
    pcall(function() obj:Destroy() end)
    if type(tex) == "string" and tex ~= "" and bannerImage.Parent then
        TianHubBackgroundSync.BannerOriginal = tex
        if not customBackgroundApplied then
            bannerImage.Image = tex
        end
        if openImage and openImage.Parent and not customBackgroundApplied then
            openImage.Image = tex
            openImage.ImageTransparency = 0
        end
        logQuiet("[TianHub] banner/floating image dimuat dari texture yang sama")
    end
end)

-- Fallback: if GetObjects cannot resolve the Decal, preload the banner itself
-- and copy its effective Image value to the floating button after it is ready.
task.spawn(function()
    pcall(function()
        ContentProvider:PreloadAsync({bannerImage})
    end)
    if bannerImage.Parent and openImage and openImage.Parent and bannerImage.IsLoaded and not customBackgroundApplied then
        openImage.Image = bannerImage.Image
        openImage.ImageTransparency = 0
    end
end)

local searchWrap = create("Frame", {
    Position = UDim2.fromOffset(10, 84),
    Size = UDim2.new(1, -20, 0, 32),
    BackgroundColor3 = C.panel,
    BackgroundTransparency = 0.12,
    BorderSizePixel = 0,
}, sidebar)
round(searchWrap, 8)
local searchStroke = outline(searchWrap, 1, 0.2, C.line)
makeSearchIcon(searchWrap, C.muted, UDim2.new(0, 10, 0.5, 0))
local search = create("TextBox", {
    Name = "Search",
    Position = UDim2.fromOffset(32, 0),
    Size = UDim2.new(1, -40, 1, 0),
    BackgroundTransparency = 1,
    Text = "",
    PlaceholderText = "Search",
    PlaceholderColor3 = C.muted,
    TextColor3 = C.text,
    TextSize = 13,
    Font = Enum.Font.Gotham,
    ClearTextOnFocus = false,
    TextXAlignment = Enum.TextXAlignment.Left,
}, searchWrap)
search.Focused:Connect(function()
    tween(searchStroke, 0.1, {Transparency = 0})
end)
search.FocusLost:Connect(function()
    tween(searchStroke, 0.1, {Transparency = 0.2})
end)

local navWrap = create("Frame", {
    Position = UDim2.fromOffset(8, 126),
    Size = UDim2.new(1, -16, 1, -184),
    BackgroundTransparency = 1,
    ClipsDescendants = true,
}, sidebar)

local navHolder = create("ScrollingFrame", {
    Name = "NavigationScroll",
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 0,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollingDirection = Enum.ScrollingDirection.Y,
}, navWrap)
create("UIListLayout", {
    -- No gaps: all navigation items visually merge into the solid sidebar.
    Padding = UDim.new(0, 0),
    SortOrder = Enum.SortOrder.LayoutOrder,

    HorizontalAlignment = Enum.HorizontalAlignment.Left,
}, navHolder)

create("Frame", {
    Position = UDim2.new(0, 12, 1, -52),
    Size = UDim2.new(1, -24, 0, 1),
    BackgroundColor3 = C.line,
    BackgroundTransparency = 0.32,
    BorderSizePixel = 0,
}, sidebar)

local avatarBtn = create("ImageButton", {
    Position = UDim2.new(0, 10, 1, -44),
    Size = UDim2.fromOffset(34, 34),
    BackgroundColor3 = C.panel2,
    BackgroundTransparency = 0.12,
    AutoButtonColor = false,
    Image = "",
}, sidebar)
round(avatarBtn, 17)
outline(avatarBtn, 1.2, 0.22, C.line)
task.spawn(function()
    local ok, thumb = pcall(function()
        return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
    end)
    if ok and avatarBtn.Parent then
        avatarBtn.Image = thumb
    end
end)

local realName = player.Name
local function maskName(n)
    local keepN = math.min(3, #n)
    return string.sub(n, 1, keepN) .. string.rep("*", math.clamp(#n - keepN, 3, 7))
end
local nameHidden = true

local namePill = create("Frame", {
    Position = UDim2.new(0, 50, 1, -44),
    Size = UDim2.new(1, -60, 0, 34),
    BackgroundColor3 = C.panel,
    BackgroundTransparency = 0.12,
    BorderSizePixel = 0,
}, sidebar)
round(namePill, 17)
outline(namePill, 1, 0.24, C.line)

local nameLabel = create("TextLabel", {
    Position = UDim2.fromOffset(12, 0),
    Size = UDim2.new(1, -44, 1, 0),
    BackgroundTransparency = 1,
    Text = maskName(realName),
    TextColor3 = C.text,
    TextSize = 12,
    Font = Enum.Font.GothamMedium,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
}, namePill)

local eyeBtn = create("TextButton", {
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -3, 0.5, 0),
    Size = UDim2.fromOffset(28, 28),
    BackgroundColor3 = C.hover,
    BackgroundTransparency = 1,
    Text = "",
    AutoButtonColor = false,
}, namePill)
round(eyeBtn, 14)
local eyeIcon = makeIcon(eyeBtn, "eye", 16, C.muted, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))

local function refreshEye(hover)
    local color = hover and C.text or C.muted
    eyeIcon.Set(nameHidden and "eye-off" or "eye")
    eyeIcon.SetColor(color, false)
end
refreshEye(false)
eyeBtn.MouseEnter:Connect(function()
    tween(eyeBtn, 0.1, {BackgroundTransparency = 0.3})
    refreshEye(true)
end)
eyeBtn.MouseLeave:Connect(function()
    tween(eyeBtn, 0.1, {BackgroundTransparency = 1})
    refreshEye(false)
end)
eyeBtn.Activated:Connect(function()
    nameHidden = not nameHidden
    nameLabel.Text = nameHidden and maskName(realName) or realName
    refreshEye(false)
end)

local content = create("Frame", {
    Name = "Content",
    Position = UDim2.new(0, CONTENT_X, 0, 0),
    Size = UDim2.new(1, -CONTENT_X, 1, 0),
    BackgroundColor3 = C.panel,
    BackgroundTransparency = 1, -- match transparent navigation tabs
    BorderSizePixel = 0,
}, main)

local topbar = create("Frame", {
    Size = UDim2.new(1, 0, 0, 54),
    BackgroundColor3 = C.panel,
    BackgroundTransparency = 1, -- match transparent navigation tabs
    BorderSizePixel = 0,
}, content)
create("Frame", {
    AnchorPoint = Vector2.new(0.5, 1),
    Position = UDim2.new(0.5, 0, 1, 0),
    Size = UDim2.new(1, -24, 0, 1),
    BackgroundColor3 = C.line,
    BackgroundTransparency = 0.6,
    BorderSizePixel = 0,
}, topbar)

local titleIcon = makeIcon(topbar, TABS[1].Icon, 20, C.text, UDim2.new(0, 28, 0.5, 0), Vector2.new(0.5, 0.5))
onAccent(function()
    titleIcon.SetColor(accent, false)
end)
local pageTitle = create("TextLabel", {
    Position = UDim2.fromOffset(50, 7),
    Size = UDim2.new(1, -140, 0, 22),
    BackgroundTransparency = 1,
    Text = TABS[1].Name,
    TextColor3 = C.text,
    TextSize = 18,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
}, topbar)
local pageDesc = create("TextLabel", {
    Position = UDim2.fromOffset(50, 29),
    Size = UDim2.new(1, -140, 0, 16),
    BackgroundTransparency = 1,
    Text = TABS[1].Desc,
    TextColor3 = C.muted,
    TextSize = 11,
    Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
}, topbar)

local function makeTopButton(posX, hoverColor, drawFn)
    local b = create("TextButton", {
        Size = UDim2.fromOffset(30, 30),
        Position = UDim2.new(1, posX, 0, 12),
        BackgroundColor3 = C.panel2,
        BackgroundTransparency = 1, -- match transparent navigation tabs
        Text = "",
        AutoButtonColor = false,
    }, topbar)
    round(b, 8)
    drawFn(b)
    b.MouseEnter:Connect(function()
        tween(b, 0.1, {BackgroundColor3 = hoverColor})
    end)
    b.MouseLeave:Connect(function()
        tween(b, 0.1, {BackgroundColor3 = C.panel2})
    end)
    return b
end

local minimize = makeTopButton(-76, C.hover, function(b)
    bar(b, 11, 2, 15, 15, 0, C.text)
end)
local close = makeTopButton(-40, C.red, function(b)
    bar(b, 13, 2, 15, 15, 45, C.text)
    bar(b, 13, 2, 15, 15, -45, C.text)
end)

local pageHolder = create("Frame", {
    Position = UDim2.new(0, 0, 0, 55),
    Size = UDim2.new(1, 0, 1, -55),
    BackgroundTransparency = 1,
    ClipsDescendants = true,
}, content)

local navButtons = {}
local pages = {}
local scrollFrames = {}
local selectedTab = nil

local function setScrollLock(locked)
    for _, sf in ipairs(scrollFrames) do
        sf.ScrollingEnabled = not locked
    end
end

for index, tab in ipairs(TABS) do
    local b = create("TextButton", {
        Name = tab.Name .. "Nav",
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundColor3 = C.panel,
        -- Clean navigation: tabs stay transparent; only the active indicator changes.
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = index,
    }, navHolder)

    local indicator = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(3, 18),
        BackgroundColor3 = accent,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 4,
    }, b)
    round(indicator, 2)
    onAccent(function()
        indicator.BackgroundColor3 = accent
    end)

    local iconBadge = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 24, 0.5, 0),
        Size = UDim2.fromOffset(26, 26),
        BackgroundColor3 = C.panel2,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 2,
    }, b)

    local navIcon = makeIcon(iconBadge, tab.Icon, 18, C.muted,
        UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))

    local label = create("TextLabel", {
        Position = UDim2.fromOffset(44, 0),
        Size = UDim2.new(1, -50, 1, 0),
        BackgroundTransparency = 1,
        Text = tab.Name,
        TextColor3 = C.muted,
        TextSize = 13,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 2,
    }, b)

    -- Killer tab remains visible; Killer gameplay controls are removed.
    local data = {button = b, active = false}
    onAccent(function()
        if data.active then navIcon.SetColor(accent, false) end
    end)
    function data.setActive(active)
        data.active = active
        -- No per-tab cards or borders: blue-silver text and a slim active marker only.
        b.BackgroundTransparency = 1
        navIcon.SetColor(active and accent or C.muted, true)
        tween(label, 0.12, {TextColor3 = active and C.sub or C.muted})
        label.Font = active and Enum.Font.GothamBold or Enum.Font.GothamMedium
        indicator.Visible = active
        if active then
            indicator.Size = UDim2.fromOffset(3, 8)
            tween(indicator, 0.16, {Size = UDim2.fromOffset(3, 18)})
        end
    end

    b.MouseEnter:Connect(function()
        if data.active or not canHover() then return end
        -- Gentle electric-blue hover is applied to icon/text, not a boxed background.
        tween(label, 0.12, {TextColor3 = C.sub})
        navIcon.SetColor(C.sub, true)
    end)
    b.MouseLeave:Connect(function()
        if data.active then return end
        tween(label, 0.12, {TextColor3 = C.muted})
        navIcon.SetColor(C.muted, true)
    end)

    navButtons[tab.Name] = data

    local scroll = create("Frame", {
        Name = tab.Name .. "Page",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
    }, pageHolder)

    local function makeColumn(order)
        local sf = create("ScrollingFrame", {
            Name = "Column" .. order,
            Position = UDim2.new((order - 1) * 0.5, order == 1 and 12 or 5, 0, 0),
            Size = UDim2.new(0.5, -17, 1, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 2,
            ScrollBarImageColor3 = C.muted,
            ScrollBarImageTransparency = 0.25,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y,
        }, scroll)
        table.insert(scrollFrames, sf)
        create("UIPadding", {
            PaddingTop = UDim.new(0, 12),
            PaddingBottom = UDim.new(0, 40),
            PaddingLeft = UDim.new(0, 1),
            PaddingRight = UDim.new(0, 5),
        }, sf)
        create("UIListLayout", {
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, sf)
        return sf
    end
    pages[tab.Name] = {scroll = scroll, columns = {makeColumn(1), makeColumn(2)}}
end

local tabInfo = {}
for _, tab in ipairs(TABS) do
    tabInfo[tab.Name] = tab
end

local function setPage(name)
    if selectedTab == name then return end
    selectedTab = name
    local info = tabInfo[name]
    pageTitle.Text = name
    pageDesc.Text = info and info.Desc or ""
    if info then
        titleIcon.Set(info.Icon)
        titleIcon.SetColor(accent, false)
    end

    for navName, data in pairs(navButtons) do
        data.setActive(navName == name)
        if navName ~= name then
            -- Navigation remains visually open; no boxed inactive tab fill.
            data.button.BackgroundTransparency = 1
        end
    end

    for pageName, p in pairs(pages) do
        p.scroll.Visible = pageName == name
    end
end

for name, data in pairs(navButtons) do
    data.button.Activated:Connect(function()
        setPage(name)
    end)
end
setPage(TABS[1].Name)

local controls = {}
local compactMode = false
local compactTargets = {}

-- TianHub purple-glass GroupBox skin. Visual-only: feature controls and callbacks remain untouched.
local function registerCardShine(card, stroke)
    if not card or not stroke then return end
    stroke.Color = C.line
    stroke.Thickness = 1.7
    stroke.Transparency = 0.14
end

local function makeCard(pageName, title, columnIndex)
    local cleanName = string.gsub(title, "%W", "")
    local card = create("Frame", {
        Name = cleanName .. "Card",
        Size = UDim2.new(1, -4, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = C.panel,
        BackgroundTransparency = 0.40,
        BorderSizePixel = 0,
    }, pages[pageName].columns[columnIndex or 1])
    round(card, 15)

    local cardStroke = outline(card, 2.2, 0.06)
    registerCardShine(card, cardStroke)
    cardStroke.Thickness = 2.2
    cardStroke.Transparency = 0.04

    -- Two-layer perimeter treatment: a broad soft halo plus a sharp moving
    -- highlight. Both stay on the GroupBox outline; the card surface stays clear.
    local cardGlowStroke = Instance.new("UIStroke")
    cardGlowStroke.Name = "TianHubGroupBoxOuterGlow"
    cardGlowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    -- Narrower outer shimmer footprint while keeping the glow bright and substantial.
    cardGlowStroke.Thickness = 3.2
    cardGlowStroke.Transparency = 0.56
    cardGlowStroke.Color = accent
    cardGlowStroke.Parent = card

    local glowGradient = Instance.new("UIGradient")
    glowGradient.Name = "TianHubGroupBoxOuterGlowGradient"
    glowGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, C.line),
        ColorSequenceKeypoint.new(0.22, accent),
        ColorSequenceKeypoint.new(0.38, C.text),
        ColorSequenceKeypoint.new(0.52, accent),
        ColorSequenceKeypoint.new(0.78, C.line),
        ColorSequenceKeypoint.new(1.00, C.line),
    })
    glowGradient.Parent = cardGlowStroke

    local cardEdgeGradient = Instance.new("UIGradient")
    cardEdgeGradient.Name = "TianHubGroupBoxEdgeGradient"
    cardEdgeGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, C.line),
        ColorSequenceKeypoint.new(0.18, accent),
        ColorSequenceKeypoint.new(0.31, C.text),
        ColorSequenceKeypoint.new(0.43, accent),
        ColorSequenceKeypoint.new(0.68, C.line),
        ColorSequenceKeypoint.new(1.00, C.line),
    })
    cardEdgeGradient.Rotation = 0
    cardEdgeGradient.Parent = cardStroke

    TweenService:Create(
        cardEdgeGradient,
        TweenInfo.new(2.7, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
        { Rotation = 360 }
    ):Play()
    TweenService:Create(
        glowGradient,
        TweenInfo.new(3.8, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
        { Rotation = -360 }
    ):Play()
    TweenService:Create(
        cardGlowStroke,
        TweenInfo.new(1.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        { Transparency = 0.34, Thickness = 4.0 }
    ):Play()

    local header = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 48),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
    }, card)
    local titleLabel = create("TextLabel", {
        Position = UDim2.fromOffset(14, 0),
        Size = UDim2.new(1, -48, 1, 0),
        BackgroundTransparency = 1,
        Text = title,
        TextColor3 = C.text,
        TextSize = 15,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, header)
    local chevron = makeChevron(header, C.muted, UDim2.new(1, -22, 0.5, 0))

    header.MouseEnter:Connect(function()
        chevron.SetColor(accent)
        tween(cardStroke, 0.14, {Color = accent, Transparency = 0.04, Thickness = 1.9})
    end)
    header.MouseLeave:Connect(function()
        chevron.SetColor(C.muted)
        tween(cardStroke, 0.16, {Color = C.line, Transparency = 0.14, Thickness = 1.7})
    end)

    local line = create("Frame", {
        Position = UDim2.new(0, 14, 0, 48),
        Size = UDim2.new(1, -28, 0, 1),
        BackgroundColor3 = C.line,
        BackgroundTransparency = 0.58,
        BorderSizePixel = 0,
    }, card)

    local clip = create("Frame", {
        Position = UDim2.fromOffset(0, 49),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        ClipsDescendants = true,
    }, card)
    local body = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
    }, clip)
    local bodyLayout = create("UIListLayout", {
        Padding = UDim.new(0, 7),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, body)
    local bodyPad = create("UIPadding", {
        PaddingTop = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 12),
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 12),
    }, body)

    local opened = true
    local token = 0
    header.Activated:Connect(function()
        opened = not opened
        token += 1
        local myToken = token
        local s = math.max(scale.Scale, 0.05)
        local hh = compactMode and 40 or 48
        local cardH = card.AbsoluteSize.Y / s
        local currentH = clip.AbsoluteSize.Y / s
        local fullH = body.AbsoluteSize.Y / s

        card.AutomaticSize = Enum.AutomaticSize.None
        clip.AutomaticSize = Enum.AutomaticSize.None
        card.Size = UDim2.new(1, -4, 0, cardH)
        clip.Size = UDim2.new(1, 0, 0, currentH)
        local clipTarget = opened and fullH or 0
        local cardTarget = opened and (hh + 1 + fullH) or hh
        tween(chevron.Holder, 0.15, {Rotation = opened and 0 or -90})
        tween(line, 0.15, {BackgroundTransparency = opened and 0.58 or 1})
        tween(cardStroke, 0.15, {Transparency = opened and 0.14 or 0.22})
        tween(clip, 0.18, {Size = UDim2.new(1, 0, 0, clipTarget)})
        local t = tween(card, 0.18, {Size = UDim2.new(1, -4, 0, cardTarget)})
        t.Completed:Connect(function()
            if opened and myToken == token then
                clip.AutomaticSize = Enum.AutomaticSize.Y
                clip.Size = UDim2.new(1, 0, 0, 0)
                card.AutomaticSize = Enum.AutomaticSize.Y
                card.Size = UDim2.new(1, -4, 0, 0)
            end
        end)
    end)

    table.insert(compactTargets, {applyCompact = function(c)
        local hh = c and 40 or 48
        header.Size = UDim2.new(1, 0, 0, hh)
        titleLabel.TextSize = c and 13 or 15
        line.Position = UDim2.new(0, 14, 0, hh)
        clip.Position = UDim2.fromOffset(0, hh + 1)
        if not opened then card.Size = UDim2.new(1, -4, 0, hh) end
        bodyLayout.Padding = UDim.new(0, c and 5 or 7)
        bodyPad.PaddingTop = UDim.new(0, c and 7 or 10)
        bodyPad.PaddingBottom = UDim.new(0, c and 8 or 12)
    end})

    return body
end

local function makeToggle(parent, labelText, defaultValue, onChanged)
    local row = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = C.hover,
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
    }, parent)
    row.BackgroundTransparency = 1
    round(row, 6)

    local label = create("TextLabel", {
        Position = UDim2.fromOffset(8, 0),
        Size = UDim2.new(1, -42, 1, 0),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = C.text,
        TextSize = 13,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, row)

    table.insert(compactTargets, {applyCompact = function(c)
        row.Size = UDim2.new(1, 0, 0, c and 25 or 32)
        label.TextSize = c and 11 or 12
    end})

    local state = defaultValue == true
    local box = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(16, 16),
        BackgroundColor3 = state and accent or C.bg,
        BorderSizePixel = 0,
    }, row)
    round(box, 4)
    local stroke = outline(box, 1.2, state and 0.15 or 0.55, state and accent or C.muted)

    local checkIcon = makeIcon(box, "check", 12, C.bg,
        UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), true)
    checkIcon.Holder.Visible = state

    onAccent(function()
        checkIcon.SetColor(C.bg, false)
        if state then
            stroke.Color = accent
            box.BackgroundColor3 = accent
            label.TextColor3 = accentText()
        end
    end)

    row.MouseEnter:Connect(function()
        tween(row, 0.1, {BackgroundTransparency = 0.72})
        tween(stroke, 0.1, {Transparency = 0.12})
    end)
    row.MouseLeave:Connect(function()
        tween(row, 0.1, {BackgroundTransparency = 1})
        tween(stroke, 0.1, {Transparency = state and 0.15 or 0.55})
    end)

    local function setState(value, silent)
        state = value == true
        checkIcon.Holder.Visible = state
        tween(box, 0.12, {BackgroundColor3 = state and accent or C.bg})
        tween(stroke, 0.12, {
            Transparency = state and 0.15 or 0.55,
            Color = state and accent or C.muted,
        })
        label.TextColor3 = state and accentText() or C.sub
        if onChanged and not silent then
            task.defer(pcall, onChanged, state)
        end
    end
    label.TextColor3 = state and accentText() or C.sub
    row.Activated:Connect(function()
        setState(not state)
    end)
    return {
        Row = row,
        Get = function() return state end,
        Set = function(v, fire) setState(v, not fire) end,
        Reset = function() setState(defaultValue == true, false) end,
    }
end

local function makeSlider(parent, labelText, minValue, maxValue, defaultValue, onChanged, suffix, precision)
    suffix = suffix or ""
    local valueScale = 10 ^ (precision or 0)
    local holder = create("Frame", {
        Size = UDim2.new(1, 0, 0, 46),
        BackgroundTransparency = 1,
    }, parent)
    local nameLabel = create("TextLabel", {
        Position = UDim2.fromOffset(8, 2),
        Size = UDim2.new(1, -78, 0, 18),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = C.text,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, holder)
    local valueLabel = create("TextLabel", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 2),
        Size = UDim2.fromOffset(64, 18),
        BackgroundTransparency = 1,
        Text = tostring(defaultValue) .. suffix,
        TextColor3 = accentText(),
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, holder)

    local hit = create("TextButton", {
        Position = UDim2.fromOffset(6, 22),
        Size = UDim2.new(1, -12, 0, 22),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
    }, holder)
    table.insert(compactTargets, {applyCompact = function(c)
        holder.Size = UDim2.new(1, 0, 0, c and 38 or 46)
        nameLabel.Size = UDim2.new(1, -62, 0, c and 16 or 18)
        valueLabel.Size = UDim2.fromOffset(46, c and 16 or 18)
        hit.Position = UDim2.fromOffset(6, c and 17 or 22)
    end})

    local trackBar = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 8, 0.5, 0),
        Size = UDim2.new(1, -16, 0, 4),
        BackgroundColor3 = C.off,
        BorderSizePixel = 0,
    }, hit)
    round(trackBar, 2)
    local isDragging = false
    local pct = math.clamp((defaultValue - minValue) / (maxValue - minValue), 0, 1)
    local fill = create("Frame", {
        Size = UDim2.new(pct, 0, 1, 0),
        BackgroundColor3 = accent,
        BorderSizePixel = 0,
    }, trackBar)
    round(fill, 2)
    local knob = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(12, 12),
        Position = UDim2.new(pct, 0, 0.5, 0),
        BackgroundColor3 = C.text,
        BorderSizePixel = 0,
        ZIndex = 2,
    }, trackBar)
    round(knob, 7)
    local knobStroke = outline(knob, 2, 0, accent)
    onAccent(function()
        fill.BackgroundColor3 = accent
        knobStroke.Color = accent
        if not isDragging then valueLabel.TextColor3 = accentText() end
    end)

    local value = defaultValue

    local function apply(v, fire)
        v = math.clamp(math.floor(v * valueScale + 0.5) / valueScale, minValue, maxValue)
        if fire and v == value then return end
        local ratio = (v - minValue) / (maxValue - minValue)
        value = v

        fill.Size = UDim2.new(ratio, 0, 1, 0)
        knob.Position = UDim2.new(ratio, 0, 0.5, 0)
        valueLabel.Text = tostring(v) .. suffix
        if onChanged and fire then
            task.defer(pcall, onChanged, v)
        end
    end
    local function setFromX(x)
        local width = math.max(trackBar.AbsoluteSize.X, 1)
        local ratio = math.clamp((x - trackBar.AbsolutePosition.X) / width, 0, 1)
        apply(minValue + (maxValue - minValue) * ratio, true)
    end

    local function setGrab(on)
        tween(knob, 0.08, {Size = on and UDim2.fromOffset(15, 15) or UDim2.fromOffset(12, 12)})
        tween(valueLabel, 0.08, {TextColor3 = on and C.text or accentText()})
    end

    hit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDragging = true
            setScrollLock(true)
            setGrab(true)
            setFromX(input.Position.X)
        end
    end)
    keep(UserInputService.InputChanged:Connect(function(input)
        if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            setFromX(input.Position.X)
        end
    end))
    keep(UserInputService.InputEnded:Connect(function(input)
        if isDragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            isDragging = false
            setScrollLock(false)
            setGrab(false)
        end
    end))

    return {
        Holder = holder,
        Get = function() return value end,
        Set = function(v, fire) apply(v, fire == true) end,
        Reset = function() apply(defaultValue, true) end,
    }
end

local function makeDropdown(parent, labelText, options, defaultValue, onChanged, optionImageResolver)
    local ITEM_H = type(optionImageResolver) == "function" and 48 or 34
    local BOX_H = 34
    local listH = math.min(#options * ITEM_H + 6, 250)

    local holder = create("Frame", {
        Size = UDim2.new(1, 0, 0, BOX_H + 6),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
    }, parent)

    local button = create("TextButton", {
        Position = UDim2.fromOffset(4, 3),
        Size = UDim2.new(1, -8, 0, BOX_H),
        BackgroundColor3 = C.bg,
        Text = "",
        AutoButtonColor = false,
    }, holder)
    round(button, 7)
    local btnStroke = outline(button, 1, 0.6)

    create("TextLabel", {
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(0.45, -10, 1, 0),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = C.sub,
        TextSize = 12,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, button)

    local selected = table.find(options, defaultValue) and defaultValue or options[1]
    local selectedAvatarImage
    if type(optionImageResolver) == "function" then
        selectedAvatarImage = create("ImageLabel", {
            Position = UDim2.new(0.45, 0, 0.5, -21),
            Size = UDim2.fromOffset(42, 42),
            BackgroundColor3 = C.hover,
            BackgroundTransparency = 0,
            Image = "",
            ScaleType = Enum.ScaleType.Crop,
        }, button)
        round(selectedAvatarImage, 6)
    end
    local valueText = create("TextLabel", {
        Position = UDim2.new(0.45, selectedAvatarImage and 38 or 0, 0, 0),
        Size = UDim2.new(0.55, selectedAvatarImage and -68 or -30, 1, 0),
        BackgroundTransparency = 1,
        Text = selected,
        TextColor3 = accentText(),
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, button)
    onAccent(function()
        valueText.TextColor3 = accentText()
    end)
    local chevron = makeChevron(button, C.muted, UDim2.new(1, -16, 0.5, 0))

    local list = create("ScrollingFrame", {
        Position = UDim2.fromOffset(4, BOX_H + 8),
        Size = UDim2.new(1, -8, 0, listH),
        BackgroundColor3 = C.bg,
        BorderSizePixel = 0,
        Visible = false,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = C.muted,
        ClipsDescendants = true,
    }, holder)
    round(list, 7)
    outline(list, 1, 0.6)
    create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder}, list)
    create("UIPadding", {
        PaddingTop = UDim.new(0, 3),
        PaddingBottom = UDim.new(0, 3),
        PaddingLeft = UDim.new(0, 3),
        PaddingRight = UDim.new(0, 3),
    }, list)

    local open = false
    local optionButtons = {}
    local optionImageCache = {}
    local optionImageLabels = {}
    local optionImageLoading = {}
    local optionImageQueue = {}
    local optionImageWorkerCount = 0
    local MAX_OPTION_IMAGE_WORKERS = 3
    local currentBoxH = BOX_H

    local function refreshSize()
        local closedH = currentBoxH + 6
        holder.Size = UDim2.new(1, 0, 0, open and (closedH + listH + 4) or closedH)
        button.Size = UDim2.new(1, -8, 0, currentBoxH)
        list.Position = UDim2.fromOffset(4, closedH + 2)
        list.Visible = open
    end

    local function loadOptionImage(opt)
        if type(optionImageResolver) ~= "function" then return end
        if optionImageCache[opt] ~= nil or optionImageLoading[opt] then return end
        if not optionImageLabels[opt] then return end
        optionImageLoading[opt] = true
        table.insert(optionImageQueue, opt)
        if optionImageWorkerCount >= MAX_OPTION_IMAGE_WORKERS then return end
        optionImageWorkerCount = optionImageWorkerCount + 1
        task.spawn(function()
            while #optionImageQueue > 0 do
                local current = table.remove(optionImageQueue, 1)
                if current then
                    local ok, userId = pcall(optionImageResolver, current)
                    if ok and tonumber(userId) then
                        local imageUrl = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=100&h=100"
                        optionImageCache[current] = imageUrl
                        local imageLabel = optionImageLabels[current]
                        if imageLabel and imageLabel.Parent then imageLabel.Image = imageUrl end
                        if current == selected and selectedAvatarImage then selectedAvatarImage.Image = imageUrl end
                    else
                        optionImageCache[current] = false
                    end
                    optionImageLoading[current] = nil
                end
                task.wait(0.02)
            end
            optionImageWorkerCount = math.max(0, optionImageWorkerCount - 1)
        end)
    end

    local function loadVisibleOptionImages()
        if not open or type(optionImageResolver) ~= "function" then return end
        local top = list.AbsolutePosition.Y
        local bottom = top + list.AbsoluteSize.Y
        for opt, imageLabel in pairs(optionImageLabels) do
            local row = optionButtons[opt] and optionButtons[opt].row
            if row and row.AbsolutePosition.Y + row.AbsoluteSize.Y >= top
                and row.AbsolutePosition.Y <= bottom then
                loadOptionImage(opt)
            end
        end
    end

    local function setOpen(v)
        open = v
        refreshSize()
        if open then task.defer(loadVisibleOptionImages) end
        tween(chevron.Holder, 0.15, {Rotation = open and 180 or 0})
        tween(btnStroke, 0.12, {Transparency = open and 0.2 or 0.6})
    end

    local function refreshChecks()
        for value, o in pairs(optionButtons) do
            local isSel = value == selected
            o.row.BackgroundTransparency = isSel and 0.85 or 1
            o.dot.Visible = isSel
            o.label.TextColor3 = isSel and C.text or C.sub
        end
    end

    local function select(v, silent)
        if not table.find(options, v) then return end
        selected = v
        valueText.Text = v
        if selectedAvatarImage then
            selectedAvatarImage.Image = (type(optionImageCache[v]) == "string" and optionImageCache[v]) or ""
            if optionImageCache[v] == nil then loadOptionImage(v) end
        end
        refreshChecks()
        if onChanged and not silent then
            task.defer(pcall, onChanged, v)
        end
    end

    for i, opt in ipairs(options) do
        local ob = create("TextButton", {
            Size = UDim2.new(1, 0, 0, ITEM_H),
            BackgroundColor3 = C.hover,
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            LayoutOrder = i,
        }, list)
        ob.BackgroundTransparency = 1
        round(ob, 5)
        local dot = create("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 2, 0.5, 0),
            Size = UDim2.fromOffset(4, 4),
            BackgroundColor3 = accent,
            BorderSizePixel = 0,
            Visible = false,
        }, ob)
        round(dot, 3)
        onAccent(function()
            dot.BackgroundColor3 = accent
        end)
        local optionAvatarImage
        if type(optionImageResolver) == "function" then
            optionAvatarImage = create("ImageLabel", {
                Position = UDim2.new(0, 8, 0.5, -19),
                Size = UDim2.fromOffset(38, 38),
                BackgroundColor3 = C.hover,
                BackgroundTransparency = 0,
                Image = "",
                ScaleType = Enum.ScaleType.Crop,
            }, ob)
            round(optionAvatarImage, 5)
            optionImageLabels[opt] = optionAvatarImage
        end
        local l = create("TextLabel", {
            Position = UDim2.fromOffset(optionAvatarImage and 54 or 22, 0),
            Size = UDim2.new(1, optionAvatarImage and -60 or -28, 1, 0),
            BackgroundTransparency = 1,
            Text = opt,
            TextColor3 = C.sub,
            TextSize = 12,
            Font = Enum.Font.Gotham,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, ob)
        ob.MouseEnter:Connect(function()
            if not canHover() then return end
            tween(ob, 0.1, {BackgroundTransparency = (selected == opt) and 0.75 or 0.6})
        end)
        ob.MouseLeave:Connect(function()
            tween(ob, 0.1, {BackgroundTransparency = (selected == opt) and 0.85 or 1})
        end)
        ob.Activated:Connect(function()
            select(opt)
            setOpen(false)
        end)
        optionButtons[opt] = {label = l, dot = dot, row = ob}
    end
    refreshChecks()
    if type(optionImageResolver) == "function" then
        list:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
            task.defer(loadVisibleOptionImages)
        end)
        -- Warm the selected preview and first screen of preset thumbnails while the menu is idle.
        task.defer(function()
            loadOptionImage(selected)
            for i, opt in ipairs(options) do
                if i > 7 then break end
                loadOptionImage(opt)
            end
        end)
    end

    button.Activated:Connect(function()
        setOpen(not open)
    end)

    table.insert(compactTargets, {
        applyCompact = function(isCompact)
            currentBoxH = isCompact and 28 or BOX_H
            refreshSize()
        end,
    })

    return {
        Holder = holder,
        Get = function() return selected end,
        Set = function(v, fire) select(v, not fire) end,
        Reset = function() select(defaultValue, false) end,
    }
end

local function makeButton(parent, text, onClick)
    local b = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = C.bg,
        Text = text,
        TextColor3 = C.text,
        TextSize = 13,
        Font = Enum.Font.GothamMedium,
        AutoButtonColor = false,
    }, parent)
    round(b, 8)
    local st = outline(b, 1, 0.4)
    b.MouseEnter:Connect(function()
        tween(b, 0.1, {BackgroundColor3 = C.panel2})
        tween(st, 0.1, {Transparency = 0.05})
    end)
    b.MouseLeave:Connect(function()
        tween(b, 0.1, {BackgroundColor3 = C.bg})
        tween(st, 0.1, {Transparency = 0.4})
    end)
    b.MouseButton1Down:Connect(function()
        tween(b, 0.06, {BackgroundColor3 = C.hover})
    end)
    b.Activated:Connect(function()
        tween(b, 0.1, {BackgroundColor3 = C.panel2})
        if onClick then onClick() end
    end)
    return b
end

local function makeNote(parent, text, height)
    return create("TextLabel", {
        Size = UDim2.new(1, 0, 0, height or 40),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = C.muted,
        TextSize = 12,
        Font = Enum.Font.Gotham,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    }, parent)
end

local function makeInfoRow(parent, key, val)
    local row = create("Frame", {
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundTransparency = 1,
    }, parent)
    create("TextLabel", {
        Position = UDim2.fromOffset(8, 0),
        Size = UDim2.new(0.5, -8, 1, 0),
        BackgroundTransparency = 1,
        Text = key,
        TextColor3 = C.sub,
        TextSize = 12,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    local valueLabel = create("TextLabel", {
        Position = UDim2.fromScale(0.5, 0),
        Size = UDim2.new(0.5, -8, 1, 0),
        BackgroundTransparency = 1,
        Text = tostring(val),
        TextColor3 = C.text,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, row)
    return {
        Row = row,
        SetValue = function(v) valueLabel.Text = tostring(v) end,
    }
end

local ACCENTS = {
    {"TianHub Blue",   Color3.fromRGB(70, 174, 255)},
    {"TianHub Pink",   Color3.fromRGB(255, 65, 190)},
    {"TianHub Purple", Color3.fromRGB(170, 91, 255)},
    {"Ice Blue",       Color3.fromRGB(105, 220, 255)},
    {"Lavender",       Color3.fromRGB(220, 160, 255)},
}

local function makeAccentPicker(parent, labelText)
    local holder = create("Frame", {
        Size = UDim2.new(1, 0, 0, 58),
        BackgroundTransparency = 1,
    }, parent)
    create("TextLabel", {
        Position = UDim2.fromOffset(8, 3),
        Size = UDim2.new(1, -16, 0, 20),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = C.text,
        TextSize = 13,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, holder)
    local row = create("Frame", {
        Position = UDim2.fromOffset(10, 28),
        Size = UDim2.new(1, -20, 0, 26),
        BackgroundTransparency = 1,
    }, holder)
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 9),
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Center,
    }, row)

    local selected = ACCENTS[1][1]
    local swatches = {}

    local function refresh()
        for name, s in pairs(swatches) do
            s.Transparency = (name == selected) and 0 or 1
        end
    end
    local function select(name)
        for _, a in ipairs(ACCENTS) do
            if a[1] == name then
                selected = name
                refresh()
                setAccent(a[2])
                return
            end
        end
    end

    for i, a in ipairs(ACCENTS) do
        local sw = create("TextButton", {
            Size = UDim2.fromOffset(20, 20),
            BackgroundColor3 = a[2],
            Text = "",
            AutoButtonColor = false,
            LayoutOrder = i,
        }, row)
        round(sw, 10)
        swatches[a[1]] = outline(sw, 2, 1, C.text)
        sw.Activated:Connect(function()
            select(a[1])
        end)
    end
    refresh()

    return {
        Holder = holder,
        Get = function() return selected end,
        Set = function(v) select(v) end,
        Reset = function() select(ACCENTS[1][1]) end,
    }
end

local currentToast = nil
local function toast(text)
    local n = controls["Notifications"]
    if n and not n.Get() then return end
    if currentToast and currentToast.Parent then currentToast:Destroy() end
    local t = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, -60),
        Size = UDim2.fromOffset(300, 42),
        BackgroundColor3 = C.panel2,
        BorderSizePixel = 0,
        ZIndex = 400,
    }, UI.gui)
    round(t, 12)
    outline(t, 1, 0.2)
    create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 12, 0.5, 0),
        Size = UDim2.fromOffset(8, 8),
        BackgroundColor3 = C.text,
        BorderSizePixel = 0,
        ZIndex = 401,
    }, t)
    local dot = t:FindFirstChildOfClass("Frame")
    if dot then round(dot, 8) end
    create("TextLabel", {
        Position = UDim2.fromOffset(30, 0),
        Size = UDim2.new(1, -40, 1, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = C.text,
        TextSize = 14,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 401,
    }, t)
    currentToast = t
    tween(t, 0.22, {Position = UDim2.new(0.5, 0, 0, 14)})
    task.delay(2.2, function()
        if t.Parent then
            local tw = tween(t, 0.2, {Position = UDim2.new(0.5, 0, 0, -60)})
            tw.Completed:Once(function()
                if t.Parent then t:Destroy() end
            end)
        end
    end)
end

local hideToken = 0

local function openUI()
    isOpen = true
    hideToken += 1
    shell.Visible = true
    tween(openStroke, 0.12, {Transparency = 0})
    popValue.Value = 0.95
    main.GroupTransparency = 1
    tween(popValue, 0.15, {Value = 1})
    tween(main, 0.15, {GroupTransparency = baseTransparency})
end

local function hideUI(callback)
    isOpen = false
    hideToken += 1
    local myToken = hideToken
    tween(openStroke, 0.12, {Transparency = 0.45})
    tween(popValue, 0.12, {Value = 0.95})
    local t = tween(main, 0.12, {GroupTransparency = 1})
    t.Completed:Once(function()
        if not isOpen and myToken == hideToken then
            shell.Visible = false
            if callback then callback() end
        end
    end)
end

do
    local a = makeCard("Settings", "General", 1)
    controls["Show Status"] = makeToggle(a, "Show Status", false, function(v)
        statusPill.Visible = v
    end)
    controls["UI Animations"] = makeToggle(a, "UI Animations", true, function(v)
        animationsEnabled = v
    end)
    controls["Interface Scale"] = makeSlider(a, "Interface Scale", 50, 120, 95, function(v)
        userScale = v / 100
        updateScale()
    end, "%")
    controls["UI Opacity"] = makeSlider(a, "UI Opacity", 70, 200, 96, function(v)
        baseTransparency = 1 - v / 100
        if isOpen then main.GroupTransparency = baseTransparency end
    end, "%")
    -- Background visibility is controlled from the Custom Background card.
    -- Background Visibility starts at maximum by default.
    local backgroundOpacity = 500
    setTianHubBackgroundVisibility(backgroundOpacity)

    local customBgCard = makeCard("Settings", "Custom Background", 2)
    makeNote(customBgCard, "Pilih preview, atur visibility, lalu tekan Apply untuk menerapkan background dan palet warna.", 34)
    controls["Background Visibility"] = makeSlider(customBgCard, "Background Visibility", 0, 500, 500, function(v)
        backgroundOpacity = math.clamp(v, 0, 500)
        setTianHubBackgroundVisibility(backgroundOpacity)
    end, "/500")

    local BACKGROUND_GALLERY = {
        {name = "TianHub Default", image = BG_ASSET, theme = "default"},
        {name = "Purple Pink", image = "rbxassetid://74361815952925", theme = "purple"},
        {name = "Blue Cyan", image = "rbxassetid://136936930738901", theme = "blue"},
        {name = "Neon Purple", image = "rbxassetid://75851313601135", theme = "neon"},
        {name = "Ice Silver", image = "rbxassetid://92271472916517", theme = "ice"},
        {name = "Lavender Silver", image = "rbxassetid://73241819072406", theme = "lavender"},
        {name = "Blonde Anime", image = "rbxassetid://91260719471257", theme = "purple"},
        {name = "White Hair Red Eyes", image = "rbxassetid://115832840612998", theme = "neon"},
        {name = "Monochrome Anime", image = "rbxassetid://115087767402767", theme = "ice"},
        {name = "White Hair Blue Eyes", image = "rbxassetid://84592355312258", theme = "lavender"},
        {name = "Black White Portrait", image = "rbxassetid://134408377408354", theme = "ice"},
    }

    -- Resolve Decal asset IDs to their underlying image texture IDs.
    -- ImageLabel.Image needs the image content ID when the supplied ID is a Decal.
    local function resolveBackgroundImage(assetId)
        if type(assetId) ~= "string" or assetId == "" then return nil end
        local ok, objects = pcall(function()
            return game:GetObjects(assetId)
        end)
        if not ok or type(objects) ~= "table" or not objects[1] then return nil end

        local root = objects[1]
        local texture
        pcall(function()
            if root:IsA("Decal") or root:IsA("Texture") then
                texture = root.Texture
            else
                local decal = root:FindFirstChildWhichIsA("Decal", true)
                    or root:FindFirstChildWhichIsA("Texture", true)
                if decal then texture = decal.Texture end
            end
        end)
        pcall(function() root:Destroy() end)
        if type(texture) == "string" and texture ~= "" then
            return texture
        end
        return nil
    end

    -- Resolve each gallery entry independently; keep the original ID as a
    -- fallback if Roblox already supplied an Image ID or GetObjects is unavailable.
    for index, item in ipairs(BACKGROUND_GALLERY) do
        if index >= 7 then
            task.spawn(function()
                local resolved = resolveBackgroundImage(item.image)
                if not resolved then return end
                item.image = resolved
                local preview = galleryButtons[index]
                if preview and preview.Parent then
                    preview.Image = resolved
                end
                if appliedBackgroundIndex == index then
                    applyTianHubBackgroundImage(resolved)
                    if openImage and openImage.Parent then openImage.Image = resolved end
                end
            end)
        end
    end

    local originalTheme = {
        bg = C.bg, sidebar = C.sidebar, panel = C.panel, panel2 = C.panel2,
        hover = C.hover, line = C.line, text = C.text, muted = C.muted,
        sub = C.sub, off = C.off, red = C.red, accent = DEFAULT_ACCENT,
    }
    local themePalettes = {
        default = originalTheme,
        purple = {
            bg = Color3.fromRGB(15, 7, 24), sidebar = Color3.fromRGB(18, 8, 30),
            panel = Color3.fromRGB(29, 12, 43), panel2 = Color3.fromRGB(48, 17, 64),
            hover = Color3.fromRGB(67, 20, 83), line = Color3.fromRGB(116, 48, 139),
            text = Color3.fromRGB(255, 241, 255), muted = Color3.fromRGB(190, 157, 198),
            sub = Color3.fromRGB(226, 190, 235), off = Color3.fromRGB(55, 28, 65),
            red = Color3.fromRGB(255, 91, 180), accent = Color3.fromRGB(239, 76, 205),
        },
        blue = {
            bg = Color3.fromRGB(4, 10, 20), sidebar = Color3.fromRGB(5, 14, 29),
            panel = Color3.fromRGB(7, 20, 39), panel2 = Color3.fromRGB(10, 34, 60),
            hover = Color3.fromRGB(12, 49, 78), line = Color3.fromRGB(22, 103, 145),
            text = Color3.fromRGB(235, 250, 255), muted = Color3.fromRGB(139, 177, 197),
            sub = Color3.fromRGB(190, 226, 241), off = Color3.fromRGB(17, 39, 55),
            red = Color3.fromRGB(255, 91, 112), accent = Color3.fromRGB(30, 211, 255),
        },
        neon = {
            bg = Color3.fromRGB(8, 5, 18), sidebar = Color3.fromRGB(11, 5, 24),
            panel = Color3.fromRGB(22, 9, 39), panel2 = Color3.fromRGB(37, 12, 61),
            hover = Color3.fromRGB(57, 15, 83), line = Color3.fromRGB(106, 43, 157),
            text = Color3.fromRGB(250, 244, 255), muted = Color3.fromRGB(174, 151, 198),
            sub = Color3.fromRGB(218, 193, 240), off = Color3.fromRGB(42, 24, 60),
            red = Color3.fromRGB(242, 63, 201), accent = Color3.fromRGB(177, 70, 255),
        },
        ice = {
            bg = Color3.fromRGB(19, 25, 34), sidebar = Color3.fromRGB(24, 31, 42),
            panel = Color3.fromRGB(40, 49, 61), panel2 = Color3.fromRGB(57, 69, 82),
            hover = Color3.fromRGB(75, 91, 106), line = Color3.fromRGB(132, 164, 184),
            text = Color3.fromRGB(248, 252, 255), muted = Color3.fromRGB(190, 207, 218),
            sub = Color3.fromRGB(220, 234, 242), off = Color3.fromRGB(74, 88, 100),
            red = Color3.fromRGB(218, 67, 78), accent = Color3.fromRGB(111, 210, 239),
        },
        lavender = {
            bg = Color3.fromRGB(25, 22, 34), sidebar = Color3.fromRGB(31, 27, 42),
            panel = Color3.fromRGB(47, 42, 59), panel2 = Color3.fromRGB(64, 57, 77),
            hover = Color3.fromRGB(82, 73, 98), line = Color3.fromRGB(150, 132, 171),
            text = Color3.fromRGB(255, 250, 255), muted = Color3.fromRGB(205, 194, 216),
            sub = Color3.fromRGB(233, 223, 242), off = Color3.fromRGB(84, 74, 96),
            red = Color3.fromRGB(133, 48, 74), accent = Color3.fromRGB(190, 157, 232),
        },
    }

    local selectedBackgroundIndex = 1
    local appliedBackgroundIndex = 1
    local galleryButtons = {}
    local themeDescendantConnection

    local function colorNear(a, b)
        return typeof(a) == "Color3" and typeof(b) == "Color3"
            and math.abs(a.R - b.R) < 0.002
            and math.abs(a.G - b.G) < 0.002
            and math.abs(a.B - b.B) < 0.002
    end

    local function applyDynamicTheme(themeName)
        local palette = themePalettes[themeName] or originalTheme
        local previous = {
            bg = C.bg, sidebar = C.sidebar, panel = C.panel, panel2 = C.panel2,
            hover = C.hover, line = C.line, text = C.text, muted = C.muted,
            sub = C.sub, off = C.off, red = C.red, accent = accent,
        }
        local keys = {"bg", "sidebar", "panel", "panel2", "hover", "line", "text", "muted", "sub", "off", "red"}
        local guiRoot = gui
        local function remapColor(value)
            for _, key in ipairs(keys) do
                if colorNear(value, previous[key]) then return palette[key] end
            end
            if colorNear(value, previous.accent) then return palette.accent end
            return value
        end
        for _, key in ipairs(keys) do C[key] = palette[key] end
        setAccent(palette.accent)
        -- Keep the main banner shimmer synchronized with the selected gallery theme.
        if shimmerGradient and shimmerGradient.Parent then
            shimmerGradient.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0.00, C.line),
                ColorSequenceKeypoint.new(0.50, accent),
                ColorSequenceKeypoint.new(1.00, C.text),
            })
        end

        local function recolorObject(obj)
            if obj:IsA("GuiObject") then
                for _, property in ipairs({"BackgroundColor3", "BorderColor3"}) do
                    pcall(function()
                        local oldValue = obj[property]
                        local newValue = remapColor(oldValue)
                        if newValue ~= oldValue then obj[property] = newValue end
                    end)
                end
                if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                    pcall(function() obj.TextColor3 = remapColor(obj.TextColor3) end)
                end
                if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
                    pcall(function() obj.ImageColor3 = remapColor(obj.ImageColor3) end)
                end
            elseif obj:IsA("UIStroke") then
                pcall(function() obj.Color = remapColor(obj.Color) end)
            elseif obj:IsA("UIGradient") then
                if obj.Name == "TianHubGroupBoxEdgeGradient" then
                    obj.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0.00, C.line),
                        ColorSequenceKeypoint.new(0.18, accent),
                        ColorSequenceKeypoint.new(0.31, C.text),
                        ColorSequenceKeypoint.new(0.43, accent),
                        ColorSequenceKeypoint.new(0.68, C.line),
                        ColorSequenceKeypoint.new(1.00, C.line),
                    })
                elseif obj.Name == "TianHubGroupBoxOuterGlowGradient" then
                    obj.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0.00, C.line),
                        ColorSequenceKeypoint.new(0.22, accent),
                        ColorSequenceKeypoint.new(0.38, C.text),
                        ColorSequenceKeypoint.new(0.52, accent),
                        ColorSequenceKeypoint.new(0.78, C.line),
                        ColorSequenceKeypoint.new(1.00, C.line),
                    })
                elseif obj.Name == "TianHubGroupBoxEdge" then
                    obj.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, C.line),
                        ColorSequenceKeypoint.new(0.5, accent),
                        ColorSequenceKeypoint.new(1, C.line),
                    })
                elseif obj.Name == "TianHubGlossSurface" then
                    obj.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, C.panel2),
                        ColorSequenceKeypoint.new(0.5, C.panel),
                        ColorSequenceKeypoint.new(1, C.bg),
                    })
                else
                    pcall(function()
                        local points = {}
                        for _, point in ipairs(obj.Color.Keypoints) do
                            table.insert(points, ColorSequenceKeypoint.new(point.Time, remapColor(point.Value)))
                        end
                        obj.Color = ColorSequence.new(points)
                    end)
                end
            end
        end
        for _, descendant in ipairs(guiRoot:GetDescendants()) do
            recolorObject(descendant)
        end
        if themeDescendantConnection then themeDescendantConnection:Disconnect() end
        themeDescendantConnection = guiRoot.DescendantAdded:Connect(function(obj)
            task.defer(function()
                if obj.Parent then recolorObject(obj) end
            end)
        end)
        pcall(function() mainStroke.Color = C.line end)
        pcall(function() openButton.BackgroundColor3 = C.bg end)
    end

    local galleryGrid = create("Frame", {
        Name = "BackgroundGalleryGrid",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
    }, customBgCard)
    create("UIGridLayout", {
        CellSize = UDim2.new(0.5, -5, 0, 112),
        CellPadding = UDim2.fromOffset(8, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, galleryGrid)

    local selectionLabel = makeNote(customBgCard, "Selected: TianHub Default", 20)
    local function refreshGallerySelection()
        for index, button in ipairs(galleryButtons) do
            local chosen = index == selectedBackgroundIndex
            button.BorderSizePixel = chosen and 2 or 0
            button.BorderColor3 = chosen and accent or C.line
            local status = button:FindFirstChild("SelectionStatus")
            if status then
                status.Text = chosen and "SELECTED" or BACKGROUND_GALLERY[index].name
                status.TextColor3 = chosen and accentText() or C.text
            end
        end
        selectionLabel.Text = "Selected: " .. BACKGROUND_GALLERY[selectedBackgroundIndex].name
    end

    for index, item in ipairs(BACKGROUND_GALLERY) do
        local preview = create("ImageButton", {
            Name = "BackgroundPreview" .. index,
            LayoutOrder = index,
            BackgroundColor3 = C.panel2,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Image = item.image,
            ScaleType = Enum.ScaleType.Crop,
        }, galleryGrid)
        round(preview, 8)
        local status = create("TextLabel", {
            Name = "SelectionStatus",
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, 0, 1, 0),
            Size = UDim2.new(1, 0, 0, 25),
            BackgroundColor3 = C.bg,
            BackgroundTransparency = 0.18,
            Text = item.name,
            TextColor3 = C.text,
            TextSize = 10,
            Font = Enum.Font.GothamBold,
            TextWrapped = true,
            ZIndex = 3,
        }, preview)
        round(status, 7)
        galleryButtons[index] = preview
        preview.Activated:Connect(function()
            selectedBackgroundIndex = index
            refreshGallerySelection()
        end)
    end
    refreshGallerySelection()

    makeButton(customBgCard, "Apply Background", function()
        local chosen = BACKGROUND_GALLERY[selectedBackgroundIndex]
        appliedBackgroundIndex = selectedBackgroundIndex
        customBackgroundApplied = selectedBackgroundIndex ~= 1
        applyTianHubBackgroundImage(chosen.image)
        openImage.Image = chosen.image
        openImage.ImageTransparency = 0
        applyDynamicTheme(chosen.theme)
        toast(chosen.name .. " applied")
    end)
    makeButton(customBgCard, "Reset Background", function()
        selectedBackgroundIndex = 1
        appliedBackgroundIndex = 1
        customBackgroundApplied = false
        TianHubBackgroundSync.AppliedImage = nil
        if bgImage.Parent then bgImage.Image = TianHubBackgroundSync.MainOriginal end
        if bannerImage.Parent then bannerImage.Image = TianHubBackgroundSync.BannerOriginal end
        if TianHubBackgroundSync.MiniBackground and TianHubBackgroundSync.MiniBackground.Parent then
            TianHubBackgroundSync.MiniBackground.Image = TianHubBackgroundSync.MiniOriginal
        end
        setTianHubBackgroundVisibility(backgroundOpacity)
        openImage.Image = TIANHUB_ASSET
        openImage.ImageTransparency = 0
        applyDynamicTheme("default")
        refreshGallerySelection()
        toast("Background and TianHub theme restored")
    end)

    local b = makeCard("Settings", "Accent Color", 2)
    controls["Accent Color"] = makeAccentPicker(b, "Accent")

    local w = makeCard("Settings", "Window", 2)
    makeButton(w, "Reset Position", function()
        shell.Position = UDim2.fromScale(0.5, 0.5)
        toast("Window position reset")
    end)

    -- Compact Mode moved into this script's Settings tab.
    local compactCard = makeCard("Settings", "Preferences", 2)
    controls["Compact Mode"] = makeToggle(compactCard, "Compact Mode", true, function(v)
        compactMode = v
        for _, item in ipairs(compactTargets) do
            if item.applyCompact then
                item.applyCompact(v)
            elseif item.object and item.object.Parent then
                local h = v and item.compact or item.normal
                item.object.Size = UDim2.new(1, 0, 0, h)
                if item.kind == "slider" then
                    local hit = item.object:FindFirstChildWhichIsA("TextButton")
                    if hit then hit.Position = UDim2.fromOffset(16, v and 21 or 26) end
                end
            end
        end
    end)

    -- Defaults: status pill hidden; main TianHub UI remains enabled.
    statusPill.Visible = false
    controls["Show Status"].Set(false, true)
    controls["Compact Mode"].Set(true, true)
end

do
    local startTime = os.clock()
    local execName = "Unknown"
    pcall(function()
        if identifyexecutor then
            local n, v = identifyexecutor()
            execName = tostring(n) .. (v and (" " .. tostring(v)) or "")
        end
    end)
    local ageDays = player.AccountAge
    local ageText = string.format("%dy %dm %dd", math.floor(ageDays / 365), math.floor((ageDays % 365) / 30), (ageDays % 365) % 30)
    local membership = (tostring(player.MembershipType):gsub("Enum.MembershipType.", ""))

    local a = makeCard("Settings", "Player", 1)
    local rowDN = makeInfoRow(a, "Display Name", player.DisplayName)
    local rowUN = makeInfoRow(a, "Username", "@" .. player.Name)
    local rowID = makeInfoRow(a, "User ID", player.UserId)
    UI.setStreamer = function(on)
        rowDN.SetValue(on and "Hidden" or player.DisplayName)
        rowUN.SetValue(on and "@hidden" or ("@" .. player.Name))
        rowID.SetValue(on and "Hidden" or player.UserId)
    end
    makeInfoRow(a, "Account Age", ageText)
    makeInfoRow(a, "Membership", membership)
    makeInfoRow(a, "Executor", execName)

    local s = makeCard("Settings", "Server", 2)
    local rowPlayers = makeInfoRow(s, "Players", "--")
    local rowSession = makeInfoRow(s, "Session", "00:00")
    local rowPing = makeInfoRow(s, "Ping", "--")
    local rowFps = makeInfoRow(s, "FPS", "--")
    makeInfoRow(s, "Place ID", game.PlaceId)
    makeInfoRow(s, "Job ID", string.sub(game.JobId, 1, 8) .. "...")

    local ab = makeCard("Settings", "About", 2)
    makeInfoRow(ab, "Name", HUB_NAME)
    makeInfoRow(ab, "Version", HUB_VERSION)

    task.spawn(function()
        while gui.Parent do
            rowFps.SetValue(currentFps)
            rowPing.SetValue(currentPing .. " ms")
            rowPlayers.SetValue(#Players:GetPlayers() .. " / " .. Players.MaxPlayers)
            local sec = math.floor(os.clock() - startTime)
            rowSession.SetValue(string.format("%02d:%02d", math.floor(sec / 60), sec % 60))
            task.wait(0.5)
        end
    end)
end

search:GetPropertyChangedSignal("Text"):Connect(function()
    local query = string.lower(search.Text)
    local counts = {}
    for pageName, p in pairs(pages) do
        local visibleCount = 0
        for _, d in ipairs(p.scroll:GetDescendants()) do
            if d:IsA("Frame") and d.Name:match("Card$") then
                local match = (query == "")
                if not match then
                    for _, t in ipairs(d:GetDescendants()) do
                        if (t:IsA("TextLabel") or t:IsA("TextButton") or t:IsA("TextBox"))
                            and t.Text ~= ""
                            and string.find(string.lower(t.Text), query, 1, true) then
                            match = true
                            break
                        end
                    end
                end
                d.Visible = match
                if match then visibleCount += 1 end
            end
        end
        counts[pageName] = visibleCount
    end

    if query ~= "" and selectedTab and (counts[selectedTab] or 0) == 0 then
        for _, tab in ipairs(TABS) do
            if (counts[tab.Name] or 0) > 0 then
                setPage(tab.Name)
                break
            end
        end
    end
end)

minimize.Activated:Connect(function()
    hideUI()
end)
local confirmOverlay = nil

local function askClose()
    if confirmOverlay and confirmOverlay.Parent then return end

    local overlay = create("TextButton", {
        Name = "CloseConfirm",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 50,
    }, main)
    round(overlay, 14)
    confirmOverlay = overlay
    tween(overlay, 0.15, {BackgroundTransparency = 0.4})

    local dialog = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(290, 138),
        BackgroundColor3 = C.panel,
        BorderSizePixel = 0,
        ZIndex = 51,
    }, overlay)
    round(dialog, 12)
    outline(dialog, 1, 0.2)
    local dialogScale = create("UIScale", {Scale = 0.92}, dialog)
    tween(dialogScale, 0.15, {Scale = 1})

    create("TextLabel", {
        Position = UDim2.fromOffset(18, 14),
        Size = UDim2.new(1, -36, 0, 22),
        BackgroundTransparency = 1,
        Text = "Close TianHub?",
        TextColor3 = C.text,
        TextSize = 15,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 52,
    }, dialog)
    create("TextLabel", {
        Position = UDim2.fromOffset(18, 40),
        Size = UDim2.new(1, -36, 0, 34),
        BackgroundTransparency = 1,
        Text = "The window will be hidden. Tap the floating button to open it again.",
        TextColor3 = C.muted,
        TextSize = 12,
        Font = Enum.Font.Gotham,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        ZIndex = 52,
    }, dialog)

    local function dialogButton(text, anchorX, posX, bgColor, hoverColor, onClick)
        local b = create("TextButton", {
            AnchorPoint = Vector2.new(anchorX, 0),
            Position = UDim2.new(anchorX, posX, 0, 92),
            Size = UDim2.new(0.5, -23, 0, 32),
            BackgroundColor3 = bgColor,
            Text = text,
            TextColor3 = C.text,
            TextSize = 13,
            Font = Enum.Font.GothamMedium,
            AutoButtonColor = false,
            ZIndex = 52,
        }, dialog)
        round(b, 8)
        b.MouseEnter:Connect(function()
            if canHover() then tween(b, 0.1, {BackgroundColor3 = hoverColor}) end
        end)
        b.MouseLeave:Connect(function()
            tween(b, 0.1, {BackgroundColor3 = bgColor})
        end)
        b.Activated:Connect(onClick)
        return b
    end

    local function dismiss()
        if confirmOverlay == overlay then confirmOverlay = nil end
        if overlay.Parent then overlay:Destroy() end
    end

    dialogButton("Cancel", 0, 18, C.panel2, C.hover, dismiss)
    dialogButton("Yes, close", 1, -18, C.red, Color3.fromRGB(240, 96, 108), function()
        dismiss()
        hideUI()
    end)
end

close.Activated:Connect(askClose)

local btnDragging, btnMoved = false, false
local btnStart, btnStartPos
openButton.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        btnDragging = true
        btnMoved = false
        btnStart = input.Position
        btnStartPos = openButton.AbsolutePosition - gui.AbsolutePosition
    end
end)
keep(UserInputService.InputChanged:Connect(function(input)
    if btnDragging and btnStart and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - btnStart
        if not btnMoved and delta.Magnitude > 8 then
            btnMoved = true
        end
        if btnMoved then
            local g = gui.AbsoluteSize
            local sz = openButton.AbsoluteSize
            local x = math.clamp(btnStartPos.X + delta.X, 0, math.max(g.X - sz.X, 0))
            local y = math.clamp(btnStartPos.Y + delta.Y, 0, math.max(g.Y - sz.Y, 0))
            openButton.Position = UDim2.fromOffset(x, y)
        end
    end
end))
keep(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        btnDragging = false
    end
end))
openButton.Activated:Connect(function()
    if btnMoved or dragging then return end
    if isOpen then
        hideUI()
    else
        openUI()
    end
end)

local grip = create("TextButton", {
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -8, 1, -8),
    Size = UDim2.fromOffset(24, 24),
    BackgroundColor3 = C.panel2,
    Text = "",
    AutoButtonColor = false,
    ZIndex = 5,
}, main)
round(grip, 7)
outline(grip, 1, 0.5)
local gripBars = {
    bar(grip, 13, 1.6, 12, 12, -45, C.muted),
    bar(grip, 6, 1.6, 16, 16, -45, C.muted),
}
for _, g in ipairs(gripBars) do g.ZIndex = 6 end
grip.MouseEnter:Connect(function()
    if not canHover() then return end
    for _, g in ipairs(gripBars) do tween(g, 0.1, {BackgroundColor3 = C.text}) end
end)
grip.MouseLeave:Connect(function()
    for _, g in ipairs(gripBars) do tween(g, 0.1, {BackgroundColor3 = C.muted}) end
end)

local resizing = false
local rStart, rW, rH, rPos
local lastGripTap = 0

grip.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        if os.clock() - lastGripTap < 0.35 then
            lastGripTap = 0
            setSize(DESIGN_W, DESIGN_H)
            shell.Position = UDim2.fromScale(0.5, 0.5)
            return
        end
        lastGripTap = os.clock()
        resizing = true
        rStart = input.Position
        rW, rH = curW, curH
        rPos = shell.Position
        setScrollLock(true)
    end
end)

keep(UserInputService.InputChanged:Connect(function(input)
    if resizing and rStart and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local k = math.max(scale.Scale, 0.01)
        local delta = (input.Position - rStart) / k
        setSize(rW + delta.X, rH + delta.Y)

        shell.Position = UDim2.new(
            rPos.X.Scale, rPos.X.Offset + (curW - rW) / 2,
            rPos.Y.Scale, rPos.Y.Offset + (curH - rH) / 2
        )
    end
end))
keep(UserInputService.InputEnded:Connect(function(input)
    if resizing and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
        resizing = false
        rStart = nil
        setScrollLock(false)
    end
end))

local dragStart, startPos
local function bindDrag(handle)
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = shell.Position
        end
    end)
end
bindDrag(topbar)
bindDrag(sidebar)

keep(UserInputService.InputChanged:Connect(function(input)
    if dragging and dragStart and startPos and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = (input.Position - dragStart) / math.max(scale.Scale, 0.01)
        shell.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
        local gp, gs = gui.AbsolutePosition, gui.AbsoluteSize
        local sp, ss = shell.AbsolutePosition, shell.AbsoluteSize
        local kk = math.max(scale.Scale, 0.01)
        local minX, maxX = gp.X - ss.X + 120, gp.X + gs.X - 120

        local minY, maxY = gp.Y - 34 * kk, gp.Y + gs.Y - 60
        local cx = math.clamp(sp.X, minX, maxX) - sp.X
        local cy = math.clamp(sp.Y, minY, maxY) - sp.Y
        if cx ~= 0 or cy ~= 0 then
            local k = math.max(scale.Scale, 0.01)
            shell.Position = shell.Position + UDim2.fromOffset(cx / k, cy / k)
        end
    end
end))
keep(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
        dragStart = nil
        startPos = nil
    end
end))

UI.gui, UI.main, UI.shell, UI.C, UI.controls, UI.pages = gui, main, shell, C, controls, pages
UI.makeCard, UI.makeToggle, UI.makeSlider, UI.makeDropdown = makeCard, makeToggle, makeSlider, makeDropdown
UI.resolveIcon = resolveIcon
UI.logoAsset = LOGO_ASSETS[1]
UI.makeButton, UI.makeNote, UI.makeInfoRow = makeButton, makeNote, makeInfoRow
UI.toast, UI.openUI, UI.hideUI, UI.startLogoResolver, UI.setPage = toast, openUI, hideUI, startLogoResolver, setPage
end

local ScreenGui = UI.gui
local MainFrame = UI.main
local C = UI.C
C.Bg, C.Panel, C.Card, C.CardHover, C.Line = C.bg, C.panel, C.panel2, C.hover, C.line
C.Text, C.TextDim, C.TextSub = C.text, C.muted, Color3.fromRGB(115, 115, 125)
C.Active, C.ActiveTxt, C.Overlay, C.IconOff = Color3.fromRGB(255, 255, 255), Color3.fromRGB(0, 0, 0), C.bg, C.off

local VERSION = "v9 (new UI)"
local LOGO_ID = "rbxassetid://134541569123256"
local EYE_ICON_ID = "rbxassetid://13321848320"
local RADIUS = 2

local function corner(parent, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or RADIUS)
    c.Parent = parent
    return c
end

local function MakeDraggable(handle, obj)

    local active, dragStart, startPos
    local function isMouse(i) return i.UserInputType == Enum.UserInputType.MouseButton1 end
    handle.InputBegan:Connect(function(input)
        if active then return end
        if isMouse(input) or input.UserInputType == Enum.UserInputType.Touch then
            active = input
            dragStart = input.Position
            startPos = obj.Position
            obj:SetAttribute("TianDragged", false)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not active then return end
        local mine = (input == active) or (isMouse(active) and input.UserInputType == Enum.UserInputType.MouseMovement)
        if not mine then return end
        local delta = input.Position - dragStart
        if delta.Magnitude > 8 then obj:SetAttribute("TianDragged", true) end
        obj.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end)
    UserInputService.InputEnded:Connect(function(input)
        if not active then return end
        if input == active or (isMouse(active) and isMouse(input)) then active = nil end
    end)
end

-- Feature status toasts are intentionally muted; this does not alter feature callbacks.
local function ShowToast(title, message)
    return
end

local BodyInfo = setmetatable({}, { __mode = "k" })
local CardList = {}
local function ctlKey(parent, name)
    local bi = BodyInfo[parent]
    local k = (bi and (bi.tab .. "/" .. bi.title .. "/") or "") .. name
    while UI.controls[k] do k = k .. "'" end
    return k
end

local function P(tab, card, list)
    local t = {}
    for _, n in ipairs(list) do t[n] = { tab, card } end
    return t
end
local PLACE = {}
local function addPlace(t) for k, v in pairs(t) do PLACE[k] = v end end

-- MAIN: feature sections are grouped by their existing tab, without moving controls.
addPlace(P("Main", "MOVEMENT", { "NO CLIP", "MOONWALK", "MOONWALK V2" }))
addPlace(P("Main", "CAMERA SETTINGS", { "FIELD OF VIEW", "CAMERA STRETCH", "CAMERA STIFFNESS", "INFINITE ZOOM" }))
addPlace(P("Main", "WEATHER & SKY", { "WEATHER & SKY", "DBD SKY" }))
addPlace(P("Main", "SKIP CUTSCENE", { "SKIP CUTSCENE" }))
addPlace(P("Main", "STREAMER MODE", { "STREAMER MODE" }))
addPlace(P("Main", "FAKE AVATAR", { "FAKE AVATAR" }))
addPlace(P("Main", "FAKE AKSESORIS 8BIT", { "Fake Aksesoris 8Bit" }))
addPlace(P("Main", "LIGHTING", { "LIGHTING" }))
addPlace(P("Main", "CONTRAST", { "CONTRAST" }))
addPlace(P("Main", "TREE & GRASS", { "TREE & GRASS" }))
addPlace(P("Main", "EMOTE WHEEL", { "EMOTE WHEEL" }))

-- SURVIVOR: separate the generator, movement and aim panels as requested.
addPlace(P("Survivor", "AUTO PUMPKIN (CRUSH ALL)", { "AUTO PUMPKIN (CRUSH ALL)" }))
addPlace(P("Survivor", "AUTO PARRY", { "AUTO PARRY", "PARRY RADIUS", "FACE SENSITIVITY", "ESP RANGE" }))
addPlace(P("Survivor", "SELF HEAL", { "SELF HEAL" }))
addPlace(P("Survivor", "TWIST OF FATE", { "TWIST OF FATE" }))
addPlace(P("Survivor", "SURVIVAL", { "GOD MODE", "AUTO DODGE CROUCH", "AUTO DODGE SPEAR" }))
addPlace(P("Survivor", "AUTO SKILL CHECK", { "AUTO SKILL CHECK" }))
addPlace(P("Survivor", "AUTO SKILL CHECK TRAP", { "AUTO SKILL CHECK TRAP" }))
addPlace(P("Survivor", "ANTI SLOW VAULT", { "VAULT", "ANTI SLOW VAULT" }))
addPlace(P("Survivor", "ESCAPE", { "INSTANT ESCAPE", "AUTO WIGGLE" }))
addPlace(P("Survivor", "FAKE PERKS", { "QUICK RECOVERY", "PERFECT LANDING", "ADRENALINE RUSH", "PERK COOLDOWN" }))
addPlace(P("Survivor", "FLOWSTATE", { "FLOWSTATE" }))
addPlace(P("Survivor", "FLASHLIGHT", { "SILENT FLASHLIGHT" }))
addPlace(P("Survivor", "SILENT FLASHLIGHT", { "SILENT FLASHLIGHT" }))

-- Killer controls requested in one shared KILLER COMBAT GroupBox.
addPlace(P("Killer", "KILLER COMBAT", {
    "KILLER COMBAT", "COUNTER AUTO PARRY", "ANTI BLIND", "AUTO HOOK",
    "UNLOCK SKILL WHILE CARRYING", "AIMLOCK ATTACK", "DESTROY PALLET"
}))
-- Silent Aim TOF remains in Survivor.
addPlace(P("Survivor", "SILENT AIM TOF", { "SILENT AIM TOF" }))

-- KILLER TAB: gameplay feature placements intentionally removed; tab remains visible.

-- ESP.
addPlace(P("ESP", "PLAYER ESP", { "PLAYER ESP" }))
addPlace(P("ESP", "KILLER ESP", { "KILLER ESP" }))
addPlace(P("ESP", "OBJECT ESP", { "GENERATOR ESP" }))
addPlace(P("ESP", "OBJECT ESP", { "OBJECT ESP" }))
addPlace(P("ESP", "INFORMATION", { "NEXT MAP", "NEXT KILLER", "KILLER PERKS", "SPECTATOR COUNTER" }))
addPlace(P("ESP", "INFORMATION", { "STUN INDICATOR" }))
addPlace(P("ESP", "HIT AREA", { "HIT AREA" }))

-- MUSIC.
addPlace(P("Music", "MUSIC LIBRARY", { "MUSIC LIBRARY" }))
addPlace(P("Music", "CUSTOM SOUND ID", { "CUSTOM SOUND ID" }))
addPlace(P("Music", "PLAYBACK", { "PLAYBACK" }))
addPlace(P("Music", "SOUND SETTINGS", { "SOUND SETTINGS" }))
addPlace(P("Music", "MINI MUSIC PLAYER", { "MINI MUSIC PLAYER" }))

local NOLABEL = {
    ["INFORMATION"] = true, ["CAMERA SETTINGS"] = true,
    ["WEATHER & SKY"] = true, ["KILLER COMBAT"] = true,
}
local MergedBodies = {}
local GroupCount = {}
local PendingLabel = setmetatable({}, { __mode = "k" })

local function flushLabel(parent, controlName)
    -- Hide generated sub-group labels in every card; keep all controls and sections intact.
    PendingLabel[parent] = nil
end

local function newCard(tab, title)
    CardList[tab] = CardList[tab] or {}
    local idx = #CardList[tab] + 1
    local column = (title == "AUTO PUMPKIN (CRUSH ALL)") and 2 or ((idx % 2 == 1) and 1 or 2)
    local body = UI.makeCard(tab, title, column)
    if title == "AUTO PUMPKIN (CRUSH ALL)" then body.Parent.Parent.LayoutOrder = -100 end
    BodyInfo[body] = { tab = tab, title = title }
    CardList[tab][idx] = { title = title, card = body.Parent.Parent, idx = idx }
    return body
end

local function CreateSection(tab, title, open)
    local p = PLACE[title]
    local tabName = p and p[1] or tab
    local cardName = p and p[2] or title
    if not UI.pages[tabName] then tabName = "Main" end
    local key = tabName .. "/" .. cardName
    local body = MergedBodies[key]
    if not body then
        body = newCard(tabName, cardName)
        MergedBodies[key] = body
    end
    GroupCount[key] = (GroupCount[key] or 0) + 1
    if GroupCount[key] > 1 or title ~= cardName then
        PendingLabel[body] = title
    end
    return body
end

local ToggleRegistry = {}
local function CreateToggle(parent, name, defaultState, callback)
    flushLabel(parent, name)
    local toggled = defaultState or false
    local ctl
    local function run(state)
        toggled = state
        if callback then
            local ok, err = pcall(callback, state)
            if not ok then logQuiet("TianHub: " .. name .. " - " .. tostring(err)) end
        end
    end
    ctl = UI.makeToggle(parent, name, toggled, function(state)
        run(state)
    end)
    local id = name:gsub("%s+", "_"):lower()
    local reg = {
        name = name,
        getState = function() return toggled end,
        setState = function(v, silent)
            v = v and true or false
            ctl.Set(v, false)
            run(v)
        end,
    }
    ToggleRegistry[id] = reg
    UI.controls[ctlKey(parent, name)] = {
        Get = function() return toggled end,
        Set = function(v, fire)
            if fire then reg.setState(v, true) else ctl.Set(v, false); toggled = v and true or false end
        end,
        Reset = function() reg.setState(defaultState or false, true) end,
    }
    return ctl.Row
end

local function CreateSlider(parent, name, minVal, maxVal, defaultVal, suffix, callback, precision)
    flushLabel(parent, name)
    local value = defaultVal
    local ctl = UI.makeSlider(parent, name, minVal, maxVal, defaultVal, function(v)
        value = v
        if callback then
            local ok, err = pcall(callback, v)
            if not ok then logQuiet("TianHub: " .. name .. " - " .. tostring(err)) end
        end
    end, suffix, precision)
    UI.controls[ctlKey(parent, name)] = {
        Get = function() return value end,
        Set = function(v, fire) ctl.Set(v, fire); if not fire then value = v end end,
        Reset = function() ctl.Set(defaultVal, true) end,
    }
    return ctl.Holder
end

local function CreateButton(parent, name, callback, silent)
    flushLabel(parent, name)
    return UI.makeButton(parent, name, function()
        if callback then
            local ok, err = pcall(callback)
            if not ok then ShowToast(name, "Error: " .. tostring(err)); return end
        end
    end)
end

local function CreateColorPicker(parent, name, defaultColor, callback)
    flushLabel(parent, name)
    local color = defaultColor
    local h, sat, val = color:ToHSV()
    local row = Instance.new("Frame")
    row.Name = "ColorRow"
    row.Size = UDim2.new(1, 0, 0, 28)
    row.BackgroundColor3 = C.panel2
    row.BorderSizePixel = 0
    row.Parent = parent
    corner(row, 8)
    local rs = Instance.new("UIStroke", row)
    rs.Color = C.line
    rs.Thickness = 1
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Position = UDim2.fromOffset(12, 0)
    lbl.Size = UDim2.new(1, -70, 1, 0)
    lbl.Font = Enum.Font.GothamMedium
    lbl.Text = name
    lbl.TextSize = 12
    lbl.TextColor3 = C.text
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row
    local sw = Instance.new("TextButton")
    sw.AnchorPoint = Vector2.new(1, 0.5)
    sw.Position = UDim2.new(1, -10, 0.5, 0)
    sw.Size = UDim2.fromOffset(30, 16)
    sw.Text = ""
    sw.AutoButtonColor = false
    sw.BackgroundColor3 = color
    sw.BorderSizePixel = 0
    sw.Parent = row
    corner(sw, 6)
    local ss = Instance.new("UIStroke", sw)
    ss.Color = Color3.fromRGB(255, 255, 255)
    ss.Transparency = 0.55
    ss.Thickness = 1

    local popup
    local conns = {}
    local function apply(fire)
        color = Color3.fromHSV(h, sat, val)
        sw.BackgroundColor3 = color
        if fire and callback then pcall(callback, color) end
    end
    local function closePopup()
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        conns = {}
        if popup then pcall(function() popup:Destroy() end) popup = nil end
    end
    local function openPopup()
        if popup then closePopup(); return end
        local W, H = 150, 112
        popup = Instance.new("Frame")
        popup.Name = "TianColorPopup"
        popup.Size = UDim2.fromOffset(W, H)
        popup.BackgroundColor3 = C.panel
        popup.BorderSizePixel = 0
        popup.ZIndex = 300
        popup.Active = true
        popup.Parent = ScreenGui
        corner(popup, 10)
        local ps = Instance.new("UIStroke", popup)
        ps.Color = C.line
        ps.Thickness = 1
        local scr = ScreenGui.AbsoluteSize
        local ap = sw.AbsolutePosition
        popup.Position = UDim2.fromOffset(math.clamp(ap.X - W + 40, 6, math.max(scr.X - W - 6, 6)), math.clamp(ap.Y + 26, 6, math.max(scr.Y - H - 6, 6)))

        local sv = Instance.new("Frame")
        sv.Position = UDim2.fromOffset(8, 8)
        sv.Size = UDim2.fromOffset(112, 72)
        sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
        sv.BorderSizePixel = 0
        sv.ZIndex = 301
        sv.Parent = popup
        corner(sv, 6)
        local white = Instance.new("Frame")
        white.Size = UDim2.fromScale(1, 1)
        white.BackgroundColor3 = Color3.new(1, 1, 1)
        white.BorderSizePixel = 0
        white.ZIndex = 302
        white.Parent = sv
        corner(white, 6)
        local wg = Instance.new("UIGradient", white)
        wg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
        local black = Instance.new("Frame")
        black.Size = UDim2.fromScale(1, 1)
        black.BackgroundColor3 = Color3.new(0, 0, 0)
        black.BorderSizePixel = 0
        black.ZIndex = 303
        black.Parent = sv
        corner(black, 6)
        local bg = Instance.new("UIGradient", black)
        bg.Rotation = 90
        bg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
        local svKnob = Instance.new("Frame")
        svKnob.AnchorPoint = Vector2.new(0.5, 0.5)
        svKnob.Size = UDim2.fromOffset(10, 10)
        svKnob.BackgroundTransparency = 1
        svKnob.ZIndex = 305
        svKnob.Parent = sv
        corner(svKnob, 5)
        local sk = Instance.new("UIStroke", svKnob)
        sk.Color = Color3.new(1, 1, 1)
        sk.Thickness = 2

        local hue = Instance.new("Frame")
        hue.Position = UDim2.fromOffset(128, 8)
        hue.Size = UDim2.fromOffset(14, 72)
        hue.BackgroundColor3 = Color3.new(1, 1, 1)
        hue.BorderSizePixel = 0
        hue.ZIndex = 301
        hue.Parent = popup
        corner(hue, 6)
        local hg = Instance.new("UIGradient", hue)
        hg.Rotation = 90
        local kp = {}
        for i = 0, 6 do kp[#kp + 1] = ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1)) end
        hg.Color = ColorSequence.new(kp)
        local hKnob = Instance.new("Frame")
        hKnob.AnchorPoint = Vector2.new(0.5, 0.5)
        hKnob.Size = UDim2.new(1, 4, 0, 6)
        hKnob.BackgroundTransparency = 1
        hKnob.ZIndex = 305
        hKnob.Parent = hue
        corner(hKnob, 3)
        local hk = Instance.new("UIStroke", hKnob)
        hk.Color = Color3.new(1, 1, 1)
        hk.Thickness = 2

        local prev = Instance.new("Frame")
        prev.Position = UDim2.fromOffset(8, 88)
        prev.Size = UDim2.fromOffset(22, 16)
        prev.BorderSizePixel = 0
        prev.ZIndex = 301
        prev.Parent = popup
        corner(prev, 5)
        local hex = Instance.new("TextLabel")
        hex.BackgroundTransparency = 1
        hex.Position = UDim2.fromOffset(36, 88)
        hex.Size = UDim2.fromOffset(108, 16)
        hex.Font = Enum.Font.GothamMedium
        hex.TextSize = 10
        hex.TextColor3 = C.muted
        hex.TextXAlignment = Enum.TextXAlignment.Left
        hex.ZIndex = 301
        hex.Parent = popup

        local function refresh()
            sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
            svKnob.Position = UDim2.fromScale(sat, 1 - val)
            hKnob.Position = UDim2.fromScale(0.5, h)
            local c = Color3.fromHSV(h, sat, val)
            prev.BackgroundColor3 = c
            hex.Text = string.format("RGB  %d, %d, %d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
        end
        refresh()

        local drag, dragInput
        local function update(pos)
            if drag == "sv" then
                sat = math.clamp((pos.X - sv.AbsolutePosition.X) / sv.AbsoluteSize.X, 0, 1)
                val = 1 - math.clamp((pos.Y - sv.AbsolutePosition.Y) / sv.AbsoluteSize.Y, 0, 1)
            elseif drag == "hue" then
                h = math.clamp((pos.Y - hue.AbsolutePosition.Y) / hue.AbsoluteSize.Y, 0, 0.999)
            end
            refresh()
            apply(true)
        end
        local function begin(kind, input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
            drag, dragInput = kind, input
            update(input.Position)
        end
        conns[#conns + 1] = sv.InputBegan:Connect(function(i) begin("sv", i) end)
        conns[#conns + 1] = hue.InputBegan:Connect(function(i) begin("hue", i) end)
        conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
            if not drag then return end
            local isMouse = dragInput.UserInputType == Enum.UserInputType.MouseButton1
            if input == dragInput or (isMouse and input.UserInputType == Enum.UserInputType.MouseMovement) then
                update(input.Position)
            end
        end)
        conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
            if drag and (input == dragInput or (dragInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1)) then
                drag, dragInput = nil, nil
            end
        end)

        conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
            local p = input.Position
            local function inside(g)
                local a, z = g.AbsolutePosition, g.AbsoluteSize
                return p.X >= a.X and p.X <= a.X + z.X and p.Y >= a.Y and p.Y <= a.Y + z.Y
            end
            if popup and not inside(popup) and not inside(sw) then closePopup() end
        end)
    end
    sw.Activated:Connect(openPopup)

    UI.controls[ctlKey(parent, name)] = {
        Get = function() return { math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5) } end,
        Set = function(v, fire)
            if type(v) ~= "table" or #v < 3 then return end
            h, sat, val = Color3.fromRGB(v[1], v[2], v[3]):ToHSV()
            apply(fire)
        end,
        Reset = function()
            h, sat, val = defaultColor:ToHSV()
            apply(true)
        end,
    }
    return row
end

local function CreateTextBox(parent, name, placeholder, callback)
    flushLabel(parent, name)
    local row = Instance.new("Frame")
    row.Name = "TextRow"
    row.Size = UDim2.new(1, 0, 0, 34)
    row.BackgroundColor3 = C.panel2
    row.BorderSizePixel = 0
    row.Parent = parent
    corner(row, 8)
    local rs = Instance.new("UIStroke", row)
    rs.Color = C.line
    rs.Thickness = 1
    local box = Instance.new("TextBox")
    box.BackgroundTransparency = 1
    box.Position = UDim2.fromOffset(12, 0)
    box.Size = UDim2.new(1, -24, 1, 0)
    box.Font = Enum.Font.GothamMedium
    box.PlaceholderText = placeholder or name
    box.PlaceholderColor3 = C.muted
    box.Text = ""
    box.TextSize = 12
    box.TextColor3 = C.text
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.ClearTextOnFocus = false
    box.Parent = row
    box.FocusLost:Connect(function() if callback then pcall(callback, box.Text) end end)
    box:GetPropertyChangedSignal("Text"):Connect(function() if callback then pcall(callback, box.Text) end end)
    return box
end

--====================================================--
-- MUSIC TAB — TianHub music library + compact player
-- TianHub song library and player features; uses the native TianHub interface.
--====================================================--
local MusicSongs = {
    {id = "123887033390123", title = "Kukira Masih Cinta"},
    {id = "86917170271693", title = "Faded x anh dang noi dau"},
    {id = "102964109340239", title = "Berdua Melulu"},
    {id = "139833412213420", title = "Tak Semudah Hompimpa x Kutetap Menanti"},
    {id = "128862178764436", title = "Tergila (Djemuur Remix)"},
    {id = "135709357945929", title = "Bahagia Lagi x Jangan Paksa Rindu"},
    {id = "101985596918228", title = "One"},
    {id = "78520199502339", title = "Two"},
    {id = "78253224480952", title = "Three"},
    {id = "136949217768985", title = "Four"},
    {id = "92143860315842", title = "Five"},
    {id = "96568301359656", title = "Six"},
    {id = "96053601899287", title = "Seven"},
    {id = "116537762304510", title = "Eight"},
    {id = "111775377151665", title = "Nine"},
    {id = "131317416582166", title = "Ten"},
    {id = "107569604895628", title = "Eleven"},
    {id = "80210594606101", title = "Danza Kuduro"},
    {id = "135887188304832", title = "Ada Yang Tumbang Jos Jis"},
    {id = "105372329671874", title = "Million Stars Asoy"},
    {id = "79296696808534", title = "My Lope Lope (Speed Up)"},
    {id = "70578919220987", title = "My Lope Lope (Andri Poter)"},
    {id = "89338419772018", title = "Habibi Ishqi"},
    {id = "93652038633690", title = "Santai Dulu"},
    {id = "124582101215124", title = "DJ Akimilaku Im Back"},
    {id = "121304834713825", title = "Dangdut Week Sebelas"},
    {id = "102944382854479", title = "Lagu Misterius"},
    {id = "126810420971446", title = "Anak Kota"},
    {id = "94299109467073", title = "Cinderella Jedag Jedug"},
    {id = "83463789936127", title = "Lagu Jawa (Kowe Siji)"},
    {id = "771523191444498", title = "Cintaku Ini Istimewa"},
    {id = "86422417888834", title = "Kini Tinggal Kenangan"},
    {id = "70868757792328", title = "Mashup Dora Dora (Funky RMX)"},
    {id = "128071048140468", title = "Always Loving You"},
    {id = "136239433509180", title = "Mysterious Girl (Funky RMX)"},
    {id = "101280279977761", title = "Kini Kita Pe Kisah"},
    {id = "117080961502380", title = "DJ Music Dubstep x Bangun Tidur Selfie"},
    {id = "110337096446518", title = "DJ Onia"},
    {id = "108556908140218", title = "Who Am I"},
    {id = "95163564243987", title = "Never Stop (DJ WHO x Mokyy)"},
    {id = "99445078556609", title = "Hope"},
    {id = "132575056090579", title = "Heroes"},
    {id = "124662835711453", title = "Where Do We Begin x An Angel's Love"},
    {id = "91303938501044", title = "AKIMILAKU PUNYA ISTRI TIGA"},
    {id = "120983443791226", title = "Rasah Bali"},
    {id = "92799532573184", title = "Runkat"},
    {id = "117224072066843", title = "Negoro Angin"},
    {id = "115035906821398", title = "Sinarengan"},
    {id = "120786497356440", title = "Pamit Ning Ati"},
    {id = "79151027570609", title = "Urip Iku Mlaku"},
    {id = "70962526173357", title = "Lintang Nyekseni"},
    {id = "135480789776959", title = "Udang Ning Atiku"},
    {id = "121796353758342", title = "Sepi Tanpo Siramu"},
    {id = "85537520513989", title = "Tresno Kinaryo Kangen"},
    {id = "71152710717244", title = "Tresnoku Selawase"},
    {id = "74761962675895", title = "Saiki"},
    {id = "134246452602760", title = "Tembang Kanggo Siramu"},
    {id = "121335955905892", title = "Ora Butoh Siramu"},
    {id = "110496212005473", title = "Tau Dadi Padhange Dalam"},
    {id = "77330130829762", title = "Nerusake Uripku"},
    {id = "100800381563349", title = "Mboyak"},
    {id = "110965259723757", title = "Kowe Ning Endi"},
    {id = "79929910199476", title = "Los Ora Rewel"},
    {id = "100644156519402", title = "Oalah Wong Kere"},
    {id = "116255319981650", title = "Jamilah Itu Bukan Anunya Aisyah"},
    {id = "138061809475625", title = "Jomblo Happy (Elsy - How Jomblo?)"},
    {id = "86862275991928", title = "Geleng Geleng"},
    {id = "125251080477114", title = "Kondang Nyeni (Pelik Pungki)"},
    {id = "83754315703513", title = "Sedia Aku Sebelum Hujan (Jazz Version)"},
    {id = "124844852560730", title = "Beauty And A Beat (Justin Bieber)"},
    {id = "71081898119547", title = "Alone (Marshmello)"},
    {id = "108835934597498", title = "Jena Jena (Oncom Gondrong)"},
    {id = "121007588302750", title = "CallFCT | ECP 1"},
    {id = "87655416274011", title = "DJ Kumenantimu Saban Waktu"},
    {id = "73831022294492", title = "Valderanaa | Nean Heart"},
    {id = "104997442302161", title = "DJ Ladom Ladom Menan"},
    {id = "111727971797221", title = "Dil ko Kaise Samjhaayein"},
    {id = "99958133967539", title = "Jika Hatimu Terbuka"},
    {id = "71278718327554", title = "Padam (DJemuur)"},
    {id = "83610443399546", title = "An Angel's Love"},
    {id = "78232989299593", title = "Papa Pulang Mama Goyang"},
    {id = "133193396302237", title = "That Should Be Me"},
    {id = "79902843921518", title = "Selamat Tinggal (Virgoun)"},
    {id = "1844008189", title = "DJ Turn The Music Up"},
    {id = "110655017987589", title = "ZKOXGH1"},
    {id = "132871226683154", title = "Salting Mengkane"},
    {id = "95910576883831", title = "Damme | Pray For Kalimantan"},
    {id = "111869264914484", title = "Gerimis Di Pelantaran"},
    {id = "124994794838360", title = "Padamu Sepi"},
    {id = "16662832435", title = "Wahra Paca"},
    {id = "78859797813378", title = "Senggol Dong"},
    {id = "91089804280618", title = "Suka Suka Bahagia"},
    {id = "110919391228823", title = "Low Cortisol"},
    {id = "122827602727670", title = "Setiap Tantangan"},
    {id = "100991657598498", title = "Batte Forte"},
    {id = "129700548831112", title = "Tenxi HTS"},
    {id = "101580869706585", title = "Sedih"},
    {id = "70614011662651", title = "Pura Pura Tak Tahu"},
    {id = "89610760702249", title = "Streo Love"},
    {id = "93596344950405", title = "Kau Di Hatiku"},
    {id = "135357032110162", title = "Armada"},
    {id = "104207837699519", title = "DJ Tabole Bale"},
    {id = "139694597836683", title = "Rahasia Hati"},
    {id = "85936017588280", title = "BBHC Hardcore"},
    {id = "110839312239968", title = "Jealousy Setuyilu"},
    {id = "136842585273816", title = "Nanana Menissu"},
    {id = "126810420971446", title = "Anak Kampung"},
    {id = "118362297271903", title = "Black Hole"},
    {id = "112447571198662", title = "Menungso Oratoto"},
    {id = "121621468837938", title = "Janda Bodong"},
    {id = "132497938577328", title = "Ade Su Nikah"},
    {id = "82268015602309", title = "Thailand Style"},
    {id = "88530410077744", title = "Berdua Lebih Baik"},
    {id = "73567175937757", title = "Bukan Siapa Siapa"},
    {id = "94809972345878", title = "DJ Mix Kane"},
    {id = "122084395776372", title = "Sesi Potret"},
    {id = "70780471034312", title = "My Mine Gueh"},
    {id = "140193000855959", title = "MixTape - Hilang Semua Janji"},
    {id = "75309299876704", title = "Sejak Aku Jatuh Cinta Padamu (Remake)"},
    {id = "75364307169277", title = "Gleer Bervitamin"},
    {id = "112643010224746", title = "Kasih Tau Mama Bkb"},
    {id = "127796757768281", title = "Natraa l AlahsiaSPY 1"},
    {id = "117924825345126", title = "Mas Pelik Suka Tobrut"},
    {id = "94074210849011", title = "As If Its Your Last"},
    {id = "114890750688823", title = "Terdiam Sepi"},
    {id = "79821601944451", title = "Abang Pilih Yang Mana"},
    {id = "77806845871903", title = "Ay"},
    {id = "128259754377999", title = "Ku Tetap Sayang"},
    {id = "79158835442971", title = "Pacar Impian (Hijau Daun)"},
    {id = "98436660793895", title = "Meski Kau Bahagia"},
    {id = "112021392466036", title = "Ilusi Tak Bertepi (Hijau Daun)"},
    {id = "113639353301886", title = "Sesuatu Yang Sempurna"},
    {id = "116986630959929", title = "Sakit Tapi Ku Rindu"},
    {id = "76769189002980", title = "Kau Nyawaku"},
    {id = "127815872735971", title = "Cinta Dalam Ilusi"},
    {id = "102485417887618", title = "D'masiv Cinta Ini Mem..."},
    {id = "81413479475955", title = "Wanna Wait (JJ Hipdut Remix)"},
    {id = "127259463798784", title = "Farhat Liqyak"},
    {id = "98915015116851", title = "Jangan Gila (DJ Kai)"},
    {id = "116222126993808", title = "Stingky - Mungkinkah"},
    {id = "92260587863977", title = "Kocel | NGAPAIN REPOT x Balinese"},
    {id = "72261803135473", title = "AYNA n RIKU | GELENG JAMET ABADI"},
    {id = "76812909425234", title = "Oleng Kiri Kanan Asik"},
    {id = "137224054872014", title = "Rindu Serindu Rindunya (Acoustic)"},
    {id = "88084542595291", title = "Mardua Holong"},
    {id = "118015329089207", title = "Onty Onty"},
    {id = "74420605236066", title = "DJ Titut"},
    {id = "10370648854661", title = "Sunset in September"},
    {id = "8572430013955", title = "Beauty and the Beat"},
    {id = "86316862829978", title = "Dear God"},
    {id = "107082200998987", title = "Kangen Band"},
    {id = "91508586586816", title = "Passacaglia"},
    {id = "105027229772988", title = "Mantan Minta Balik"},
    {id = "131349024936829", title = "Hanya Mimpi"},
    {id = "139413752809835", title = "Di Cari Onty Onty"},
    {id = "120020130234541", title = "Old Fibes"},
    {id = "136298946425465", title = "Kicau Mania"},
    {id = "132933526380611", title = "Rama Kaki Patah"},
    {id = "105763776719810", title = "Potong Bebek Kane"},
    {id = "93838483947219", title = "Gucci x Linting"},
    {id = "131738149206785", title = "Luz Roja"},
    {id = "133907735451392", title = "Om Telolet Om"},
    {id = "73337743865439", title = "Bertemu Sempurna"},
    {id = "88298140757535", title = "Walading"},
    {id = "138706512017388", title = "Lingkar Janji"},
    {id = "81721947434460", title = "Bukan Waktunya"},
    {id = "78052967336602", title = "DJ DMD"},
    {id = "128980917495390", title = "Amnesia"},
    {id = "115168486094850", title = "Mala Mia"},
    {id = "129210850162895", title = "Mainanmu"},
}

local MusicState = {
    Sound = nil,
    SelectedTrack = "Kukira Masih Cinta",
    CurrentTrack = "Kukira Masih Cinta",
    CustomId = "",
    Volume = 2,
    Looped = false,
    AutoNext = true,
    MiniEnabled = false,
    MiniGui = nil,
    MiniFrame = nil,
    MiniTrackLabel = nil,
    MiniTimeLabel = nil,
    MiniProgress = nil,
    MiniPlayButton = nil,
    MiniEqBars = {},
    MiniExpanded = true,
    MiniConnections = {},
    MiniPosition = UDim2.new(0, 12, 0, 12),
    IsPlaying = false,
    IsPaused = false,
}

local MusicByName = {}
local MusicNames = {}
for _, track in ipairs(MusicSongs) do
    MusicByName[track.title] = "rbxassetid://" .. track.id
    table.insert(MusicNames, track.title)
end

-- Replace only this hub's previous Sound instance.
pcall(function()
    local old = SoundService:FindFirstChild("TianHubMusicPlayerSound")
    if old then old:Stop(); old:Destroy() end
end)
pcall(function()
    local parent = ScreenGui and ScreenGui.Parent
    local oldMini = parent and parent:FindFirstChild("TianHubMusicMini")
    if oldMini then oldMini:Destroy() end
end)
local musicSound = Instance.new("Sound")
musicSound.Name = "TianHubMusicPlayerSound"
musicSound.Volume = MusicState.Volume
musicSound.Looped = MusicState.Looped
musicSound.Parent = SoundService
MusicState.Sound = musicSound

local function musicNotify(message)
    if UI and UI.toast then
        pcall(UI.toast, "Music: " .. tostring(message))
    end
end

local function musicUpdateMini()
    local gui = MusicState.MiniGui
    if not gui or not gui.Parent then return end
    if MusicState.MiniTrackLabel then
        MusicState.MiniTrackLabel.Text = MusicState.CurrentTrack or "No track playing"
    end
    if MusicState.MiniPlayButton then
        MusicState.MiniPlayButton.Text = (MusicState.IsPlaying and not MusicState.IsPaused) and "Ⅱ" or "▶"
    end
end

local function musicPlay(soundId, trackName)
    local cleanId = tostring(soundId or ""):gsub("rbxassetid://", ""):gsub("%D", "")
    if cleanId == "" then musicNotify("Sound ID tidak valid"); return false end
    local snd = MusicState.Sound
    if not snd or not snd.Parent then
        snd = Instance.new("Sound")
        snd.Name = "TianHubMusicPlayerSound"
        snd.Parent = SoundService
        MusicState.Sound = snd
    end
    pcall(function() snd:Stop() end)
    snd.SoundId = "rbxassetid://" .. cleanId
    snd.TimePosition = 0
    snd.Volume = MusicState.Volume
    snd.Looped = MusicState.Looped
    local ok, err = pcall(function() snd:Play() end)
    if not ok then
        MusicState.IsPlaying = false
        MusicState.IsPaused = false
        musicNotify("Play error: " .. tostring(err))
        musicUpdateMini()
        return false
    end
    MusicState.CurrentTrack = trackName or ("Custom: " .. cleanId)
    MusicState.IsPlaying = true
    MusicState.IsPaused = false
    musicUpdateMini()
    return true
end

local function musicRandom(excludeCurrent)
    local choices = {}
    for _, track in ipairs(MusicSongs) do
        if not excludeCurrent or track.title ~= MusicState.CurrentTrack then
            table.insert(choices, track)
        end
    end
    if #choices == 0 then return end
    local pick = choices[math.random(1, #choices)]
    musicPlay(MusicByName[pick.title], pick.title)
end

local function musicPause()
    if MusicState.Sound and MusicState.IsPlaying and not MusicState.IsPaused then
        pcall(function() MusicState.Sound:Pause() end)
        MusicState.IsPaused = true
        musicUpdateMini()
    end
end

local function musicResume()
    if MusicState.Sound and MusicState.IsPaused then
        local ok = pcall(function() MusicState.Sound:Resume() end)
        if ok then MusicState.IsPaused = false; MusicState.IsPlaying = true end
        musicUpdateMini()
    end
end

local function musicStop()
    if MusicState.Sound then pcall(function() MusicState.Sound:Stop(); MusicState.Sound.TimePosition = 0 end) end
    MusicState.IsPlaying = false
    MusicState.IsPaused = false
    musicUpdateMini()
end

musicSound.Ended:Connect(function()
    MusicState.IsPlaying = false
    MusicState.IsPaused = false
    if MusicState.AutoNext and not MusicState.Looped then
        musicRandom(true)
    else
        musicUpdateMini()
    end
end)

local function musicFormatTime(seconds)
    seconds = tonumber(seconds) or 0
    return string.format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

local function musicDisconnectMini()
    for _, connection in ipairs(MusicState.MiniConnections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(MusicState.MiniConnections)
end

local function musicBuildMini()
    MusicState.MiniExpanded = true
    if MusicState.MiniGui and MusicState.MiniGui.Parent then
        MusicState.MiniGui.Enabled = true
        musicUpdateMini()
        return
    end
    local parent = ScreenGui and ScreenGui.Parent
    if not parent then parent = LocalPlayer:WaitForChild("PlayerGui") end
    local old = parent:FindFirstChild("TianHubMusicMini")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "TianHubMusicMini"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 250
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = parent
    MusicState.MiniGui = gui

    -- Keep the original compact mini-player footprint.
    local frame = Instance.new("Frame")
    frame.Name = "MainFrame"
    frame.Size = UDim2.fromOffset(320, 145)
    frame.Position = UDim2.new(
        MusicState.MiniPosition.X.Scale, MusicState.MiniPosition.X.Offset,
        MusicState.MiniPosition.Y.Scale, MusicState.MiniPosition.Y.Offset - 10
    )
    frame.BackgroundColor3 = Color3.fromRGB(13, 13, 22)
    frame.BackgroundTransparency = 0.30
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.ClipsDescendants = true
    frame.Parent = gui
    MusicState.MiniFrame = frame

    local background = Instance.new("ImageLabel")
    background.Name = "MiniMusicBackground"
    background.Size = UDim2.fromScale(1, 1)
    background.BackgroundTransparency = 1
    background.Image = "rbxassetid://102799496393192"
    background.ScaleType = Enum.ScaleType.Crop
    background.ImageTransparency = 0.44
    background.ZIndex = 0
    background.Parent = frame
    local backgroundSync = _G.TianHubBackgroundSync
    if type(backgroundSync) == "table" then
        -- Register the live Mini Music banner so every later Apply/Reset updates it.
        backgroundSync.MiniBackground = background
        backgroundSync.MiniOriginal = "rbxassetid://102799496393192"

        -- Also inherit the currently selected background when Mini Music is
        -- created after the user has already applied a gallery image.
        local appliedImage = backgroundSync.AppliedImage
        if type(appliedImage) == "string" and appliedImage ~= "" then
            pcall(function() background.Image = appliedImage end)
        else
            pcall(function() background.Image = backgroundSync.MiniOriginal end)
        end
        pcall(function()
            local visibility = math.clamp(tonumber(backgroundSync.Visibility) or 500, 0, 500)
            background.ImageTransparency = 1 - visibility / 500
        end)
    end
    local bgCorner = Instance.new("UICorner")
    bgCorner.CornerRadius = UDim.new(0, 20)
    bgCorner.Parent = background

    local tint = Instance.new("Frame")
    tint.Size = UDim2.fromScale(1, 1)
    tint.BackgroundColor3 = Color3.fromRGB(8, 12, 28)
    tint.BackgroundTransparency = 0.62
    tint.BorderSizePixel = 0
    tint.ZIndex = 0
    tint.Parent = frame
    local tintCorner = Instance.new("UICorner")
    tintCorner.CornerRadius = UDim.new(0, 20)
    tintCorner.Parent = tint

    -- Mini Music gets its own matching shimmer sweep, above the artwork tint
    -- and below the player controls (which use ZIndex 2 and 3).
    local miniShimmer = Instance.new("Frame")
    miniShimmer.Name = "TianHubMiniMusicShimmer"
    miniShimmer.Size = UDim2.fromScale(1, 1)
    miniShimmer.Position = UDim2.fromScale(0, 0)
    miniShimmer.BackgroundColor3 = Color3.fromRGB(185, 220, 255)
    miniShimmer.BackgroundTransparency = 0
    miniShimmer.BorderSizePixel = 0
    miniShimmer.Active = false
    miniShimmer.Selectable = false
    miniShimmer.ZIndex = 1
    miniShimmer.Parent = frame
    miniShimmer.ClipsDescendants = true
    local miniShimmerCorner = Instance.new("UICorner")
    miniShimmerCorner.CornerRadius = UDim.new(0, 20)
    miniShimmerCorner.Parent = miniShimmer
    local miniShimmerGradient = Instance.new("UIGradient")
    miniShimmerGradient.Name = "TianHubMiniMusicShimmerGradient"
    miniShimmerGradient.Rotation = 18
    miniShimmerGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0.00, 1.00),
        NumberSequenceKeypoint.new(0.43, 1.00),
        NumberSequenceKeypoint.new(0.50, 0.78),
        NumberSequenceKeypoint.new(0.57, 1.00),
        NumberSequenceKeypoint.new(1.00, 1.00),
    })
    miniShimmerGradient.Offset = Vector2.new(-1.25, 0)
    miniShimmerGradient.Parent = miniShimmer
    TweenService:Create(miniShimmerGradient,
        TweenInfo.new(3.0, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false, 1.0),
        { Offset = Vector2.new(1.25, 0) }
    ):Play()

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 20)
    corner.Parent = frame
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(82, 128, 255)
    stroke.Transparency = 0.14
    stroke.Thickness = 1
    stroke.Parent = frame

    local cover = Instance.new("ImageLabel")
    cover.Name = "AlbumArt"
    cover.Position = UDim2.fromOffset(10, 30)
    cover.Size = UDim2.fromOffset(78, 78)
    cover.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
    cover.Image = "rbxassetid://102799496393192"
    cover.ScaleType = Enum.ScaleType.Crop
    cover.ZIndex = 2
    cover.Parent = frame

    -- Album artwork follows the selected custom background as well.
    -- Keep its own original image so Reset restores the default cover.
    local miniBackgroundSync = _G.TianHubBackgroundSync
    if type(miniBackgroundSync) == "table" then
        miniBackgroundSync.MiniAlbumArt = cover
        miniBackgroundSync.MiniAlbumArtOriginal = "rbxassetid://102799496393192"
        local selectedBackground = miniBackgroundSync.AppliedImage
        if type(selectedBackground) == "string" and selectedBackground ~= "" then
            pcall(function() cover.Image = selectedBackground end)
        end
    end

    local coverCorner = Instance.new("UICorner")
    coverCorner.CornerRadius = UDim.new(0, 10)
    coverCorner.Parent = cover

    -- Track title centered in the right-hand panel, not clipped against an edge.
    local title = Instance.new("TextLabel")
    title.Name = "TrackTitle"
    title.Position = UDim2.fromOffset(96, 15)
    title.Size = UDim2.new(1, -112, 0, 20)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextXAlignment = Enum.TextXAlignment.Center
    title.TextYAlignment = Enum.TextYAlignment.Center
    title.TextTruncate = Enum.TextTruncate.AtEnd
    title.Text = "No track playing"
    title.ZIndex = 2
    title.Parent = frame
    MusicState.MiniTrackLabel = title

    local eqFrame = Instance.new("Frame")
    eqFrame.Position = UDim2.fromOffset(96, 47)
    eqFrame.Size = UDim2.new(1, -112, 0, 25)
    eqFrame.BackgroundTransparency = 1
    eqFrame.ZIndex = 2
    eqFrame.Parent = frame
    MusicState.MiniEqBars = {}
    for i = 1, 23 do
        local bar = Instance.new("Frame")
        bar.AnchorPoint = Vector2.new(0, 1)
        bar.Position = UDim2.new(0, (i - 1) * 8.7, 1, 0)
        bar.Size = UDim2.new(0, 3, 0.18, 0)
        bar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        bar.BorderSizePixel = 0
        bar.ZIndex = 2
        bar.Parent = eqFrame
        local barCorner = Instance.new("UICorner")
        barCorner.CornerRadius = UDim.new(1, 0)
        barCorner.Parent = bar
        table.insert(MusicState.MiniEqBars, bar)
    end

    -- Restore the music progress bar under the equalizer.
    local progressTrack = Instance.new("Frame")
    progressTrack.Name = "SongProgressTrack"
    progressTrack.Position = UDim2.fromOffset(96, 76)
    progressTrack.Size = UDim2.new(1, -112, 0, 4)
    progressTrack.BackgroundColor3 = Color3.fromRGB(210, 215, 230)
    progressTrack.BackgroundTransparency = 0.15
    progressTrack.BorderSizePixel = 0
    progressTrack.ZIndex = 2
    progressTrack.Parent = frame
    local progressFill = Instance.new("Frame")
    progressFill.Name = "SongProgressFill"
    progressFill.Size = UDim2.new(0, 0, 1, 0)
    progressFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    progressFill.BorderSizePixel = 0
    progressFill.ZIndex = 3
    progressFill.Parent = progressTrack

    local timer = Instance.new("TextLabel")
    timer.Position = UDim2.fromOffset(96, 86)
    timer.Size = UDim2.new(1, -112, 0, 11)
    timer.BackgroundTransparency = 1
    timer.Font = Enum.Font.Gotham
    timer.TextSize = 9
    timer.TextColor3 = Color3.fromRGB(235, 238, 248)
    timer.TextXAlignment = Enum.TextXAlignment.Center
    timer.Text = "0:00 / 0:00"
    timer.ZIndex = 2
    timer.Parent = frame
    MusicState.MiniTimeLabel = timer

    local function miniButton(text, x, width)
        local button = Instance.new("TextButton")
        button.Position = UDim2.fromOffset(x, 98)
        button.Size = UDim2.fromOffset(width, 25)
        button.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        button.BackgroundTransparency = 1
        button.BorderSizePixel = 0
        button.TextColor3 = Color3.fromRGB(255, 255, 255)
        button.Text = text
        button.TextSize = 19
        button.Font = Enum.Font.GothamBold
        button.AutoButtonColor = false
        button.ZIndex = 3
        button.Parent = frame
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = button
        return button
    end

    -- Exactly three transport controls: previous, play/pause, next. No random button.
    local prev = miniButton("◀◀", 128, 30)
    local play = miniButton("Ⅱ", 168, 30)
    local nextBtn = miniButton("▶▶", 208, 30)
    MusicState.MiniPlayButton = play
    prev.Activated:Connect(function() musicRandom(true) end)
    play.Activated:Connect(function()
        if MusicState.IsPlaying and not MusicState.IsPaused then
            musicPause()
        elseif MusicState.IsPaused then
            musicResume()
        elseif MusicState.CurrentTrack and MusicByName[MusicState.CurrentTrack] then
            musicPlay(MusicByName[MusicState.CurrentTrack], MusicState.CurrentTrack)
        else
            musicRandom(false)
        end
    end)
    nextBtn.Activated:Connect(function() musicRandom(true) end)

    -- Working volume slider with speaker icon and draggable/touch input.
    local volumeIcon = Instance.new("TextLabel")
    volumeIcon.Position = UDim2.fromOffset(10, 119)
    volumeIcon.Size = UDim2.fromOffset(14, 13)
    volumeIcon.BackgroundTransparency = 1
    volumeIcon.Text = "🔊"
    volumeIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
    volumeIcon.TextSize = 11
    volumeIcon.ZIndex = 3
    volumeIcon.Parent = frame

    local volumeTrack = Instance.new("Frame")
    volumeTrack.Position = UDim2.fromOffset(28, 124)
    volumeTrack.Size = UDim2.fromOffset(76, 4)
    volumeTrack.BackgroundColor3 = Color3.fromRGB(210, 215, 230)
    volumeTrack.BackgroundTransparency = 0.2
    volumeTrack.BorderSizePixel = 0
    volumeTrack.ZIndex = 3
    volumeTrack.Parent = frame
    local volumeFill = Instance.new("Frame")
    volumeFill.Size = UDim2.new(math.clamp(MusicState.Volume / 10, 0, 1), 0, 1, 0)
    volumeFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    volumeFill.BorderSizePixel = 0
    volumeFill.ZIndex = 4
    volumeFill.Parent = volumeTrack
    local volumeKnob = Instance.new("Frame")
    volumeKnob.AnchorPoint = Vector2.new(0.5, 0.5)
    volumeKnob.Position = UDim2.new(math.clamp(MusicState.Volume / 10, 0, 1), 0, 0.5, 0)
    volumeKnob.Size = UDim2.fromOffset(11, 11)
    volumeKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    volumeKnob.BorderSizePixel = 0
    volumeKnob.ZIndex = 5
    volumeKnob.Parent = volumeTrack
    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = volumeKnob

    local volumeHit = Instance.new("TextButton")
    volumeHit.Position = UDim2.fromOffset(8, 114)
    volumeHit.Size = UDim2.fromOffset(100, 24)
    volumeHit.BackgroundTransparency = 1
    volumeHit.Text = ""
    volumeHit.ZIndex = 6
    volumeHit.Parent = frame
    local changingVolume = false
    local function setVolumeFromX(x)
        local ratio = math.clamp((x - volumeTrack.AbsolutePosition.X) / volumeTrack.AbsoluteSize.X, 0, 1)
        MusicState.Volume = ratio * 10
        if MusicState.Sound then MusicState.Sound.Volume = MusicState.Volume end
        volumeFill.Size = UDim2.new(ratio, 0, 1, 0)
        volumeKnob.Position = UDim2.new(ratio, 0, 0.5, 0)
        volumeIcon.Text = ratio <= 0.01 and "🔇" or (ratio < 0.5 and "🔉" or "🔊")
    end
    volumeHit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            changingVolume = true
            setVolumeFromX(input.Position.X)
        end
    end)
    table.insert(MusicState.MiniConnections, UserInputService.InputChanged:Connect(function(input)
        if changingVolume and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            setVolumeFromX(input.Position.X)
        end
    end))
    table.insert(MusicState.MiniConnections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            changingVolume = false
        end
    end))

    local minimize = Instance.new("TextButton")
    minimize.Position = UDim2.new(1, -30, 0, 5)
    minimize.Size = UDim2.fromOffset(24, 20)
    minimize.BackgroundTransparency = 1
    minimize.Text = "−"
    minimize.TextColor3 = Color3.fromRGB(255, 255, 255)
    minimize.TextSize = 18
    minimize.Font = Enum.Font.GothamBold
    minimize.ZIndex = 7
    minimize.Parent = frame
    minimize.Activated:Connect(function()
        MusicState.MiniExpanded = not MusicState.MiniExpanded
        cover.Visible = MusicState.MiniExpanded
        eqFrame.Visible = MusicState.MiniExpanded
        timer.Visible = MusicState.MiniExpanded
        progressTrack.Visible = MusicState.MiniExpanded
        prev.Visible = MusicState.MiniExpanded
        play.Visible = MusicState.MiniExpanded
        nextBtn.Visible = MusicState.MiniExpanded
        volumeIcon.Visible = MusicState.MiniExpanded
        volumeTrack.Visible = MusicState.MiniExpanded
        volumeHit.Visible = MusicState.MiniExpanded
        title.Position = MusicState.MiniExpanded and UDim2.fromOffset(96, 8) or UDim2.fromOffset(10, 0)
        title.Size = MusicState.MiniExpanded and UDim2.new(1, -108, 0, 22) or UDim2.new(1, -42, 1, 0)
        frame.Size = MusicState.MiniExpanded and UDim2.fromOffset(320, 145) or UDim2.fromOffset(190, 28)
        minimize.Text = MusicState.MiniExpanded and "−" or "+"
    end)

    local dragging, dragStart, startPos = false, nil, nil
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if input.Position.X >= frame.AbsolutePosition.X + frame.AbsoluteSize.X - 32
                and input.Position.Y <= frame.AbsolutePosition.Y + 26 then return end
            if volumeHit:IsDescendantOf(frame) and input.Position.X >= volumeHit.AbsolutePosition.X
                and input.Position.X <= volumeHit.AbsolutePosition.X + volumeHit.AbsoluteSize.X
                and input.Position.Y >= volumeHit.AbsolutePosition.Y
                and input.Position.Y <= volumeHit.AbsolutePosition.Y + volumeHit.AbsoluteSize.Y then return end
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)
    table.insert(MusicState.MiniConnections, UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end))
    table.insert(MusicState.MiniConnections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            MusicState.MiniPosition = frame.Position
        end
    end))

    musicUpdateMini()
    task.spawn(function()
        while gui.Parent and MusicState.MiniGui == gui do
            local snd = MusicState.Sound
            if snd and snd.Parent then
                local active = MusicState.IsPlaying and not MusicState.IsPaused and snd.IsPlaying
                for _, eqBar in ipairs(MusicState.MiniEqBars) do
                    if eqBar.Parent then
                        local target = active and (math.random(20, 100) / 100) or 0.1
                        TweenService:Create(eqBar, TweenInfo.new(active and 0.15 or 0.3, Enum.EasingStyle.Sine), {
                            Size = UDim2.new(0, 3, target, 0)
                        }):Play()
                    end
                end
                local length = snd.TimeLength or 0
                local position = snd.TimePosition or 0
                if progressFill and progressFill.Parent then
                    local ratio = length > 0 and math.clamp(position / length, 0, 1) or 0
                    progressFill.Size = UDim2.new(ratio, 0, 1, 0)
                end
                if MusicState.MiniTimeLabel then
                    MusicState.MiniTimeLabel.Text = musicFormatTime(position) .. " / " .. musicFormatTime(length)
                end
            end
            task.wait(0.15)
        end
    end)
end

local function musicSetMiniEnabled(enabled)
    MusicState.MiniEnabled = enabled and true or false
    if MusicState.MiniEnabled then
        musicBuildMini()
    else
        musicStop()
        musicDisconnectMini()
        if MusicState.MiniGui then
            pcall(function() MusicState.MiniGui:Destroy() end)
        end
        local backgroundSync = _G.TianHubBackgroundSync
        if type(backgroundSync) == "table" and backgroundSync.MiniBackground then
            backgroundSync.MiniBackground = nil
            backgroundSync.MiniOriginal = nil
        end
        MusicState.MiniGui = nil
        MusicState.MiniFrame = nil
        MusicState.MiniTrackLabel = nil
        MusicState.MiniTimeLabel = nil
        MusicState.MiniPlayButton = nil
        MusicState.MiniEqBars = {}
    end
end

local MusicMiniSection = CreateSection("Music", "MINI MUSIC PLAYER", false)
CreateToggle(MusicMiniSection, "SHOW MINI MUSIC GUI", false, musicSetMiniEnabled)

local MusicLibrarySection = CreateSection("Music", "MUSIC LIBRARY", false)
UI.makeNote(MusicLibrarySection, "151 lagu dari library TianHub. Pilih lagu untuk langsung memutarnya.", 30)
local musicDropdown = UI.makeDropdown(MusicLibrarySection, "PILIH LAGU", MusicNames, MusicState.SelectedTrack, function(choice)
    MusicState.SelectedTrack = choice
    local id = MusicByName[choice]
    if id then musicPlay(id, choice) end
end)

local MusicCustomSection = CreateSection("Music", "CUSTOM SOUND ID", false)
UI.makeNote(MusicCustomSection, "Masukkan angka Sound ID Roblox atau format rbxassetid://ID.", 28)
CreateTextBox(MusicCustomSection, "CUSTOM SOUND ID", "Contoh: 1848354536", function(value)
    MusicState.CustomId = value
end)
CreateButton(MusicCustomSection, "PLAY CUSTOM ID", function()
    local id = tostring(MusicState.CustomId or ""):gsub("rbxassetid://", ""):gsub("%D", "")
    if id == "" then musicNotify("Masukkan Sound ID yang valid dulu"); return end
    musicPlay(id, "Custom: " .. id)
end)

local MusicPlaybackSection = CreateSection("Music", "PLAYBACK", false)
CreateButton(MusicPlaybackSection, "PAUSE", musicPause)
CreateButton(MusicPlaybackSection, "RESUME", musicResume)
CreateButton(MusicPlaybackSection, "STOP", musicStop)
CreateButton(MusicPlaybackSection, "NEXT TRACK (RANDOM)", function() musicRandom(true) end)
CreateButton(MusicPlaybackSection, "PREVIOUS / RANDOM TRACK", function() musicRandom(true) end)
CreateButton(MusicPlaybackSection, "REPLAY CURRENT TRACK", function()
    local id = MusicState.CurrentTrack and MusicByName[MusicState.CurrentTrack]
    if id then musicPlay(id, MusicState.CurrentTrack) else musicNotify("Belum ada lagu library yang diputar") end
end)

local MusicSettingsSection = CreateSection("Music", "SOUND SETTINGS", false)
CreateSlider(MusicSettingsSection, "VOLUME", 0, 10, MusicState.Volume, "x", function(value)
    MusicState.Volume = value
    if MusicState.Sound then MusicState.Sound.Volume = value end
end, 1)
CreateToggle(MusicSettingsSection, "LOOP CURRENT TRACK", false, function(value)
    MusicState.Looped = value
    if MusicState.Sound then MusicState.Sound.Looped = value end
end)
CreateToggle(MusicSettingsSection, "AUTO NEXT TRACK", true, function(value)
    MusicState.AutoNext = value
end)

-- Keep the opening track selected for the dropdown and mini player,
-- but do not start playback automatically when the script executes.
-- Playback begins only when the user presses Play or selects a track.
MusicState.SelectedTrack = "Kukira Masih Cinta"
MusicState.CurrentTrack = "Kukira Masih Cinta"
MusicState.IsPlaying = false
MusicState.IsPaused = false
musicUpdateMini()

UI.disableAll = function()
    for _, t in pairs(ToggleRegistry) do
        if t.getState() then t.setState(false, true) end
    end
    for _, conn in pairs(_G.TianConns) do pcall(function() conn:Disconnect() end) end
    _G.TianConns = {}
    ShowToast("Reset Complete", "All features disabled")
end

_G.TianConns = _G.TianConns or {}
local function disconnect(name)
    if _G.TianConns[name] then
        pcall(function() _G.TianConns[name]:Disconnect() end)
        _G.TianConns[name] = nil
    end
end
local function setConn(name, conn)
    disconnect(name)
    _G.TianConns[name] = conn
end

local InfoTab, SurvTab, KillerTab, VisualTab, ConfigTab = "Settings", "Survivor", "Killer", "Visuals", "Settings"
-- TianHub initializes directly; no legacy TianHub splash screen.
task.wait()

local function TianHub_Notify(title, content, duration)
    -- Feature activation notifications are disabled.
end

-- TianHub Fake Perks backend; controls remain inside the TianHub UI.
        -- Integrated Fake Perks backend (no secondary UI window).
        do
            local Players = game:GetService("Players")
            local localPlayer = Players.LocalPlayer
_G.Ox = _G.Ox or {}
_G.Ox.FakePerks = {
    QuickRecoveryEnabled = false,
    PerfectLandingEnabled = false,
    FlowstateEnabled = false,
    FakeAdrenalineRush = false,
    PerkCooldown = 10,
    boostActive = false,
    perfectLandingBoostActive = false,
    fsOnCooldown = false,
    lastQRTime = 0,
    lastPLTime = 0,
    lastFSTime = 0,
    qrConnection = nil,
    plConnection = nil,
    fsConnection = nil,
    fsAnimConnection = nil,
    adrenalineOn = false,
    adrenalineConns = {},
    lastARTime = 0,
}

local FakePerks = _G.Ox.FakePerks

local function isSurvivor()
    local team = localPlayer.Team
    return team ~= nil and team.Name == "Survivors"
end

local function isPlayingVaultAnimation(character)
    if not character then return false end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then return false end

    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        if track.Animation and string.find(tostring(track.Animation.AnimationId), "126081405469607", 1, true) then
            return true
        end
    end
    return false
end

local function startQuickRecoveryBoost(character)
    if not FakePerks.QuickRecoveryEnabled or not isSurvivor() then return end
    if FakePerks.boostActive then return end
    if tick() - FakePerks.lastQRTime < FakePerks.PerkCooldown then return end

    FakePerks.boostActive = true
    FakePerks.lastQRTime = tick()
    local startedAt = tick()

    task.spawn(function()
        while FakePerks.QuickRecoveryEnabled and tick() - startedAt < 3 do
            if character and character.Parent then
                character:SetAttribute("speedboost", 1.4)
            end
            task.wait()
        end
        if character and character.Parent then
            character:SetAttribute("speedboost", 1)
        end
        FakePerks.boostActive = false
    end)
end

local function attachQuickRecovery(character)
    if FakePerks.qrConnection then
        FakePerks.qrConnection:Disconnect()
        FakePerks.qrConnection = nil
    end
    if not character then return end

    FakePerks.qrConnection = character:GetAttributeChangedSignal("isvaulting"):Connect(function()
        if character:GetAttribute("isvaulting") == true then
            task.spawn(function()
                task.wait(0.05)
                local playingVault = isPlayingVaultAnimation(character)
                if not playingVault then
                    task.wait(0.05)
                    playingVault = isPlayingVaultAnimation(character)
                end
                if not playingVault and character:GetAttribute("isvaulting") == true then
                    startQuickRecoveryBoost(character)
                end
            end)
        end
    end)
end

local function toggleQuickRecovery(enabled)
    FakePerks.QuickRecoveryEnabled = enabled
    if enabled and localPlayer.Character then
        attachQuickRecovery(localPlayer.Character)
    elseif not enabled and FakePerks.qrConnection then
        FakePerks.qrConnection:Disconnect()
        FakePerks.qrConnection = nil
    end
    TianHub_Notify("Fake Quick Recovery", enabled and "AKTIF" or "NONAKTIF", 2)
end

local function startPerfectLandingBoost(character)
    if not FakePerks.PerfectLandingEnabled or not isSurvivor() then return end
    if FakePerks.perfectLandingBoostActive then return end
    if tick() - FakePerks.lastPLTime < FakePerks.PerkCooldown then return end

    FakePerks.perfectLandingBoostActive = true
    FakePerks.lastPLTime = tick()
    local startedAt = tick()
    task.spawn(function()
        while FakePerks.perfectLandingBoostActive and tick() - startedAt < 3 do
            if character and character.Parent then
                character:SetAttribute("speedboost", 1.4)
            end
            task.wait()
        end
        if character and character.Parent then
            character:SetAttribute("speedboost", 1)
        end
        FakePerks.perfectLandingBoostActive = false
    end)
end

local function attachPerfectLanding(character)
    if FakePerks.plConnection then
        FakePerks.plConnection:Disconnect()
        FakePerks.plConnection = nil
    end
    if not character then return end

    FakePerks.plConnection = character:GetAttributeChangedSignal("speedboost"):Connect(function()
        if not isSurvivor() then return end
        if character:GetAttribute("speedboost") == 0.625 then
            startPerfectLandingBoost(character)
        end
    end)
end

local function togglePerfectLanding(enabled)
    FakePerks.PerfectLandingEnabled = enabled
    if enabled then
        if localPlayer.Character then attachPerfectLanding(localPlayer.Character) end
    else
        if FakePerks.plConnection then
            FakePerks.plConnection:Disconnect()
            FakePerks.plConnection = nil
        end
        if FakePerks.perfectLandingBoostActive and localPlayer.Character then
            localPlayer.Character:SetAttribute("speedboost", 1)
            FakePerks.perfectLandingBoostActive = false
        end
    end
    TianHub_Notify("Fake Perfect Landing", enabled and "AKTIF" or "NONAKTIF", 2)
end

local function attachFlowstate(character)
    if FakePerks.fsConnection then
        FakePerks.fsConnection:Disconnect()
        FakePerks.fsConnection = nil
    end
    if FakePerks.fsAnimConnection then
        FakePerks.fsAnimConnection:Disconnect()
        FakePerks.fsAnimConnection = nil
    end
    if not character then return end

    local humanoid = character:WaitForChild("Humanoid", 3)
    if not humanoid then return end
    local animator = humanoid:WaitForChild("Animator", 3)
    if not animator then return end

    FakePerks.fsAnimConnection = animator.AnimationPlayed:Connect(function(track)
        if not track.Animation or track.Animation.AnimationId ~= "rbxassetid://136962284480779" then return end
        local stoppedConnection
        stoppedConnection = track.Stopped:Connect(function()
            if stoppedConnection then stoppedConnection:Disconnect() end
            FakePerks.lastFSTime = tick()
            FakePerks.fsOnCooldown = true
            if character and character.Parent then
                character:SetAttribute("Flowstate", false)
            end
            task.delay(FakePerks.PerkCooldown, function()
                FakePerks.fsOnCooldown = false
                if FakePerks.FlowstateEnabled and character and character.Parent then
                    character:SetAttribute("Flowstate", true)
                end
            end)
        end)
    end)

    FakePerks.fsConnection = character:GetAttributeChangedSignal("Flowstate"):Connect(function()
        if not FakePerks.FlowstateEnabled or not isSurvivor() then return end
        local value = character:GetAttribute("Flowstate")
        if value == true then
            if FakePerks.fsOnCooldown or tick() - FakePerks.lastFSTime < FakePerks.PerkCooldown then
                character:SetAttribute("Flowstate", false)
            end
        elseif value == false and not FakePerks.fsOnCooldown then
            if FakePerks.PerkCooldown <= tick() - FakePerks.lastFSTime then
                character:SetAttribute("Flowstate", true)
            end
        end
    end)

    task.wait(0.5)
    if FakePerks.FlowstateEnabled and character and character.Parent then
        character:SetAttribute("Flowstate", true)
    end
end

local function toggleFlowstate(enabled)
    FakePerks.FlowstateEnabled = enabled
    if enabled then
        if localPlayer.Character then attachFlowstate(localPlayer.Character) end
    else
        if FakePerks.fsConnection then
            FakePerks.fsConnection:Disconnect()
            FakePerks.fsConnection = nil
        end
        if FakePerks.fsAnimConnection then
            FakePerks.fsAnimConnection:Disconnect()
            FakePerks.fsAnimConnection = nil
        end
        if localPlayer.Character then
            localPlayer.Character:SetAttribute("Flowstate", false)
        end
    end
    TianHub_Notify("Fake Flowstate", enabled and "AKTIF" or "NONAKTIF", 2)
end

local function clearAdrenalineConnections()
    for _, connection in ipairs(FakePerks.adrenalineConns or {}) do
        pcall(function() connection:Disconnect() end)
    end
    FakePerks.adrenalineConns = {}
end

local function startAdrenalineRush(character)
    if not FakePerks.FakeAdrenalineRush or not isSurvivor() then return end
    if not character or not character.Parent or FakePerks.boostActive then return end
    if tick() - (FakePerks.lastARTime or 0) < FakePerks.PerkCooldown then return end

    FakePerks.boostActive = true
    FakePerks.lastARTime = tick()
    local startedAt = tick()
    task.spawn(function()
        while FakePerks.FakeAdrenalineRush and tick() - startedAt < 5 do
            if character and character.Parent then
                character:SetAttribute("speedboost", 1.4)
            end
            task.wait()
        end
        if character and character.Parent then
            character:SetAttribute("speedboost", 1)
        end
        FakePerks.boostActive = false
    end)
end

local function attachAdrenalineRush(character)
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
    if not humanoid then return end
    local previousHealth = humanoid.Health

    table.insert(FakePerks.adrenalineConns, humanoid.HealthChanged:Connect(function(newHealth)
        if not FakePerks.FakeAdrenalineRush then return end
        if newHealth < previousHealth and newHealth <= 50 and newHealth > 0 then
            startAdrenalineRush(character)
        end
        previousHealth = newHealth
    end))
end

local function toggleAdrenalineRush(enabled)
    FakePerks.FakeAdrenalineRush = enabled == true
    FakePerks.adrenalineOn = enabled == true
    clearAdrenalineConnections()

    if not enabled then
        TianHub_Notify("Fake Perks", "Adrenaline Rush OFF", 2)
        return
    end

    attachAdrenalineRush(localPlayer.Character)
    TianHub_Notify("Fake Perks", "Adrenaline Rush ON", 3)
end

-- Restore listeners after respawn while each related toggle remains enabled.
local respawnConnection = localPlayer.CharacterAdded:Connect(function(character)
    task.wait(0.5)
    if FakePerks.QuickRecoveryEnabled then attachQuickRecovery(character) end
    if FakePerks.PerfectLandingEnabled then attachPerfectLanding(character) end
    if FakePerks.FlowstateEnabled then attachFlowstate(character) end
    if FakePerks.FakeAdrenalineRush then attachAdrenalineRush(character) end
end)


            _G.TianHub_FakePerks = {
                SetQuickRecovery = toggleQuickRecovery,
                SetPerfectLanding = togglePerfectLanding,
                SetFlowstate = toggleFlowstate,
                SetAdrenalineRush = toggleAdrenalineRush,
                SetCooldown = function(value) FakePerks.PerkCooldown = math.max(0, tonumber(value) or 10) end,
            }
        end


for k, v in pairs({
    AutoParry = false,
    ShowFloatingButton = false,
}) do TianHubState[k] = v end


local function TianHub_IsKiller(plr)
    return plr and plr.Team and plr.Team.Name == "Killer"
end



TianHubState.LastVault = 0
pcall(function()
    local function watch(char)
        if not char then return end
        char:GetAttributeChangedSignal("__VaultFireCount"):Connect(function() TianHubState.LastVault = os.clock() end)
    end
    watch(LocalPlayer.Character)
    LocalPlayer.CharacterAdded:Connect(watch)
    local r = ReplicatedStorage:FindFirstChild("Remotes")
    local w = r and r:FindFirstChild("Window")
    local vb = w and w:FindFirstChild("Vaultbindable")
    if vb and vb:IsA("BindableEvent") then vb.Event:Connect(function() TianHubState.LastVault = os.clock() end) end
end)

TianHubState.IsLocked = function() return os.clock() < (TianHubState.ParryReadyAt or 0) end


TianHubState.CreateDropdown = function(parent, name, options, default, callback, optionImageResolver)
    flushLabel(parent, name)
    local ctl = UI.makeDropdown(parent, name, options, default, function(v)
        if callback then pcall(callback, v) end
    end, optionImageResolver)
    UI.controls[ctlKey(parent, name)] = ctl
    return {
        Button = ctl.Holder,
        Set = function(v) ctl.Set(v, false) end,
        Get = ctl.Get,
    }
end

-- Pasang aset ikon ke ImageLabel (dipakai billboard). Gunakan fallback jika provider ikon belum termuat.
TianHubState.ApplyIconAssets = function(img, name, fallbackAsset)
    local info = UI.resolveIcon and UI.resolveIcon(name)
    if info then
        img.Image = info.Url
        img.ImageRectSize = info.ImageRectSize or Vector2.new(0, 0)
        img.ImageRectOffset = info.ImageRectOffset or Vector2.new(0, 0)
        return true
    end
    if fallbackAsset then
        img.Image = fallbackAsset
        img.ImageRectSize = Vector2.new(0, 0)
        img.ImageRectOffset = Vector2.new(0, 0)
        return true
    end
    return false
end

TianHubState.MakeFloat = function(name, label, pos, onTap, round, customSize)
    local old = ScreenGui:FindFirstChild(name)
    if old then pcall(function() old:Destroy() end) end
    local f = Instance.new("Frame")
    f.Name = name
    f.Parent = ScreenGui
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Position = pos
    f.Size = customSize or (round and UDim2.fromOffset(58, 58) or UDim2.fromOffset(118, 40))
    f.BackgroundColor3 = round and Color3.fromRGB(24, 24, 27) or Color3.fromRGB(20, 20, 23)
    f.BackgroundTransparency = round and 0.06 or 0.04
    f.BorderSizePixel = 0
    f.ZIndex = 150
    f.Active = true
    corner(f, round and 32 or 12)
    local st = Instance.new("UIStroke", f)
    st.Color = round and Color3.fromRGB(225, 225, 235) or Color3.fromRGB(105, 105, 115)
    st.Thickness = round and 1.7 or 1.2
    st.Transparency = round and 0.18 or 0.12

    local text = Instance.new("TextLabel")
    text.Parent = f
    text.BackgroundTransparency = 1
    text.Font = Enum.Font.GothamBold
    text.TextColor3 = Color3.fromRGB(255, 255, 255)
    text.TextScaled = true
    text.TextWrapped = false
    text.ZIndex = 151
    local tc = Instance.new("UITextSizeConstraint", text)
    tc.MaxTextSize = round and 20 or 14
    tc.MinTextSize = 10
    if round then
        text.Position = UDim2.fromOffset(4, 4)
        text.Size = UDim2.new(1, -8, 1, -8)
    else
        text.TextXAlignment = Enum.TextXAlignment.Left
        text.TextYAlignment = Enum.TextYAlignment.Center
    end

    local badge
    if not round then
        badge = Instance.new("TextLabel")
        badge.Parent = f
        badge.BackgroundTransparency = 1
        badge.Font = Enum.Font.GothamBold
        badge.TextSize = 11
        badge.ZIndex = 151
        badge.AnchorPoint = Vector2.new(1, 0.5)
        badge.Position = UDim2.new(1, -9, 0.5, 0)
        badge.Size = UDim2.fromOffset(40, 20)
        badge.TextXAlignment = Enum.TextXAlignment.Right
    end

    local function titleCase(t)
        return (t:lower():gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
    end
    local function apply(t)
        local base, stt = t:match("^(.-)%s+(ON)$")
        if not base then base, stt = t:match("^(.-)%s+(OFF)$") end
        if round then
            text.Text = string.upper(base or t)
            if stt then
                local on = stt == "ON"
                st.Transparency = on and 0 or 0.6
                st.Thickness = on and 2.2 or 1.5
                text.TextColor3 = on and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(165, 165, 165)
            end
        else
            text.Text = titleCase(base or t)
            if stt then
                badge.Visible = true
                badge.Text = "[" .. stt .. "]"
                badge.TextColor3 = (stt == "ON") and Color3.fromRGB(245, 245, 245) or Color3.fromRGB(105, 105, 112)
                text.Position = UDim2.fromOffset(11, 0)
                text.Size = UDim2.new(1, -56, 1, 0)
            else
                badge.Visible = false
                text.Position = UDim2.fromOffset(11, 0)
                text.Size = UDim2.new(1, -22, 1, 0)
            end
        end
    end
    apply(label)

    local conns, active, moved, startPos, startMouse = {}, nil, false, nil, nil
    local function isMouse(i) return i.UserInputType == Enum.UserInputType.MouseButton1 end
    conns[#conns + 1] = f.InputBegan:Connect(function(input)
        if active then return end
        if isMouse(input) or input.UserInputType == Enum.UserInputType.Touch then
            active, moved = input, false
            startPos, startMouse = f.Position, input.Position
        end
    end)
    conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
        if not active then return end
        local mine = (input == active) or (isMouse(active) and input.UserInputType == Enum.UserInputType.MouseMovement)
        if not mine then return end
        local d = input.Position - startMouse
        if d.Magnitude > 8 then moved = true end
        if moved then
            f.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
        if not active then return end
        if input == active or (isMouse(active) and isMouse(input)) then
            active = nil
            if not moved and onTap then pcall(onTap) end
        end
    end)

    return {
        Destroy = function()
            for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
            pcall(function() f:Destroy() end)
        end,
        SetText = function(t) apply(t) end,
    }
end

-- ============================================================
-- TIAN HUB AUTO PARRY V2
-- Animation tracking + ParryClient hook + fallback GUI/tool
-- Floating mobile button + CylinderHandleAdornment range circle
-- ============================================================
local AP
do
    local W = getgenv()
    local rawSpawn = task.spawn
    local CollectionService = game:GetService("CollectionService")
    local ProximityPromptService = game:GetService("ProximityPromptService")


    AP = {
        Enabled = false,
        Range = 14,
        FaceSensitivity = 10,
        AggressiveMode = false,
        CircleVisible = false,
        RangeColor = Color3.fromRGB(255, 255, 255),
        Distance = 15,
        FaceBias = 10,
    }
    W.TianHub_AutoParry = AP


    local AttackSkip = {
        ["106871536134254"] = false,
        ["117070354890871"] = false,
        ["73681849513551"]  = false,
        ["100014992013740"] = false,
    }
    AP.AttackSkip = AttackSkip


    local LUNGE_IDS = {}
    for _, id in ipairs({
        "71008020992570","72742711718023","72908958549833","73923929500477","74968262036854",
        "75857500533792","76385865186777","76503974441748","77081789642514","78432063483146",
        "78935059863801","79935565590141","79965656177566","80411309607666","82666958311998",
        "83873880822918","84525330720658","85030641905220","89185525343404","92125118598365",
        "92362656727126","92554564590253","96839438835309","99472251587670","102055678391920",
        "104689417033027","105374834496520","109402730355822","111920872708571","112166042383605",
        "112633191985365","112840768179724","113255068724446","115244153053858","117042998468241",
        "117207742458428","118907603246885","119752564209631","121216847022485","121571390309073",
        "122812055447896","123047897844134","123812278891591","124706657239027","124735239320776",
        "125224839697689","126081405469607","126497551689502","126527634689050","126626340093785",
        "126751859125353","128241974219045","129784271201071","130012819736632","130585295123651",
        "130593238885843","132817836308238","133002120549396","133881825716964","133963973694098",
        "134838390519433","135002183282873","135403091566760","135727476735024","136365031119137",
        "137504605181913","137688077908355","137795837089724","137846825408335","138045669415653",
        "138720291317243","117187218825161","105221485497534","86868198964957","134758728973154",
        "132636403911470","125350153877085","2874840706","110850539331763","72042024",
        "139369275981139","113691709436161","129626174716003","75618342544502","93902163029544",
        "79310600168078","104540716539347","101636125032002","125430111937587","81963230963908",
        "84926129581106","83333467665074","127417297154354",
    }) do LUNGE_IDS[id] = true end


    local SKIP_IDS = {}
    for _, id in ipairs({
        "86266790353635","84093948968516","102746205979822","99210996402874","121108316060822",
        "109928123357793","110466971021611","110355011987939","135181748009911","77210283630654",
        "108211560927158","104192089592095","109257644640676","98163597193511","111223305405046",
        "75258958842388","93136435416899","92098503722633","117886494230451",
    }) do SKIP_IDS[id] = true end


    local SPECIAL_NAMES = {
        ["101443662521580"] = "Veil Spear Throw 1",
        ["127622545856523"] = "Veil Spear Throw 2",
        ["76744850905644"]  = "Myers Grab",
        ["71001061734896"]  = "Take Out Spear",
        ["129669521834246"] = "Put Away Spear",
    }
    local DEFAULT_ATTACKS = {
        ["106871536134254"] = {Name = "Masked Alex Attack", Default = true},
        ["117070354890871"] = {Name = "Masked Alex Lunge",  Default = true},
        ["73681849513551"]  = {Name = "Hidden Dash",        Default = true},
        ["100014992013740"] = {Name = "Abysswalker Slash",  Default = true},
    }


    local state = {
        LastAttempt = 0, LastSuccess = 0,
        SeenAnimators = setmetatable({}, {__mode = "k"}),
        SeenModels = setmetatable({}, {__mode = "k"}),
        ActiveClient = nil, ClientModule = nil, ClientHooked = false,
        WarnedFallback = false, LastGcScan = 0,
    }
    local Connections = {}
    local function addConn(c) table.insert(Connections, c); return c end


    local prompt = { HoldingPrompt = false, HoldSince = 0, UntilTime = 0 }
    addConn(ProximityPromptService.PromptButtonHoldBegan:Connect(function(_, plr)
        if plr == LocalPlayer then prompt.HoldingPrompt = true; prompt.HoldSince = tick() end
    end))
    addConn(ProximityPromptService.PromptButtonHoldEnded:Connect(function(_, plr)
        if plr == LocalPlayer then
            prompt.HoldingPrompt = false
            prompt.UntilTime = math.max(prompt.UntilTime, tick() + 0.35)
        end
    end))
    addConn(ProximityPromptService.PromptTriggered:Connect(function(_, plr)
        if plr == LocalPlayer then
            prompt.HoldingPrompt = false
            prompt.UntilTime = tick() + 1.2
        end
    end))


    local function checkFace(killerHRP, myHRP)
        if AP.AggressiveMode then return true end
        if not killerHRP or not myHRP then return false end
        local delta = myHRP.Position - killerHRP.Position
        if delta.Magnitude <= 0.001 then return true end
        local angle = 15 + math.clamp(tonumber(AP.FaceSensitivity) or 10, 0, 10) / 10 * 75
        return killerHRP.CFrame.LookVector:Dot(delta.Unit) >= math.cos(math.rad(angle))
    end


    local function checkRange(killerHRP, myHRP, tPos, vel)
        if not killerHRP or not myHRP then return false end
        local dist = ((tPos or killerHRP.Position) - myHRP.Position).Magnitude
        local maxRange = math.clamp(tonumber(AP.Range) or 14, 5, 35)
        if dist > maxRange and not tPos then
            local extend = 0
            pcall(function()
                local delta = myHRP.Position - killerHRP.Position
                if delta.Magnitude > 0.01 then
                    local unit = delta.Unit
                    local vel1 = killerHRP.AssemblyLinearVelocity or Vector3.zero
                    if vel and vel.Magnitude > vel1.Magnitude then vel1 = vel end
                    local vel2 = myHRP.AssemblyLinearVelocity or Vector3.zero
                    local closing = math.max(0, vel1:Dot(unit) - vel2:Dot(unit))
                    local ping = 0.05
                    local ok, p = pcall(function() return LocalPlayer:GetNetworkPing() end)
                    if ok and type(p) == "number" then ping = p end
                    extend = math.clamp(closing * (ping * 2 + 0.16), 0, 26)
                end
            end)
            maxRange = maxRange + extend
        end
        if dist > maxRange then return false end
        return checkFace(killerHRP, myHRP)
    end


    local function hasParryTool()
        local char = LocalPlayer.Character
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        local equipped = tostring(LocalPlayer:GetAttribute("EquippedItem") or ""):lower()
        if equipped:find("parry") or equipped:find("dagger") then
            if char then
                local t = char:FindFirstChild("Parrying Dagger") or char:FindFirstChild("Parry Dagger")
                if t then return t end
            end
            if backpack then
                local t = backpack:FindFirstChild("Parrying Dagger") or backpack:FindFirstChild("Parry Dagger")
                if t then return t end
            end
            return true
        end
        local containers = {}
        if char then table.insert(containers, char) end
        if backpack then table.insert(containers, backpack) end
        for _, c in ipairs(containers) do
            for _, child in ipairs(c:GetChildren()) do
                local n = child.Name:lower()
                if n:find("parry") or n:find("dagger") then return child end
            end
        end
        return nil
    end


    local function getClient()
        local function isValid(c)
            return type(c) == "table" and type(c.Parry) == "function" and c.tool and c.tool.Parent
        end
        if isValid(state.ActiveClient) then return state.ActiveClient end
        if isValid(_G.TianHub_ActiveParryClient) then state.ActiveClient = _G.TianHub_ActiveParryClient; return state.ActiveClient end
        if not state.ClientModule then
            pcall(function()
                local M = ReplicatedStorage:FindFirstChild("Modules")
                local I = M and M:FindFirstChild("Items")
                local P = I and I:FindFirstChild("ParryingDagger")
                local PC = P and P:FindFirstChild("ParryClient")
                if PC then state.ClientModule = require(PC) end
            end)
        end
        if type(state.ClientModule) == "table" and not state.ClientHooked then
            state.ClientHooked = true
            pcall(function()
                local origNew = state.ClientModule.new
                if type(origNew) == "function" then
                    state.ClientModule.new = function(...)
                        local c = origNew(...)
                        state.ActiveClient = c
                        _G.TianHub_ActiveParryClient = c
                        return c
                    end
                end
            end)
        end
        if typeof(getgc) == "function" and tick() - state.LastGcScan > 3 then
            state.LastGcScan = tick()
            local ok, gc = pcall(getgc, true)
            if ok and type(gc) == "table" then
                for _, c in ipairs(gc) do
                    if type(c) == "table" and type(c.Parry) == "function" and c.tool and c.tool.Parent then
                        if getmetatable(c) == state.ClientModule or rawget(c, "parryEvent") or rawget(c, "daggerFolder") or rawget(c, "tool") then
                            state.ActiveClient = c
                            _G.TianHub_ActiveParryClient = c
                                return c
                        end
                    end
                end
            end
        end
        return nil
    end


    local function doFallback()
        local fired = false
        pcall(function()
            local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            local mob = pg and (pg:FindFirstChild("Survivor-mob") or pg:FindFirstChild("Survivor"))
            local ctrl = mob and mob:FindFirstChild("Controls")
            local btn = ctrl and (ctrl:FindFirstChild("Gui-mob") or ctrl:FindFirstChild("action"))
            if btn then
                if typeof(firesignal) == "function" then
                    pcall(function() firesignal(btn.MouseButton1Down) end)
                    task.defer(function() pcall(function() firesignal(btn.MouseButton1Up) end) end)
                    fired = true
                end
                if typeof(getconnections) == "function" then
                    local ok, conns = pcall(function() return getconnections(btn.MouseButton1Down) end)
                    if ok and type(conns) == "table" then
                        for _, c in ipairs(conns) do pcall(function() c:Fire(); fired = true end) end
                    end
                    local ok1, conns1 = pcall(function() return getconnections(btn.MouseButton1Up) end)
                    if ok1 and type(conns1) == "table" then
                        task.defer(function() for _, c in ipairs(conns1) do pcall(function() c:Fire() end) end end)
                    end
                end
            end
        end)
        local tool = hasParryTool()
        if typeof(tool) == "Instance" and tool:IsA("Tool") then
            pcall(function() tool:Activate(); fired = true end)
        end
        return fired
    end


    local function autoroateGuard()
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum then return nil end
        local orig = hum.AutoRotate
        pcall(function() hum.AutoRotate = false end)
        local done = false
        return function()
            if done then return end
            done = true
            task.delay(0.04, function()
                if hum and hum.Parent and char == LocalPlayer.Character then
                    pcall(function() hum.AutoRotate = orig end)
                end
            end)
        end
    end


    local ACTION_KEYWORDS = {"repair","generator","unhook","hooking","rescu","gate","vault","pallet","dropping","interact","opening"}
    local ANIM_KEYWORDS   = {"repair","generator","unhook","rescue","hook","gate","exit","vault","window","pallet","drop"}


    local function hasBlockingAttr(inst)
        local ok, attrs = pcall(function() return inst:GetAttributes() end)
        if not ok or type(attrs) ~= "table" then return false end
        for k, v in pairs(attrs) do
            if v == true then
                local n = string.lower(tostring(k))
                if not (n:find("^can") or n:find("^has") or n:find("^allow")) then
                    for _, kw in ipairs(ACTION_KEYWORDS) do
                        if n:find(kw, 1, true) then return true end
                    end
                end
            end
        end
        return false
    end


    local function isDoingAction()
        local t = tick()
        if t < prompt.UntilTime then return true end
        if prompt.HoldingPrompt and t - prompt.HoldSince < 15 then return true end
        local char = LocalPlayer.Character
        if not char then return false end
        if hasBlockingAttr(char) or hasBlockingAttr(LocalPlayer) then return true end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local animator = hum and hum:FindFirstChildOfClass("Animator")
        if animator then
            local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
            if ok and tracks then
                for _, track in ipairs(tracks) do
                    local s = ""
                    pcall(function()
                        local p = track.Priority
                        if p == Enum.AnimationPriority.Action or p == Enum.AnimationPriority.Action2
                            or p == Enum.AnimationPriority.Action3 or p == Enum.AnimationPriority.Action4 then
                            s = string.lower(tostring(track.Name) .. " " .. tostring(track.Animation and track.Animation.Name or ""))
                        end
                    end)
                    if s ~= "" and not s:find("parry", 1, true) and not s:find("dagger", 1, true) then
                        for _, kw in ipairs(ANIM_KEYWORDS) do
                            if s:find(kw, 1, true) then return true end
                        end
                    end
                end
            end
        end
        return false
    end


    local function tryParry(reason)
        if AP.Enabled ~= true then return false end
        if tick() - state.LastAttempt < 0.012 then return false end
        if not hasParryTool() then return false end
        if isDoingAction() then return false end
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not char or not hum or hum.Health <= 0 then return false end
        if char:GetAttribute("Knocked") or LocalPlayer:GetAttribute("Knocked")
            or char:GetAttribute("IsHooked") or LocalPlayer:GetAttribute("IsHooked")
            or char:GetAttribute("IsCarried") or LocalPlayer:GetAttribute("IsCarried")
            or char:GetAttribute("IsDead") or LocalPlayer:GetAttribute("IsDead") then return false end
        local client = getClient()
        if client and (client.isParryOnCooldown or client.isParryResolving) then return false end
        if tick() - state.LastSuccess < 0.1 then return false end
        state.LastAttempt = tick()
        local restore = autoroateGuard()
        if client then
            local ok, result = pcall(function()
                if client.character ~= char and type(client._bindCharacter) == "function" then
                    pcall(function() client:_bindCharacter(char) end)
                end
                return client:Parry()
            end)
            if ok and result ~= false then
                state.LastSuccess = tick()
                if restore then restore() end
                return true
            end
            if restore then restore() end
            return false
        end
        local ok2, result2 = pcall(doFallback)
        if ok2 and result2 then
            state.LastSuccess = tick()
            if restore then restore() end
            if not state.WarnedFallback then
                state.WarnedFallback = true
                warn("[TIAN HUB AUTO PARRY V2] GUI/tool fallback activated")
            end
            return true
        end
        if restore then restore() end
        if not state.WarnedFallback then
            state.WarnedFallback = true
            warn("[TIAN HUB AUTO PARRY V2] Attack detected, no ParryClient available")
        end
        return false
    end


    local function handleAnim(track, char)
        if not AP.Enabled or not track or not char or not char.Parent then return end
        local id = ""
        pcall(function() id = tostring(track.Animation.AnimationId):match("%d+") or "" end)
        if id == "" then return end
        if SKIP_IDS[id] then return end
        if SPECIAL_NAMES[id] then return end
        if string.lower(tostring(char.Name or "")):find("veil", 1, true) then
            local n1, n2 = "", ""
            pcall(function() n1 = string.lower(tostring(track.Name or "")) end)
            pcall(function() n2 = string.lower(tostring(track.Animation and track.Animation.Name or "")) end)
            local s = n1 .. " " .. n2
            if s:find("spear", 1, true) or s:find("throw", 1, true) or s:find("charge", 1, true) then return end
        end
        local def = DEFAULT_ATTACKS[id]
        if def and AttackSkip[id] == true then return end
        if LUNGE_IDS[id] ~= true and (def == nil or def.Default ~= true) then return end
        local ok, timePos = pcall(function() return track.TimePosition or 0 end)
        if ok and timePos > 0.55 then return end
        -- raw spawn: per-anim thread, tidak ikut tracker utama (short-lived)
        rawSpawn(function()
            local startT = tick()
            local lastPos, lastT, velEst
            while AP.Enabled and track.IsPlaying do
                local tp = 0
                pcall(function() tp = track.TimePosition or 0 end)
                if tp > 0.55 then break end
                local myChar = LocalPlayer.Character
                local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
                local kHRP = char:FindFirstChild("HumanoidRootPart")
                if kHRP then
                    local now = tick()
                    local pos = kHRP.Position
                    if lastPos and now > lastT then
                        local v = (pos - lastPos) / (now - lastT)
                        velEst = velEst and velEst * 0.5 + v * 0.5 or v
                    end
                    lastPos, lastT = pos, now
                end
                if myHRP and kHRP and checkRange(kHRP, myHRP, nil, velEst) then
                    if tryParry("anim:" .. id) then return end
                end
                RunService.Heartbeat:Wait()
                if tick() - startT >= 0.60 then break end
            end
        end)
    end


    local function hookAnimator(animator, char)
        if not animator or state.SeenAnimators[animator] then return end
        state.SeenAnimators[animator] = true
        local ok, conn = pcall(function()
            return animator.AnimationPlayed:Connect(function(track)
                pcall(handleAnim, track, char)
            end)
        end)
        if ok and conn then addConn(conn) end
        pcall(function()
            for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
                rawSpawn(handleAnim, t, char)
            end
        end)
    end


    local function hookCharacter(char)
        if not char or state.SeenModels[char] then return end
        state.SeenModels[char] = true
        local function bind(inst)
            if inst:IsA("Humanoid") then
                local animator = inst:FindFirstChildOfClass("Animator")
                if animator then hookAnimator(animator, char) end
                addConn(inst.ChildAdded:Connect(function(c)
                    if c:IsA("Animator") then hookAnimator(c, char) end
                end))
            end
        end
        for _, c in ipairs(char:GetChildren()) do pcall(bind, c) end
        addConn(char.ChildAdded:Connect(function(c) pcall(bind, c) end))
    end


    local function isKillerChar(char)
        if not char or not char:IsA("Model") or char == LocalPlayer.Character then return false end
        if not char:FindFirstChildOfClass("Humanoid") or not char:FindFirstChild("HumanoidRootPart") then return false end
        local plr = Players:GetPlayerFromCharacter(char)
        if plr == LocalPlayer then return false end
        local function chk(inst)
            return inst and (inst:GetAttribute("Role") == "Killer" or inst:GetAttribute("IsKiller") == true)
        end
        if chk(char) or chk(plr) then return true end
        if plr and plr.Team then
            local t = plr.Team.Name:lower()
            if t:find("killer") or t:find("slasher") or t:find("hunter") or t:find("monster") then return true end
            if not t:find("survivor") and not t:find("lobby") and not t:find("spectat") then return true end
        end
        local K = workspace:FindFirstChild("Killers")
        if K and char:IsDescendantOf(K) then return true end
        local n = char.Name:lower()
        for _, kw in ipairs({"zombie","slasher","monster","killer","veil","stalker","masked","abysswalker","hunter"}) do
            if n:find(kw, 1, true) then return true end
        end
        return false
    end


    local function getAllKillers()
        local list, seen = {}, {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                local c = p.Character
                if c and not seen[c] and isKillerChar(c) then
                    seen[c] = true
                    table.insert(list, c)
                end
            end
        end
        local K = workspace:FindFirstChild("Killers")
        if K then
            for _, d in ipairs(K:GetDescendants()) do
                if d:IsA("Model") and not seen[d] and isKillerChar(d) then
                    seen[d] = true
                    table.insert(list, d)
                end
            end
        end
        for _, c in ipairs(workspace:GetChildren()) do
            if c:IsA("Model") and not seen[c] and isKillerChar(c) then
                seen[c] = true
                table.insert(list, c)
            end
        end
        return list
    end


    addConn(task.spawn(function()
        while true do
            if AP.Enabled then
                for _, k in ipairs(getAllKillers()) do pcall(hookCharacter, k) end
                task.wait(0.1)
            else
                task.wait(0.35)
            end
        end
    end))


    addConn(Players.PlayerAdded:Connect(function(player)
        if player == LocalPlayer then return end
        addConn(player.CharacterAdded:Connect(function(char)
            task.defer(function()
                if char and isKillerChar(char) then hookCharacter(char) end
            end)
        end))
    end))


    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            addConn(p.CharacterAdded:Connect(function(char)
                task.defer(function()
                    if char and isKillerChar(char) then hookCharacter(char) end
                end)
            end))
        end
    end


    -- Range circle: segmented neon ring (visual-only; Auto Parry logic unchanged)
    local ringFolder
    local ringSegments = {}
    local RING_SEGMENTS = 96
    local RING_ALPHA = 0.2
    local RING_THICK = 0.3
    local RING_HEIGHT = 0.1

    local function cleanupRing()
        for _, segment in ipairs(ringSegments) do
            pcall(function() segment:Destroy() end)
        end
        ringSegments = {}
        if ringFolder then
            pcall(function() ringFolder:Destroy() end)
            ringFolder = nil
        end
    end

    local function ensureRing()
        if #ringSegments == RING_SEGMENTS and ringFolder and ringFolder.Parent then return end
        cleanupRing()
        ringFolder = Instance.new("Folder")
        ringFolder.Name = "TIANHUB_ParryCircleVisual"
        ringFolder.Parent = workspace

        for i = 1, RING_SEGMENTS do
            local segment = Instance.new("Part")
            segment.Name = "ParryRingSegment" .. i
            segment.Anchored = true
            segment.CanCollide = false
            segment.CanTouch = false
            segment.CanQuery = false
            segment.CastShadow = false
            segment.Material = Enum.Material.Neon
            segment.Color = Color3.fromRGB(168, 85, 247)
            segment.Transparency = RING_ALPHA
            segment.Size = Vector3.new(RING_THICK, RING_HEIGHT, 1)
            segment.Parent = ringFolder
            ringSegments[i] = segment
        end
    end

    local function updateRing(center, range)
        local segmentLength = (2 * math.pi * range / RING_SEGMENTS) * 1.05
        for i, segment in ipairs(ringSegments) do
            local theta = (i - 1) / RING_SEGMENTS * math.pi * 2
            segment.Size = Vector3.new(RING_THICK, RING_HEIGHT, segmentLength)
            segment.CFrame = CFrame.new(center)
                * CFrame.Angles(0, theta, 0)
                * CFrame.new(range, 0, 0)
        end
    end

    addConn(RunService.Heartbeat:Connect(function()
        local myChar = LocalPlayer.Character
        local hrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not AP.Enabled or not AP.CircleVisible or not hrp then
            cleanupRing()
            return
        end

        ensureRing()
        local range = math.clamp(tonumber(AP.Range) or 14, 5, 35)
        local center = hrp.Position + Vector3.new(0, -2.8, 0)
        updateRing(center, range)
    end))

    -- TIAN HUB UI adapter: expose only controls belonging to the new engine.
    function AP.SetEnabled(value)
        AP.Enabled = value == true
        TianHubState.AutoParry = AP.Enabled
    end
    function AP.SetRange(value)
        AP.Range = math.clamp(tonumber(value) or 14, 5, 35)
    end
    function AP.SetRangeESP(value)
        AP.CircleVisible = value == true
    end
    function AP.SetFaceSensitivity(value)
        AP.FaceSensitivity = math.clamp(tonumber(value) or 10, 0, 10)
    end
    function AP.SetAggressiveMode(value)
        AP.AggressiveMode = value == true
    end

    -- Lifecycle-only recovery: invalidate a cached ParryClient when the local
    -- character/tool changes (for example, lobby -> match). The parry detector,
    -- timing, range checks and Parry() call above remain unchanged.
    function AP.ResetClientCache()
        state.ActiveClient = nil
        _G.TianHub_ActiveParryClient = nil
        state.LastGcScan = 0
    end
end

-- Rebind cached ParryClient references around local character/tool lifecycle.
-- This is deliberately outside the Auto Parry engine and does not change its logic.
do
    local function isParryRelatedTool(inst)
        if not inst or not inst:IsA("Tool") then return false end
        local n = string.lower(inst.Name or "")
        return n:find("parry", 1, true) ~= nil or n:find("dagger", 1, true) ~= nil
    end

    local function watchCharacter(character)
        if not character then return end
        AP.ResetClientCache()
        character.ChildAdded:Connect(function(child)
            if isParryRelatedTool(child) then AP.ResetClientCache() end
        end)
        character.ChildRemoved:Connect(function(child)
            if isParryRelatedTool(child) then AP.ResetClientCache() end
        end)
    end

    if LocalPlayer.Character then
        watchCharacter(LocalPlayer.Character)
    end
    LocalPlayer.CharacterAdded:Connect(function(character)
        watchCharacter(character)
    end)
    LocalPlayer.CharacterRemoving:Connect(function()
        AP.ResetClientCache()
    end)

    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack then
        backpack.ChildAdded:Connect(function(child)
            if isParryRelatedTool(child) then AP.ResetClientCache() end
        end)
        backpack.ChildRemoved:Connect(function(child)
            if isParryRelatedTool(child) then AP.ResetClientCache() end
        end)
    end
    LocalPlayer.ChildAdded:Connect(function(child)
        if child:IsA("Backpack") then
            child.ChildAdded:Connect(function(tool)
                if isParryRelatedTool(tool) then AP.ResetClientCache() end
            end)
            child.ChildRemoved:Connect(function(tool)
                if isParryRelatedTool(tool) then AP.ResetClientCache() end
            end)
        end
    end)
end

local function TianHub_ReAttachAll() end

local FloatingParryButton

local function TianHub_ParryLabel() return TianHubState.AutoParry and "AUTO PARRY ON" or "AUTO PARRY OFF" end

local function TianHub_SetFloatingButtonVisible(state)
    TianHubState.ShowFloatingButton = state
    if FloatingParryButton then
        FloatingParryButton.Destroy()
        FloatingParryButton = nil
    end
    if not state then return end
    FloatingParryButton = TianHubState.MakeFloat("TianFloatingAutoParry", TianHub_ParryLabel(), UDim2.new(0.5, 0, 0.82, 0), function()
        local reg = ToggleRegistry["auto_parry"]
        if reg and reg.setState then
            reg.setState(not TianHubState.AutoParry, true)
        else
            AP.SetEnabled(not AP.Enabled)
        end
        if FloatingParryButton then FloatingParryButton.SetText(TianHub_ParryLabel()) end
    end)
end

local Plrs = game:GetService("Players")
local Rns  = game:GetService("RunService")
local RS2  = game:GetService("ReplicatedStorage")
local WS2  = game:GetService("Workspace")
local VIM2 = game:GetService("VirtualInputManager")
local GS2  = game:GetService("GuiService")
local UIS2 = game:GetService("UserInputService")
local LP2  = Plrs.LocalPlayer
local PGui2 = LP2:WaitForChild("PlayerGui")
local isMob2 = UIS2.TouchEnabled and not UIS2.KeyboardEnabled

local genCache = { t = 0, list = {} }
TianHubState.NearestGenProgress = function()
    local ch = LocalPlayer.Character
    local root = ch and ch:FindFirstChild("HumanoidRootPart")
    if not root then return 0 end
    local now = os.clock()
    if now - genCache.t > 3 then
        genCache.t = now
        genCache.list = {}
        local map = workspace:FindFirstChild("Map")
        if map then
            for _, o in ipairs(map:GetDescendants()) do
                if o:IsA("Model") and (o:GetAttribute("RepairProgress") ~= nil or o:GetAttribute("ProgressRepair") ~= nil) then
                    genCache.list[#genCache.list + 1] = o
                end
            end
        end
    end
    local best, bd = 0, 15
    for _, g in ipairs(genCache.list) do
        if g.Parent then
            local part = g.PrimaryPart or g:FindFirstChildWhichIsA("BasePart", true)
            if part then
                local d = (part.Position - root.Position).Magnitude
                if d < bd then
                    bd = d
                    best = g:GetAttribute("RepairProgress") or g:GetAttribute("ProgressRepair") or 0
                end
            end
        end
    end
    return best
end

local AutoSkill = {
    Mode = "Normal", Active = false, HideUI = false, Speed = 1,
    SpeedCharacter = nil, SpeedOriginal = nil,
    LastGR = nil, HasClicked = false, LastLR = nil, LastTick = nil, WasActive = false,
    PerfLastGR = nil, PerfHasClicked = false, PerfLastLR = nil, PerfLastTick = nil, PerfWasActive = false,
}

local function AS_PressSkill()
    if isMob2 then
        local btn = PGui2:FindFirstChild("check", true)
        if btn and btn:IsA("GuiObject") and btn.Visible then
            local pos, size = btn.AbsolutePosition, btn.AbsoluteSize
            local ins = GS2:GetGuiInset()
            local x = pos.X + size.X/2 + ins.X
            local y = pos.Y + size.Y/2 + ins.Y
            pcall(function()
                VIM2:SendTouchEvent(8822, Enum.UserInputState.Begin.Value, x, y)
                task.wait(0.01)
                VIM2:SendTouchEvent(8822, Enum.UserInputState.End.Value, x, y)
            end)
            if firesignal and btn:IsA("GuiButton") then
                pcall(function() firesignal(btn.MouseButton1Click) end)
            end
            return true
        end
    end
    return pcall(function()
        VIM2:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
        task.wait(0.01)
        VIM2:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
    end)
end

local function AS_GetSC()
    for _, gn in ipairs({"SkillCheckPromptGui", "SkillCheckPromptGui-con"}) do
        local root = PGui2:FindFirstChild(gn, true)
        if root then
            local c = root:FindFirstChild("Check", true)
            if c and c.Visible then
                local tp = c:FindFirstChild("TrapPerfect", true)
                local tg = c:FindFirstChild("TrapGoal", true)
                if (tp and tp.Visible) or (tg and tg.Visible) then return nil end
                local l, g = c:FindFirstChild("Line", true), c:FindFirstChild("Goal", true)
                if l and g then return l, g end
            end
        end
    end
end

local function AS_Delta(a, b)
    local d = b - a
    if d > 180 then d = d - 360 end
    if d < -180 then d = d + 360 end
    return d
end

local function AS_Crossed(prev, now, sp, ep)
    local function inside(r)
        if sp > ep then return r >= sp or r <= ep end
        return r >= sp and r <= ep
    end
    if inside(now) then return true end
    if prev == nil then return false end
    local d = AS_Delta(prev, now)
    local steps = math.abs(math.floor(d))
    if steps < 2 then return false end
    local step = d / steps
    for i = 1, steps do
        if inside((prev + step*i) % 360) then return true end
    end
    return false
end

local function AS_Reset()
    AutoSkill.LastGR, AutoSkill.LastLR, AutoSkill.LastTick = nil, nil, nil
    AutoSkill.HasClicked, AutoSkill.WasActive = false, false
    AutoSkill.PerfLastGR, AutoSkill.PerfLastLR, AutoSkill.PerfLastTick = nil, nil, nil
    AutoSkill.PerfHasClicked, AutoSkill.PerfWasActive = false, false
end

local function AS_Normal()
    local l,g = AS_GetSC()
    if not (l and g) then AutoSkill.WasActive=false return end
    local lr,gr,nw = l.Rotation%360,g.Rotation%360,os.clock()
    if not AutoSkill.WasActive then
        AutoSkill.WasActive=true; AutoSkill.HasClicked=false
        AutoSkill.LastGR=gr; AutoSkill.LastLR=lr; AutoSkill.LastTick=nw
        return
    end
    if AutoSkill.LastGR and math.abs(AS_Delta(AutoSkill.LastGR,gr)) > 5 then
        AutoSkill.HasClicked=false; AutoSkill.LastLR=nil; AutoSkill.LastTick=nil
    end
    AutoSkill.LastGR=gr
    if AutoSkill.HasClicked then AutoSkill.LastLR=lr; AutoSkill.LastTick=nw; return end
    if AutoSkill.LastLR and AutoSkill.LastTick then
        local dt=nw-AutoSkill.LastTick
        if dt>0 then
            local ls=AS_Delta(AutoSkill.LastLR,lr)/dt
            local pr=(lr+ls*dt*0)%360
            if AS_Crossed(AutoSkill.LastLR,pr,(gr+104)%360,(gr+109)%360) then
                AutoSkill.HasClicked=true
                task.spawn(function() task.wait(0.03); AS_PressSkill() end)
            end
        end
    end
    AutoSkill.LastLR,AutoSkill.LastTick=lr,nw
end

local function AS_Perfect()
    local l,g=AS_GetSC()
    if not (l and g) then AutoSkill.PerfWasActive=false return end
    local lr,gr,nw=l.Rotation%360,g.Rotation%360,os.clock()
    if not AutoSkill.PerfWasActive then
        AutoSkill.PerfWasActive=true; AutoSkill.PerfHasClicked=false
        AutoSkill.PerfLastGR=gr; AutoSkill.PerfLastLR=lr; AutoSkill.PerfLastTick=nw
        return
    end
    if AutoSkill.PerfLastGR and math.abs(AS_Delta(AutoSkill.PerfLastGR,gr))>5 then
        AutoSkill.PerfHasClicked=false; AutoSkill.PerfLastLR=nil; AutoSkill.PerfLastTick=nil
    end
    AutoSkill.PerfLastGR=gr
    if AutoSkill.PerfHasClicked then AutoSkill.PerfLastLR=lr; AutoSkill.PerfLastTick=nw; return end
    if AutoSkill.PerfLastLR and AutoSkill.PerfLastTick then
        local dt=nw-AutoSkill.PerfLastTick
        if dt>0 then
            local ls=AS_Delta(AutoSkill.PerfLastLR,lr)/dt
            local pr=(lr+ls*dt*0)%360
            if AS_Crossed(AutoSkill.PerfLastLR,pr,(gr+104)%360,(gr+108)%360) then
                AutoSkill.PerfHasClicked=true
                AS_PressSkill()
            end
        end
    end
    AutoSkill.PerfLastLR,AutoSkill.PerfLastTick=lr,nw
end


local function AS_ApplySpeed(enabled)
    local char = LocalPlayer.Character
    if enabled and char then
        if AutoSkill.SpeedCharacter ~= char then
            -- Restore the previous character before caching a respawned character.
            if AutoSkill.SpeedCharacter and AutoSkill.SpeedOriginal then
                pcall(function()
                    AutoSkill.SpeedCharacter:SetAttribute("skillcheckspeed", AutoSkill.SpeedOriginal.lower)
                    AutoSkill.SpeedCharacter:SetAttribute("SkillCheckSpeed", AutoSkill.SpeedOriginal.upper)
                end)
            end
            AutoSkill.SpeedCharacter = char
            AutoSkill.SpeedOriginal = {
                lower = char:GetAttribute("skillcheckspeed"),
                upper = char:GetAttribute("SkillCheckSpeed"),
            }
        end
        local speed = math.clamp(tonumber(AutoSkill.Speed) or 1, 0.1, 3)
        if char:GetAttribute("skillcheckspeed") ~= speed then
            pcall(function() char:SetAttribute("skillcheckspeed", speed) end)
        end
        if char:GetAttribute("SkillCheckSpeed") ~= speed then
            pcall(function() char:SetAttribute("SkillCheckSpeed", speed) end)
        end
    elseif AutoSkill.SpeedCharacter then
        local oldChar, oldValues = AutoSkill.SpeedCharacter, AutoSkill.SpeedOriginal
        pcall(function()
            oldChar:SetAttribute("skillcheckspeed", oldValues and oldValues.lower)
            oldChar:SetAttribute("SkillCheckSpeed", oldValues and oldValues.upper)
        end)
        AutoSkill.SpeedCharacter, AutoSkill.SpeedOriginal = nil, nil
    end
end

local function AS_HideUI()
    local hidden = AutoSkill.HideUI
    for _, gn in ipairs({"SkillCheckPromptGui","SkillCheckPromptGui-con"}) do
        local root=PGui2:FindFirstChild(gn,true)
        if root then
            if root:IsA("ScreenGui") then
                root.Enabled = not hidden
            else
                for _, o in ipairs(root:GetDescendants()) do
                    if o:IsA("GuiObject") then o.Visible = not hidden end
                end
            end
        end
    end
end

setConn("TianHub_AutoSkill", Rns.RenderStepped:Connect(function()
    AS_ApplySpeed(AutoSkill.Active)
    if AutoSkill.Active then
        local mode = AutoSkill.Mode
        if AutoSkill.KingScourge and TianHubState.KillerHasPerk and TianHubState.KillerHasPerk("King's Scourge")
            and TianHubState.NearestGenProgress() >= 90 then
            mode = "Normal"
        end
        if mode=="Perfect" then AS_Perfect()
        else AS_Normal() end
    else
        AS_Reset()
    end
    AS_HideUI()
end))

-- Bypass Generator feature removed. Clean up any instance left by an earlier execution.
do
    local W = getgenv()
    if W.TianHub_GenBypass and W.TianHub_GenBypass.destroy then
        pcall(W.TianHub_GenBypass.destroy)
    end
    W.TianHub_GenBypass = nil
end

-- Legacy TianHub Gen Boost backend and floating button removed; generator controls use the current TianHub systems.

local SelfHeal = {
    SelfEnabled = false, AllEnabled = false,
    SelfThread = nil, AllThread = nil,
    HealEvent = nil, SelfActive = false, AllActive = {},
}

local function SH_GetHealEvent()
    if SelfHeal.HealEvent and SelfHeal.HealEvent.Parent then return SelfHeal.HealEvent end
    local r = ReplicatedStorage:FindFirstChild("Remotes")
    local h = r and r:FindFirstChild("Healing")
    local ev = h and h:FindFirstChild("HealEvent")
    SelfHeal.HealEvent = ev
    return ev
end

local function SH_Fire(targetChar, state)
    local ev = SH_GetHealEvent()
    if not ev or not targetChar then return end
    local hrp = targetChar:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    pcall(function() ev:FireServer(hrp, state) end)
end

local function SH_StopSelf()
    if SelfHeal.SelfActive then
        local c = LocalPlayer.Character
        if c then SH_Fire(c, false) end
        SelfHeal.SelfActive = false
    end
end

local function SH_StopAll()
    for plr, _ in pairs(SelfHeal.AllActive) do
        if plr and plr.Character then
            pcall(function() SH_Fire(plr.Character, false) end)
        end
    end
    SelfHeal.AllActive = {}
end

local function SH_StartSelf()
    if SelfHeal.SelfThread then pcall(function() task.cancel(SelfHeal.SelfThread) end) end
    SelfHeal.SelfThread = task.spawn(function()
        while SelfHeal.SelfEnabled do
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if char and hum and hum.Health > 0 then
                local hpPct = hum.Health / math.max(hum.MaxHealth, 1)
                if hpPct < 0.95 then
                    SH_Fire(char, true)
                    SelfHeal.SelfActive = true
                else
                    if SelfHeal.SelfActive then
                        SH_Fire(char, false)
                        SelfHeal.SelfActive = false
                    end
                end
            else
                SelfHeal.SelfActive = false
            end
            task.wait(0.4)
        end
        SH_StopSelf()
    end)
end

local function SH_StartAll()
    if SelfHeal.AllThread then pcall(function() task.cancel(SelfHeal.AllThread) end) end
    SelfHeal.AllThread = task.spawn(function()
        while SelfHeal.AllEnabled do
            for _, p in ipairs(Players:GetPlayers()) do
                local validTeam = p.Team and (p.Team.Name == "Survivors" or p.Team.Name == "Survivor")
                if validTeam and p.Character then
                    local hum = p.Character:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 and hum.Health < hum.MaxHealth * 0.95 then
                        SH_Fire(p.Character, true)
                        SelfHeal.AllActive[p] = true
                    else
                        if SelfHeal.AllActive[p] then
                            SH_Fire(p.Character, false)
                            SelfHeal.AllActive[p] = nil
                        end
                    end
                elseif SelfHeal.AllActive[p] then
                    if p.Character then SH_Fire(p.Character, false) end
                    SelfHeal.AllActive[p] = nil
                end
            end
            task.wait(0.5)
        end
        SH_StopAll()
    end)
end

local function SH_SetSelf(enabled)
    SelfHeal.SelfEnabled = enabled and true or false
    if SelfHeal.SelfEnabled then SH_StartSelf()
    else
        if SelfHeal.SelfThread then pcall(function() task.cancel(SelfHeal.SelfThread) end); SelfHeal.SelfThread = nil end
        SH_StopSelf()
    end
end

local function SH_SetAll(enabled)
    SelfHeal.AllEnabled = enabled and true or false
    if SelfHeal.AllEnabled then SH_StartAll()
    else
        if SelfHeal.AllThread then pcall(function() task.cancel(SelfHeal.AllThread) end); SelfHeal.AllThread = nil end
        SH_StopAll()
    end
end

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    SelfHeal.SelfActive = false
    SelfHeal.AllActive = {}
    if SelfHeal.SelfEnabled then SH_StartSelf() end
    if SelfHeal.AllEnabled then SH_StartAll() end
end)

local TianNoclipOriginal = {}
local function Tian_SetNoclip(enabled)
    TianHubState.Noclip = enabled == true
    if not TianHubState.Noclip then
        for part, cc in pairs(TianNoclipOriginal) do
            if part and part.Parent then pcall(function() part.CanCollide = cc end) end
        end
        table.clear(TianNoclipOriginal)
    end
end

setConn("Tian_SurvivorMovement", RunService.Heartbeat:Connect(function()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        if TianHubState.GodMode and hum.Health > 0 and hum.Health < hum.MaxHealth then
            pcall(function() hum.Health = hum.MaxHealth end)
        end
    end
end))

setConn("Tian_SurvivorNoclip", RunService.Stepped:Connect(function()
    if not TianHubState.Noclip then return end
    local char = LocalPlayer.Character
    if not char then return end
    for _, obj in ipairs(char:GetDescendants()) do
        if obj:IsA("BasePart") then
            if TianNoclipOriginal[obj] == nil then
                TianNoclipOriginal[obj] = obj.CanCollide
            end
            obj.CanCollide = false
        end
    end
end))

setConn("Tian_NoclipRestore", LocalPlayer.CharacterRemoving:Connect(function()
    table.clear(TianNoclipOriginal)
end))

-- language: Luau, file: esp_cd_killer_merged.lua
-- Unified Killer CD HUD + control panel.
-- Original cooldown detection logic retained; both panels now share one ScreenGui/Frame.

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local CollectionService  = game:GetService("CollectionService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local LP                 = Players.LocalPlayer

local State = _G.TianHub_KillerCDState or {}
_G.TianHub_KillerCDState = State

State.KillerCD = (function()
	local K = { Enabled = false }

	local MOVES = {
		Slasher = { name = "Slasher", move1 = "rbxassetid://134862031194933", move2 = "rbxassetid://136973921948245", move1Name = "Lake of Mist", move2Name = "Pursuit", move1CD = 30, move2CD = 60, missCD = 1.4 },
		Stalker = { name = "Stalker", move1 = "rbxassetid://85894094209457", move2 = "rbxassetid://110045688062234", move1Name = "Hunt Mode", move2Name = "Evil Surge", move1CD = 30, move2CD = 40, missCD = 1.5 },
		Masked = { name = "Masked", move1 = "rbxassetid://110441838520158", move2 = "rbxassetid://95375588266919", move1Name = "Frenzy Sprint", move2Name = "Mask Swap", move1CD = 30, move2CD = 30, missCD = 1.5 },
		Killer = { name = "Nina", move1 = "rbxassetid://108114231850675", move2 = "rbxassetid://95375588266919", move1Name = "Shadow Step", move2Name = "Agony Lunge", move1CD = 30, move2CD = 30, missCD = 1.5 },
		Hidden = { name = "Hidden", move1 = "rbxassetid://129570234771869", move2 = "rbxassetid://130915693370693", move1Name = "Phantom Dash", move2Name = "Leap Vault", move1CD = 20, move2CD = 20, missCD = 1.5 },
		Abysswalker = { name = "Abysswalker", move1 = "rbxassetid://86213737463907", move2 = "rbxassetid://100395868673407", move1Name = "Abyssal Wave", move2Name = "Shadow Leap", move1CD = 30, move2CD = 6, missCD = 1.5 },
		Veil = { name = "Veil", move1 = "rbxassetid://110881025348309", move2 = "rbxassetid://95375588266919", move1Name = "Spear Throw", move2Name = "Spear Reload", move1CD = 30, move2CD = 3.5, missCD = 1.5 },
		Cure = { name = "The Cure", move1 = "rbxassetid://119792658841268", move2 = "rbxassetid://81019828986691", move1Name = "Elucidation", move2Name = "Gas Cloud", move1CD = 15, move2CD = 15, missCD = 1.5 },
		Butcher = { name = "Butcher", move1 = "rbxassetid://121475438777829", move2 = "rbxassetid://95375588266919", move1Name = "Chain Throw", move2Name = "Bear Trap", move1CD = 15, move2CD = 45, missCD = 1.5 },
	}
	local THEME = {
		Veil = Color3.fromRGB(0,150,255), Abysswalker = Color3.fromRGB(168,85,247), Butcher = Color3.fromRGB(239,68,68),
		Cure = Color3.fromRGB(34,197,94), Masked = Color3.fromRGB(244,63,94), Slasher = Color3.fromRGB(249,115,22),
		Stalker = Color3.fromRGB(148,163,184), Hidden = Color3.fromRGB(99,102,241), Killer = Color3.fromRGB(217,119,6),
	}
	local M1_ICON = "rbxassetid://123571635310131"
	local RED, GREEN, AMBER = Color3.fromRGB(244,63,94), Color3.fromRGB(52,230,150), Color3.fromRGB(251,191,36)

	local H = {
		Gui = nil, Frame = nil, Rows = {}, Conns = {}, UIConns = {}, RemoteConns = {},
		Active = nil, Type = "Unknown", Moves = MOVES.Veil,
		Att = {Until=0,Total=1.5}, S1 = {Until=0,Total=30}, S2 = {Until=0,Total=12},
		Action = {Text="",Until=0,Total=0}, ToastUntil=0, Min=false,
	}

	local function new(cls, props, parent)
		local obj = Instance.new(cls)
		for k,v in pairs(props) do obj[k] = v end
		if parent then obj.Parent = parent end
		return obj
	end
	local function corner(obj, radius)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0,radius)
		c.Parent = obj
	end
	local function track(conn) table.insert(H.Conns,conn); return conn end
	local function clear(list)
		for _,conn in ipairs(list) do pcall(function() conn:Disconnect() end) end
		table.clear(list)
	end
	local function trig(slot,duration)
		slot.Until = os.clock() + duration
		slot.Total = duration
	end
	local function triggerAttack(d) trig(H.Att,d or 1.5) end
	local function toast(skill,duration)
		if not H.Toast then return end
		local theme = THEME[H.Type] or Color3.fromRGB(168,85,247)
		H.ToastText.Text = ("%s  •  %s  •  CD %.1fs"):format(string.upper(H.Moves.name or H.Type),skill,duration)
		H.ToastStroke.Color = theme
		H.ToastIcon.ImageColor3 = theme
		H.Toast.Visible = true
		H.ToastUntil = os.clock()+2.5
	end
	local function triggerSkill1(d)
		local fresh = H.S1.Until < os.clock()
		trig(H.S1,d or H.Moves.move1CD)
		if fresh then toast(H.Moves.move1Name,H.S1.Total) end
	end
	local function triggerSkill2(d)
		local fresh = H.S2.Until < os.clock()
		trig(H.S2,d or H.Moves.move2CD)
		if fresh then toast(H.Moves.move2Name,H.S2.Total) end
	end
	local function triggerSafe(txt,d,col)
		H.Action.Text, H.Action.Until, H.Action.Total, H.Action.Color = txt,os.clock()+d,d,col or GREEN
	end
	local function guiParent()
		local ok,hui = pcall(function() return gethui and gethui() end)
		if ok and typeof(hui)=="Instance" then return hui end
		local core = game:GetService("CoreGui")
		local okCore = pcall(function() local f=Instance.new("Folder"); f.Parent=core; f:Destroy() end)
		if okCore then return core end
		return LP:WaitForChild("PlayerGui")
	end
	local function makeRow(parent,order,iconImage)
		local row = new("Frame",{Size=UDim2.new(1,0,0,27),BackgroundTransparency=1,LayoutOrder=order},parent)
		local icon = new("ImageLabel",{Position=UDim2.new(0,9,0.5,-9),Size=UDim2.fromOffset(18,18),BackgroundTransparency=1,Image=iconImage or "",ScaleType=Enum.ScaleType.Fit},row)
		corner(icon,4)
		local name = new("TextLabel",{Position=UDim2.new(0,34,0,0),Size=UDim2.new(1,-92,1,0),BackgroundTransparency=1,Text="-",TextColor3=Color3.fromRGB(235,235,245),Font=Enum.Font.GothamBold,TextSize=11,TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd},row)
		local tm = new("TextLabel",{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-10,0,0),Size=UDim2.fromOffset(55,26),BackgroundTransparency=1,Text="READY",TextColor3=GREEN,Font=Enum.Font.GothamBold,TextSize=10,TextXAlignment=Enum.TextXAlignment.Right},row)
		local bg = new("Frame",{Position=UDim2.new(0,34,1,-2),Size=UDim2.new(1,-46,0,2),BackgroundColor3=Color3.fromRGB(40,40,52),BorderSizePixel=0,Visible=false},row)
		local bar = new("Frame",{Size=UDim2.fromScale(0,1),BackgroundColor3=RED,BorderSizePixel=0},bg)
		return {Row=row,Icon=icon,Name=name,Time=tm,BarBg=bg,Bar=bar}
	end
	local function separator(parent,order)
		new("Frame",{Size=UDim2.new(1,-18,0,1),Position=UDim2.new(0,9,0,0),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=0.88,BorderSizePixel=0,LayoutOrder=order or 1},parent)
	end
	local function paintRow(r,remaining,total)
		if remaining>0 then
			r.Time.Text=("%.1fs"):format(remaining); r.Time.TextColor3=RED; r.BarBg.Visible=true
			r.Bar.Size=UDim2.fromScale(math.clamp(remaining/math.max(.01,total),0,1),1); r.Icon.ImageTransparency=.5
		else
			r.Time.Text="READY"; r.Time.TextColor3=GREEN; r.BarBg.Visible=false; r.Icon.ImageTransparency=0
		end
	end

	local function buildUI()
		if H.Gui then return end
		local gui = new("ScreenGui",{Name="TianHubKillerCD",ResetOnSpawn=false,IgnoreGuiInset=true,DisplayOrder=997,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},guiParent())
		H.Gui=gui
		local frame = new("Frame",{Name="UnifiedPanel",Size=UDim2.fromOffset(155,0),AutomaticSize=Enum.AutomaticSize.Y,Position=UDim2.new(.015,0,.12,0),BackgroundColor3=Color3.fromRGB(22,23,31),BackgroundTransparency=.24,BorderSizePixel=0,Active=true},gui)
		corner(frame,11)
		new("UIStroke",{Color=Color3.fromRGB(120,135,165),Transparency=.55,Thickness=1},frame)
		new("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,2)},frame)
		new("UIPadding",{PaddingTop=UDim.new(0,4),PaddingBottom=UDim.new(0,7)},frame)
		H.Frame=frame

		local head=new("Frame",{Size=UDim2.new(1,0,0,28),BackgroundTransparency=1,LayoutOrder=1},frame)
		new("TextLabel",{Position=UDim2.new(0,11,0,0),Size=UDim2.new(1,-80,1,0),BackgroundTransparency=1,Text="Killer CD",TextColor3=Color3.fromRGB(240,242,250),Font=Enum.Font.GothamBold,TextSize=12,TextXAlignment=Enum.TextXAlignment.Left},head)
		H.Portrait=new("ImageLabel",{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-9,.5,0),Size=UDim2.fromOffset(21,21),BackgroundColor3=Color3.fromRGB(40,40,52),BorderSizePixel=0,Image="rbxassetid://10709798433",ScaleType=Enum.ScaleType.Crop},head)
		corner(H.Portrait,6)
		H.PortraitStroke=new("UIStroke",{Color=Color3.fromRGB(0,170,255),Transparency=.35,Thickness=1.3},H.Portrait)
		H.MinBtn=new("TextButton",{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-39,.5,0),Size=UDim2.fromOffset(20,20),BackgroundColor3=Color3.fromRGB(43,46,59),BorderSizePixel=0,Text="−",TextColor3=Color3.new(1,1,1),Font=Enum.Font.GothamBold,TextSize=14,AutoButtonColor=false},head)
		corner(H.MinBtn,6)

		local info=new("Frame",{Size=UDim2.new(1,0,0,22),BackgroundTransparency=1,LayoutOrder=2},frame)
		H.KillerLbl=new("TextLabel",{Position=UDim2.new(0,11,0,0),Size=UDim2.new(1,-75,1,0),BackgroundTransparency=1,Text="Killer: -",TextColor3=Color3.fromRGB(170,174,190),Font=Enum.Font.GothamMedium,TextSize=10,TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd},info)
		H.DistLbl=new("TextLabel",{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-10,0,0),Size=UDim2.fromOffset(62,25),BackgroundTransparency=1,Text="--m",TextColor3=GREEN,Font=Enum.Font.GothamBold,TextSize=10,TextXAlignment=Enum.TextXAlignment.Right},info)
		separator(frame,3)
		H.Rows.Attack=makeRow(frame,4,M1_ICON); H.Rows.Attack.Name.Text="Attack"
		H.Rows.S1=makeRow(frame,5); H.Rows.S2=makeRow(frame,6)
		separator(frame,7)
		-- Compact Auto ON switch sits directly below the two skill cooldown rows.
		local autoRow=new("Frame",{Size=UDim2.new(1,0,0,27),BackgroundTransparency=1,LayoutOrder=8},frame)
		H.Rows.Safe=makeRow(frame,9,"rbxassetid://10709798433"); H.Rows.Safe.Row.Visible=false
		new("TextLabel",{Position=UDim2.new(0,10,0,0),Size=UDim2.new(1,-62,1,0),BackgroundTransparency=1,Text="Auto ON",TextColor3=Color3.fromRGB(235,235,245),Font=Enum.Font.GothamBold,TextSize=10,TextXAlignment=Enum.TextXAlignment.Left},autoRow)
		H.AutoBtn=new("TextButton",{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-10,.5,0),Size=UDim2.fromOffset(35,18),BackgroundColor3=GREEN,BorderSizePixel=0,Text="",AutoButtonColor=false},autoRow)
		corner(H.AutoBtn,9)
		H.AutoKnob=new("Frame",{Position=UDim2.fromOffset(19,2),Size=UDim2.fromOffset(14,14),BackgroundColor3=Color3.fromRGB(255,255,255),BorderSizePixel=0},H.AutoBtn)
		corner(H.AutoKnob,7)

		local function paintControls()
			local on=K.Enabled==true
			H.AutoBtn.BackgroundColor3=on and GREEN or Color3.fromRGB(75,78,91)
			H.AutoKnob.Position=on and UDim2.fromOffset(19,2) or UDim2.fromOffset(2,2)
		end
		H.PaintControls=paintControls
		H.AutoBtn.MouseButton1Click:Connect(function() K.SetEnabled(not K.Enabled); paintControls() end)
		H.Min=false
		H.MinBtn.MouseButton1Click:Connect(function()
			H.Min=not H.Min
			H.MinBtn.Text=H.Min and "+" or "−"
			for _,child in ipairs(frame:GetChildren()) do
				if child:IsA("GuiObject") then
					local order=child.LayoutOrder
					if order>=2 and order<=9 then child.Visible=not H.Min end
				end
			end
		end)

		local dragging,dragStart,startPos
		table.insert(H.UIConns,frame.InputBegan:Connect(function(input)
			if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
				dragging,dragStart,startPos=true,input.Position,frame.Position
				input.Changed:Connect(function() if input.UserInputState==Enum.UserInputState.End then dragging=false end end)
			end
		end))
		table.insert(H.UIConns,UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
				local delta=input.Position-dragStart
				frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+delta.X,startPos.Y.Scale,startPos.Y.Offset+delta.Y)
			end
		end))
		table.insert(H.UIConns,UserInputService.InputBegan:Connect(function(input,gp)
			if not gp and input.KeyCode==Enum.KeyCode.RightControl then
				K.SetEnabled(not K.Enabled)
				if H.PaintControls then H.PaintControls() end
			end
		end))

		H.Toast=new("Frame",{Name="SkillToast",AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,.09,0),Size=UDim2.fromOffset(0,26),AutomaticSize=Enum.AutomaticSize.X,BackgroundColor3=Color3.fromRGB(22,23,31),BackgroundTransparency=.04,BorderSizePixel=0,Visible=false},gui)
		corner(H.Toast,8)
		H.ToastStroke=new("UIStroke",{Color=Color3.fromRGB(0,170,255),Transparency=.2,Thickness=1.2},H.Toast)
		new("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,VerticalAlignment=Enum.VerticalAlignment.Center,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6)},H.Toast)
		new("UIPadding",{PaddingLeft=UDim.new(0,9),PaddingRight=UDim.new(0,10)},H.Toast)
		H.ToastIcon=new("ImageLabel",{Size=UDim2.fromOffset(14,14),BackgroundTransparency=1,Image="rbxassetid://10709798433",LayoutOrder=1},H.Toast)
		H.ToastText=new("TextLabel",{Size=UDim2.fromOffset(0,26),AutomaticSize=Enum.AutomaticSize.X,BackgroundTransparency=1,Text="",TextColor3=Color3.fromRGB(235,235,245),Font=Enum.Font.GothamBold,TextSize=10,LayoutOrder=2},H.Toast)
		paintControls()
	end

	local function isKillerChar(char)
		if not char or not char:IsA("Model") or char==LP.Character or not char:FindFirstChildOfClass("Humanoid") then return false end
		local plr=Players:GetPlayerFromCharacter(char)
		if plr==LP then return false end
		if char:GetAttribute("Role")=="Killer" or char:GetAttribute("IsKiller")==true then return true end
		if plr and plr.Team then
			local team=string.lower(plr.Team.Name)
			if team:find("killer") or team:find("slasher") then return true end
		end
		return false
	end
	local function findKiller()
		for _,tag in ipairs(CollectionService:GetTagged("Killer")) do
			local model=tag:IsA("Model") and tag or tag:FindFirstAncestorOfClass("Model")
			if model and model~=LP.Character and model:FindFirstChild("HumanoidRootPart") then return model end
		end
		for _,plr in ipairs(Players:GetPlayers()) do if plr~=LP and plr.Character and isKillerChar(plr.Character) then return plr.Character end end
		return nil
	end
	local function resolveType(char)
		local name=char:GetAttribute("MorphedKiller") or char:GetAttribute("SelectedKiller")
		local plr=Players:GetPlayerFromCharacter(char)
		if not name and plr then name=plr:GetAttribute("SelectedKiller") or plr:GetAttribute("Killer") end
		if not name and MOVES[char.Name] then name=char.Name end
		if not name then for key in pairs(MOVES) do if string.find(string.lower(char.Name),string.lower(key),1,true) then name=key; break end end end
		if name and not MOVES[name] then name=nil end
		return name or "Veil"
	end
	local function bind(char)
		if not char or char==H.Active then return end
		clear(H.Conns)
		H.Active=char
		local kType=resolveType(char); H.Type=kType; H.Moves=MOVES[kType] or MOVES.Veil
		local moves=H.Moves; local theme=THEME[kType] or Color3.fromRGB(168,85,247)
		local plr=Players:GetPlayerFromCharacter(char)
		H.S1.Total,H.S2.Total,H.Att.Total=moves.move1CD,moves.move2CD,moves.missCD
		H.S1.Until,H.S2.Until,H.Att.Until=0,0,0
		if H.Gui then
			H.KillerLbl.Text="Killer: "..(plr and (plr.DisplayName~="" and plr.DisplayName or plr.Name) or moves.name)
			H.PortraitStroke.Color=theme; H.PortraitStroke.Transparency=0
			if plr and plr.UserId>0 then H.Portrait.Image=("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(plr.UserId) end
			H.Rows.S1.Icon.Image=moves.move1; H.Rows.S2.Icon.Image=moves.move2
			H.Rows.S1.Name.Text=moves.move1Name; H.Rows.S2.Name.Text=moves.move2Name
		end
		local hum=char:FindFirstChildOfClass("Humanoid")
		local animator=hum and hum:FindFirstChildOfClass("Animator")
		local function hookAnim(anim)
			track(anim.AnimationPlayed:Connect(function(trk)
				local id=(trk.Animation and trk.Animation.AnimationId) or ""
				local name=string.lower(trk.Name or "")
				local m1=moves.move1:match("%d+"); local m2=moves.move2:match("%d+")
				if (m1 and id:find(m1,1,true)) or name:find("flask") or name:find("spear") or name:find("chain") or name:find("wave") or name:find("mist") then
					triggerSkill1(moves.move1CD)
				elseif (m2 and id:find(m2,1,true)) or name:find("gas") or name:find("inject") or name:find("trap") or name:find("leap") or name:find("frenzy") or name:find("stalk") or name:find("reload") or name:find("pursuit") or name:find("mask") then
					triggerSkill2(moves.move2CD)
				elseif name:find("attack") or name:find("swing") or name:find("lunge") or name:find("slash") or id:find("113691709436161",1,true) then
					triggerAttack(moves.missCD)
				elseif trk.Priority==Enum.AnimationPriority.Action or trk.Priority==Enum.AnimationPriority.Action2 or trk.Priority==Enum.AnimationPriority.Action3 or trk.Priority==Enum.AnimationPriority.Action4 then
					triggerAttack(moves.missCD)
				end
			end))
		end
		if animator then hookAnim(animator) else track(char.DescendantAdded:Connect(function(d) if d:IsA("Animator") then hookAnim(d) end end)) end
		track(char.AttributeChanged:Connect(function(attr)
			local value=char:GetAttribute(attr)
			if (attr=="isBreakingPallet" or attr=="isBreaking") and value==true then triggerSafe("Breaking Pallet",2.16,GREEN)
			elseif attr=="isBreakingGen" and value==true then triggerSafe("Kicking Generator",1.90,AMBER)
			elseif attr=="isVaulting" and value==true then triggerSafe("Vaulting Window",1.525,Color3.fromRGB(6,182,212))
			elseif (attr=="IsStunned" or attr=="isTrueStunned") and value==true then triggerSafe("Pallet Stunned",3,RED)
			elseif attr=="isAttacking" or attr=="isLunging" then if value==true then triggerAttack(moves.missCD) end
			elseif attr=="ChainMove1CD" then if type(value)=="number" and value>0 then triggerSkill1(math.max(value,15)) end
			elseif attr=="PlacingTrap" and value==true then triggerSkill2(45) end
		end))
		local function hookWeapon(weapon)
			if not weapon then return end
			for _,desc in ipairs(weapon:GetDescendants()) do
				if desc:IsA("Trail") and desc:GetAttribute("SwingTrail") then
					track(desc:GetPropertyChangedSignal("Enabled"):Connect(function() if desc.Enabled then triggerAttack(moves.missCD) end end))
				end
			end
		end
		hookWeapon(char:FindFirstChild("Weapon"))
		track(char.ChildAdded:Connect(function(child) if child.Name=="Weapon" then hookWeapon(child) end end))
		track(workspace.ChildAdded:Connect(function(child)
			local name=string.lower(child.Name)
			if name:find("flask") then triggerSkill1(15) elseif name:find("spear") then triggerSkill1(30) elseif name:find("wave") then triggerSkill1(30) end
		end))
	end
	local function hookRemotes()
		clear(H.RemoteConns)
		local remotes=ReplicatedStorage:FindFirstChild("Remotes"); if not remotes then return end
		local function attach(remote,handler)
			if remote and remote:IsA("RemoteEvent") then table.insert(H.RemoteConns,remote.OnClientEvent:Connect(handler)) end
		end
		local killers=remotes:FindFirstChild("Killers")
		if killers then
			local cure=killers:FindFirstChild("Cure"); attach(cure and cure:FindFirstChild("VisualizeFlask"),function() triggerSkill1(15) end)
			local veil=killers:FindFirstChild("Veil"); attach(veil and veil:FindFirstChild("SpearState"),function(state) if state=="launch" or not state then triggerSkill1(30) end end)
			local butcher=killers:FindFirstChild("Butcher"); attach(butcher and butcher:FindFirstChild("ChainThrow"),function() triggerSkill1(15) end)
			local abyss=killers:FindFirstChild("Abysswalker"); attach(abyss and abyss:FindFirstChild("visualize"),function() triggerSkill1(30) end)
		end
		local attacks=remotes:FindFirstChild("Attacks")
		if attacks then for _,name in ipairs({"BasicAttack","Lunge","LungeDetect","AfterAttack","AttackLock"}) do attach(attacks:FindFirstChild(name),function() triggerAttack(1.5) end) end end
	end
	local accumulator=0
	local function render(dt)
		if not K.Enabled or not H.Gui then return end
		accumulator=accumulator+dt; if accumulator<.05 then return end; accumulator=0
		if not H.Active or not H.Active.Parent then
			H.Active=nil
			local killer=findKiller()
			if killer then bind(killer) else H.KillerLbl.Text="Killer: -"; H.DistLbl.Text="--m" end
		end
		local now=os.clock()
		if H.Toast and H.Toast.Visible and now>H.ToastUntil then H.Toast.Visible=false end
		local root=H.Active and H.Active:FindFirstChild("HumanoidRootPart")
		local mine=LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
		if root and mine then
			local distance=(root.Position-mine.Position).Magnitude
			H.DistLbl.Text=("%dm"):format(math.floor(distance))
			H.DistLbl.TextColor3=distance<25 and RED or (distance<50 and AMBER or GREEN)
		end
		paintRow(H.Rows.Attack,H.Att.Until-now,H.Att.Total)
		paintRow(H.Rows.S1,H.S1.Until-now,H.S1.Total)
		paintRow(H.Rows.S2,H.S2.Until-now,H.S2.Total)
		local remaining=H.Action.Until-now; local safe=H.Rows.Safe
		if H.Min then safe.Row.Visible=false
		elseif remaining>0 then
			safe.Row.Visible=true; safe.Name.Text=H.Action.Text; safe.Time.Text=("%.1fs"):format(remaining)
			safe.Time.TextColor3=H.Action.Color or GREEN; safe.BarBg.Visible=true
			safe.Bar.BackgroundColor3=H.Action.Color or GREEN
			safe.Bar.Size=UDim2.fromScale(math.clamp(remaining/math.max(.01,H.Action.Total),0,1),1)
		else safe.Row.Visible=false; safe.BarBg.Visible=false end
	end

	local stepConn
	function K.SetEnabled(value,legacyValue)
		local on=(type(value)=="table" and value==K) and legacyValue or value
		K.Enabled=(on==true)
		if K.Enabled then
			buildUI()
			hookRemotes()
			local killer=findKiller(); if killer then bind(killer) end
			if stepConn then stepConn:Disconnect() end
			stepConn=RunService.RenderStepped:Connect(render)
		else
			K.Destroy()
		end
		if H.PaintControls then H.PaintControls() end
	end
	function K.StopMonitoring()
		K.Enabled=false
		if stepConn then stepConn:Disconnect(); stepConn=nil end
		clear(H.Conns)
		clear(H.RemoteConns)
		H.Active=nil
		if H.PaintControls then H.PaintControls() end
		-- Keep the compact HUD alive so the Auto ON switch can turn monitoring back on.
	end
	function K.Destroy()
		K.StopMonitoring()
		clear(H.UIConns)
		if H.Gui then pcall(function() H.Gui:Destroy() end) end
		H.Gui,H.Frame=nil,nil
		table.clear(H.Rows)
	end
	return K
end)()

local K=State.KillerCD
-- HUD is controlled by the TianHub Survivor toggle.
K.SetEnabled(false)



local KillerCDSection = CreateSection(SurvTab, "KILLER CD HUD", false)
CreateToggle(KillerCDSection, "Show CD Killer [Beta]", false, function(enabled)
    local stateStore = _G.TianHub_KillerCDState
    local api = stateStore and stateStore.KillerCD
    if api and api.SetEnabled then
        api.SetEnabled(enabled)
    end
end)

local AutoParrySection = CreateSection(SurvTab, "AUTO PARRY", false)
-- UI hanya memetakan pengaturan yang memang tersedia pada engine Auto Parry V2 baru.
CreateToggle(AutoParrySection, "Enable Auto Parry", false, function(state)
    AP.SetEnabled(state)
end)
CreateSlider(AutoParrySection, "Parry Range", 5, 35, 14, " studs", function(v) AP.SetRange(v) end)
CreateSlider(AutoParrySection, "Face Sensitivity", 0, 10, 10, "", function(v) AP.SetFaceSensitivity(v) end)
CreateToggle(AutoParrySection, "Aggressive Mode", false, function(v) AP.SetAggressiveMode(v) end)
CreateToggle(AutoParrySection, "Range Circle", false, function(v) AP.SetRangeESP(v) end)


-- Killer FOV ditempatkan tepat di bawah pengaturan Auto Parry utama.
local KillerFOVSection = AutoParrySection

-- Create these panels here so their order is directly below Auto Parry.
local AutomationSection = CreateSection(SurvTab, "AUTO SKILL CHECK", false)
local TrapSkillSection = CreateSection(SurvTab, "AUTO SKILL CHECK TRAP", false)

local FastBandageSection = CreateSection("Survivor", "FAST BANDAGE", false)
CreateToggle(FastBandageSection, "Fast Bandage", false, function(enabled)
    local api = _G.TianHub_FastBandage
    if api and api.FB_SetEnabled then
        api.FB_SetEnabled(enabled)
    end
    ShowToast("Fast Bandage", enabled and "Enabled" or "Disabled")
end)
CreateSlider(FastBandageSection, "Bandage Speed", 10, 200, 50, "", function(value)
    local api = _G.TianHub_FastBandage
    if api and api.FB_SetSpeed then
        api.FB_SetSpeed(value)
    else
        _G.TianHubBandageSpeed = value
    end
end, 0)

local SelfHealSection = CreateSection(SurvTab, "SELF HEAL", false)
CreateToggle(SelfHealSection, "Self Heal", false, function(state) SH_SetSelf(state) end)
CreateToggle(SelfHealSection, "Self Heal All", false, function(state) SH_SetAll(state) end)

-- Floating quick-toggle for Self Heal All (matches Moonwalk floating button behavior).
local HealAllFloat = nil
local function healAllFloatLabel()
    return SelfHeal.AllEnabled and "HEAL ALL ON" or "HEAL ALL OFF"
end
local function toggleHealAllFromFloat()
    local reg = ToggleRegistry["self_heal_all"]
    if reg and reg.setState then
        reg.setState(not SelfHeal.AllEnabled, true)
    else
        SH_SetAll(not SelfHeal.AllEnabled)
    end
    if HealAllFloat then HealAllFloat.SetText(healAllFloatLabel()) end
end
local function setHealAllFloatVisible(on)
    if HealAllFloat then HealAllFloat.Destroy(); HealAllFloat = nil end
    if on then
        HealAllFloat = TianHubState.MakeFloat(
            "TianHealAllButton",
            healAllFloatLabel(),
            UDim2.new(0.85, 0, 0.56, 0),
            toggleHealAllFromFloat
        )
    end
end
CreateToggle(SelfHealSection, "Show Floating Button Heal All", false, function(v)
    setHealAllFloatVisible(v)
end)

CreateToggle(AutomationSection, "Auto Skill Check", false, function(state)
    AutoSkill.Active = state
    if not state then AS_Reset(); AS_ApplySpeed(false) end
end)

-- Trap skill checks are handled separately from generator skill checks.
local TrapSkill = { Enabled = false, Mode = "Legit", Busy = false, LastLine = nil, LastPress = 0 }
setConn("Tian_AutoTrapSkill", RunService.RenderStepped:Connect(function()
    if not TrapSkill.Enabled or TrapSkill.Busy then return end
    for _, guiName in ipairs({"SkillCheckPromptGui", "SkillCheckPromptGui-con"}) do
        local prompt = PGui2:FindFirstChild(guiName, true)
        if prompt and prompt.Enabled ~= false then
            local check = prompt:FindFirstChild("Check", true)
            if check and check.Visible then
                local line = check:FindFirstChild("Line", true)
                local target = check:FindFirstChild("TrapPerfect", true)
                if not (target and target.Visible) then target = check:FindFirstChild("TrapGoal", true) end
                if line and target and target.Visible then
                    local lr, tr = line.Rotation % 360, target.Rotation % 360
                    local shouldPress = false
                    if TrapSkill.Mode == "Instant" then
                        pcall(function() line.Rotation = target.Rotation + 109 end)
                        shouldPress = true
                    else
                        local startAngle, endAngle = (tr + 102) % 360, (tr + 116) % 360
                        shouldPress = AS_Crossed(TrapSkill.LastLine, lr, startAngle, endAngle)
                    end
                    TrapSkill.LastLine = lr
                    if shouldPress and os.clock() - TrapSkill.LastPress > 0.25 then
                        TrapSkill.Busy = true
                        TrapSkill.LastPress = os.clock()
                        task.spawn(function()
                            pcall(AS_PressSkill)
                            task.wait(TrapSkill.Mode == "Instant" and 0.35 or 0.08)
                            TrapSkill.Busy = false
                            TrapSkill.LastLine = nil
                        end)
                    end
                    return
                end
            end
        end
    end
    TrapSkill.LastLine = nil
end))
CreateToggle(TrapSkillSection, "Auto Skill Check Trap", false, function(v)
    TrapSkill.Enabled = v
    TrapSkill.LastLine = nil
    TrapSkill.Busy = false
end)
TianHubState.CreateDropdown(TrapSkillSection, "Trap Skillcheck Method", {"Legit", "Instant"}, TrapSkill.Mode, function(mode)
    TrapSkill.Mode = mode
    TrapSkill.LastLine = nil
end)

CreateSlider(AutomationSection, "Skill Check Speed", 0.1, 3, 1, "x", function(v)
    AutoSkill.Speed = v
end, 1)

local SkillModes = {"Normal","Perfect"}
TianHubState.CreateDropdown(AutomationSection, "Skillcheck Method", SkillModes, AutoSkill.Mode, function(mode)
    AutoSkill.Mode = mode
    AS_Reset()
    ShowToast("Skillcheck", "Method: "..mode)
end)
CreateToggle(AutomationSection, "Auto Normal Skill Check",  false, function(v) AutoSkill.KingScourge = v end)

CreateToggle(AutomationSection, "Hide Skill UI", false, function(state)
    AutoSkill.HideUI = state
    AS_HideUI()
end)

-- Manual Generator UI removed as requested.



-- Aim Lock Gun: isolated module with real FOV filtering, capped range and hold-to-aim.
do
    local GunAim = {
        Enabled = false, Holding = false, TargetMode = "Killer",
        Strength = 10, Predict = true, PredictStrength = 0.18,
        FOV = 100, LockDistance = 500, VisibilityCheck = false,
        AimPart = "HumanoidRootPart", Target = nil,
    }

    local GunAimConnection
    local CurrentGunButton
    local FOVGui, FOVCircle, FOVStroke

    local function GA_IsVisible(part)
        local cam = workspace.CurrentCamera
        if not cam or not part or not part.Parent then return true end
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
        rp.FilterDescendantsInstances = { LocalPlayer.Character }
        local origin = cam.CFrame.Position
        local result = workspace:Raycast(origin, part.Position - origin, rp)
        if not result then return true end
        return result.Instance:IsDescendantOf(part.Parent)
    end

    local function GA_GetButton()
        local current = LocalPlayer:FindFirstChild("PlayerGui")
        for segment in string.gmatch("Survivor-mob.Controls.Gui-mob", "[^%.]+") do
            current = current and current:FindFirstChild(segment)
        end
        return current
    end

    local function GA_IsValidPlayer(player)
        if player == LocalPlayer or not player.Character or not player.Team then return false end
        local teamName = string.lower(player.Team.Name or "")
        return string.find(teamName, "killer", 1, true) ~= nil
    end

    -- Returns the nearest valid target on screen and its screen-space distance.
    -- FOV is applied separately so the circle can show red/ purple accurately.
    local function GA_GetNearestCandidate()
        local cam = workspace.CurrentCamera
        if not cam then return nil, math.huge end
        local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
        local closest, shortest = nil, math.huge
        for _, player in ipairs(Players:GetPlayers()) do
            if GA_IsValidPlayer(player) then
                local character = player.Character
                local part = character:FindFirstChild(GunAim.AimPart)
                local humanoid = character:FindFirstChildOfClass("Humanoid")
                if part and humanoid and humanoid.Health > 0 then
                    local worldDistance = (part.Position - cam.CFrame.Position).Magnitude
                    if worldDistance <= GunAim.LockDistance then
                        local screenPosition, onScreen = cam:WorldToViewportPoint(part.Position)
                        if onScreen then
                            local screenDistance = (Vector2.new(screenPosition.X, screenPosition.Y) - center).Magnitude
                            if screenDistance < shortest then
                                if GunAim.VisibilityCheck and not GA_IsVisible(part) then continue end
                                shortest, closest = screenDistance, part
                            end
                        end
                    end
                end
            end
        end
        return closest, shortest
    end

    local function GA_CreateFOV()
        if FOVGui and FOVGui.Parent then return end
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not playerGui then return end
        FOVGui = Instance.new("ScreenGui")
        FOVGui.Name = "TianHub_AimlockGun_FOV"
        FOVGui.ResetOnSpawn = false
        FOVGui.IgnoreGuiInset = true
        FOVGui.DisplayOrder = 999
        FOVGui.Enabled = false
        FOVGui.Parent = playerGui

        FOVCircle = Instance.new("Frame")
        FOVCircle.Name = "FOVCircle"
        FOVCircle.AnchorPoint = Vector2.new(0.5, 0.5)
        FOVCircle.Position = UDim2.fromScale(0.5, 0.5)
        FOVCircle.Size = UDim2.fromOffset(GunAim.FOV * 2, GunAim.FOV * 2)
        FOVCircle.BackgroundTransparency = 1
        FOVCircle.BorderSizePixel = 0
        FOVCircle.Parent = FOVGui
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = FOVCircle
        FOVStroke = Instance.new("UIStroke")
        FOVStroke.Thickness = 2
        FOVStroke.Transparency = 0
        FOVStroke.Color = Color3.fromRGB(190, 115, 255)
        FOVStroke.Parent = FOVCircle
    end

    local function GA_UpdateFOV(candidateDistance)
        GA_CreateFOV()
        if not FOVGui or not FOVCircle then return end
        local cam = workspace.CurrentCamera
        if not cam then FOVGui.Enabled = false; return end
        FOVCircle.Size = UDim2.fromOffset(GunAim.FOV * 2, GunAim.FOV * 2)
        FOVGui.Enabled = GunAim.Enabled
        if FOVStroke then
            FOVStroke.Color = (candidateDistance <= GunAim.FOV)
                and Color3.fromRGB(255, 65, 65)
                or Color3.fromRGB(190, 115, 255)
        end
    end

    local function GA_Start()
        if GunAimConnection then return end
        GunAimConnection = RunService.RenderStepped:Connect(function()
            if not GunAim.Enabled then
                GunAim.Target = nil
                if FOVGui then FOVGui.Enabled = false end
                return
            end
            local candidate, screenDistance = GA_GetNearestCandidate()
            GA_UpdateFOV(screenDistance)
            if not GunAim.Holding then
                GunAim.Target = nil
                return
            end
            if not candidate or screenDistance > GunAim.FOV then
                GunAim.Target = nil
                return
            end
            GunAim.Target = candidate
            local aimPosition = candidate.Position
            if GunAim.Predict then
                aimPosition = aimPosition + candidate.AssemblyLinearVelocity * GunAim.PredictStrength
            end
            local cam = workspace.CurrentCamera
            if cam then
                local strength = math.clamp(tonumber(GunAim.Strength) or 10, 1, 20)
                local alpha

                -- 1-10: gradual tracking; 11-15: strong lock; 16-20: near-instant to instant.
                if strength <= 10 then
                    alpha = strength * 0.055
                elseif strength <= 15 then
                    alpha = 0.55 + (strength - 10) * 0.07
                else
                    alpha = 0.90 + (strength - 15) * 0.02
                end

                cam.CFrame = cam.CFrame:Lerp(
                    CFrame.new(cam.CFrame.Position, aimPosition),
                    math.clamp(alpha, 0, 1)
                )
            end
        end)
    end

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.UserInputType == Enum.UserInputType.MouseButton2 and GunAim.Enabled then
            GunAim.Holding = true
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            GunAim.Holding = false
            GunAim.Target = nil
        end
    end)

    task.spawn(function()
        while true do
            task.wait(1)
            local button = GA_GetButton()
            if button and button ~= CurrentGunButton then
                CurrentGunButton = button
                button.InputBegan:Connect(function(input)
                    if (input.UserInputType == Enum.UserInputType.Touch
                        or input.UserInputType == Enum.UserInputType.MouseButton2) and GunAim.Enabled then
                        GunAim.Holding = true
                    end
                end)
                button.InputEnded:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.Touch
                        or input.UserInputType == Enum.UserInputType.MouseButton2 then
                        GunAim.Holding = false
                        GunAim.Target = nil
                    end
                end)
            end
        end
    end)

    TianHubState.GunAimGun = GunAim
    TianHubState.GunAimGunStart = GA_Start
end

local ToFSection = CreateSection(SurvTab, "SILENT AIM TOF", false)
CreateToggle(ToFSection, "Enable Silent Aim TOF", false, function(v)
    local api = getgenv().TianHub_TOF
    if api then api.setEnabled(v) end
end)
CreateToggle(ToFSection, "Smart Predict", true, function(v)
    local api = getgenv().TianHub_TOF
    if api then api.setSmartPredict(v) end
end)
CreateToggle(ToFSection, "Predict Move", false, function(v)
    local api = getgenv().TianHub_TOF
    if api then api.setPredict(v) end
end)
CreateToggle(ToFSection, "ZigZag Predict", false, function(v)
    local api = getgenv().TianHub_TOF
    if api then api.setZigZag(v) end
end)
CreateToggle(ToFSection, "Show Aim Laser", true, function(v)
    local api = getgenv().TianHub_TOF
    if api then api.setShowLaser(v) end
end)
CreateSlider(ToFSection, "FOV Range", 10, 360, 360, "°", function(v)
    local api = getgenv().TianHub_TOF
    if api then api.setFOV(v) end
end)
CreateSlider(ToFSection, "Lead Scale", 30, 300, 100, "%", function(v)
    local api = getgenv().TianHub_TOF
    if api then api.setLeadScale(v) end
end)



local AimlockGunSection = CreateSection(SurvTab, "AIMBOT SURVIVOR", false)
local AimlockGunConfig = TianHubState.GunAimGun

CreateToggle(AimlockGunSection, "Enable Aimbot Survivor", false, function(v)
    AimlockGunConfig.Enabled = v
    if v and TianHubState.GunAimGunStart then
        TianHubState.GunAimGunStart()
    end
    if not v then
        AimlockGunConfig.Holding = false
        AimlockGunConfig.Target = nil
    end
    ShowToast("Aimbot Survivor", v and "Enabled — hold M2 / mobile attack" or "Disabled")
end)
-- Target mode is fixed to Killer; no target-mode selector is shown.
AimlockGunConfig.TargetMode = "Killer"
CreateSlider(AimlockGunSection, "FOV Radius", 50, 1000, 100, "px", function(v)
    AimlockGunConfig.FOV = v
end, 0)
CreateSlider(AimlockGunSection, "Lock Distance", 25, 1000, 500, " studs", function(v)
    AimlockGunConfig.LockDistance = math.clamp(tonumber(v) or 500, 25, 1000)
end, 0)
CreateSlider(AimlockGunSection, "Aim Smoothness", 1, 20, 10, "x", function(v)
    AimlockGunConfig.Strength = math.clamp(math.floor(tonumber(v) or 10), 1, 20)
end, 0)
CreateSlider(AimlockGunSection, "Prediction Strength", 0, 1, 0.18, "x", function(v)
    AimlockGunConfig.PredictStrength = v
end, 2)
-- Visibility check remains available internally but is hidden and defaults OFF.
AimlockGunConfig.VisibilityCheck = false

do
-- Pistol X Predict source integrated as TianHub's complete Silent Aim TOF implementation.
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")

local LP        = Players.LocalPlayer
local unloaded  = false
local connections = {}
local function track(conn)
    table.insert(connections, conn)
    return conn
end

local function getTOFGunPart(ch)
    local tool = ch and ch:FindFirstChild("Twist of Fate", true)
    if not tool then return nil end
    local rightArm = tool:FindFirstChild("Right Arm", true)
    if rightArm then
        for _, name in ipairs({ "gun", "EmperorGun" }) do
            local gun = rightArm:FindFirstChild(name)
            if gun then
                if gun:IsA("BasePart") then return gun end
                local part = gun:FindFirstChildWhichIsA("BasePart", true)
                if part then return part end
            end
        end
    end
    if tool:IsA("BasePart") then return tool end
    return tool:FindFirstChildWhichIsA("BasePart", true)
end

local function getTOFLaserOrigin(ch)
    local gunPart = getTOFGunPart(ch)
    return gunPart and gunPart.Position or nil
end

local State = {}

-- ============================================================
-- MOTION (legacy predictor, dipakai kalau SmartPredict = false)
-- ============================================================
State.Motion = {}
do
    local M   = State.Motion
    local exp = math.exp
    function M.Regress(list, tn, window, tau)
        if not list then return nil end
        local sw, sdt, sdt2, n = 0, 0, 0, 0
        local sp, sdtp = Vector3.zero, Vector3.zero
        for i = #list, 1, -1 do
            local e = list[i]
            local dt = e.t - tn
            if dt < -window then break end
            local w = exp(dt / tau)
            sw   = sw   + w
            sdt  = sdt  + w * dt
            sdt2 = sdt2 + w * dt * dt
            sp   = sp   + e.p * w
            sdtp = sdtp + e.p * (w * dt)
            n    = n + 1
        end
        if n < 3 then return nil end
        local denom = sw * sdt2 - sdt * sdt
        if denom < 1e-9 then return nil end
        local slope = (sdtp * sw - sp * sdt) / denom
        local c     = (sp - slope * sdt) / sw
        return slope, c, n
    end
    function M.Estimate(list)
        if not list or #list < 4 then return nil end
        local tn = list[#list].t
        local vS = M.Regress(list, tn, 0.14, 0.07)
        local vL = M.Regress(list, tn, 0.40, 0.2)
        if not vS and not vL then return nil end
        if not vS then return vL, Vector3.zero, false end
        if not vL then return vS, Vector3.zero, false end
        local fs, fl = Vector3.new(vS.X, 0, vS.Z), Vector3.new(vL.X, 0, vL.Z)
        local reversal = fl.Magnitude > 2 and fs.Magnitude > 2 and fs:Dot(fl) < 0
        local vel = reversal and vS or (vS * 0.7 + vL * 0.3)
        local acc = (vS - vL) / 0.12
        if acc.Magnitude > 50 then acc = acc.Unit * 50 end
        return vel, acc, reversal
    end
end

-- ============================================================
-- HIGHLIGHT MARK
-- ============================================================
do
    local marks = {}
    local function setNameColor(char, color)
        pcall(function()
            local bb  = char and char:FindFirstChild("PE_Text")
            local box = bb and bb:FindFirstChild("Box")
            local row = box and box:FindFirstChild("NameRow")
            local lbl = row and row:FindFirstChild("NameText")
            if lbl and lbl:IsA("TextLabel") then lbl.TextColor3 = color end
        end)
    end
    local function clear(key)
        local m = marks[key]
        if not m then return end
        marks[key] = nil
        if m.highlight then pcall(function() m.highlight:Destroy() end) end
        if m.char then
            local stillMarked, activeColor = false, nil
            for _, other in pairs(marks) do
                if other.char == m.char then
                    stillMarked = true
                    activeColor = other.color
                    break
                end
            end
            if stillMarked then
                setNameColor(m.char, activeColor or Color3.fromRGB(255, 40, 40))
            else
                setNameColor(m.char, Color3.fromRGB(240, 240, 248))
            end
        end
    end
    State.ClearMark = clear
    State.SetMark = function(key, char, color)
        if not char or not char.Parent then return clear(key) end
        local m = marks[key]
        if m and m.char == char and m.highlight and m.highlight.Parent == char then
            m.highlight.FillColor         = color
            m.highlight.OutlineColor      = Color3.new(1, 1, 1)
            m.highlight.FillTransparency  = 0
            m.highlight.OutlineTransparency = 0
            m.color = color
            setNameColor(char, color)
            return
        end
        clear(key)
        local hl = Instance.new("Highlight")
        hl.Name    = "TianHub_TargetHighlight_" .. tostring(key)
        hl.Adornee = char
        hl.FillColor    = color
        hl.OutlineColor = Color3.new(1, 1, 1)
        hl.FillTransparency    = 0
        hl.OutlineTransparency = 0
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent    = char
        setNameColor(char, color)
        marks[key] = { char = char, highlight = hl, color = color }
    end
end

-- ============================================================
-- AIM HOLD (FireServer sniffer)
-- ============================================================
State.AimHold = { held = false, ok = false, tried = false }
do
    local AH  = State.AimHold
    local old
    AH.Install = function()
        if AH.tried then return end
        AH.tried = true
        if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then return end
        local wrapf = newcclosure or function(f) return f end
        local ok = pcall(function()
            old = hookmetamethod(game, "__namecall", wrapf(function(self, ...)
                local method = getnamecallmethod()
                if setnamecallmethod then setnamecallmethod(method) end
                if not unloaded and method == "FireServer" and typeof(self) == "Instance"
                   and self.Name == "AimHold" and self.ClassName == "RemoteEvent" then
                    local v = select(2, ...)
                    if type(v) == "boolean" then AH.held = v end
                end
                if setnamecallmethod then setnamecallmethod(method) end
                return old(self, ...)
            end))
        end)
        AH.ok = ok and old ~= nil
    end
end

-- ============================================================
-- TOF SETTINGS
-- ============================================================
State.TOFSilent = {
    Enabled    = false,
    FOV        = 360,
    Predict    = false,
    ZigZag     = false,
    LeadScale  = 100,
    ShowCircle = false,
    ShowLaser  = true,
    -- ===== SMART PREDICT =====
    SmartPredict = true,   -- master: pakai sistem baru (fallback ke lama kalau false)
    UseSnap      = true,   -- pakai snapshot server (NetRemote) untuk velocity akurat
    UseTravel    = true,   -- belajar waktu terbang peluru otomatis
    WallCheck    = true,   -- clamp lead kalau ketemu dinding
    Windup       = 0.05,   -- jeda dasar sebelum learning aktif
    LineSmooth   = 70,     -- 0 = mentah, 100 = halus (garis preview saja)
}

-- ============================================================
-- SMART PREDICTION MODULE
-- ============================================================
State.SmartPredict = (function()
    local T  = State.TOFSilent
    local SP = {}

    -- VD = Value Data: nilai yang dipelajari otomatis dari tembakan asli
    local VD = {
        TOF_HitGainN    = 1,     -- gain lead jarak dekat
        TOF_HitGainM    = 1,     -- gain lead jarak sedang
        TOF_HitGainF    = 1,     -- gain lead jarak jauh
        TOF_TravelK     = 0.5,   -- faktor waktu terbang
        TOF_BulletSpeed = 800,   -- kecepatan peluru (auto-update dari server)
        TOF_DelayAuto   = nil,   -- delay tembak terpelajari (nil = belum)
    }
    SP.VD = VD

    local Track   = setmetatable({}, { __mode = "k" })
    local SnapBuf = {}
    local Shot    = nil
    local LastPred, LastReal = nil, nil
    local RawMode = false
    local LastVel, LastMult, LastBase, LastVB = nil, 1, 0, 800

    function SP.Ping()
        local p = 0.08
        pcall(function() p = math.clamp(LP:GetNetworkPing(), 0, 0.35) end)
        return p
    end

    function SP.Delay()
        if tonumber(VD.TOF_DelayAuto) then
            return math.clamp(VD.TOF_DelayAuto, 0.05, 1.5)
        end
        return (tonumber(T.Windup) or 0.05) + SP.Ping() * 0.8
    end

    local function Band(d) return d < 15 and "N" or (d < 35 and "M" or "F") end
    SP.Band = Band

    function SP.ArcDisp(vel, omega, Tm)
        local N, dt = 6, Tm / 6
        local rot = CFrame.Angles(0, omega * dt, 0)
        local pos, dir = Vector3.zero, vel
        for _ = 1, N do
            pos = pos + dir * dt
            dir = rot:VectorToWorldSpace(dir)
        end
        return pos
    end

    function SP.ConfEff(S)
        if math.abs(S.omega or 0) > 0.35 then return math.max(S.conf, 0.6) end
        return S.conf
    end

    -- ---------- VisualizeBullet hook: belajar delay & gain ----------
    local hooked = setmetatable({}, { __mode = "k" })
    local function HookBullet(r)
        if hooked[r] then return end
        hooked[r] = true
        r.OnClientEvent:Connect(function(origin, endp, spd)
            local sh = Shot
            if not sh or sh.used or typeof(origin) ~= "Vector3" or typeof(endp) ~= "Vector3" then return end
            local dt = os.clock() - sh.t
            if dt < 0.05 or dt > 1.6 then return end
            local ch  = LP.Character
            local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
            if not hrp or (origin - hrp.Position).Magnitude > 15 then return end
            sh.used = true
            if type(spd) == "number" and spd > 5 then VD.TOF_BulletSpeed = spd end
            local cur = tonumber(VD.TOF_DelayAuto)
            VD.TOF_DelayAuto = cur and (cur + (dt - cur) * 0.3) or dt
            if sh.real and sh.aim and sh.tc and sh.vel then
                task.delay(0.1, function()
                    local root = sh.tc:FindFirstChild("HumanoidRootPart") or sh.tc:FindFirstChild("Torso")
                    if not (root and root.Parent) then return end
                    local real, aim = sh.real, sh.aim
                    local L  = Vector3.new(aim.X - real.X, 0, aim.Z - real.Z)
                    local D  = Vector3.new(root.Position.X - real.X, 0, root.Position.Z - real.Z)
                    local vh = Vector3.new(sh.vel.X, 0, sh.vel.Z)
                    if L.Magnitude <= 2 or vh.Magnitude <= 2 or D.Magnitude < 0.5 then return end
                    if D:Dot(vh) <= 0 or D.Unit:Dot(vh.Unit) < 0.6 then return end
                    local vb = sh.vb or 200
                    local travel = (sh.d or 0) / vb
                    if T.UseTravel and travel >= 0.1 then
                        local tTrue = D:Dot(vh) / vh:Dot(vh)
                        local tUsed = tTrue / math.max(sh.mult or 1, 0.2)
                        local kTrue = (tUsed - (sh.base or 0)) / travel
                        local k = tonumber(VD.TOF_TravelK) or 0.5
                        VD.TOF_TravelK = math.clamp(k + (math.clamp(kTrue, 0, 2.5) - k) * 0.25, 0, 2.5)
                    else
                        local ratio = math.clamp(D:Dot(L) / L:Dot(L), 0, 2.5)
                        local key = "TOF_HitGain" .. (sh.band or "M")
                        local g = tonumber(VD[key]) or 1
                        VD[key] = math.clamp(g + (g * ratio - g) * 0.3, 0.3, 2)
                    end
                end)
            end
        end)
    end

    task.spawn(function()
        local rs = game:GetService("ReplicatedStorage")
        local function try(d)
            if d.Name == "VisualizeBullet"
               and (d:IsA("RemoteEvent") or d.ClassName == "UnreliableRemoteEvent") then
                pcall(HookBullet, d)
            end
        end
        for _, d in ipairs(rs:GetDescendants()) do try(d) end
        rs.DescendantAdded:Connect(try)
    end)

    -- ---------- NetRemote snapshot (posisi server ~30Hz) ----------
    task.spawn(function()
        local rs = game:GetService("ReplicatedStorage")
        local r = rs:WaitForChild("Remotes", 15)
        r = r and r:WaitForChild("Mechanics", 15)
        r = r and r:WaitForChild("NetRemote", 15)
        if not r then return end
        r.OnClientEvent:Connect(function(pkt)
            if not (T.SmartPredict and T.UseSnap) then return end
            if type(pkt) ~= "table" or pkt.kind ~= "Snapshot" then return end
            local dd = pkt.data
            if type(dd) ~= "table" or type(dd.players) ~= "table" or type(dd.t) ~= "number" then return end
            local nowc = os.clock()
            for _, pe in pairs(dd.players) do
                if type(pe) == "table" and typeof(pe.pos) == "Vector3" and type(pe.id) == "number" then
                    local e = SnapBuf[pe.id]
                    if not e then e = { s = {} }; SnapBuf[pe.id] = e end
                    local sb = e.s
                    local last = sb[#sb]
                    if not last or dd.t > last.ts then
                        if last and (pe.pos - last.pos).Magnitude / math.max(dd.t - last.ts, 0.001) > 250 then
                            e.s = {}; sb = e.s
                        end
                        sb[#sb + 1] = { ts = dd.t, pos = pe.pos, tl = nowc }
                        while #sb > 24 do table.remove(sb, 1) end
                    end
                end
            end
        end)
    end)

    function SP.GetSnap(char)
        local pl = char and Players:GetPlayerFromCharacter(char)
        local e  = pl and SnapBuf[pl.UserId]
        if not e then return nil end
        local sb, n = e.s, #(e.s)
        if n < 3 then return nil end
        local last = sb[n]
        if os.clock() - last.tl > 0.4 then return nil end
        local function seg(t0, t1)
            local a, b
            for i = 1, n do
                local x   = sb[i]
                local age = last.ts - x.ts
                if age >= t0 and age <= t1 then
                    if not a then a = x end
                    b = x
                end
            end
            if a and b and b.ts - a.ts >= 0.07 then
                local v = (b.pos - a.pos) / (b.ts - a.ts)
                return Vector3.new(v.X, 0, v.Z), v.Y
            end
        end
        local w0, vy = seg(0, 0.15)
        if not w0 then return nil end
        local vNow = seg(0, 0.1)
        local vs = vNow or w0
        if vs.Magnitude < 1 then vs = Vector3.zero end
        local w1, w2 = seg(0.15, 0.3), seg(0.3, 0.45)
        local conf, omega = 1, 0
        local function turn(a, b)
            if not (a and b) or a.Magnitude < 2 or b.Magnitude < 2 then return nil end
            local phi = math.atan2(a.Z, a.X) - math.atan2(b.Z, b.X)
            if phi > math.pi then phi = phi - 2*math.pi elseif phi < -math.pi then phi = phi + 2*math.pi end
            return phi
        end
        local flips = 0
        if w0 and w1 and w0.Magnitude > 2 and w1.Magnitude > 2 and w0.Unit:Dot(w1.Unit) < 0.2 then flips = flips + 1 end
        if w1 and w2 and w1.Magnitude > 2 and w2.Magnitude > 2 and w1.Unit:Dot(w2.Unit) < 0.2 then flips = flips + 1 end
        if flips >= 2 then
            local net = seg(0, 0.45)
            vs = net or Vector3.zero
            if vs.Magnitude < 1.5 then vs = Vector3.zero end
            return { pos = last.pos, tl = last.tl, vel = vs, vy = vy or 0, conf = 0.6, omega = 0 }
        end
        local p1, p2 = turn(w1, w0), turn(w2, w1)
        if p1 and p2 and math.abs(p1) > 0.08 and math.abs(p2) > 0.08 then
            if p1 * p2 > 0 then
                omega = math.clamp((p1 + p2) / 2 / 0.15, -8, 8)
            else
                conf = 0.5
            end
        end
        return { pos = last.pos, tl = last.tl, vel = vs, vy = vy or 0, conf = conf, omega = omega }
    end

    function SP.SampleVel(char)
        local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
        if not (root and root:IsA("BasePart")) then return end
        local S = Track[char]
        if not S then
            S = { s = {}, pend = {}, mAuto = 1, conf = 1, omega = 0,
                  vShort = Vector3.zero, lead = Vector3.zero, leadT = 0, lastPend = 0 }
            Track[char] = S
        end
        local now, pos = os.clock(), root.Position
        local s = S.s
        local last = s[#s]
        if last then
            if now - last.t < 0.004 then return end
            if (pos - last.pos).Magnitude / (now - last.t) > 200 then
                S.s = {}; S.pend = {}; S.lead = Vector3.zero; s = S.s
            end
        end
        s[#s + 1] = { t = now, pos = pos }
        while #s > 2 and now - s[1].t > 0.45 do table.remove(s, 1) end

        local function seg(t0, t1)
            local a, b
            for i = 1, #s do
                local e = s[i]
                if e.t >= now - t1 and e.t <= now - t0 then
                    if not a then a = e end
                    b = e
                end
            end
            if a and b and b.t - a.t >= 0.04 then
                local v = (b.pos - a.pos) / (b.t - a.t)
                return Vector3.new(v.X, 0, v.Z), v.Y
            end
        end
        local vs, vy = seg(0, 0.15)
        vs = vs or Vector3.zero
        S.vy = vy or 0
        if vs.Magnitude < 1 then vs = Vector3.zero end
        local vl = seg(0.15, 0.4)
        local conf = 1
        if vl and vs.Magnitude > 1 and vl.Magnitude > 1 then
            conf = math.clamp(vs.Unit:Dot(vl.Unit), 0.25, 1)
        end
        S.vShort, S.conf = vs, conf
        if vl and vs.Magnitude > 2 and vl.Magnitude > 2 then
            local phi = math.atan2(vl.Z, vl.X) - math.atan2(vs.Z, vs.X)
            if phi > math.pi then phi = phi - 2*math.pi elseif phi < -math.pi then phi = phi + 2*math.pi end
            S.omega = S.omega * 0.5 + math.clamp(phi / 0.2, -8, 8) * 0.5
        else
            S.omega = S.omega * 0.8
        end

        S.vIn, S.stopping, S.air = nil, false, false
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            local md  = hum.MoveDirection
            local mdh = Vector3.new(md.X, 0, md.Z)
            if mdh.Magnitude > 0.1 then
                if not S.hadInput then S.inT0 = now; S.holdT0 = now end
                local dirNow = mdh.Unit
                if S.inDir and S.inDir:Dot(dirNow) < 0.9 then S.inT0 = now end
                S.inDir = dirNow
                S.hadInput = true
                local wsNow = hum.WalkSpeed
                if wsNow > 0 and (now - (S.holdT0 or now)) > 0.15 and vs.Magnitude < 0.3 * wsNow then
                    if not S.blocked then S.blocked = true; S.blockDir = dirNow end
                elseif wsNow > 0 and vs.Magnitude >= 0.5 * wsNow then
                    S.blocked = false
                end
                if vs.Magnitude > 2 then S.mdWorks = true end
                if vs.Magnitude > 2 then
                    S.vIn = mdh.Unit * vs.Magnitude
                elseif hum.WalkSpeed > 0 then
                    S.vIn = mdh.Unit * hum.WalkSpeed * 0.6
                end
            else
                S.hadInput = false
                S.blocked, S.inDir = false, nil
                if S.mdWorks then S.stopping = true end
            end
            local okf, fm = pcall(function() return hum.FloorMaterial end)
            S.air = okf and fm == Enum.Material.Air
        end

        -- SMART: bandingkan prediksi vs posisi nyata → belajar multiplier
        local pend = S.pend
        if T.SmartPredict then
            if vs.Magnitude > 2 and conf > 0.7 and now - S.lastPend > 0.06 and #pend < 24 then
                local tau = SP.Delay()
                S.lastPend = now
                pend[#pend + 1] = { due = now + tau, base = pos, vl = vs * tau }
            end
            local i = 1
            while i <= #pend do
                local pd = pend[i]
                if now >= pd.due then
                    local disp = pos - pd.base
                    disp = Vector3.new(disp.X, 0, disp.Z)
                    local den = pd.vl:Dot(pd.vl)
                    if den > 1 then
                        local m = math.clamp(disp:Dot(pd.vl) / den, 0, 2.5)
                        S.mAuto = S.mAuto + (m - S.mAuto) * 0.12
                    end
                    table.remove(pend, i)
                else
                    i = i + 1
                end
            end
        elseif #pend > 0 then
            S.pend = {}
        end
    end

    -- Inti prediksi. Return aimPos (Vector3) atau nil (target diam / dekat).
    function SP.Compute(t, tc, op, d)
        LastReal, LastPred = nil, nil
        if not (T.SmartPredict and tc) then return nil end

        SP.SampleVel(tc)
        local S = Track[tc]
        if not S then return nil end

        local SN   = T.UseSnap and SP.GetSnap(tc) or nil
        local hrpR = tc:FindFirstChild("HumanoidRootPart")
        if SN and (not hrpR or (SN.pos - hrpR.Position).Magnitude > 50) then SN = nil end
        if SN then
            S.vShort, S.vy, S.omega, S.conf = SN.vel, SN.vy, SN.omega, SN.conf
        end

        local vel  = S.vShort or Vector3.zero
        local nowc = os.clock()
        if S.vIn then
            local startingUp = S.inT0 and (nowc - S.inT0) < 0.25
            local exiting = S.blocked and S.blockDir and S.vIn.Magnitude > 0.1
                and S.vIn.Unit:Dot(S.blockDir) < 0.85
            if exiting then
                vel = S.vIn.Unit * math.max(vel.Magnitude, S.vIn.Magnitude * 0.8)
            elseif startingUp or vel.Magnitude >= 0.5 * S.vIn.Magnitude then
                vel = vel:Lerp(S.vIn, startingUp and 0.6 or 0.5)
            end
        elseif S.stopping then
            vel = vel * 0.3
        end

        local vy = S.vy or 0
        if not (vel.Magnitude > 1 or (S.air and math.abs(vy) > 1)) then
            S.lead  = Vector3.zero
            S.leadT = nowc
            return nil
        end

        -- dekat: tidak perlu lead
        if d < 5 then
            S.lead  = Vector3.zero
            S.leadT = nowc
            return nil
        end

        local tp = t.Position
        local mult = math.clamp(
            math.clamp(S.mAuto, 0.2, 1.8) * SP.ConfEff(S)
                * (tonumber(VD["TOF_HitGain" .. SP.Band(d)]) or 1),
            0.3, 1.6
        )

        local base = SP.Delay()
        local vb   = math.max(tonumber(VD.TOF_BulletSpeed) or 800, 50)
        local kT   = T.UseTravel and math.clamp(tonumber(VD.TOF_TravelK) or 0.5, 0, 2.5) or 0
        local om   = S.omega or 0
        local ex, snapOff, realBase = 0, Vector3.zero, tp
        if SN then
            ex = math.clamp(os.clock() - SN.tl, 0, 0.15)
            local off = hrpR and (tp - hrpR.Position) or Vector3.zero
            realBase = SN.pos + off
            snapOff  = realBase - tp
        end

        local function leadFor(dl0)
            local dl = dl0 + ex
            local ld = vel * dl * mult
            if vel.Magnitude > 2 and math.abs(om) > 0.35 then
                local lim = math.rad(100) / math.max(dl, 0.05)
                local omE = math.clamp(om * 0.7, -lim, lim)
                ld = SP.ArcDisp(vel, omE, dl) * mult
            end
            local cap = math.clamp(math.max(d * 0.6, vel.Magnitude * dl * mult * 1.2), 3, 120)
            if ld.Magnitude > cap then ld = ld.Unit * cap end
            return ld
        end

        local delay = base + kT * d / vb
        local lead  = leadFor(delay)
        if kT > 0 then
            for _ = 1, 2 do
                delay = base + kT * (tp + lead - op).Magnitude / vb
                lead  = leadFor(delay)
            end
        end

        -- prediksi vertikal (lompat / jatuh)
        local dy = 0
        if S.air then
            dy = vy * delay - 0.5 * workspace.Gravity * delay * delay
            local okr, hit = pcall(function()
                local rp2 = RaycastParams.new()
                rp2.FilterType = Enum.RaycastFilterType.Exclude
                rp2.FilterDescendantsInstances = { tc, LP.Character }
                return workspace:Raycast(tp, Vector3.new(0, -300, 0), rp2)
            end)
            if okr and hit then dy = math.max(dy, -((tp.Y - hit.Position.Y) - 1)) end
            dy = math.clamp(dy, -40, 25)
        end

        -- clamp di dinding (target tidak bisa menembus)
        if T.WallCheck then
            local lh = Vector3.new(lead.X, 0, lead.Z)
            if lh.Magnitude > 1.5 then
                local okw, wh = pcall(function()
                    local rp3 = RaycastParams.new()
                    rp3.FilterType = Enum.RaycastFilterType.Exclude
                    rp3.RespectCanCollide = true
                    local ex2 = { tc, LP.Character }
                    for _, pl2 in ipairs(Players:GetPlayers()) do
                        if pl2.Character then ex2[#ex2 + 1] = pl2.Character end
                    end
                    rp3.FilterDescendantsInstances = ex2
                    return workspace:Raycast(realBase, lh, rp3)
                end)
                if okw and wh then
                    local wd = math.max((wh.Position - realBase).Magnitude - 1.2, 0)
                    lead = lh.Unit * math.min(wd, lh.Magnitude) + Vector3.new(0, lead.Y, 0)
                end
            end
        end

        lead = lead + snapOff
        lead = Vector3.new(lead.X, dy + snapOff.Y, lead.Z)
        LastReal = realBase
        LastVel, LastMult, LastBase, LastVB = vel, mult, base, vb

        -- smoothing untuk garis preview
        local dt = math.clamp(nowc - S.leadT, 0, 0.2)
        S.leadT = nowc
        local sm   = math.clamp((tonumber(T.LineSmooth) or 70) / 100, 0, 1)
        local rate = 80 * (1 - sm) + 8 * sm
        S.lead = S.lead:Lerp(lead, math.clamp(dt * rate, 0.05, 1))
        local aimPos = tp + (RawMode and lead or S.lead)

        LastPred = {
            tc = tc, real = LastReal or tp, aim = aimPos, band = SP.Band(d),
            vel = LastVel, mult = LastMult, base = LastBase, d = d, vb = LastVB,
        }
        return aimPos
    end

    function SP.RecordShot()
        local lp = LastPred
        if not lp then return end
        Shot = {
            t = os.clock(), tc = lp.tc, real = lp.real, aim = lp.aim, band = lp.band,
            vel = lp.vel, mult = lp.mult, base = lp.base, d = lp.d, vb = lp.vb, used = false,
        }
    end

    function SP.SetRawMode(v) RawMode = v == true end
    SP.Track = Track

    -- sampling kontinu (biar history siap walau belum aiming)
    track(RunService.Heartbeat:Connect(function()
        if unloaded or not T.SmartPredict then return end
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and p.Character then SP.SampleVel(p.Character) end
        end
    end))

    return SP
end)()

-- ============================================================
-- SILENT AIM (dengan SmartPredict terintegrasi)
-- ============================================================
State.SilentObj = (function()
    local T   = State.TOFSilent
    local obj = {}
    local effects, original
    local installing = false

    local killerCache, killerCacheAt = nil, 0
    local function killerChar()
        local now = os.clock()
        if killerCache and killerCache.Parent and now - killerCacheAt < 0.5 then return killerCache end
        killerCacheAt = now
        killerCache = nil
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and p.Character then
                local team = p.Team and string.lower(p.Team.Name) or ""
                if string.find(team, "killer", 1, true) or p.Character:FindFirstChild("Lookscriptkiller", true) then
                    killerCache = p.Character
                    return killerCache
                end
            end
        end
        return nil
    end

    local function targetPart(ch)
        local pick = T.AimPart
        if pick == "Head" then
            local h = ch:FindFirstChild("Head")
            if h then return h end
        elseif pick == "HumanoidRootPart" then
            local r = ch:FindFirstChild("HumanoidRootPart")
            if r then return r end
        end
        return ch:FindFirstChild("UpperTorso") or ch:FindFirstChild("Torso") or ch:FindFirstChild("HumanoidRootPart")
    end

    local function hasTOF(ch)
        if not ch then return false end
        if ch:FindFirstChild("Twist of Fate") then return true end
        local eq = string.lower(tostring(LP:GetAttribute("EquippedItem") or ""))
        return eq:find("twist", 1, true) ~= nil or eq:find("fate", 1, true) ~= nil
    end

    local function muzzle(ch)
        return getTOFLaserOrigin(ch)
    end

    -- konstanta legacy predictor
    local PROJ_SPEED     = 800
    local INTERP_DELAY   = 0.05
    local HISTORY_KEEP   = 1.4
    local VEL_CAP        = 60
    local Y_VEL_CLAMP    = 14
    local TELEPORT_STEP  = 12
    local history = setmetatable({}, { __mode = "k" })

    local function record(part, now)
        local list = history[part]
        if not list then list = {}; history[part] = list end
        local pos  = part.Position
        local last = list[#list]
        if last and (pos - last.p).Magnitude > TELEPORT_STEP then table.clear(list) end
        list[#list + 1] = { t = now, p = pos }
        while #list > 2 and now - list[1].t > HISTORY_KEEP do table.remove(list, 1) end
    end

    local function limitVel(v)
        v = Vector3.new(v.X, math.clamp(v.Y, -Y_VEL_CLAMP, Y_VEL_CLAMP), v.Z)
        if v.Magnitude > VEL_CAP then v = v.Unit * VEL_CAP end
        return v
    end
    local function flat(v) return Vector3.new(v.X, 0, v.Z) end

    local function latencyLead()
        local ok, ping = pcall(function() return LP:GetNetworkPing() end)
        local rtt = (ok and type(ping) == "number" and ping > 0) and math.clamp(ping, 0.02, 0.4) or 0.08
        return (rtt + INTERP_DELAY) * 0.8
    end

    -- legacy recorder (dipakai kalau SmartPredict = false dan Predict/ZigZag on)
    track(RunService.Heartbeat:Connect(function()
        if unloaded or not (T.Enabled and not T.SmartPredict and (T.Predict or T.ZigZag)) then return end
        local kc = killerChar()
        local part = kc and targetPart(kc)
        if part then record(part, os.clock()) end
    end))

    local function observedVel(part)
        local list = history[part]
        if not list or #list < 3 then return nil end
        if os.clock() - list[#list].t > 0.15 then return nil end
        return State.Motion.Regress(list, list[#list].t, 0.14, 0.07)
    end

    local function getVelocity(part, hrp, hum)
        local base = hrp.AssemblyLinearVelocity
        local obs  = observedVel(part)
        if obs and obs.Magnitude > 3 and obs.Magnitude < 120 then
            local bf = flat(base)
            if bf.Magnitude < 1.5 or flat(obs):Dot(bf) < 0 then base = obs end
        end
        if hum then
            local md = hum.MoveDirection
            if md.Magnitude > 0.05 then
                local intent = md * hum.WalkSpeed
                local bf = flat(base)
                if bf.Magnitude > 0.5 and flat(intent):Dot(bf) < 0 then base = intent end
            end
        end
        return limitVel(base)
    end

    local function zzResiduals(list, tn, centerAt)
        local res = {}
        for i = 1, #list do
            local e = list[i]
            if e.t >= tn - 1.2 then res[#res + 1] = { t = e.t, p = e.p, r = flat(e.p - centerAt(e.t)) } end
        end
        return res
    end

    local function zzCross(res, u)
        local sm = {}
        local n = #res
        for i = 1, n do
            local a1, a2, a3 = res[math.max(i - 1, 1)].r:Dot(u), res[i].r:Dot(u), res[math.min(i + 1, n)].r:Dot(u)
            sm[i] = (a1 + a2 + a3) / 3
        end
        local cross, amps, curMax = {}, {}, 0
        for i = 2, n do
            curMax = math.max(curMax, math.abs(sm[i - 1]))
            if sm[i - 1] * sm[i] < 0 then
                local f = math.abs(sm[i - 1]) / (math.abs(sm[i - 1]) + math.abs(sm[i]))
                cross[#cross + 1] = res[i - 1].t + (res[i].t - res[i - 1].t) * f
                amps[#amps + 1] = curMax
                curMax = 0
            end
        end
        return cross, amps, sm
    end

    local function zzMean(res, t1, t2)
        local sx, sz, st, n = 0, 0, 0, 0
        for i = 1, #res do
            local e = res[i]
            if e.t >= t1 and e.t <= t2 then
                sx, sz, st, n = sx + e.p.X, sz + e.p.Z, st + e.t, n + 1
            end
        end
        if n < 2 then return nil end
        return Vector3.new(sx / n, 0, sz / n), st / n
    end

    local function zigzagPoint(part, from)
        local list = history[part]
        if not list or #list < 12 then return nil end
        local tn = list[#list].t
        if tn - list[1].t < 0.6 then return nil end
        local slope3, center = State.Motion.Regress(list, tn, 1.2, 0.6)
        if not slope3 then return nil end
        local res = zzResiduals(list, tn, function(t) return center + slope3 * (t - tn) end)
        local best, bestMag = nil, 0
        for i = 1, #res do
            local m = res[i].r.Magnitude
            if m > bestMag then best, bestMag = res[i].r, m end
        end
        local t0 = (center - from).Magnitude / PROJ_SPEED + latencyLead()
        if not best or bestMag < 0.5 or #res < 9 then return nil end
        local u = best.Unit
        local cross = zzCross(res, u)
        if #cross < 4 then return nil end
        local idx0, k = 1, #cross - 1
        if k % 2 == 1 then idx0, k = 2, k - 1 end
        if k < 2 then return nil end
        local cm, tm = zzMean(res, cross[idx0], cross[idx0 + k])
        if not cm then return nil end
        local drift = Vector3.zero
        if k >= 4 then
            local m1, t1 = zzMean(res, cross[idx0], cross[idx0 + 2])
            local m2, t2 = zzMean(res, cross[idx0 + k - 2], cross[idx0 + k])
            if m1 and m2 and t2 - t1 > 0.2 then drift = (m2 - m1) / (t2 - t1) end
        end
        if drift.Magnitude > 30 then drift = drift.Unit * 30 end
        local cNow = cm + drift * (tn - tm)
        local res2 = zzResiduals(list, tn, function(t) return cNow + drift * (t - tn) end)
        local cross2, amps2, sm2 = zzCross(res2, u)
        if #cross2 < 3 then return nil end
        local halves, hsum = {}, 0
        for i = 2, #cross2 do
            local h = cross2[i] - cross2[i - 1]
            halves[#halves + 1] = h
            hsum = hsum + h
        end
        local H = hsum / #halves
        local base = Vector3.new(cNow.X, list[#list].p.Y, cNow.Z) + drift * t0
        if H < 0.1 or H > 0.8 then return nil end
        local var = 0
        for _, h in ipairs(halves) do var = var + (h - H) * (h - H) end
        local conf = math.clamp(1 - (math.sqrt(var / #halves) / H) / 0.35, 0, 1)
        if conf <= 0.1 then return nil end
        local ampSum, ampN = 0, 0
        for i = 2, #amps2 do ampSum, ampN = ampSum + amps2[i], ampN + 1 end
        local A = ampN > 0 and ampSum / ampN or bestMag
        local sgn = sm2[#sm2] >= 0 and 1 or -1
        local phase = (tn - cross2[#cross2] + t0) / H
        return base + u * (sgn * A * math.sin(math.pi * phase) * conf)
    end

    local lastMoveAt = setmetatable({}, { __mode = "k" })

    local function aimPoint(part, from)
        local pos = part.Position

        -- ===== SMART PREDICT =====
        if T.SmartPredict then
            local ch = part.Parent
            if ch then
                local d = (pos - from).Magnitude
                local aimPos = State.SmartPredict.Compute(part, ch, from, d)
                if aimPos then return aimPos end
            end
            return pos
        end

        -- ===== Fallback: legacy predictor =====
        if not (T.Predict or T.ZigZag) then return pos end
        do
            local ch0  = part.Parent
            local hrp0 = ch0 and ch0:FindFirstChild("HumanoidRootPart")
            local hum0 = ch0 and ch0:FindFirstChildOfClass("Humanoid")
            local now  = os.clock()
            local moving = false
            if hrp0 then
                local v1 = flat(hrp0.AssemblyLinearVelocity).Magnitude
                local v2 = flat(getVelocity(part, hrp0, hum0)).Magnitude
                moving = v1 > 2.5 or v2 > 2.5
            end
            if moving or not lastMoveAt[part] then lastMoveAt[part] = now end
            if now - lastMoveAt[part] > 0.25 then return pos end
        end
        if T.ZigZag then
            local zp = zigzagPoint(part, from)
            if zp then return zp end
        end
        if not T.Predict then return pos end
        local ch  = part.Parent
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        if not hrp then return pos end
        local hum = ch:FindFirstChildOfClass("Humanoid")
        local vel = getVelocity(part, hrp, hum)
        if vel.Magnitude < 1 then return pos end
        local lat = latencyLead()
        local _, acc = State.Motion.Estimate(history[part])
        acc = acc and flat(acc) * 0.8 or Vector3.zero
        local t = (pos - from).Magnitude / PROJ_SPEED + lat
        local predicted = pos
        for _ = 1, 3 do
            local tc = math.min(t, 0.3)
            local a2 = acc
            if (vel + a2 * tc):Dot(vel) < 0 then a2 = -vel / math.max(tc, 0.05) end
            predicted = pos + vel * t + a2 * (0.5 * tc * tc)
            t = (predicted - from).Magnitude / PROJ_SPEED + lat
        end
        local scale  = math.clamp((tonumber(T.LeadScale) or 100) / 100, 0.3, 3)
        local offset = (predicted - pos) * scale
        if offset.Magnitude > 30 then offset = offset.Unit * 30 end
        return pos + offset
    end

    local function inFov(pos)
        local cam = workspace.CurrentCamera
        if not cam then return false end
        local to = pos - cam.CFrame.Position
        if to.Magnitude < 0.1 then return true end
        local dot = math.clamp(cam.CFrame.LookVector:Dot(to.Unit), -1, 1)
        return math.deg(math.acos(dot)) <= (tonumber(T.FOV) or 120) / 2
    end

    local function compute(character, ignoreFov)
        local kc   = killerChar()
        local part = kc and targetPart(kc)
        if not part then return nil end
        local from = muzzle(character)
        if not from then return nil end
        local pos  = aimPoint(part, from)
        if not ignoreFov and not inFov(pos) then return nil end
        local d = pos - from
        if d.Magnitude < 0.01 then return nil end
        return d.Unit
    end

    local circleGui, circleFrame, laserPart
    local activeTool, toolConns = nil, {}
    local isFiring, releaseUntil  = false, 0
    local lastAimDir, lastAimAt   = nil, 0

    local function clearToolConnections()
        for _, c in ipairs(toolConns) do pcall(function() c:Disconnect() end) end
        table.clear(toolConns)
        activeTool    = nil
        isFiring, releaseUntil = false, 0
    end

    local mouseHeld = false
    track(UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            mouseHeld = true
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            mouseHeld    = false
            releaseUntil = tick() + 0.12
        end
    end))

    local BULLET_LASER_MAX = 500

    local function bindActiveTool(ch)
        local tool = ch and ch:FindFirstChild("Twist of Fate")
        if tool == activeTool then return end
        clearToolConnections()
        mouseHeld = false
        if not (tool and tool:IsA("Tool")) then return end
        activeTool = tool
        toolConns[#toolConns + 1] = tool.Activated:Connect(function()
            isFiring = true; releaseUntil = 0
        end)
        toolConns[#toolConns + 1] = tool.Deactivated:Connect(function()
            State.AimHold.held = false
            isFiring = false
            releaseUntil = tick() + 0.12
        end)
        toolConns[#toolConns + 1] = tool.Unequipped:Connect(function()
            State.AimHold.held = false
            isFiring = false
            releaseUntil = 0
        end)
    end

    local function ensureCircle()
        if circleGui and circleGui.Parent then return true end
        local parent
        pcall(function() parent = (gethui and gethui()) or game:GetService("CoreGui") end)
        parent = parent or LP:FindFirstChildOfClass("PlayerGui")
        if not parent then return false end
        local sg = Instance.new("ScreenGui")
        sg.Name = "TianHub_TOFSilentFOV"; sg.ResetOnSpawn = false
        sg.IgnoreGuiInset = true; sg.DisplayOrder = 20
        local f = Instance.new("Frame")
        f.AnchorPoint = Vector2.new(0.5, 0.5)
        f.Position = UDim2.fromScale(0.5, 0.5)
        f.BackgroundTransparency = 1; f.BorderSizePixel = 0
        f.Parent = sg
        local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(1, 0); corner.Parent = f
        local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(255, 255, 255)
        stroke.Thickness = 1.5; stroke.Transparency = 0.2; stroke.Parent = f
        local ok = pcall(function() sg.Parent = parent end)
        if not ok then return false end
        circleGui, circleFrame = sg, f
        return true
    end

    local function circleRadius(cam)
        local half  = math.rad(math.clamp((tonumber(T.FOV) or 120) / 2, 1, 85))
        local halfV = math.rad(cam.FieldOfView) / 2
        local r = (cam.ViewportSize.Y / 2) * math.tan(half) / math.tan(halfV)
        local visibleCap = math.min(cam.ViewportSize.X, cam.ViewportSize.Y) * 0.48
        return math.clamp(r, 12, visibleCap)
    end

    local function hideLaser()
        if laserPart then laserPart.Transparency = 1 end
    end

    local function updateLaser(from, to)
        if not (laserPart and laserPart.Parent) then
            local p = Instance.new("Part")
            p.Name = "TianHub_TOFSilentLaser"
            p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
            p.Material = Enum.Material.Neon
            p.Color    = Color3.fromRGB(160, 32, 240) -- Purple aim laser
            p.Transparency = 1
            p.Parent = workspace
            laserPart = p
        end
        local dist = (to - from).Magnitude
        if dist < 0.5 then return hideLaser() end
        local thick = math.clamp(dist * 0.0015, 0.12, 0.3)
        laserPart.Size  = Vector3.new(thick, thick, dist)
        laserPart.CFrame = CFrame.new((from + to) / 2, to)
        laserPart.Transparency = 0
    end

    local aimRay = RaycastParams.new()
    aimRay.FilterType = Enum.RaycastFilterType.Exclude
    aimRay.RespectCanCollide = true

    local function drawAimLaser(ch, from, dir)
        aimRay.FilterDescendantsInstances = { ch }
        local res = workspace:Raycast(from, dir * BULLET_LASER_MAX, aimRay)
        updateLaser(from, res and res.Position or (from + dir * BULLET_LASER_MAX))
    end

    local renderBindName = "TianHub_TOFSilentLaser_" .. tostring(LP.UserId)
    pcall(function() RunService:UnbindFromRenderStep(renderBindName) end)
    RunService:BindToRenderStep(renderBindName, Enum.RenderPriority.Last.Value, function()
        local active = T.Enabled and not unloaded
        local cam = workspace.CurrentCamera
        if active and T.ShowCircle and cam and ensureCircle() then
            circleGui.Enabled = true
            local r = circleRadius(cam)
            circleFrame.Size = UDim2.fromOffset(r * 2, r * 2)
        elseif circleGui then
            circleGui.Enabled = false
        end

        if not active or not T.ShowLaser then return hideLaser() end
        local ch = LP.Character
        bindActiveTool(ch)
        if not hasTOF(ch) then State.AimHold.held = false; return hideLaser() end
        if State.AimHold.ok and not State.AimHold.held then return hideLaser() end
        local from = muzzle(ch)
        if not from then return hideLaser() end
        local good, dir = pcall(compute, ch, true)
        if not (good and typeof(dir) == "Vector3") then
            dir = nil
            if cam then
                aimRay.FilterDescendantsInstances = { ch }
                local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * BULLET_LASER_MAX, aimRay)
                local target = hit and hit.Position or (cam.CFrame.Position + cam.CFrame.LookVector * BULLET_LASER_MAX)
                local d = target - from
                dir = d.Magnitude > 0.5 and d.Unit or cam.CFrame.LookVector
            end
        end
        if not dir then return hideLaser() end
        pcall(drawAimLaser, ch, from, dir)
    end)

    local function restore()
        if effects and original then
            pcall(function() effects.aimDirection = original end)
        end
    end

    local function install()
        if original or installing then return end
        installing = true
        task.spawn(function()
            local ok = pcall(function()
                local rs = game:GetService("ReplicatedStorage")
                local m  = rs:WaitForChild("Modules", 10):WaitForChild("Items", 10):WaitForChild("TwistOfFate", 10):WaitForChild("TwistoffateEffects", 10)
                local e  = require(m)
                local orig = e.aimDirection
                if type(orig) ~= "function" then error("no aimDirection") end
                e.aimDirection = function(character, camCF)
                    if unloaded or not T.Enabled then return orig(character, camCF) end
                    -- RawMode ON saat menembak (lead mentah = presisi), OFF saat preview (smooth)
                    if T.SmartPredict then State.SmartPredict.SetRawMode(true) end
                    local good, dir = pcall(compute, character)
                    if T.SmartPredict then State.SmartPredict.SetRawMode(false) end
                    if good and dir then
                        lastAimDir, lastAimAt = dir, tick()
                        if T.SmartPredict then State.SmartPredict.RecordShot() end
                        return dir
                    end
                    local res = orig(character, camCF)
                    if typeof(res) == "Vector3" then lastAimDir, lastAimAt = res, tick() end
                    return res
                end
                effects, original = e, orig
            end)
            installing = false
            if ok and unloaded then restore() end
        end)
    end

    function obj:Refresh()
        if T.Enabled then State.AimHold.Install(); install() end
    end

    function obj:Destroy()
        T.Enabled = false
        pcall(function() RunService:UnbindFromRenderStep(renderBindName) end)
        clearToolConnections()
        mouseHeld = false
        restore()
        if circleGui then pcall(function() circleGui:Destroy() end) end
        if laserPart then pcall(function() laserPart:Destroy() end) end
    end

    return obj
end)()

-- ============================================================
-- EXPORT
-- ============================================================
local function SetTOFSilent(enabled)
    State.TOFSilent.Enabled = enabled == true
    State.SilentObj:Refresh()
end

SetTOFSilent(false)

local TOF_API = {
    State = State,
    setEnabled = SetTOFSilent,
    setPredict = function(value) State.TOFSilent.Predict = value == true end,
    setZigZag = function(value) State.TOFSilent.ZigZag = value == true end,
    setSmartPredict = function(value) State.TOFSilent.SmartPredict = value == true end,
    setUseSnap = function(value) State.TOFSilent.UseSnap = value == true end,
    setUseTravel = function(value) State.TOFSilent.UseTravel = value == true end,
    setWallCheck = function(value) State.TOFSilent.WallCheck = value == true end,
    setShowFOV = function(value) State.TOFSilent.ShowCircle = value == true end,
    setShowLaser = function(value) State.TOFSilent.ShowLaser = value == true end,
    setFOV = function(value)
        State.TOFSilent.FOV = math.clamp(tonumber(value) or 120, 10, 360)
    end,
    setLeadScale = function(value)
        State.TOFSilent.LeadScale = math.clamp(tonumber(value) or 100, 30, 300)
    end,
}

getgenv().TianHub_TOF = TOF_API
getgenv().TianHub_SetToFSilentAim = SetTOFSilent
getgenv().TianHub_ToFPeekTarget = function() return nil end
getgenv().KinonTOFSilent = {
    State = State,
    Set = SetTOFSilent,
}
end

TianHubState.GodMode = TianHubState.GodMode == true
TianHubState.Noclip = TianHubState.Noclip == true

xpcall(function()
    local function setFlowstateAnim(v)
        local c = LocalPlayer.Character
        if c then c:SetAttribute("Flowstate", v and true or false) end
        if v then
            setConn("Tian_FlowstateAnim", RunService.Heartbeat:Connect(function()
                local ch = LocalPlayer.Character
                if ch and not TianHub_IsKiller(LocalPlayer) and ch:GetAttribute("Flowstate") ~= true then ch:SetAttribute("Flowstate", true) end
            end))
        else
            disconnect("Tian_FlowstateAnim")
        end
    end
    local FlowstateSection = CreateSection(SurvTab, "FLOWSTATE", false)
    CreateToggle(FlowstateSection, "Flowstate No CD", false, function(v) setFlowstateAnim(v) end)



end, function(e) logQuiet("[TianHub] feature block error: " .. tostring(e)) end)

xpcall(function()
    local CollectionService = game:GetService("CollectionService")
    local genv = (getgenv and getgenv()) or _G
    local SV = { AutoGen = false, EscapeDist = 30, UnlimitedVault = false, AutoDodge = false }
    genv.TianSV = SV

    local function remote(...)
        local node = ReplicatedStorage
        for _, name in ipairs({ ... }) do node = node and node:FindFirstChild(name) end
        return node
    end
    local function myRoot()
        local c = LocalPlayer.Character
        return c and c:FindFirstChild("HumanoidRootPart")
    end

    local genCache, genCacheT = {}, 0
    local function allGens()
        local now = os.clock()
        if now - genCacheT < 3 then return genCache end
        genCacheT = now
        genCache = {}
        local mf = workspace:FindFirstChild("Map")
        if mf then
            for _, obj in ipairs(mf:GetDescendants()) do
                if obj:IsA("Model") and obj.Name == "Generator" then
                    if obj:GetAttribute("RepairProgress") ~= nil or obj:GetAttribute("kickcount") ~= nil
                        or obj:GetAttribute("ProgressRepair") ~= nil then
                        genCache[#genCache + 1] = obj
                    end
                end
            end
        end
        return genCache
    end
    local function genPoints(m)
        local pts = {}
        for _, o in ipairs(m:GetChildren()) do
            if o:IsA("BasePart") and string.find(o.Name, "GeneratorPoint") then pts[#pts + 1] = o end
        end
        return pts
    end
    local function genDone(gen)
        return (gen:GetAttribute("RepairProgress") or gen:GetAttribute("ProgressRepair") or 0) >= 100
    end
    local function killerNear(pos, radius)
        for _, pl in ipairs(Players:GetPlayers()) do
            if pl ~= LocalPlayer and TianHub_IsKiller(pl) and pl.Character then
                local hrp = pl.Character:FindFirstChild("HumanoidRootPart")
                if hrp and (hrp.Position - pos).Magnitude <= radius then return true end
            end
        end
        return false
    end
    local function nearestKillerDist()
        local me = myRoot()
        if not me then return math.huge end
        local dist = math.huge
        for _, pl in ipairs(Players:GetPlayers()) do
            if pl ~= LocalPlayer and TianHub_IsKiller(pl) and pl.Character then
                local hrp = pl.Character:FindFirstChild("HumanoidRootPart")
                if hrp then dist = math.min(dist, (hrp.Position - me.Position).Magnitude) end
            end
        end
        return dist
    end
    local function pointInReach()
        local me = myRoot()
        if not me then return nil end
        local best, bd = nil, 5.5
        for _, gen in ipairs(allGens()) do
            for _, pt in ipairs(genPoints(gen)) do
                if pt.Parent then
                    local d = (me.Position - pt.Position).Magnitude
                    if d < bd then bd, best = d, pt end
                end
            end
        end
        return best
    end
    local function safePoint()
        local me = myRoot()
        if not me then return nil end
        local best, bd = nil, math.huge
        for _, gen in ipairs(allGens()) do
            if not genDone(gen) then
                local okP, pivot = pcall(function() return gen:GetPivot().Position end)
                if okP and not killerNear(pivot, SV.EscapeDist) then
                    for _, pt in ipairs(genPoints(gen)) do
                        if pt.Parent then
                            local d = (pt.Position - me.Position).Magnitude
                            if d < bd then bd, best = d, pt end
                        end
                    end
                end
            end
        end
        return best
    end

    local repairTrack
    local function playRepairAnim()
        local c = LocalPlayer.Character
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        local an = hum and hum:FindFirstChildOfClass("Animator")
        if not an or (repairTrack and repairTrack.IsPlaying) then return end
        pcall(function()
            local anim = Instance.new("Animation")
            anim.AnimationId = "rbxassetid://92960319113695"
            repairTrack = an:LoadAnimation(anim)
            repairTrack.Priority = Enum.AnimationPriority.Action
            repairTrack:Play()
        end)
    end
    local function stopRepair(point)
        if repairTrack and repairTrack.IsPlaying then pcall(function() repairTrack:Stop() end) end
        repairTrack = nil
        local ev = remote("Remotes", "Generator", "RepairEvent")
        if point and ev then pcall(function() ev:FireServer(point, false) end) end
    end

    local autoThread, autoPoint, lastFire = nil, nil, 0
    local function stopAutoGen()
        if autoThread then pcall(task.cancel, autoThread); autoThread = nil end
        if autoPoint then stopRepair(autoPoint) end
        autoPoint = nil
    end
    local function startAutoGen()
        stopAutoGen()
        autoThread = task.spawn(function()
            while SV.AutoGen do
                local c = LocalPlayer.Character
                local me = myRoot()
                local hum = c and c:FindFirstChildOfClass("Humanoid")
                if not me or not hum or hum.Health <= 0 then task.wait(0.3); continue end

                if nearestKillerDist() <= SV.EscapeDist then

                    if autoPoint then stopRepair(autoPoint); autoPoint = nil end
                    local sp = safePoint()
                    if sp then
                        autoPoint = sp
                        pcall(function() me.CFrame = CFrame.new(sp.Position + Vector3.new(0, 3, 0)) end)
                        task.wait(0.2)
                    end
                    task.wait(0.2)
                    continue
                end

                if autoPoint and autoPoint.Parent then
                    local now = tick()
                    if now - lastFire >= 0.5 then
                        local ev = remote("Remotes", "Generator", "RepairEvent")
                        if ev then pcall(function() ev:FireServer(autoPoint, true) end) end
                        playRepairAnim()
                        lastFire = now
                    end
                else
                    autoPoint = nil
                    local pt = pointInReach()
                    if pt then
                        autoPoint = pt
                    else
                        local sp = safePoint()
                        if sp then
                            autoPoint = sp
                            pcall(function() me.CFrame = CFrame.new(sp.Position + Vector3.new(0, 3, 0)) end)
                            task.wait(0.2)
                        end
                    end
                end
                task.wait(0.1)
            end
            if autoPoint then stopRepair(autoPoint) end
            autoPoint = nil
        end)
    end
    LocalPlayer.CharacterAdded:Connect(function()
        task.wait(1)
        if SV.AutoGen then startAutoGen() end
    end)

    local function tagRemover(tagName, connName, enabledFn)
        return function(on)
            if on then
                for _, v in ipairs(CollectionService:GetTagged(tagName)) do
                    CollectionService:RemoveTag(v, tagName)
                end
                setConn(connName, CollectionService:GetInstanceAddedSignal(tagName):Connect(function(inst)
                    if enabledFn() then CollectionService:RemoveTag(inst, tagName) end
                end))
            else
                disconnect(connName)
            end
        end
    end
    local setUnlimitedVault = tagRemover("Blocked", "Tian_UnlimitedVault", function() return SV.UnlimitedVault end)

    local function triggerCrouch()
        task.spawn(function()
            local c = LocalPlayer.Character
            if not c then return end
            local hum = c:FindFirstChildOfClass("Humanoid")
            local changeAttr = remote("Remotes", "Mechanics", "ChangeAttribute")
            local function pressCrouchBtn()
                pcall(function()
                    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
                    local mob = pg and pg:FindFirstChild("Survivor-mob")
                    local ctrl = mob and mob:FindFirstChild("Controls")
                    local btn = ctrl and ctrl:FindFirstChild("crouch")
                    if btn and firesignal then firesignal(btn.MouseButton1Click) end
                end)
            end
            pcall(function() c:SetAttribute("Crouching", true) end)
            if changeAttr then pcall(function() changeAttr:FireServer("Crouchingserver", true) end) end
            local run = remote("Remotes", "Chase", "Runevent")
            if run then pcall(function() run:FireServer(c, false) end) end
            if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Landed) end) end
            pressCrouchBtn()
            local t0 = tick()
            while tick() - t0 < 1.2 do
                if changeAttr then pcall(function() changeAttr:FireServer("Crouchingserver", true) end) end
                task.wait(0.1)
            end
            pcall(function() c:SetAttribute("Crouching", false) end)
            if changeAttr then pcall(function() changeAttr:FireServer("Crouchingserver", false) end) end
            if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Landed) end) end
            pressCrouchBtn()
        end)
    end

    -- TianHub Auto Crouch Dodge: listens for the trigger animation instead of polling tracks.
    local CROUCH_DODGE_ANIMATION_ID = "100014992013740"
    local watchedCharacters = setmetatable({}, { __mode = "k" })
    local watchedAnimators = setmetatable({}, { __mode = "k" })

    local function attachCrouchDodgeAnimator(killerCharacter, animator)
        if not animator or watchedAnimators[animator] then return end
        watchedAnimators[animator] = true
        animator.AnimationPlayed:Connect(function(track)
            if not TianHubState.AutoCrouch then return end
            local animation = track and track.Animation
            local animationId = animation and animation.AnimationId or ""
            if animationId:match("%d+") ~= CROUCH_DODGE_ANIMATION_ID then return end
            local myCharacter = LocalPlayer.Character
            if not myCharacter then return end
            local state = myCharacter:GetAttribute("State")
            if myCharacter:GetAttribute("Knocked") == true
                or myCharacter:GetAttribute("IsHooked") == true
                or state == "Downed" or state == "Dead" then return end
            local myRoot = myCharacter:FindFirstChild("HumanoidRootPart")
            local killerRoot = killerCharacter and killerCharacter:FindFirstChild("HumanoidRootPart")
            if myRoot and killerRoot and (myRoot.Position - killerRoot.Position).Magnitude <= 40 then
                triggerCrouch()
            end
        end)
    end

    local function attachCrouchDodgeCharacter(killerCharacter)
        if not killerCharacter or watchedCharacters[killerCharacter] then return end
        watchedCharacters[killerCharacter] = true
        local humanoid = killerCharacter:FindFirstChildOfClass("Humanoid")
            or killerCharacter:WaitForChild("Humanoid", 5)
        if not humanoid then return end
        local animator = humanoid:FindFirstChildOfClass("Animator")
            or humanoid:WaitForChild("Animator", 5)
        if animator then attachCrouchDodgeAnimator(killerCharacter, animator) end
        humanoid.ChildAdded:Connect(function(child)
            if child:IsA("Animator") then attachCrouchDodgeAnimator(killerCharacter, child) end
        end)
    end

    local function watchCrouchDodgePlayer(player)
        if player == LocalPlayer then return end
        local function tryAttach()
            if player.Team and player.Team.Name == "Killer" and player.Character then
                attachCrouchDodgeCharacter(player.Character)
            end
        end
        player.CharacterAdded:Connect(function()
            task.wait(0.2)
            tryAttach()
        end)
        player:GetPropertyChangedSignal("Team"):Connect(tryAttach)
        tryAttach()
    end

    for _, player in ipairs(Players:GetPlayers()) do watchCrouchDodgePlayer(player) end
    setConn("Anon_AutoCrouch_PlayerAdded", Players.PlayerAdded:Connect(watchCrouchDodgePlayer))

    local function escapeNow()
        local me = myRoot()
        if not me then TianHub_Notify("Escape", "Karakter tidak ditemukan", 2); return end
        local found
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Name:lower() == "fininshline" then found = obj; break end
        end
        if not found then TianHub_Notify("Escape", "Finish line tidak ditemukan", 2); return end
        pcall(function() me.CFrame = found.CFrame + Vector3.new(0, 5, 0) end)
    end

    local escFloat
    local function setEscapeButtonVisible(on)
        if escFloat then escFloat.Destroy(); escFloat = nil end
        if on then
            escFloat = TianHubState.MakeFloat("TianEscapeButton", "ESCAPE", UDim2.new(0.5, 0, 0.62, 0), function() pcall(escapeNow) end)
        end
    end

    -- Auto Generator UI removed as requested.

    local AntiSlowVaultSection = CreateSection(SurvTab, "ANTI SLOW VAULT", false)
    CreateToggle(AntiSlowVaultSection, "Unlimited Vault", false, function(v)
        SV.UnlimitedVault = v
        setUnlimitedVault(v)
    end)

    local NS = { On = false, Conn = nil, Base = 17, Until = 0 }
    local genvA = (getgenv and getgenv()) or _G
    local AF = genvA.TianAntiFall or { On = false }
    genvA.TianAntiFall = AF
    AF.On = false
    local afConn

    local function nsAttach(hum)
        if NS.Conn then NS.Conn:Disconnect(); NS.Conn = nil end
        if not hum then return end
        NS.Conn = RunService.Heartbeat:Connect(function()
            if not NS.On or os.clock() > NS.Until or not hum.Parent then return end
            if TianHub_IsKiller(LocalPlayer) then return end
            local ch = LocalPlayer.Character
            if ch and (ch:GetAttribute("IsHooked") or ch:GetAttribute("IsCarried") or hum.Health <= 50) then return end
            if hum.WalkSpeed < NS.Base - 0.05 then
                pcall(function() hum.WalkSpeed = NS.Base end)
            end
        end)
    end
    local function setNoSlowdown(on)
        NS.On = on
        local ch = LocalPlayer.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if on then
            nsAttach(hum)
        elseif NS.Conn then
            NS.Conn:Disconnect(); NS.Conn = nil
        end
    end

    local function afAttach(hum)
        if afConn then afConn:Disconnect(); afConn = nil end
        if not hum then return end
        local fallStart
        afConn = hum.StateChanged:Connect(function(_, new)
            if not AF.On then return end
            if new == Enum.HumanoidStateType.Freefall then
                fallStart = os.clock()
            elseif new == Enum.HumanoidStateType.Landed then
                local fell = fallStart and (os.clock() - fallStart) > 0.3
                fallStart = nil
                if not fell or TianHub_IsKiller(LocalPlayer) then return end

                task.spawn(function()
                    local t0 = os.clock()
                    while AF.On and hum.Parent and os.clock() - t0 < 1.2 do
                        local ch = LocalPlayer.Character
                        if ch and hum.Health > 0 and not (ch:GetAttribute("IsHooked") or ch:GetAttribute("IsCarried"))
                            and hum.WalkSpeed < NS.Base - 0.05 then
                            pcall(function() hum.WalkSpeed = NS.Base end)
                        end
                        RunService.Heartbeat:Wait()
                    end
                end)
            end
        end)
    end
    if hookmetamethod and not genvA.TianFallHooked then
        genvA.TianFallHooked = true
        task.spawn(function()
            local okF, fall = pcall(function()
                return ReplicatedStorage:WaitForChild("Remotes", 10):WaitForChild("Mechanics", 10):WaitForChild("Fall", 10)
            end)
            if not okF or not fall then genvA.TianFallHooked = false; return end
            local old
            old = hookmetamethod(game, "__namecall", function(self, ...)
                local cur = genvA.TianAntiFall
                if cur and cur.On and getnamecallmethod() == "FireServer" and rawequal(self, fall) then
                    return nil
                end
                return old(self, ...)
            end)
        end)
    end
    TianHubState.SetAntiFallDamage = function(enabled)
        AF.On = enabled and true or false
        local ch = LocalPlayer.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if AF.On then
            afAttach(hum)
        elseif afConn then
            afConn:Disconnect()
            afConn = nil
        end
    end
    setConn("Tian_SlowCharAdded", LocalPlayer.CharacterAdded:Connect(function(ch)
        local hum = ch:WaitForChild("Humanoid", 5)
        if NS.On then nsAttach(hum) end
        if AF.On then afAttach(hum) end
    end))

    -- Vault controls: Always Fast Vault remains available.
    -- Keep all vault controls in the single ANTI SLOW VAULT groupbox.
    local VaultSection = AntiSlowVaultSection
    local AlwaysFastVaultState = genv.TianAlwaysFastVaultState or { Enabled = false }
    genv.TianAlwaysFastVaultState = AlwaysFastVaultState
    AlwaysFastVaultState.Enabled = false
    local function InstallAlwaysFastVaultHooks()
        pcall(function()
            local modules = ReplicatedStorage:WaitForChild("Modules", 5)
            local survivors = modules and modules:WaitForChild("Survivors", 5)
            local module = survivors and survivors:WaitForChild("SurvivorVault", 5)
            local mod = module and require(module)
            if mod and type(mod.evaluate) == "function" and not mod._TianAlwaysFastVaultHooked then
                mod._TianAlwaysFastVaultOriginal = mod.evaluate
                mod.evaluate = function(self, ...)
                    if genv.TianAlwaysFastVaultState and genv.TianAlwaysFastVaultState.Enabled then return true, "ready", 5 end
                    return mod._TianAlwaysFastVaultOriginal(self, ...)
                end
                mod._TianAlwaysFastVaultHooked = true
            end
        end)
        pcall(function()
            local modules = ReplicatedStorage:WaitForChild("Modules", 5)
            local survivors = modules and modules:WaitForChild("Survivors", 5)
            local module = survivors and survivors:WaitForChild("SurvivorAnimationsController", 5)
            local ctl = module and require(module)
            if ctl and type(ctl._validateFastVault) == "function" and not ctl._TianAlwaysFastVaultHooked then
                ctl._TianAlwaysFastVaultOriginal = ctl._validateFastVault
                ctl._validateFastVault = function(self, ...)
                    if genv.TianAlwaysFastVaultState and genv.TianAlwaysFastVaultState.Enabled then return true, "ready", 5 end
                    return ctl._TianAlwaysFastVaultOriginal(self, ...)
                end
                ctl._TianAlwaysFastVaultHooked = true
            end
        end)
    end
    CreateToggle(VaultSection, "Always Fast Vault", false, function(v)
        AlwaysFastVaultState.Enabled = v and true or false
        if AlwaysFastVaultState.Enabled then
            task.spawn(function()
                for _ = 1, 20 do
                    InstallAlwaysFastVaultHooks()
                    task.wait(0.25)
                end
            end)
        end
    end)


    CreateToggle(AntiSlowVaultSection, "Anti Fall Slow", false, function(v)
        AF.On = v
        local ch = LocalPlayer.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if v then
            afAttach(hum)
        else
            if afConn then afConn:Disconnect(); afConn = nil end
        end
    end)

    local DodgeSection = CreateSection(SurvTab, "AUTO DODGE CROUCH", false)
    CreateToggle(DodgeSection, "Auto Dodge Crouch", false, function(v)
        SV.AutoDodge = v
        TianHubState.AutoCrouch = v
    end)

    local EscapeSection = CreateSection(SurvTab, "INSTANT ESCAPE", false)
    CreateToggle(EscapeSection, "Instant Escape", false, function(v) setEscapeButtonVisible(v) end)
end, function(e) logQuiet("[TianHub] survivor block error: " .. tostring(e)) end)

xpcall(function()

    -- TianHub Fake Perks implementation
local FakePerksSection = CreateSection(SurvTab, "FAKE PERKS", false)
CreateToggle(FakePerksSection, "Quick Recovery", false, function(v)
    if _G.TianHub_FakePerks then _G.TianHub_FakePerks.SetQuickRecovery(v) end
end)
CreateToggle(FakePerksSection, "Perfect Landing", false, function(v)
    if _G.TianHub_FakePerks then _G.TianHub_FakePerks.SetPerfectLanding(v) end
end)
CreateToggle(FakePerksSection, "Flowstate", false, function(v)
    if _G.TianHub_FakePerks then _G.TianHub_FakePerks.SetFlowstate(v) end
end)
CreateToggle(FakePerksSection, "Adrenaline Rush", false, function(v)
    if _G.TianHub_FakePerks then _G.TianHub_FakePerks.SetAdrenalineRush(v) end
end)
CreateSlider(FakePerksSection, "Perk Cooldown", 0, 180, 10, "s", function(v)
    if _G.TianHub_FakePerks then _G.TianHub_FakePerks.SetCooldown(v) end
end)


end, function(e) logQuiet("[TianHub] fake perks error: " .. tostring(e)) end)

xpcall(function()
    -- Moonwalk V2: movement logic integrated with TianHub.
    local TianMW2 = { On = false, Float = nil, MoveConn = nil, CharConn = nil }
    local TIAN_SIDE_SPEED, TIAN_BACK_SPEED = 1.3, 1.5
    local TIAN_INTERVAL, TIAN_ROTATION_INTENSITY = 0.07, 0.9

    local function stopTianMoonwalkV2()
        if TianMW2.MoveConn then TianMW2.MoveConn:Disconnect(); TianMW2.MoveConn = nil end
        local c = LocalPlayer.Character
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        if hum then hum.AutoRotate = true end
        if hrp then
            local gyro = hrp:FindFirstChild("Tian_MoonwalkV2Gyro")
            if gyro then gyro:Destroy() end
        end
    end

    local function startTianMoonwalkV2()
        stopTianMoonwalkV2()
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum then return end
        local lastSwitch, direction = 0, 1
        TianMW2.MoveConn = RunService.RenderStepped:Connect(function()
            if not TianMW2.On then return end
            local c = LocalPlayer.Character
            local root = c and c:FindFirstChild("HumanoidRootPart")
            local h = c and c:FindFirstChildOfClass("Humanoid")
            if not root or not h or h.Health <= 0 then return end
            local moveDir = h.MoveDirection
            if moveDir.Magnitude > 0 then
                h.AutoRotate = false
                local gyro = root:FindFirstChild("Tian_MoonwalkV2Gyro")
                if not gyro then
                    gyro = Instance.new("BodyGyro")
                    gyro.Name = "Tian_MoonwalkV2Gyro"
                    gyro.MaxTorque = Vector3.new(0, 100000, 0)
                    gyro.P = 50000
                    gyro.Parent = root
                end
                local now = tick()
                if now - lastSwitch >= TIAN_INTERVAL then
                    direction = -direction
                    lastSwitch = now
                end
                local baseLook = CFrame.lookAt(root.Position, root.Position - moveDir)
                local glitchAngle = math.atan2(TIAN_SIDE_SPEED, TIAN_BACK_SPEED) * TIAN_ROTATION_INTENSITY
                gyro.CFrame = baseLook * CFrame.Angles(0, direction * glitchAngle, 0)
                local forwardGlitch = moveDir * TIAN_BACK_SPEED
                local sideGlitch = baseLook.RightVector * (direction * TIAN_SIDE_SPEED)
                h:Move(forwardGlitch + sideGlitch, false)
            else
                h.AutoRotate = true
                local gyro = root:FindFirstChild("Tian_MoonwalkV2Gyro")
                if gyro then gyro:Destroy() end
            end
        end)
    end

    local function setTianMoonwalkV2(v)
        TianMW2.On = v == true
        if TianMW2.On then startTianMoonwalkV2() else stopTianMoonwalkV2() end
        if TianMW2.Float then TianMW2.Float.SetText(TianMW2.On and "MOON V2 ON" or "MOON V2 OFF") end
    end
    local function toggleTianMoonwalkV2FromFloat()
        local reg = ToggleRegistry["moonwalk_v2"]
        if reg and reg.setState then reg.setState(not TianMW2.On, true)
        else setTianMoonwalkV2(not TianMW2.On) end
    end
    local function setTianMoonwalkV2Float(on)
        if TianMW2.Float then TianMW2.Float.Destroy(); TianMW2.Float = nil end
        if on then
            TianMW2.Float = TianHubState.MakeFloat(
                "TianMoonwalkV2Button",
                TianMW2.On and "MOON V2 ON" or "MOON V2 OFF",
                UDim2.new(0.85, 0, 0.50, 0),
                toggleTianMoonwalkV2FromFloat
            )
        end
    end
    TianMW2.CharConn = LocalPlayer.CharacterAdded:Connect(function()
        if TianMW2.On then task.wait(0.5); if TianMW2.On then startTianMoonwalkV2() end end
    end)
    setConn("Tian_MoonwalkV2Character", TianMW2.CharConn)

    local MoonwalkSection = CreateSection("Main", "MOONWALK", false)
    CreateToggle(MoonwalkSection, "Moonwalk V2", false, setTianMoonwalkV2)
    CreateToggle(MoonwalkSection, "Show Floating Button V2", false, setTianMoonwalkV2Float)

    -- Moonwalk V1: existing TianHub implementation retained.
    local MW = { On = false, Spam = 35, Intensity = 30, Float = nil }

    setConn("Tian_Moonwalk", RunService.RenderStepped:Connect(function()
        if not MW.On then return end
        local c = LocalPlayer.Character
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        local cam = workspace.CurrentCamera
        if not hum or not hrp or not cam or hum.Health <= 0 then return end
        local st = c:GetAttribute("State")
        if st == "Downed" or st == "Dead" then return end

        if hum.AutoRotate ~= false then hum.AutoRotate = false end
        local look, right = cam.CFrame.LookVector, cam.CFrame.RightVector
        local unit = Vector3.new(look.X, 0, look.Z)
        if unit.Magnitude > 0.001 then unit = unit.Unit end
        local unit2 = Vector3.new(right.X, 0, right.Z)
        if unit2.Magnitude > 0.001 then unit2 = unit2.Unit end
        local sw = math.sin(tick() * MW.Spam)
        local face = CFrame.Angles(0, math.rad(MW.Intensity * sw), 0) * unit
        hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + face)
        hum:Move(-unit * 1.2 + unit2 * (sw * 1.05), false)
    end))

    local function label() return MW.On and "MOON V1 ON" or "MOON V1 OFF" end
    local function setMoonwalk(v)
        MW.On = v
        if not v then
            local c = LocalPlayer.Character
            local hum = c and c:FindFirstChildOfClass("Humanoid")
            if hum then hum.AutoRotate = true end
        end
        if MW.Float then MW.Float.SetText(label()) end
    end
    local function toggleViaRegistry()
        local reg = ToggleRegistry["moonwalk_v1"] or ToggleRegistry["moonwalk"]
        if reg and reg.setState then reg.setState(not MW.On, true)
        else setMoonwalk(not MW.On) end
        if MW.Float then MW.Float.SetText(label()) end
    end
    local function setFloat(on)
        if MW.Float then MW.Float.Destroy(); MW.Float = nil end
        if on then
            MW.Float = TianHubState.MakeFloat("TianMoonwalkButton", label(), UDim2.new(0.85, 0, 0.45, 0), toggleViaRegistry)
        end
    end

    setConn("Tian_MoonwalkKey", UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == Enum.KeyCode.B then toggleViaRegistry() end
    end))

    CreateToggle(MoonwalkSection, "Moonwalk V1", false, setMoonwalk)
    CreateToggle(MoonwalkSection, "Show Floating Button V1", false, setFloat)
    CreateSlider(MoonwalkSection, "V1 Spam Speed", 1, 50, 35, "", function(v) MW.Spam = tonumber(v) or 35 end)
    CreateSlider(MoonwalkSection, "V1 Intensity", 1, 60, 30, "", function(v) MW.Intensity = tonumber(v) or 30 end)
end, function(e) logQuiet("[TianHub] moonwalk error: " .. tostring(e)) end)

xpcall(function()
    local DS = { On = false, Dodging = false }
    setConn("Tian_DodgeSpear", workspace.ChildAdded:Connect(function(child)
        if not DS.On or not child or child.Name ~= "Spearprojectile" then return end
        if not LocalPlayer.Team or TianHub_IsKiller(LocalPlayer) then return end
        task.spawn(function()
            if DS.Dodging then return end
            local char = LocalPlayer.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if not root then return end
            task.wait(0.05)
            local mainPart = child:WaitForChild("Hitbox", 1) or child:WaitForChild("Spear1", 1)
                or child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart")
            if not mainPart then return end
            task.wait()
            local originPos = mainPart.Position
            local spearDir = mainPart.CFrame.UpVector
            local toPlayer = (root.Position - originPos)
            if toPlayer.Magnitude < 0.1 then return end

            if spearDir:Dot(toPlayer.Unit) > 0.85 then
                DS.Dodging = true
                local original = root.CFrame

                local side = spearDir:Cross(Vector3.yAxis)
                if side.Magnitude < 0.1 then side = root.CFrame.RightVector end
                side = side.Unit
                local sign = (toPlayer:Dot(side) >= 0) and 1 or -1
                root.CFrame = root.CFrame + side * (8 * sign)
                task.wait(1)
                if root and root.Parent then root.CFrame = original end
                DS.Dodging = false
            end
        end)
    end))

    local DodgeSpearSection = CreateSection(SurvTab, "AUTO DODGE SPEAR", false)
    CreateToggle(DodgeSpearSection, "Auto Dodge Spear", false, function(v) DS.On = v end)
end, function(e) logQuiet("[TianHub] dodge spear error: " .. tostring(e)) end)

xpcall(function()
    TianHubState.FLASH_SilentAim = TianHubState.FLASH_SilentAim or false
    TianHubState.FLASH_Laser = TianHubState.FLASH_Laser ~= false
    TianHubState.FLASH_TargetPart = TianHubState.FLASH_TargetPart or "Head"
    TianHubState.FLASH_Range = TianHubState.FLASH_Range or 120
    TianHubState.FLASH_Smooth = TianHubState.FLASH_Smooth or 0.35

    local FlashState = { Active = false, LaserBeam = nil, FlashlightPart = nil, Hooked = false }
    local function Flash_GetActivateRemote()
        local r = ReplicatedStorage:FindFirstChild("Remotes")
        local i = r and r:FindFirstChild("Items")
        local f = i and i:FindFirstChild("Flashlight")
        local a = f and f:FindFirstChild("Activate")
        if a and a:IsA("RemoteEvent") then return a end
    end
    local function Flash_GetTargetPart(char)
        if not char then return nil end
        local part = char:FindFirstChild(TianHubState.FLASH_TargetPart or "Head")
        if part and part:IsA("BasePart") then return part end
        return char:FindFirstChild("Head") or char:FindFirstChild("UpperTorso")
            or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
    end
    local function Flash_GetTarget()
        local myChar = LocalPlayer.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not myRoot then return nil end
        local best, bestD = nil, math.huge
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character and TianHub_IsKiller(plr) then
                local hum = plr.Character:FindFirstChildOfClass("Humanoid")
                local part = hum and hum.Health > 0 and Flash_GetTargetPart(plr.Character)
                if part then
                    local d = (myRoot.Position - part.Position).Magnitude
                    if d <= (tonumber(TianHubState.FLASH_Range) or 120) and d < bestD then
                        best, bestD = part, d
                    end
                end
            end
        end
        return best
    end
    local function Flash_ClearLaser()
        if FlashState.LaserBeam then
            pcall(function() FlashState.LaserBeam:Destroy() end)
            FlashState.LaserBeam = nil
        end
    end
    local function Flash_UpdateLaser(origin, target)
        if not FlashState.LaserBeam then
            local beam = Instance.new("Part")
            beam.Name = "TianSilentFlashlightLaser"
            beam.Anchored = true
            beam.CanCollide = false
            beam.CanTouch = false
            beam.CanQuery = false
            beam.CastShadow = false
            beam.Material = Enum.Material.Neon
            beam.Color = Color3.fromRGB(255, 255, 255)
            beam.Transparency = 0.35
            beam.Parent = workspace
            FlashState.LaserBeam = beam
        end
        local dist = (target - origin).Magnitude
        if dist < 0.1 then return end
        local beam = FlashState.LaserBeam
        beam.Size = Vector3.new(0.16, 0.16, dist)
        beam.CFrame = CFrame.new((origin + target) / 2, target)
        beam.Transparency = 0.35
    end
    local function Flash_GetOrigin(cam)
        local src = FlashState.FlashlightPart
        if typeof(src) == "Instance" then
            if src:IsA("BasePart") then return src.Position end
            local part = src:FindFirstChildWhichIsA("BasePart", true)
            if part then return part.Position end
        end
        local char = LocalPlayer.Character
        local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
            or char:FindFirstChild("HumanoidRootPart"))
        if hand and hand:IsA("BasePart") then return hand.Position end
        return cam and cam.CFrame.Position
    end
    local function Flash_Step()
        if not (TianHubState.FLASH_SilentAim and FlashState.Active) then
            if FlashState.LaserBeam then FlashState.LaserBeam.Transparency = 1 end
            return
        end
        local cam = workspace.CurrentCamera
        local target = Flash_GetTarget()
        if not (cam and target) then
            if FlashState.LaserBeam then FlashState.LaserBeam.Transparency = 1 end
            return
        end
        local smooth = math.clamp(tonumber(TianHubState.FLASH_Smooth) or 0.35, 0.05, 1)
        local origin = Flash_GetOrigin(cam)
        if TianHubState.FLASH_Laser and origin then
            pcall(Flash_UpdateLaser, origin, target.Position)
        elseif FlashState.LaserBeam then
            FlashState.LaserBeam.Transparency = 1
        end
        pcall(function()
            cam.CFrame = cam.CFrame:Lerp(CFrame.new(cam.CFrame.Position, target.Position), smooth)
        end)
        pcall(function()
            local char = LocalPlayer.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root then
                root.CFrame = CFrame.new(root.Position, Vector3.new(target.Position.X, root.Position.Y, target.Position.Z))
            end
        end)
    end
    local function Flash_SetActive(active, part)
        FlashState.Active = active and true or false
        FlashState.FlashlightPart = FlashState.Active and part or nil
        if not FlashState.Active and FlashState.LaserBeam then FlashState.LaserBeam.Transparency = 1 end
    end
    local function Flash_InstallHook()
        if FlashState.Hooked or type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then return end
        local remote = Flash_GetActivateRemote()
        if not remote then return end
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            if self == remote and getnamecallmethod() == "FireServer" then
                local args = {...}
                pcall(function() Flash_SetActive(args[2] == true, args[1]) end)
            end
            return oldNamecall(self, ...)
        end)
        FlashState.Hooked = true
    end

    local flashConn
    local function Flash_SetEnabled(v)
        TianHubState.FLASH_SilentAim = v and true or false
        if v then
            if not flashConn then flashConn = RunService.RenderStepped:Connect(function() pcall(Flash_Step) end) end
            task.spawn(function()
                for _ = 1, 20 do
                    pcall(Flash_InstallHook)
                    if FlashState.Hooked then break end
                    task.wait(0.25)
                end
            end)
        else
            if flashConn then flashConn:Disconnect(); flashConn = nil end
            FlashState.Active = false
            FlashState.FlashlightPart = nil
            Flash_ClearLaser()
        end
    end

    local FlashSection = CreateSection(SurvTab, "SILENT FLASHLIGHT", false)
    CreateToggle(FlashSection, "Enable Silent Flashlight", false, Flash_SetEnabled)
    TianHubState.CreateDropdown(FlashSection, "Target Part", {"Head", "UpperTorso", "Torso", "HumanoidRootPart"}, TianHubState.FLASH_TargetPart, function(v)
        TianHubState.FLASH_TargetPart = type(v) == "table" and v[1] or v or "Head"
    end)
    CreateSlider(FlashSection, "Max Range", 20, 250, TianHubState.FLASH_Range, " studs", function(v)
        TianHubState.FLASH_Range = tonumber(v) or 120
    end)
    CreateSlider(FlashSection, "Smoothness", 0.05, 1, TianHubState.FLASH_Smooth, "", function(v)
        TianHubState.FLASH_Smooth = tonumber(v) or 0.35
    end)
    CreateToggle(FlashSection, "Show Laser", TianHubState.FLASH_Laser, function(v)
        TianHubState.FLASH_Laser = v
        if not v then Flash_ClearLaser() end
    end)
end, function(e) logQuiet("[TianHub] silent flashlight error: " .. tostring(e)) end)

SurvivorUtilSection = CreateSection(SurvTab, "GOD MODE", false)
CreateToggle(SurvivorUtilSection, "God Mode", TianHubState.GodMode, function(state)
    TianHubState.GodMode = state
    if not state then
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > hum.MaxHealth then
            pcall(function() hum.Health = hum.MaxHealth end)
        end
    end
end)
CreateToggle(SurvivorUtilSection, "Anti Fall Damage", false, function(state)
    if TianHubState.SetAntiFallDamage then
        TianHubState.SetAntiFallDamage(state)
    end
end)


SurvivorUtilSection = CreateSection(SurvTab, "NO CLIP", false)
CreateToggle(SurvivorUtilSection, "No Clip", TianHubState.Noclip, function(state)
    Tian_SetNoclip(state)
end)


-- Killer tab intentionally retained as an empty placeholder; all Killer-tab gameplay modules removed.


xpcall(function()
    -- Auto Wiggle: saat sedang digendong killer, spam SelfUnHookEvent (logika dari kode lua referensi).
    local WG = { On = false, Spam = 5, Last = 0 }
    local WiggleSection = CreateSection(SurvTab, "AUTO WIGGLE", false)
    CreateToggle(WiggleSection, "Auto Wiggle", false, function(v) WG.On = v end)

    setConn("Tian_AutoWiggle", RunService.Heartbeat:Connect(function()
        if not WG.On then return end
        local now = os.clock()
        if now - WG.Last < 0.1 then return end
        WG.Last = now
        local char = LocalPlayer.Character
        if not char then return end
        local c1, c2 = char:FindFirstChild("IsCarried"), char:FindFirstChild("IsCarrying")
        local carried = (c1 and c1.Value) or (c2 and c2.Value)
        if not carried then return end
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local carry = remotes and remotes:FindFirstChild("Carry")
        local event = carry and carry:FindFirstChild("SelfUnHookEvent")
        if not event then return end
        for _ = 1, WG.Spam do pcall(function() event:FireServer() end) end
    end))
end, function(e) logQuiet("[TianHub] auto wiggle error: " .. tostring(e)) end)


-- TianHub ESP UI: player/killer controls first, followed by the ordered object ESP panel.
local VisualESP = CreateSection(VisualTab, "PLAYER ESP", false)

xpcall(function()
local TianHub_ESP = { Player = false, KillerEnabled = false, PlayerName = false, ShowName = true, ShowDistance = true, ShowHealth = true, Radius = 500,
    KillerColor = Color3.fromRGB(255, 55, 55), SurvivorColor = Color3.fromRGB(64, 224, 208),
    KillerOutline = nil, SurvivorOutline = nil,
    KillerName = false, SurvivorName = false, PlayerShowDistance = true,
    KillerOutlineOn = true, SurvivorOutlineOn = true,
    OutlineOnly = false, OutlineAll = true, SurvivorDistance = 500, FillTransparency = 0.7,
    Status = false, ItemIcon = false, KillerWarn = false, HookCount = false }

local function TianHub_ClearPlayerESP()
    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr.Character
        if char then
            for _, objectName in ipairs({"TianHub_PlayerESP", "TianHub_PlayerTag", "TianHub_ItemESP", "PEH", "KEH", "PE_Text", "KE_Text", "KillerWarn"}) do
                local object = char:FindFirstChild(objectName)
                if object then object:Destroy() end
            end
        end
    end
end

local TianHub_ImageCache = {}
local function TianHub_GetItemImage(itemName)
    if TianHub_ImageCache[itemName] ~= nil then return TianHub_ImageCache[itemName] or nil end
    local result = nil
    local items = ReplicatedStorage:FindFirstChild("Items")
    local item = items and (items:FindFirstChild(itemName) or items:FindFirstChild(itemName, true))
    if item then
        local rawImage
        pcall(function()
            if item:IsA("Decal") or item:IsA("Texture") then
                rawImage = item.Texture
            else
                rawImage = item.Texture or item.Image
                if not rawImage or rawImage == "" then
                    local texture = item:FindFirstChildWhichIsA("Decal", true) or item:FindFirstChildWhichIsA("Texture", true)
                    if texture then rawImage = texture.Texture end
                end
            end
        end)
        if rawImage and rawImage ~= "" then
            local assetId = tostring(rawImage):match("(%d+)")
            result = assetId and string.format("rbxthumb://type=Asset&id=%s&w=420&h=420", assetId) or tostring(rawImage)
        end
    end
    TianHub_ImageCache[itemName] = result or false
    return result
end

-- TianHub ESP implementation: modern player labels, survivor status, item icon, killer warning and hook count.
-- TianHub's existing menu framework and unrelated features remain unchanged.
local function TianHub_ESPInfoRich(distance, hookCount, isFovTarget)
    local parts = {}
    if distance ~= nil then
        local distanceColor = isFovTarget and "#FF3030" or "#00FF00"
        parts[#parts + 1] = string.format('<font color="%s">[%ds]</font>', distanceColor, distance)
    end
    if hookCount ~= nil and hookCount ~= "" then
        parts[#parts + 1] = string.format('<font color="#FF4444">[%s]</font>', hookCount)
    end
    return table.concat(parts, ' ')
end

local function TianHub_ESPStatus(character)
    if not character then return nil end
    if character:GetAttribute("IsHooked") == true then return "HOOKED" end
    if character:GetAttribute("Knocked") == true then return "DOWN" end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then return "INJURED" end
    return nil
end

local function TianHub_ESPCreateModernESP(character, key, data)
    if not character or not character.Parent then return end
    local gui = character:FindFirstChild(key)
    if not gui then
        gui = Instance.new("BillboardGui")
        gui.Name = key
        gui.AlwaysOnTop = true
        gui.Size = UDim2.fromOffset(110, 24)
        gui.StudsOffset = Vector3.new(0, 0.85, 0)
        gui.MaxDistance = 0
        gui.Adornee = character:FindFirstChild("Head")
            or character:FindFirstChild("HumanoidRootPart")
            or character:FindFirstChildWhichIsA("BasePart")
        gui.Parent = character

        local wrapper = Instance.new("Frame")
        wrapper.Name = "Wrapper"
        wrapper.AutomaticSize = Enum.AutomaticSize.XY
        wrapper.Size = UDim2.fromOffset(0, 0)
        wrapper.Position = UDim2.new(0.5, 0, 0.5, -3)
        wrapper.AnchorPoint = Vector2.new(0.5, 1)
        wrapper.BackgroundTransparency = 1
        wrapper.ZIndex = 2
        wrapper.Parent = gui
        local layout = Instance.new("UIListLayout")
        layout.FillDirection = Enum.FillDirection.Vertical
        layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        layout.Padding = UDim.new(0, 0)
        layout.Parent = wrapper

        local status = Instance.new("TextLabel")
        status.Name = "StatusText"
        status.AutomaticSize = Enum.AutomaticSize.X
        status.Size = UDim2.fromOffset(0, 8)
        status.BackgroundTransparency = 1
        status.Font = Enum.Font.GothamBold
        status.TextSize = 9
        status.TextColor3 = Color3.fromRGB(255, 255, 255)
        status.TextStrokeTransparency = 0.25
        status.TextXAlignment = Enum.TextXAlignment.Center
        status.LayoutOrder = 1
        status.ZIndex = 3
        status.Parent = wrapper

        local box = Instance.new("Frame")
        box.Name = "Box"
        box.AutomaticSize = Enum.AutomaticSize.X
        box.Size = UDim2.fromOffset(0, 14)
        box.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
        box.BackgroundTransparency = 0.12
        box.BorderSizePixel = 0
        box.LayoutOrder = 2
        box.ZIndex = 2
        box.Parent = wrapper
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)
        local padding = Instance.new("UIPadding")
        padding.PaddingLeft = UDim.new(0, 6)
        padding.PaddingRight = UDim.new(0, 6)
        padding.Parent = box
        local row = Instance.new("UIListLayout")
        row.FillDirection = Enum.FillDirection.Horizontal
        row.VerticalAlignment = Enum.VerticalAlignment.Center
        row.HorizontalAlignment = Enum.HorizontalAlignment.Center
        row.Padding = UDim.new(0, 4)
        row.Parent = box

        local icon = Instance.new("ImageLabel")
        icon.Name = "Icon"
        icon.Size = UDim2.fromOffset(9, 9)
        icon.BackgroundTransparency = 1
        icon.Visible = false
        icon.LayoutOrder = 1
        icon.ZIndex = 3
        icon.Parent = box

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "Name"
        nameLabel.AutomaticSize = Enum.AutomaticSize.X
        nameLabel.Size = UDim2.new(0, 0, 1, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextSize = 9
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameLabel.TextStrokeTransparency = 0.35
        nameLabel.LayoutOrder = 2
        nameLabel.ZIndex = 3
        nameLabel.Parent = box

        local info = Instance.new("TextLabel")
        info.Name = "Info"
        info.AutomaticSize = Enum.AutomaticSize.X
        info.Size = UDim2.new(0, 0, 1, 0)
        info.BackgroundTransparency = 1
        info.Font = Enum.Font.GothamMedium
        info.TextSize = 9
        info.TextColor3 = Color3.fromRGB(230, 230, 230)
        info.RichText = true
        info.LayoutOrder = 3
        info.ZIndex = 3
        info.Parent = box

    end

    gui.Adornee = character:FindFirstChild("Head")
        or character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChildWhichIsA("BasePart")
    gui.StudsOffset = Vector3.new(0, 0.85, 0)

    local wrapper = gui:FindFirstChild("Wrapper")
    if wrapper then
        wrapper.Position = UDim2.new(0.5, 0, 0.5, -3)
        wrapper.AnchorPoint = Vector2.new(0.5, 1)
    end
    gui.Size = UDim2.fromOffset(110, 24)
    local box = wrapper and wrapper:FindFirstChild("Box")
    if box then box.Size = UDim2.fromOffset(0, 14) end
    local statusLabel = wrapper and wrapper:FindFirstChild("StatusText")
    local nameLabel = box and box:FindFirstChild("Name")
    local infoLabel = box and box:FindFirstChild("Info")
    local icon = box and box:FindFirstChild("Icon")
    if statusLabel then statusLabel.TextSize = 9; statusLabel.Size = UDim2.fromOffset(0, 8) end
    if nameLabel then nameLabel.TextSize = 9 end
    if infoLabel then infoLabel.TextSize = 9 end
    if icon then icon.Size = UDim2.fromOffset(9, 9) end
    if nameLabel then
        nameLabel.Text = data.name or ""
        nameLabel.Visible = data.name ~= nil and data.name ~= ""
        nameLabel.TextColor3 = data.isFovTarget and Color3.fromRGB(255, 48, 48) or Color3.fromRGB(255, 255, 255)
    end
    if infoLabel then
        infoLabel.Text = data.infoRich or ""
        infoLabel.Visible = data.infoRich ~= nil and data.infoRich ~= ""
    end
    if icon then
        icon.Image = data.icon or ""
        icon.Visible = data.icon ~= nil and data.icon ~= ""
    end
    if statusLabel then
        statusLabel.Text = data.status or ""
        statusLabel.Visible = data.status ~= nil and data.status ~= ""
        if data.status == "HOOKED" then
            statusLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
        elseif data.status == "DOWN" then
            statusLabel.TextColor3 = Color3.fromRGB(255, 150, 50)
        elseif data.status == "INJURED" then
            statusLabel.TextColor3 = Color3.fromRGB(255, 255, 50)
        else
            statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        end
    end
end

local function TianHub_ESPApplyESP(plr, camPos)
    if not plr or plr == LocalPlayer or not plr.Parent then return end
    local char = plr.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso"))
    if not char or not root then return end
    local killer = TianHub_IsKiller(plr)
    local enabled = killer and TianHub_ESP.KillerEnabled or (not killer and (TianHub_ESP.Player or TianHub_ESP.HookCount))
    local tagName = killer and "KE_Text" or "PE_Text"
    local highlightName = killer and "KEH" or "PEH"
    local color = killer and TianHub_ESP.KillerColor or TianHub_ESP.SurvivorColor
    local distance = (camPos - root.Position).Magnitude
    local maxDistance = TianHub_ESP.SurvivorDistance
    if not enabled or distance > (tonumber(maxDistance) or 500) then
        for _, name in ipairs({tagName, highlightName}) do
            local old = char:FindFirstChild(name)
            if old then old:Destroy() end
        end
        return
    end

    local highlight = char:FindFirstChild(highlightName)
    if not highlight then
        highlight = Instance.new("Highlight")
        highlight.Name = highlightName
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Parent = char
    end
    highlight.Adornee = char
    highlight.FillColor = color
    highlight.OutlineColor = color
    highlight.FillTransparency = TianHub_ESP.OutlineAll and 1 or (_G.TianHubESPTransparency or TianHub_ESP.FillTransparency)
    highlight.OutlineTransparency = 0

    distance = math.floor(distance + 0.5)
    local status = (not killer and TianHub_ESP.Status) and TianHub_ESPStatus(char) or nil
    local hookCountValue = (not killer and TianHub_ESP.HookCount) and (tonumber(plr:GetAttribute("HookCount")) or 0) or nil
    local hookCount = hookCountValue and (hookCountValue == 1 and "I" or hookCountValue == 2 and "II" or hookCountValue >= 3 and "III" or nil) or nil
    local name = (killer and TianHub_ESP.KillerName or (not killer and TianHub_ESP.PlayerName)) and plr.Name or nil
    if killer and name then
        local selected = plr:GetAttribute("SelectedKiller")
        if not selected then
            local selectedValue = plr:FindFirstChild("SelectedKiller")
            if selectedValue then pcall(function() selected = selectedValue.Value end) end
        end
        if selected and tostring(selected) ~= "" then name = tostring(selected) end
    end
    local itemIcon
    if not killer and TianHub_ESP.ItemIcon then
        local item = plr:GetAttribute("EquippedItem")
        if item and item ~= "" then itemIcon = TianHub_GetItemImage(tostring(item)) end
    end
    local fovTarget = rawget(_G, "TianHub_SilentVeilFOVTarget") == char
    local info = TianHub_ESPInfoRich(TianHub_ESP.PlayerShowDistance and distance or nil, hookCount, fovTarget)
    if name or info ~= "" or itemIcon or status then
        TianHub_ESPCreateModernESP(char, tagName, {name=name, infoRich=info, status=status, color=color, icon=itemIcon, isFovTarget=fovTarget})
    else
        local old = char:FindFirstChild(tagName)
        if old then old:Destroy() end
    end
end

local function TianHub_ESPKillerWarn()
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root or not TianHub_ESP.KillerWarn or TianHub_IsKiller(LocalPlayer) then
        local old = root and root:FindFirstChild("KillerWarn")
        if old then old:Destroy() end
        return
    end
    local nearest = math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and TianHub_IsKiller(plr) and plr.Character then
            local killerRoot = plr.Character:FindFirstChild("HumanoidRootPart")
            if killerRoot then nearest = math.min(nearest, (killerRoot.Position - root.Position).Magnitude) end
        end
    end
    local warn = root:FindFirstChild("KillerWarn")
    if nearest <= 80 then
        if not warn then
            warn = Instance.new("BillboardGui")
            warn.Name = "KillerWarn"
            warn.Size = UDim2.fromOffset(30, 30)
            warn.AlwaysOnTop = true
            warn.StudsOffset = Vector3.new(0, 4, 0)
            warn.Parent = root
            local label = Instance.new("TextLabel")
            label.Name = "WarnText"
            label.Size = UDim2.fromScale(1, 1)
            label.BackgroundTransparency = 1
            label.TextScaled = true
            label.TextStrokeTransparency = 0
            label.Font = Enum.Font.GothamBlack
            label.Parent = warn
        end
        local label = warn:FindFirstChild("WarnText")
        if label then
            label.Text = nearest <= 40 and "!!" or "!"
            label.TextColor3 = nearest <= 40 and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(255, 255, 0)
        end
    elseif warn then warn:Destroy() end
end

local function TianHub_RefreshPlayerESPConnection()
    if TianHub_ESP.Player or TianHub_ESP.KillerEnabled or TianHub_ESP.KillerWarn or TianHub_ESP.HookCount then
        if not _G.TianHub_PlayerESP_Running then
            _G.TianHub_PlayerESP_Running = true
            local last = 0
            setConn("TianHub_PlayerESP", RunService.Heartbeat:Connect(function()
                local now = os.clock()
                if now - last < 1.0 then return end
                last = now
                local camera = workspace.CurrentCamera
                if not camera then return end
                local pos = camera.CFrame.Position
                for _, plr in ipairs(Players:GetPlayers()) do pcall(TianHub_ESPApplyESP, plr, pos) end
                pcall(TianHub_ESPKillerWarn)
            end))
        end
        -- Color-only FOV pass: update existing labels every rendered frame,
        -- independently of the slower 1-second ESP creation/refresh worker.
        if not _G.TianHub_PlayerESP_FOVColorRunning then
            _G.TianHub_PlayerESP_FOVColorRunning = true
            setConn("TianHub_PlayerESP_FOVColor", RunService.RenderStepped:Connect(function()
                local target = rawget(_G, "TianHub_SilentVeilFOVTarget")
                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr ~= LocalPlayer then
                        local char = plr.Character
                        if char then
                            local tagName = TianHub_IsKiller(plr) and "KE_Text" or "PE_Text"
                            local gui = char:FindFirstChild(tagName)
                            local wrapper = gui and gui:FindFirstChild("Wrapper")
                            local box = wrapper and wrapper:FindFirstChild("Box")
                            local nameLabel = box and box:FindFirstChild("Name")
                            local infoLabel = box and box:FindFirstChild("Info")
                            local inside = target == char
                            if nameLabel then
                                nameLabel.TextColor3 = inside and Color3.fromRGB(255, 48, 48) or Color3.fromRGB(255, 255, 255)
                            end
                            if infoLabel and infoLabel.RichText then
                                local distanceColor = inside and "#FF3030" or "#00FF00"
                                infoLabel.Text = infoLabel.Text:gsub('(<font color=")[^"]+("%>%[%d+s%]</font>)', '%1' .. distanceColor .. '%2')
                            end
                        end
                    end
                end
            end))
        end
    else
        disconnect("TianHub_PlayerESP")
        disconnect("TianHub_PlayerESP_FOVColor")
        _G.TianHub_PlayerESP_Running = false
        _G.TianHub_PlayerESP_FOVColorRunning = false
        TianHub_ClearPlayerESP()
    end
end

CreateToggle(VisualESP, "Player ESP", true, function(state)
    TianHub_ESP.Player = state
    TianHub_RefreshPlayerESPConnection()
end)
CreateToggle(VisualESP, "ESP Name", false, function(v) TianHub_ESP.PlayerName = v; TianHub_RefreshPlayerESPConnection() end)
CreateToggle(VisualESP, "ESP Distance", false, function(v) TianHub_ESP.PlayerShowDistance = v; TianHub_RefreshPlayerESPConnection() end)
CreateToggle(VisualESP, "ESP Status Survivor", false, function(v) TianHub_ESP.Status = v; TianHub_RefreshPlayerESPConnection() end)
CreateToggle(VisualESP, "ESP Item Icon", false, function(v) TianHub_ESP.ItemIcon = v; TianHub_RefreshPlayerESPConnection() end)
CreateToggle(VisualESP, "ESP Hook Count", false, function(v) TianHub_ESP.HookCount = v; TianHub_RefreshPlayerESPConnection() end)
CreateToggle(VisualESP, "ESP Killer Warn", false, function(v)
    TianHub_ESP.KillerWarn = v
    TianHub_RefreshPlayerESPConnection()
end)
CreateColorPicker(VisualESP, "Player ESP Color", TianHub_ESP.SurvivorColor, function(c) TianHub_ESP.SurvivorColor = c end)
CreateSlider(VisualESP, "ESP Max Distance", 25, 600, 500, " studs", function(v) TianHub_ESP.SurvivorDistance = tonumber(v) or 500; TianHub_RefreshPlayerESPConnection() end)
CreateToggle(VisualESP, "Killer ESP", true, function(v)
    TianHub_ESP.KillerEnabled = v
    TianHub_RefreshPlayerESPConnection()
end)
CreateToggle(VisualESP, "Killer ESP Name", false, function(v) TianHub_ESP.KillerName = v end)
CreateColorPicker(VisualESP, "Killer ESP Color", TianHub_ESP.KillerColor, function(c) TianHub_ESP.KillerColor = c end)
-- Apply the requested default-on player and killer ESP immediately at execution.
if ToggleRegistry["player_esp"] then ToggleRegistry["player_esp"].setState(true, true) end
if ToggleRegistry["killer_esp"] then ToggleRegistry["killer_esp"].setState(true, true) end
if ToggleRegistry["esp_distance"] then ToggleRegistry["esp_distance"].setState(false, true) end
CreateToggle(VisualESP, "Mode Outline ESP", true, function(v) TianHub_ESP.OutlineAll = v; TianHub_RefreshPlayerESPConnection() end)
CreateButton(VisualESP, "Refresh All Player ESP", function()
    TianHub_ClearPlayerESP()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then pcall(TianHub_ESPApplyESP, p, workspace.CurrentCamera.CFrame.Position) end
    end
end)

end, function(e) logQuiet("[TianHub] ESP block error: " .. tostring(e)) end)

local TianHubObjectESPSection = CreateSection(VisualTab, "OBJECT ESP", false)
_G.TianHubESPTransparency = 0.7

-- TianHub Dynamic Map ESP: Generator and Hook scanner/renderer.
-- Only Generator and Hook are replaced here; Gate and all other TianHub ESP remain intact.
xpcall(function()
    local GeneratorESP = { Enabled = false }
    local MapObjectESP = {
        Hook = false, Gate = false, ShowProgress = true, Distance = math.huge,
        GeneratorColor = Color3.fromRGB(255, 255, 255),
        HookColor = Color3.fromRGB(255, 105, 180),
        GateColor = Color3.fromRGB(255, 255, 255),
    }

    local generators, hooks, gates = {}, {}, {}
    local objectHighlights = setmetatable({}, { __mode = "k" })
    local generatorLabels = setmetatable({}, { __mode = "k" })
    local scanLast, scanBusy, updateLast = 0, false, 0
    local Bridge
    local SCAN_INTERVAL, UPDATE_INTERVAL = 6, 1.0 -- Lightweight cadence: map scan every 6s; ESP refresh every 1s

    local function valid(obj)
        return obj ~= nil and obj.Parent ~= nil
    end

    local function targetPart(obj)
        if not valid(obj) then return nil end
        if obj:IsA("BasePart") then return obj end
        if obj:IsA("Model") or obj:IsA("Folder") then
            return obj:FindFirstChild("HookPoint", true)
                or (obj:IsA("Model") and obj.PrimaryPart)
                or obj:FindFirstChild("Handle", true)
                or obj:FindFirstChildWhichIsA("BasePart", true)
        end
        return nil
    end

    local function clearHighlight(obj)
        local h = objectHighlights[obj]
        if h then pcall(function() h:Destroy() end) end
        objectHighlights[obj] = nil
        if valid(obj) then
            local old = obj:FindFirstChild("__TianHubObjectOutline")
            if old then pcall(function() old:Destroy() end) end
        end
    end

    -- TianHub highlight behavior, adapted to Outline-only and isolated ownership.
    local function applyOutline(obj, color)
        if not valid(obj) then return end
        local adornee = obj:IsA("Model") and obj or targetPart(obj)
        if not adornee then return end
        local h = objectHighlights[obj]
        if not h or not h.Parent then
            h = Instance.new("Highlight")
            h.Name = "__TianHubObjectOutline"
            h.Adornee = adornee
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.Parent = obj
            objectHighlights[obj] = h
        end
        h.Enabled = true
        h.FillColor = color
        h.OutlineColor = color
        h.FillTransparency = MapObjectESP.ShowOutline and 1 or (_G.TianHubESPTransparency or 0.7)
        h.OutlineTransparency = 0
    end

    local function clearGeneratorLabel(obj)
        local gui = generatorLabels[obj]
        if gui then pcall(function() gui:Destroy() end) end
        generatorLabels[obj] = nil
    end

    local function generatorProgress(model)
        -- Prefer authoritative game attributes/values; otherwise count completed
        -- GeneratorPoint parts without inventing a percentage.
        local candidates = {"RepairProgress", "ProgressRepair", "Progress", "Repair"}
        for _, key in ipairs(candidates) do
            local value = model:GetAttribute(key)
            if typeof(value) == "number" then
                return math.clamp(math.floor(value), 0, 100)
            end
        end
        for _, key in ipairs(candidates) do
            local valueObj = model:FindFirstChild(key, true)
            if valueObj and (valueObj:IsA("NumberValue") or valueObj:IsA("IntValue")) then
                return math.clamp(math.floor(valueObj.Value), 0, 100)
            end
        end
        local points, completed = {}, 0
        for _, child in ipairs(model:GetDescendants()) do
            if child:IsA("BasePart") and child.Name:find("GeneratorPoint", 1, true) then
                points[#points + 1] = child
                local done = child:GetAttribute("Completed") == true
                    or child:GetAttribute("Repaired") == true
                local status = child:FindFirstChild("Completed")
                    or child:FindFirstChild("Repaired")
                if status and status:IsA("BoolValue") and status.Value then done = true end
                if done then completed = completed + 1 end
            end
        end
        if #points > 0 then return math.floor((completed / #points) * 100) end
        return 0
    end

    local function updateGeneratorLabel(model, index)
        if not valid(model) then return end
        local part = targetPart(model)
        if not part then return end
        local gui = generatorLabels[model]
        if not gui or not gui.Parent then
            gui = Instance.new("BillboardGui")
            gui.Name = "__TianHubGeneratorProgress"
            gui.Size = UDim2.fromOffset(110, 24)
            gui.StudsOffset = Vector3.new(0, 2.2, 0)
            gui.AlwaysOnTop = true
            gui.Adornee = part
            gui.Parent = model
            local label = Instance.new("TextLabel")
            label.Name = "Progress"
            label.Size = UDim2.fromScale(1, 1)
            label.BackgroundTransparency = 1
            label.TextColor3 = Color3.fromRGB(255, 255, 255)
            label.TextStrokeColor3 = Color3.new(0, 0, 0)
            label.TextStrokeTransparency = 0
            label.Font = Enum.Font.GothamBold
            label.TextSize = 9
            label.TextScaled = false
            label.Parent = gui
            generatorLabels[model] = gui
        end
        gui.Adornee = part
        local label = gui:FindFirstChild("Progress")
        if label then
            local progress = generatorProgress(model)
            local repairing = tonumber(model:GetAttribute("PlayersRepairingCount")) or 0
            label.Text = repairing > 0 and string.format("GEN%d [%d%%] (%d plyr)", index, progress, repairing)
                or string.format("GEN%d [%d%%]", index, progress)
        end
    end

    local function removeMissing(oldList, newList, clearLabel)
        local seen = {}
        for _, obj in ipairs(newList) do seen[obj] = true end
        for _, obj in ipairs(oldList) do
            if not seen[obj] then
                clearHighlight(obj)
                if clearLabel then clearGeneratorLabel(obj) end
            end
        end
    end

    local function scanMapObjects()
        if scanBusy then return end
        scanBusy = true
        task.spawn(function()
            local ok, err = pcall(function()
                local map = workspace:FindFirstChild("Map")
                local root = map or workspace
                local descendants = root:GetDescendants()
                local genList, hookList, gateList = {}, {}, {}
                local seenGen, seenHook, seenGate, characters = {}, {}, {}, {}
                for _, player in ipairs(Players:GetPlayers()) do
                    if player.Character then characters[player.Character] = true end
                end

                -- TianHub object-scanner-style batched scan; refreshes on map changes.
                for i, inst in ipairs(descendants) do
                    if i % 1200 == 0 then task.wait() end
                    local name = inst.Name
                    if name == "Generator" or name == "GeneratorPoint" then
                        -- Match Hook ESP detection: resolve GeneratorPoint parts
                        -- to their owning Generator model, with loose-object fallback.
                        local generatorObject = inst
                        if name == "GeneratorPoint" then
                            local parentModel = inst:FindFirstAncestorWhichIsA("Model")
                            if parentModel and parentModel.Name == "Generator" then
                                generatorObject = parentModel
                            end
                        end

                        local generatorPart = nil
                        if generatorObject:IsA("BasePart") then
                            generatorPart = generatorObject
                        elseif generatorObject:IsA("Model") or generatorObject:IsA("Folder") then
                            generatorPart = generatorObject:FindFirstChild("GeneratorPoint", true)
                                or (generatorObject:IsA("Model") and generatorObject.PrimaryPart)
                                or generatorObject:FindFirstChild("Handle", true)
                                or generatorObject:FindFirstChildWhichIsA("BasePart", true)
                        end

                        if generatorPart and not seenGen[generatorObject] then
                            seenGen[generatorObject] = true
                            genList[#genList + 1] = generatorObject
                        end
                    elseif name == "Hook" or name == "HookPoint" then
                        -- TianHub hook detection, adapted only to
                        -- TianHub's existing hook list and outline renderer.
                        local isCharacterPart = false
                        local ancestor = inst
                        while ancestor and ancestor ~= workspace and ancestor ~= map do
                            if characters[ancestor] then
                                isCharacterPart = true
                                break
                            end
                            ancestor = ancestor.Parent
                        end

                        if not isCharacterPart then
                            local hookPart = nil
                            if inst:IsA("BasePart") then
                                hookPart = inst
                            elseif inst:IsA("Model") or inst:IsA("Folder") then
                                hookPart = inst:FindFirstChild("HookPoint")
                                    or (inst:IsA("Model") and inst.PrimaryPart)
                                    or inst:FindFirstChild("Handle")
                                    or inst:FindFirstChildWhichIsA("BasePart")
                            end

                            if hookPart then
                                -- Prefer the full Hook model for a clean outline; fall back to
                                -- the detected Hook/HookPoint part when the map uses loose parts.
                                local hookObject = inst
                                if inst.Name == "HookPoint" then
                                    local parentModel = inst:FindFirstAncestorWhichIsA("Model")
                                    if parentModel and parentModel.Name == "Hook" then hookObject = parentModel end
                                elseif inst:IsA("BasePart") then
                                    local parentModel = inst:FindFirstAncestorWhichIsA("Model")
                                    if parentModel and parentModel.Name == "Hook" then hookObject = parentModel end
                                end
                                if not seenHook[hookObject] then
                                    seenHook[hookObject] = true
                                    hookList[#hookList + 1] = hookObject
                                end
                            end
                        end
                    end
                    if map then
                        local lower = name:lower()
                        if not (lower:find("spot", 1, true) or lower:find("spawn", 1, true)
                            or lower:find("marker", 1, true) or lower:find("point", 1, true)) then
                            local lever = name == "ExitLever" and inst or inst:FindFirstChild("ExitLever", true)
                            if lever and not seenGate[lever] then
                                seenGate[lever] = true
                                gateList[#gateList + 1] = lever
                            end
                        end
                    end
                end

                removeMissing(generators, genList, true)
                removeMissing(hooks, hookList, false)
                removeMissing(gates, gateList, false)
                generators, hooks, gates = genList, hookList, gateList
                if Bridge then
                    Bridge.Generators, Bridge.Hooks, Bridge.Gates = generators, hooks, gates
                end
            end)
            if not ok then logQuiet("[TianHub] ESP scan: " .. tostring(err)) end
            scanBusy = false
        end)
    end

    local function clearList(list, clearLabel)
        for _, obj in ipairs(list) do
            clearHighlight(obj)
            if clearLabel then clearGeneratorLabel(obj) end
        end
    end

    Bridge = {
        Generator = GeneratorESP, Map = MapObjectESP,
        ClearObject = function(obj) clearHighlight(obj); clearGeneratorLabel(obj) end,
        ClearHookObject = clearHighlight,
        ClearLabel = clearGeneratorLabel,
        Generators = generators, Hooks = hooks, Gates = gates,
    }
    _G.TianHubObjectESPBridge = Bridge

    setConn("TianHub_GeneratorESP", RunService.Heartbeat:Connect(function()
        local now = os.clock()
        if now - updateLast < UPDATE_INTERVAL then return end
        updateLast = now

        local genOn, hookOn, gateOn = GeneratorESP.Enabled, MapObjectESP.Hook, MapObjectESP.Gate
        if not (genOn or hookOn or gateOn) then
            clearList(generators, true)
            clearList(hooks, false)
            clearList(gates, false)
            return
        end

        if now - scanLast >= SCAN_INTERVAL then
            scanLast = now
            scanMapObjects()
        end

        -- TianHub global ESP pass: every discovered object is rendered,
        -- independent of the local player's position or camera distance.
        local function inRange(obj)
            return valid(obj) and targetPart(obj) ~= nil
        end

        local genIndex = 0
        for _, obj in ipairs(generators) do
            if genOn and valid(obj) and inRange(obj) then
                genIndex = genIndex + 1
                local progress = generatorProgress(obj)
                local genColor = progress >= 100 and Color3.fromRGB(0, 255, 0) or MapObjectESP.GeneratorColor
                applyOutline(obj, genColor)
                if MapObjectESP.ShowProgress then
                    updateGeneratorLabel(obj, genIndex)
                    local genGui = generatorLabels[obj]
                    local genText = genGui and genGui:FindFirstChild("Progress")
                    if genText then genText.TextColor3 = genColor end
                else
                    clearGeneratorLabel(obj)
                end
            else
                clearHighlight(obj)
                clearGeneratorLabel(obj)
            end
        end

        for _, obj in ipairs(hooks) do
            if hookOn and valid(obj) and inRange(obj) then
                applyOutline(obj, MapObjectESP.HookColor)
            else
                clearHighlight(obj)
            end
        end

        for _, obj in ipairs(gates) do
            if gateOn and valid(obj) and inRange(obj) then
                applyOutline(obj, MapObjectESP.GateColor)
            else
                clearHighlight(obj)
            end
        end
    end))

    setConn("TianHub_ESP_MapAdded", workspace.DescendantAdded:Connect(function(inst)
        local n = inst.Name:lower()
        if n == "generator" or n == "generatorpoint" or n == "hook" or n == "hookpoint" or n == "exitlever" then
            scanLast = 0
        end
    end))
    setConn("TianHub_ESP_MapRemoved", workspace.DescendantRemoving:Connect(function(inst)
        if objectHighlights[inst] then clearHighlight(inst) end
        if generatorLabels[inst] then clearGeneratorLabel(inst) end
        scanLast = 0
    end))
end, function(e) logQuiet("[TianHub] object ESP error: " .. tostring(e)) end)

-- TianHub Map Object ESP: Pallet, Window, Pumpkin and SCP. Generator ESP remains separate.
xpcall(function()
    local OESP = { Pallet = false, Vault = false, Window = false, Pumpkin = false, SCP = false, Distance = math.huge }
    local COLORS = {
        Pallet = Color3.fromRGB(60, 255, 255),
        Window = Color3.fromRGB(60, 255, 255),
        Pumpkin = Color3.fromRGB(255, 140, 0),
        SCP = Color3.fromRGB(255, 0, 255),
    }
    local ESPObjects, CachedSCP, CachedPumpkin, CachedPallet = {}, {}, {}, {}
    local PumpkinLabels, WindowObjects = {}, {}
    local Workspace = workspace

    local function IsPumpkinObject(obj)
        if not obj or not (obj:IsA("Model") or obj:IsA("BasePart")) then return false end
        local map = Workspace:FindFirstChild("Map")
        local pumpkins = map and map:FindFirstChild("Pumpkins")
        return pumpkins ~= nil and obj.Parent == pumpkins and string.match(obj.Name, "^Pumpkin%d+$") ~= nil
    end

    local function CacheObject(obj)
        if not obj then return end
        local ln = string.lower(obj.Name)
        if string.find(ln, "scp", 1, true) then CachedSCP[obj] = true end
        if IsPumpkinObject(obj) then CachedPumpkin[obj] = true end
        if obj.Name == "Pallet" or obj.Name == "Palletwrong" then CachedPallet[obj] = true end
    end

    local function RemoveESP(obj)
        if not obj then return end
        if ESPObjects[obj] then pcall(function() ESPObjects[obj]:Destroy() end); ESPObjects[obj] = nil end
    end

    local function CreateESP(obj, color)
        if not obj or not obj.Parent then return end
        if ESPObjects[obj] then
            ESPObjects[obj].FillColor = color
            ESPObjects[obj].OutlineColor = color
            ESPObjects[obj].FillTransparency = _G.TianHubESPTransparency or 0.7
            return
        end
        local h = Instance.new("Highlight")
        h.Name = "__TianHubObjectESP__"
        h.FillColor = color
        h.OutlineColor = color
        h.FillTransparency = _G.TianHubESPTransparency or 0.7
        h.OutlineTransparency = 0.3
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Parent = obj
        ESPObjects[obj] = h
        obj.AncestryChanged:Connect(function(_, parent) if not parent then RemoveESP(obj) end end)
    end

    local function GetObjectPosition(obj)
        if not obj then return nil end
        if obj:IsA("BasePart") then return obj.Position end
        if obj:IsA("Model") then
            local ok, pivot = pcall(function() return obj:GetPivot().Position end)
            if ok then return pivot end
            local part = obj:FindFirstChildWhichIsA("BasePart", true)
            return part and part.Position or nil
        end
        return nil
    end

    local function RemovePumpkinLabel(obj)
        local label = PumpkinLabels[obj]
        if label then pcall(function() label:Destroy() end); PumpkinLabels[obj] = nil end
    end

    local function GetPumpkinPosition(obj)
        if obj:IsA("BasePart") then return obj.Position, obj end
        if obj:IsA("Model") then
            local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
            local ok, pivot = pcall(function() return obj:GetPivot().Position end)
            if ok then return pivot, part end
            return part and part.Position or nil, part
        end
        return nil, nil
    end

    local function UpdatePumpkinESP(root)
        if not OESP.Pumpkin then return end
        for obj in pairs(CachedPumpkin) do
            if not obj or not obj.Parent then
                RemoveESP(obj); RemovePumpkinLabel(obj); CachedPumpkin[obj] = nil
            else
                local pos, adornee = GetPumpkinPosition(obj)
                if pos and adornee and (pos - root.Position).Magnitude <= OESP.Distance then
                    CreateESP(obj, COLORS.Pumpkin)
                    local label = PumpkinLabels[obj]
                    if not label or not label.Parent then
                        label = Instance.new("BillboardGui")
                        label.Name = "TianHub_PumpkinESPLabel"
                        label.Size = UDim2.new(0, 150, 0, 28)
                        label.StudsOffset = Vector3.new(0, 3, 0)
                        label.AlwaysOnTop = true
                        label.Adornee = adornee
                        local text = Instance.new("TextLabel")
                        text.Name = "Label"
                        text.Size = UDim2.new(1, 0, 1, 0)
                        text.BackgroundTransparency = 1
                        text.TextColor3 = COLORS.Pumpkin
                        text.TextStrokeTransparency = 0.15
                        text.Font = Enum.Font.GothamBold
                        text.TextSize = 5
                        text.Parent = label
                        label.Parent = adornee
                        PumpkinLabels[obj] = label
                    else
                        label.Adornee = adornee
                    end
                    local text = label:FindFirstChild("Label")
                    if text then
                        text.Text = string.format("PUMPKIN [%d studs]", math.floor((pos - root.Position).Magnitude + 0.5))
                        text.TextColor3 = COLORS.Pumpkin
                    end
                else
                    RemoveESP(obj); RemovePumpkinLabel(obj)
                end
            end
        end
    end

    local function UpdateSCPEsp(root)
        if not OESP.SCP then return end
        for obj in pairs(CachedSCP) do
            if obj and obj.Parent then
                local pos = GetObjectPosition(obj)
                if pos and (pos - root.Position).Magnitude <= OESP.Distance then
                    CreateESP(obj, COLORS.SCP)
                else
                    RemoveESP(obj)
                end
            end
        end
    end

    local function RemoveWindowESP(model)
        if not model then return end
        local data = WindowObjects[model]
        if data then
            if data.highlight then pcall(function() data.highlight:Destroy() end) end
            if data.box then pcall(function() data.box:Destroy() end) end
            if data.bottomPart and data.bottomPart.Parent then
                pcall(function()
                    local original = data.bottomPart:GetAttribute("ESP_OrigTrans")
                    if original ~= nil then
                        data.bottomPart.Transparency = original
                        data.bottomPart:SetAttribute("ESP_OrigTrans", nil)
                    end
                end)
            end
            WindowObjects[model] = nil
        end
    end

    local function HandleWindowObject(child)
        if not OESP.Vault or not child or child.Name ~= "VaultTrigger" then return end
        local model = child.Parent
        if not model or not model:IsA("Model") or WindowObjects[model] then return end
        local bottomPart = model:FindFirstChild("Bottom")
        if not bottomPart or not bottomPart:IsA("BasePart") then
            local bestSize = 0
            for _, part in ipairs(model:GetChildren()) do
                if part:IsA("BasePart") and part.Name ~= "VaultTrigger" and part.Name ~= "inviswall" and part.Size.Magnitude > bestSize then
                    bestSize = part.Size.Magnitude
                    bottomPart = part
                end
            end
        end
        if not bottomPart then return end
        if bottomPart:GetAttribute("ESP_OrigTrans") == nil then bottomPart:SetAttribute("ESP_OrigTrans", bottomPart.Transparency) end
        if bottomPart.Transparency > 0.5 then bottomPart.Transparency = 0.5 end
        local box = Instance.new("BoxHandleAdornment")
        box.Name = "GlutoWindowBox"
        box.Adornee = bottomPart
        box.Size = bottomPart.Size
        box.Color3 = COLORS.Window
        box.Transparency = 0.3
        box.AlwaysOnTop = true
        box.ZIndex = 5
        box.Parent = bottomPart
        local hl = Instance.new("Highlight")
        hl.Name = "GlutoWindowHighlight"
        hl.Adornee = model
        hl.FillColor = COLORS.Window
        hl.FillTransparency = _G.TianHubESPTransparency or 0.7
        hl.OutlineColor = COLORS.Window
        hl.OutlineTransparency = 0.1
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = model
        WindowObjects[model] = { highlight = hl, box = box, bottomPart = bottomPart }
    end

    local function ScanAllWindows()
        if not OESP.Vault then return end
        local map = Workspace:FindFirstChild("Map")
        if not map then return end
        for _, obj in ipairs(map:GetDescendants()) do
            if obj.Name == "VaultTrigger" then HandleWindowObject(obj) end
        end
    end

    local objectCacheReady = false
    local function EnsureObjectCache()
        if objectCacheReady then return end
        objectCacheReady = true
        local descendants = Workspace:GetDescendants()
        for i = 1, #descendants do CacheObject(descendants[i]) end
    end
    Workspace.DescendantAdded:Connect(function(obj)
        if objectCacheReady or OESP.Pallet or OESP.Pumpkin or OESP.SCP then CacheObject(obj) end
        if obj.Name == "VaultTrigger" and OESP.Vault then task.defer(function() HandleWindowObject(obj) end) end
    end)
    Workspace.DescendantRemoving:Connect(function(obj)
        CachedSCP[obj] = nil; CachedPumpkin[obj] = nil; CachedPallet[obj] = nil
        RemovePumpkinLabel(obj); RemoveESP(obj)
        if WindowObjects[obj] then RemoveWindowESP(obj) end
    end)

    local elapsed, lastScan = 0, 0
    setConn("TianHub_ObjectESP", RunService.Heartbeat:Connect(function(dt)
        elapsed = elapsed + dt
        if elapsed < 1.0 then return end -- Lightweight cadence: cached ESP render/update every 1s; object types remain unchanged
        elapsed = 0
        local anyEnabled = OESP.Pallet or OESP.Vault or OESP.Pumpkin or OESP.SCP
        if not anyEnabled then return end
        EnsureObjectCache()
        if os.clock() - lastScan >= 10 then
            lastScan = os.clock()
            if OESP.Vault then ScanAllWindows() end
        end
        local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not root then return end
        if OESP.Pallet then
            for obj in pairs(CachedPallet) do
                if obj and obj.Parent then
                    local pos = GetObjectPosition(obj)
                    if pos and (pos - root.Position).Magnitude <= OESP.Distance then
                        CreateESP(obj, COLORS.Pallet)
                    else
                        RemoveESP(obj)
                    end
                end
            end
        end
        if OESP.Pumpkin then UpdatePumpkinESP(root) end
        if OESP.SCP then UpdateSCPEsp(root) end
    end))

    local ObjectESPSection = TianHubObjectESPSection
    local Bridge = _G.TianHubObjectESPBridge
    CreateToggle(ObjectESPSection, "ESP Generator", false, function(v)
        Bridge.Generator.Enabled = v
        if not v then
            -- The dynamic-map renderer owns generator adornment cleanup.
            for _, obj in ipairs(Bridge.Generators or {}) do Bridge.ClearObject(obj) end
        end
    end)
    CreateToggle(ObjectESPSection, "Show Progress Gen", false, function(v)
        Bridge.Map.ShowProgress = v
        if not v then
            -- Existing generator labels are refreshed by the renderer on its next heartbeat.
            for _, obj in ipairs(Bridge.Generators or {}) do Bridge.ClearLabel(obj) end
        end
    end)
    CreateToggle(ObjectESPSection, "ESP Pallet", false, function(v)
        OESP.Pallet = v
        if v then EnsureObjectCache() else for obj in pairs(CachedPallet) do RemoveESP(obj) end end
    end)
    CreateToggle(ObjectESPSection, "ESP Vault", false, function(v)
        -- This source detects VaultTrigger through the existing window renderer.
        OESP.Vault = v
        if v then EnsureObjectCache(); ScanAllWindows()
        else for model in pairs(WindowObjects) do RemoveWindowESP(model) end end
    end)
    CreateToggle(ObjectESPSection, "ESP Hook", false, function(v)
        Bridge.Map.Hook = v
        if not v then
            for _, obj in ipairs(Bridge.Hooks or {}) do Bridge.ClearHookObject(obj) end
        end
    end)
    CreateToggle(ObjectESPSection, "ESP Gate", false, function(v)
        Bridge.Map.Gate = v
        if not v then
            for _, obj in ipairs(Bridge.Gates or {}) do Bridge.ClearObject(obj) end
        end
    end)
    CreateToggle(ObjectESPSection, "ESP SCP", false, function(v)
        OESP.SCP = v
        if v then EnsureObjectCache() else for obj in pairs(CachedSCP) do RemoveESP(obj) end end
    end)
    CreateToggle(ObjectESPSection, "ESP Pumpkin", false, function(v)
        OESP.Pumpkin = v
        if v then EnsureObjectCache() else
            for obj in pairs(CachedPumpkin) do RemoveESP(obj); RemovePumpkinLabel(obj) end
        end
    end)

    -- Bear Trap ESP: independent lightweight scanner, rendered inside the Visual > Object ESP section.
    local BearTrapESP = {
        Enabled = false,
        Color = Color3.fromRGB(180, 120, 255),
        MaxDistance = 500,
        Highlights = setmetatable({}, { __mode = "k" }),
        Generation = 0,
    }

    local function IsBearTrapObject(obj)
        if not obj or not obj.Parent then return false end
        local name = string.lower(obj.Name or "")
        name = name:gsub("[%s_%-]", "")
        return name == "beartrap" or name == "beartrapmodel"
            or name:find("beartrap", 1, true) ~= nil
    end

    local function GetBearTrapAdornee(obj)
        if obj:IsA("BasePart") then return obj end
        if obj:IsA("Model") then
            return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
        end
        return obj:FindFirstChildWhichIsA("BasePart", true)
    end

    local function ClearBearTrapESP()
        for obj, highlight in pairs(BearTrapESP.Highlights) do
            if highlight then pcall(function() highlight:Destroy() end) end
            if obj then
                local label = obj:FindFirstChild("__TianHubBearTrapLabel")
                if label then pcall(function() label:Destroy() end) end
            end
            BearTrapESP.Highlights[obj] = nil
        end
    end

    local function ApplyBearTrapESP(obj, root)
        if not IsBearTrapObject(obj) then return end
        local adornee = GetBearTrapAdornee(obj)
        if not adornee or not root then return end
        if (adornee.Position - root.Position).Magnitude > BearTrapESP.MaxDistance then return end
        local h = BearTrapESP.Highlights[obj]
        if not h or not h.Parent then
            h = Instance.new("Highlight")
            h.Name = "TianHub_BearTrap_ESP"
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.FillTransparency = _G.TianHubESPTransparency or 0.7
            h.OutlineTransparency = 0
            h.Parent = obj
            BearTrapESP.Highlights[obj] = h
        end
        h.Adornee = obj
        h.FillColor = BearTrapESP.Color
        h.OutlineColor = BearTrapESP.Color
        h.Enabled = true

        -- Name label removed by request; keep the Bear Trap Highlight ESP only.
        local label = obj:FindFirstChild("__TianHubBearTrapLabel")
        if label then pcall(function() label:Destroy() end) end
    end

    local function StartBearTrapESP()
        BearTrapESP.Generation += 1
        local generation = BearTrapESP.Generation
        task.spawn(function()
            while BearTrapESP.Enabled and generation == BearTrapESP.Generation do
                local char = LocalPlayer.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                if root then
                    for _, obj in ipairs(workspace:GetDescendants()) do
                        if not BearTrapESP.Enabled or generation ~= BearTrapESP.Generation then break end
                        if IsBearTrapObject(obj) then
                            pcall(ApplyBearTrapESP, obj, root)
                        end
                    end
                end
                for obj, h in pairs(BearTrapESP.Highlights) do
                    if not obj or not obj.Parent or not h or not h.Parent then
                        if h then pcall(function() h:Destroy() end) end
                        if obj then
                            local label = obj:FindFirstChild("__TianHubBearTrapLabel")
                            if label then pcall(function() label:Destroy() end) end
                        end
                        BearTrapESP.Highlights[obj] = nil
                    end
                end
                task.wait(2.5)
            end
        end)
    end

    CreateToggle(ObjectESPSection, "ESP Bear Trap", true, function(v)
        BearTrapESP.Enabled = v == true
        if BearTrapESP.Enabled then
            StartBearTrapESP()
        else
            BearTrapESP.Generation += 1
            ClearBearTrapESP()
        end
    end)
    if ToggleRegistry["esp_bear_trap"] then ToggleRegistry["esp_bear_trap"].setState(true, true) end

    -- All object ESP color controls are placed together after the toggles.
    CreateColorPicker(ObjectESPSection, "Generator ESP Color", Bridge.Map.GeneratorColor, function(c)
        Bridge.Map.GeneratorColor = c
    end)
    CreateColorPicker(ObjectESPSection, "Pallet ESP Color", COLORS.Pallet, function(c) COLORS.Pallet = c end)
    CreateColorPicker(ObjectESPSection, "Vault ESP Color", COLORS.Window, function(c)
        COLORS.Window = c
        for _, data in pairs(WindowObjects) do
            if data.highlight then data.highlight.FillColor = c; data.highlight.OutlineColor = c end
            if data.box then data.box.Color3 = c end
        end
    end)
    CreateColorPicker(ObjectESPSection, "Hook ESP Color", Bridge.Map.HookColor, function(c) Bridge.Map.HookColor = c end)
    CreateColorPicker(ObjectESPSection, "Gate ESP Color", Bridge.Map.GateColor, function(c) Bridge.Map.GateColor = c end)
    CreateColorPicker(ObjectESPSection, "SCP ESP Color", COLORS.SCP, function(c) COLORS.SCP = c end)
    CreateColorPicker(ObjectESPSection, "Pumpkin ESP Color", COLORS.Pumpkin, function(c) COLORS.Pumpkin = c end)
    CreateColorPicker(ObjectESPSection, "Bear Trap ESP Color", Color3.fromRGB(180, 120, 255), function(c)
        BearTrapESP.Color = c
        for _, h in pairs(BearTrapESP.Highlights) do
            if h then h.FillColor = c; h.OutlineColor = c end
        end
    end)
    CreateSlider(ObjectESPSection, "Object ESP Radius", 10, 1000, 500, " studs", function(v) OESP.Distance = tonumber(v) or 500; Bridge.Map.Distance = OESP.Distance end)
    CreateSlider(ObjectESPSection, "ESP Transparency", 0, 10, 7, " / 10", function(v)
        _G.TianHubESPTransparency = math.clamp((tonumber(v) or 7) / 10, 0, 1)
        Bridge.Map.ShowOutline = false
        for _, data in pairs(WindowObjects) do
            if data.highlight then data.highlight.FillTransparency = _G.TianHubESPTransparency end
        end
        for _, h in pairs(BearTrapESP.Highlights) do
            if h then h.FillTransparency = _G.TianHubESPTransparency end
        end
        for _, h in pairs(ESPObjects) do
            if h then h.FillTransparency = _G.TianHubESPTransparency end
        end
        -- Player, generator, hook, and map ESP renderers reuse this shared opacity.
    end)
end, function(e) logQuiet("[TianHub] object ESP error: " .. tostring(e)) end)


xpcall(function()
    -- TianHub Killer FOV: Line Always, Sensor Range, Always Length.
    -- Kept isolated from the other TianHub systems.
    local KillerFOV = {
        LineEnabled = false,
        SensorEnabled = false,
        AlwaysLength = 50,
        LineObjects = setmetatable({}, { __mode = "k" }),
        SensorObjects = setmetatable({}, { __mode = "k" }),
        Connection = nil,
    }

    local LINE_COLOR = Color3.fromRGB(248, 248, 255)
    local ATTACK_COLOR = Color3.fromRGB(199, 21, 133)
    local ATTACK_ANIMATIONS = {
        [75258958842388] = true,
        [96744338559260] = true,
        [137846825408335] = true,
        [139928639611415] = true,
        [92098503722633] = true,
        [84093948968516] = true,
        [138045669415653] = true,
        [137688077908355] = true,
        [117886494230451] = true,
    }

    local function isKillerCharacter(char)
        local plr = char and Players:GetPlayerFromCharacter(char)
        return plr ~= nil and plr ~= LocalPlayer and TianHub_IsKiller(plr)
    end

    local function getLineColor(char)
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
        if not animator then return LINE_COLOR end

        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            if track and track.IsPlaying then
                local animationId
                pcall(function()
                    local raw = track.Animation and track.Animation.AnimationId
                    animationId = tonumber(tostring(raw or ""):match("%d+"))
                end)
                if animationId and ATTACK_ANIMATIONS[animationId] then
                    return ATTACK_COLOR
                end
            end
        end
        return LINE_COLOR
    end

    local function destroyLine(char)
        local data = KillerFOV.LineObjects[char]
        if not data then return end
        for _, object in ipairs({
            data.Beam, data.Endpoint, data.EndpointAttachment, data.StartAttachment
        }) do
            if object then pcall(function() object:Destroy() end) end
        end
        KillerFOV.LineObjects[char] = nil
    end

    local function destroySensor(char)
        local parts = KillerFOV.SensorObjects[char]
        if parts then
            for _, part in ipairs(parts) do
                if part then pcall(function() part:Destroy() end) end
            end
        end
        KillerFOV.SensorObjects[char] = nil
    end

    local function cleanupCharacter(char)
        destroyLine(char)
        destroySensor(char)
    end

    local function createLine(char)
        if not char or not char.Parent then return nil end
        local head = char:FindFirstChild("Head")
        if not head then return nil end

        destroyLine(char)

        local endpoint = Instance.new("Part")
        endpoint.Name = "TianHub_KillerFOV_Endpoint"
        endpoint.Anchored = true
        endpoint.CanCollide = false
        endpoint.CanTouch = false
        endpoint.CanQuery = false
        endpoint.CastShadow = false
        endpoint.Shape = Enum.PartType.Ball
        endpoint.Material = Enum.Material.Neon
        endpoint.Color = LINE_COLOR
        endpoint.Transparency = 0.04
        endpoint.Size = Vector3.new(0.26, 0.26, 0.26)
        endpoint.CFrame = CFrame.new(head.Position)
        endpoint.Parent = workspace

        local startAttachment = Instance.new("Attachment")
        startAttachment.Name = "TianHub_KillerFOV_Start"
        startAttachment.Position = Vector3.zero
        startAttachment.Parent = head

        local endpointAttachment = Instance.new("Attachment")
        endpointAttachment.Name = "TianHub_KillerFOV_End"
        endpointAttachment.Position = Vector3.zero
        endpointAttachment.Parent = endpoint

        local beam = Instance.new("Beam")
        beam.Name = "TianHub_KillerFOV_LineAlways"
        beam.Attachment0 = startAttachment
        beam.Attachment1 = endpointAttachment
        beam.FaceCamera = true
        beam.LightEmission = 1
        beam.LightInfluence = 0
        beam.Segments = 1
        beam.Width0 = 0.12
        beam.Width1 = 0.12
        beam.Transparency = NumberSequence.new(0.45)
        beam.Color = ColorSequence.new(LINE_COLOR)
        beam.Parent = endpoint

        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        rayParams.IgnoreWater = true
        local ignore = { char }
        if LocalPlayer.Character and LocalPlayer.Character ~= char then
            table.insert(ignore, LocalPlayer.Character)
        end
        rayParams.FilterDescendantsInstances = ignore

        local data = {
            Beam = beam,
            Endpoint = endpoint,
            StartAttachment = startAttachment,
            EndpointAttachment = endpointAttachment,
            RayParams = rayParams,
            LocalCharacter = LocalPlayer.Character,
            LastRaycast = 0,
            LastLength = nil,
            CurrentLength = KillerFOV.AlwaysLength,
            TargetLength = KillerFOV.AlwaysLength,
        }
        KillerFOV.LineObjects[char] = data
        return data
    end

    local function updateLine(char, dt)
        if not char or not char.Parent then
            destroyLine(char)
            return
        end

        local head = char:FindFirstChild("Head")
        local root = char:FindFirstChild("HumanoidRootPart")
        if not head or not root then
            destroyLine(char)
            return
        end

        local data = KillerFOV.LineObjects[char]
        if not data or not data.Endpoint or not data.Endpoint.Parent
            or not data.Beam or not data.Beam.Parent
            or not data.StartAttachment or not data.StartAttachment.Parent
            or not data.EndpointAttachment or not data.EndpointAttachment.Parent then
            data = createLine(char)
            if not data then return end
        end

        local look = root.CFrame.LookVector
        if look.Magnitude <= 0.001 then return end
        look = look.Unit

        local localCharacter = LocalPlayer.Character
        if data.LocalCharacter ~= localCharacter then
            data.LocalCharacter = localCharacter
            local ignore = { char }
            if localCharacter and localCharacter ~= char then
                table.insert(ignore, localCharacter)
            end
            data.RayParams.FilterDescendantsInstances = ignore
            data.LastRaycast = 0
        end

        local length = math.clamp(tonumber(KillerFOV.AlwaysLength) or 50, 10, 100)
        local targetLength = length
        local now = tick()
        if data.LastRaycast == 0 or now - data.LastRaycast >= 0.055
            or not data.LastLength or math.abs(data.LastLength - length) >= 0.05 then
            local hit = workspace:Raycast(head.Position, look * length, data.RayParams)
            if hit then
                targetLength = math.clamp(hit.Distance - data.Endpoint.Size.X * 0.5, 0.12, length)
            end
            data.LastRaycast = now
            data.LastLength = length
            data.TargetLength = targetLength
        else
            targetLength = data.TargetLength or length
        end

        local currentLength = tonumber(data.CurrentLength) or length
        if typeof(dt) == "number" and dt > 0 then
            local alpha = 1 - math.exp(-18 * math.clamp(dt, 0, 0.1))
            currentLength = currentLength + (targetLength - currentLength) * alpha
            if math.abs(targetLength - currentLength) < 0.015 then
                currentLength = targetLength
            end
        else
            currentLength = targetLength
        end
        data.CurrentLength = currentLength
        data.TargetLength = targetLength

        local color = getLineColor(char)
        data.Beam.Color = ColorSequence.new(color)
        data.Endpoint.Color = color
        data.Endpoint.CFrame = CFrame.new(head.Position + look * currentLength)
        data.StartAttachment.Position = Vector3.zero
        data.EndpointAttachment.Position = Vector3.zero
        data.Beam.Enabled = true
    end

    local function createSensorPart()
        local part = Instance.new("Part")
        part.Name = "TianHub_KillerFOV_SensorRange"
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.CastShadow = false
        part.Material = Enum.Material.Neon
        part.Color = LINE_COLOR
        part.Transparency = 0.02
        part.Size = Vector3.new(0.0825, 0.0825, 0.1)
        part.Parent = workspace
        return part
    end

    local function drawSensorSegment(part, fromPosition, toPosition)
        local delta = toPosition - fromPosition
        local length = delta.Magnitude
        if length <= 0.001 then
            part.Transparency = 1
            return
        end
        part.Transparency = 0.05
        part.Size = Vector3.new(0.0825, 0.0825, length)
        part.CFrame = CFrame.lookAt((fromPosition + toPosition) * 0.5, toPosition)
    end

    local function updateSensor(char)
        if not KillerFOV.SensorEnabled or not char or not char.Parent then
            destroySensor(char)
            return
        end

        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end

        local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
        if look.Magnitude <= 0.01 then return end
        look = look.Unit
        local right = Vector3.new(-look.Z, 0, look.X)

        local y = root.Position.Y - 3
        local halfWidth, forwardLength, curveDepth = 7.85, 11.5, 3
        local startPoint = Vector3.new(
            root.Position.X + look.X * 0.8, y,
            root.Position.Z + look.Z * 0.8
        )
        local leftEnd = Vector3.new(
            root.Position.X + look.X * forwardLength - right.X * halfWidth, y,
            root.Position.Z + look.Z * forwardLength - right.Z * halfWidth
        )
        local rightEnd = Vector3.new(
            root.Position.X + look.X * forwardLength + right.X * halfWidth, y,
            root.Position.Z + look.Z * forwardLength + right.Z * halfWidth
        )

        local parts = KillerFOV.SensorObjects[char]
        if not parts or #parts ~= 9 then
            destroySensor(char)
            parts = {}
            for i = 1, 9 do parts[i] = createSensorPart() end
            KillerFOV.SensorObjects[char] = parts
        end

        drawSensorSegment(parts[1], startPoint, leftEnd)
        drawSensorSegment(parts[2], startPoint, rightEnd)

        local curvePoints = {}
        for i = 0, 7 do
            local t = i / 7
            local sideOffset = -halfWidth + 2 * halfWidth * t
            local forwardOffset = math.sin(math.pi * t) * curveDepth
            local point = root.Position + look * (forwardLength + forwardOffset) + right * sideOffset
            curvePoints[i + 1] = Vector3.new(point.X, y, point.Z)
        end
        for i = 1, 7 do
            drawSensorSegment(parts[i + 2], curvePoints[i], curvePoints[i + 1])
        end

        for _, part in ipairs(parts) do
            part.Color = LINE_COLOR
            part.Material = Enum.Material.Neon
            part.Transparency = 0.02
        end
    end

    local function refreshKillerObjects()
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                local char = plr.Character
                if TianHub_IsKiller(plr) then
                    if KillerFOV.LineEnabled then updateLine(char) end
                    if KillerFOV.SensorEnabled then updateSensor(char) end
                else
                    cleanupCharacter(char)
                end
            end
        end
        for char in pairs(KillerFOV.LineObjects) do
            if not char or not char.Parent or not isKillerCharacter(char) or not KillerFOV.LineEnabled then
                destroyLine(char)
            end
        end
        for char in pairs(KillerFOV.SensorObjects) do
            if not char or not char.Parent or not isKillerCharacter(char) or not KillerFOV.SensorEnabled then
                destroySensor(char)
            end
        end
    end

    local function ensureLoop()
        if KillerFOV.Connection then return end
        KillerFOV.Connection = RunService.RenderStepped:Connect(function(dt)
            if not KillerFOV.LineEnabled and not KillerFOV.SensorEnabled then
                return
            end
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer and plr.Character then
                    local char = plr.Character
                    if TianHub_IsKiller(plr) then
                        if KillerFOV.LineEnabled then
                            pcall(updateLine, char, dt)
                        else
                            destroyLine(char)
                        end
                        if KillerFOV.SensorEnabled then
                            pcall(updateSensor, char)
                        else
                            destroySensor(char)
                        end
                    else
                        cleanupCharacter(char)
                    end
                end
            end
            for char in pairs(KillerFOV.LineObjects) do
                if not char or not char.Parent or not isKillerCharacter(char) or not KillerFOV.LineEnabled then
                    destroyLine(char)
                end
            end
            for char in pairs(KillerFOV.SensorObjects) do
                if not char or not char.Parent or not isKillerCharacter(char) or not KillerFOV.SensorEnabled then
                    destroySensor(char)
                end
            end
        end)
    end

    local function stopLoopIfIdle()
        if not KillerFOV.LineEnabled and not KillerFOV.SensorEnabled then
            if KillerFOV.Connection then
                KillerFOV.Connection:Disconnect()
                KillerFOV.Connection = nil
            end
            for char in pairs(KillerFOV.LineObjects) do destroyLine(char) end
            for char in pairs(KillerFOV.SensorObjects) do destroySensor(char) end
        end
    end

    local function setLineAlways(enabled)
        KillerFOV.LineEnabled = enabled == true
        if KillerFOV.LineEnabled then
            ensureLoop()
            refreshKillerObjects()
        else
            for char in pairs(KillerFOV.LineObjects) do destroyLine(char) end
            stopLoopIfIdle()
        end
    end

    local function setSensorRange(enabled)
        KillerFOV.SensorEnabled = enabled == true
        if KillerFOV.SensorEnabled then
            ensureLoop()
            refreshKillerObjects()
        else
            for char in pairs(KillerFOV.SensorObjects) do destroySensor(char) end
            stopLoopIfIdle()
        end
    end

    local function setAlwaysLength(value)
        KillerFOV.AlwaysLength = math.clamp(tonumber(value) or 50, 10, 100)
        for char, data in pairs(KillerFOV.LineObjects) do
            if data then
                data.LastRaycast = 0
                data.LastLength = nil
                data.TargetLength = KillerFOV.AlwaysLength
            end
            if char and char.Parent and KillerFOV.LineEnabled then
                pcall(updateLine, char)
            end
        end
    end

    setConn("Tian_KillerFOV_PlayerRemoving", Players.PlayerRemoving:Connect(function(plr)
        if plr.Character then cleanupCharacter(plr.Character) end
        disconnect("Tian_KillerFOV_Char_" .. tostring(plr.UserId))
    end))
    setConn("Tian_KillerFOV_PlayerAdded", Players.PlayerAdded:Connect(function(plr)
        if plr ~= LocalPlayer then
            setConn("Tian_KillerFOV_Char_" .. tostring(plr.UserId), plr.CharacterRemoving:Connect(function(char)
                cleanupCharacter(char)
            end))
        end
    end))
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            setConn("Tian_KillerFOV_Char_" .. tostring(plr.UserId), plr.CharacterRemoving:Connect(function(char)
                cleanupCharacter(char)
            end))
        end
    end

    -- Kontrol Killer FOV mengisi section yang sudah dibuat tepat di bawah Auto Parry.
    CreateToggle(KillerFOVSection, "Killer Trace", false, setLineAlways)
    CreateToggle(KillerFOVSection, "Threat Scope", false, setSensorRange)
    CreateSlider(KillerFOVSection, "Always Range", 10, 100, 50, " studs", setAlwaysLength)
end, function(e) logQuiet("[TianHub] Killer FOV error: " .. tostring(e)) end)

xpcall(function()
    -- Remove Tree & Grass: sembunyikan pohon, rumput, semak, dan dedaunan hanya di sisi lokal (bisa dikembalikan).
    local TG = {
        On = false, Saved = {}, Conn = nil, Gen = 0,
        Terrain = workspace:FindFirstChildOfClass("Terrain"), TerrainOrig = nil,
    }
    local PATTERNS = {
        "%f[%a]trees?%f[%A]", "%f[%a]grass", "%f[%a]bush", "%f[%a]shrub", "%f[%a]foliage",
        "%f[%a]leaf", "%f[%a]leaves", "%f[%a]weeds?%f[%A]", "%f[%a]fern", "%f[%a]plants?%f[%A]",
        "%f[%a]trunk", "%f[%a]branch", "%f[%a]stump", "%f[%a]pine", "%f[%a]oak", "%f[%a]birch",
        "%f[%a]spruce", "%f[%a]palm", "%f[%a]bamboo", "%f[%a]hedge", "%f[%a]vines?%f[%A]",
        "%f[%a]flowers?%f[%A]", "%f[%a]reeds?%f[%A]", "%f[%a]cypress", "%f[%a]willow",
        "%f[%a]vegetation", "%f[%a]forest", "%f[%a]twig", "%f[%a]sapling",
    }
    -- Jangan sentuh objek gameplay.
    local EXCLUDE = { "generator", "pallet", "hook", "gate", "window", "vault", "exit", "chest", "locker", "door",
        "rock", "stone", "boulder", "crate", "barrel", "box", "brick", "wall", "fence" }

    local function matches(name, list)
        local n = string.lower(name)
        for _, pat in ipairs(list) do
            if string.find(n, pat) then return true end
        end
        return false
    end

    -- Model dianggap pohon kalau namanya cocok atau ada anak (daun/batang) yang namanya cocok.
    -- Dengan begitu batang yang namanya tidak mengandung kata "tree" ikut hilang bersama daunnya.
    local modelCache = setmetatable({}, { __mode = "k" })
    local function treeModel(m)
        local c = modelCache[m]
        if c == true then return true end
        if c and os.clock() < c then return false end -- hasil "bukan pohon" disimpan 3 detik saja
        local res = false
        if matches(m.Name, PATTERNS) then
            res = true
        else
            local okSize, ext = pcall(function() return m:GetExtentsSize() end)
            if okSize and ext.Magnitude < 150 then
                local kids = m:GetChildren()
                for i = 1, math.min(#kids, 80) do
                    local kid = kids[i]
                    if matches(kid.Name, PATTERNS) or (kid:IsA("BasePart") and kid.Material == Enum.Material.LeafyGrass) then
                        res = true
                        break
                    end
                end
            end
        end
        modelCache[m] = res and true or (os.clock() + 3)
        return res
    end

    -- Cek nama objek dan induknya (maks 6 tingkat) sampai workspace.
    local function isFoliage(inst)
        local hit = false
        local cur, depth = inst, 0
        while cur and cur ~= workspace and depth < 10 do
            if cur:IsA("Model") and cur:FindFirstChildOfClass("Humanoid") then return false end
            if cur:IsA("Model") and treeModel(cur) then hit = true end
            local n = string.lower(cur.Name)
            for _, ex in ipairs(EXCLUDE) do
                if string.find(n, ex, 1, true) then return false end
            end
            if matches(cur.Name, PATTERNS) then hit = true end
            cur = cur.Parent
            depth = depth + 1
        end
        return hit
    end

    local function hide(inst)
        if TG.Saved[inst] then return end
        if inst:IsA("BasePart") and inst.Material == Enum.Material.Grass and not inst:IsA("Terrain") then
            -- Part berbahan rumput: ganti materialnya (bukan disembunyikan) supaya lantai tetap ada.
            TG.Saved[inst] = { kind = "mat", m = inst.Material }
            inst.Material = Enum.Material.Ground
            return
        end
        if inst:IsA("BasePart") then
            if not (isFoliage(inst) or inst.Material == Enum.Material.LeafyGrass) then return end
            TG.Saved[inst] = { kind = "part", t = inst.Transparency, cs = inst.CastShadow }
            inst.Transparency = 1
            inst.CastShadow = false
        elseif inst:IsA("Decal") or inst:IsA("Texture") then
            if not isFoliage(inst) then return end
            TG.Saved[inst] = { kind = "decal", t = inst.Transparency }
            inst.Transparency = 1
        elseif inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") then
            if not isFoliage(inst) then return end
            TG.Saved[inst] = { kind = "fx", e = inst.Enabled }
            inst.Enabled = false
        end
    end

    local function restoreAll()
        for inst, o in pairs(TG.Saved) do
            pcall(function()
                if o.kind == "part" then
                    inst.Transparency = o.t
                    inst.CastShadow = o.cs
                elseif o.kind == "mat" then
                    inst.Material = o.m
                elseif o.kind == "decal" then
                    inst.Transparency = o.t
                elseif o.kind == "fx" then
                    inst.Enabled = o.e
                end
            end)
        end
        TG.Saved = {}
        if TG.Terrain and TG.TerrainOrig ~= nil then
            local okSet = pcall(function() TG.Terrain.Decoration = TG.TerrainOrig end)
            if not okSet and sethiddenproperty then pcall(sethiddenproperty, TG.Terrain, "Decoration", TG.TerrainOrig) end
        end
        TG.TerrainOrig = nil
    end

    local function setOn(v)
        TG.On = v
        TG.Gen = TG.Gen + 1
        local myGen = TG.Gen
        if v then
            -- Rumput terrain bawaan Roblox
            if TG.Terrain then
                local okGet, cur = pcall(function() return TG.Terrain.Decoration end)
                if not okGet and gethiddenproperty then
                    okGet, cur = pcall(gethiddenproperty, TG.Terrain, "Decoration")
                end
                if TG.TerrainOrig == nil and okGet then TG.TerrainOrig = cur end
                local okSet = pcall(function() TG.Terrain.Decoration = false end)
                if not okSet and sethiddenproperty then pcall(sethiddenproperty, TG.Terrain, "Decoration", false) end
            end
            -- Objek baru yang muncul saat map dimuat
            if not TG.Conn then
                TG.Conn = workspace.DescendantAdded:Connect(function(inst)
                    if TG.On then pcall(hide, inst) end
                end)
            end
            -- Pindai objek yang sudah ada, bertahap supaya tidak lag.
            task.spawn(function()
                local list = workspace:GetDescendants()
                for i, inst in ipairs(list) do
                    if not TG.On or TG.Gen ~= myGen then return end
                    pcall(hide, inst)
                    if i % 150 == 0 then task.wait() end
                end
            end)
        else
            if TG.Conn then TG.Conn:Disconnect(); TG.Conn = nil end
            restoreAll()
        end
    end

    local TreeSection = CreateSection(VisualTab, "TREE & GRASS", false)
    CreateToggle(TreeSection, "Remove Tree & Grass", false, function(v) setOn(v) end)
    -- Alat bantu: arahkan layar ke pohon yang masih ada lalu tekan, info objeknya disalin ke clipboard.
    CreateButton(TreeSection, "Inspect Aimed Object", function()
        local cam = workspace.CurrentCamera
        if not cam then return end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { LocalPlayer.Character }
        local res = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 500, params)
        local inst = res and res.Instance
        if not inst then TianHub_Notify("Inspect", "Tidak ada objek di tengah layar", 3); return end
        local chain, cur = {}, inst
        for _ = 1, 6 do
            if not cur or cur == workspace then break end
            chain[#chain + 1] = cur.Name .. " (" .. cur.ClassName .. ")"
            cur = cur.Parent
        end
        local info = string.format("%s | Material=%s | Size=%.1f,%.1f,%.1f | Collide=%s | Chain: %s",
            inst.Name, tostring(inst.Material), inst.Size.X, inst.Size.Y, inst.Size.Z, tostring(inst.CanCollide),
            table.concat(chain, " < "))
        if setclipboard then pcall(setclipboard, info) end
        TianHub_Notify("Inspect", info, 8)
    end, true)
end, function(e) logQuiet("[TianHub] remove tree error: " .. tostring(e)) end)




-- Dua modul visual trajectory yang diminta telah dihapus.


xpcall(function()
    -- Camera Stretch: layar tampak melebar (efek stretched resolution) dengan menskalakan sumbu Y kamera.
    local ST = { On = false, Amount = 0.67 }
    pcall(function() RunService:UnbindFromRenderStep("Tian_CameraStretch") end)
    RunService:BindToRenderStep("Tian_CameraStretch", Enum.RenderPriority.Last.Value + 1, function()
        if not ST.On then return end
        local cam = workspace.CurrentCamera
        if not cam then return end
        cam.CFrame = cam.CFrame * CFrame.new(0, 0, 0, 1, 0, 0, 0, ST.Amount, 0, 0, 0, 1)
    end)
    local StretchSection = CreateSection(VisualTab, "CAMERA STRETCH", false)
    CreateToggle(StretchSection, "Camera Stretch", false, function(v) ST.On = v end)
    CreateSlider(StretchSection, "Stretch", 40, 100, 67, " %", function(v) ST.Amount = (tonumber(v) or 67) / 100 end)
end, function(e) logQuiet("[TianHub] camera stretch error: " .. tostring(e)) end)

xpcall(function()
    -- Streamer Mode: sembunyikan nama pemain (nama di atas kepala, leaderboard, chat, ESP, dan info akun di hub).
    local StarterGui = game:GetService("StarterGui")
    TianHubState.Streamer = false
    TianHubState.PlrName = function(p)
        if TianHubState.Streamer then return TianHub_IsKiller(p) and "Killer" or "TIANHUB" end
        return (p.DisplayName ~= "" and p.DisplayName) or p.Name
    end

    local SM = { Hum = {}, Conns = {}, Core = {}, HudConns = {}, Gen = 0 }
    local LOGO = UI.logoAsset or "rbxassetid://134541569123256"

    local function escapePat(str) return (string.gsub(str, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end

    -- Teks yang memuat nama / display name pemain diganti "TIANHUB"; gambar yang memuat UserId pemain
    -- (foto profil) diganti logo Tian. Berjalan lewat event sehingga langsung ikut saat game memperbaruinya.
    local function hookInst(inst)
        if UI.gui and inst:IsDescendantOf(UI.gui) then return end
        if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
            local function apply()
                if not TianHubState.Streamer then return end
                local text = inst.Text
                if text == "" then return end
                local new = text
                for _, pl in ipairs(Players:GetPlayers()) do
                    for _, nm in ipairs({ pl.Name, pl.DisplayName }) do
                        if #nm >= 3 and string.find(new, nm, 1, true) then
                            if inst:GetAttribute("TianOrigText") == nil then inst:SetAttribute("TianOrigText", text) end
                            new = string.gsub(new, escapePat(nm), "TIANHUB")
                        end
                    end
                end
                if new ~= text then inst.Text = new end
            end
            apply()
            SM.HudConns[#SM.HudConns + 1] = inst:GetPropertyChangedSignal("Text"):Connect(apply)
        elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
            local function apply()
                if not TianHubState.Streamer then return end
                local img = inst.Image
                if img == "" or img == LOGO then return end
                local low = string.lower(img)
                local hit = string.find(low, "headshot", 1, true) or string.find(low, "type=avatar", 1, true)
                if not hit then
                    for _, pl in ipairs(Players:GetPlayers()) do
                        if string.find(img, tostring(pl.UserId), 1, true) then hit = true; break end
                    end
                end
                if hit then
                    if inst:GetAttribute("TianOrigImage") == nil then
                        inst:SetAttribute("TianOrigImage", img)
                    end
                    inst.Image = LOGO
                    inst.ImageRectSize = Vector2.new(0, 0)
                    inst.ImageRectOffset = Vector2.new(0, 0)
                end
            end
            apply()
            SM.HudConns[#SM.HudConns + 1] = inst:GetPropertyChangedSignal("Image"):Connect(apply)
        end
    end

    local function startHud(myGen)
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not pg then return end
        SM.HudConns[#SM.HudConns + 1] = pg.DescendantAdded:Connect(function(inst)
            task.defer(function() if TianHubState.Streamer then pcall(hookInst, inst) end end)
        end)
        local list = pg:GetDescendants()
        for i, inst in ipairs(list) do
            if not TianHubState.Streamer or SM.Gen ~= myGen then return end
            pcall(hookInst, inst)
            if i % 200 == 0 then task.wait() end
        end
    end

    local function stopHud()
        for _, c in ipairs(SM.HudConns) do pcall(function() c:Disconnect() end) end
        SM.HudConns = {}
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not pg then return end
        for _, inst in ipairs(pg:GetDescendants()) do
            pcall(function()
                local ot = inst:GetAttribute("TianOrigText")
                if ot ~= nil then inst.Text = ot; inst:SetAttribute("TianOrigText", nil) end
                local oi = inst:GetAttribute("TianOrigImage")
                if oi ~= nil then inst.Image = oi; inst:SetAttribute("TianOrigImage", nil) end
            end)
        end
    end

    local CORE = { Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Chat }

    local function hideOverhead(char)
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        if SM.Hum[hum] == nil then SM.Hum[hum] = hum.DisplayDistanceType end
        hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    end
    local function hookPlayer(plr)
        if plr.Character then pcall(hideOverhead, plr.Character) end
        SM.Conns[#SM.Conns + 1] = plr.CharacterAdded:Connect(function(c)
            task.wait(0.3)
            if TianHubState.Streamer then pcall(hideOverhead, c) end
        end)
    end

    local function setOn(v)
        TianHubState.Streamer = v
        SM.Gen = SM.Gen + 1
        if v then
            task.spawn(startHud, SM.Gen)
            for _, t in ipairs(CORE) do
                local ok, cur = pcall(function() return StarterGui:GetCoreGuiEnabled(t) end)
                if ok and SM.Core[t] == nil then SM.Core[t] = cur end
                pcall(function() StarterGui:SetCoreGuiEnabled(t, false) end)
            end
            for _, plr in ipairs(Players:GetPlayers()) do hookPlayer(plr) end
            SM.Conns[#SM.Conns + 1] = Players.PlayerAdded:Connect(hookPlayer)
        else
            for _, c in ipairs(SM.Conns) do pcall(function() c:Disconnect() end) end
            SM.Conns = {}
            for hum, orig in pairs(SM.Hum) do pcall(function() hum.DisplayDistanceType = orig end) end
            SM.Hum = {}
            for t, orig in pairs(SM.Core) do pcall(function() StarterGui:SetCoreGuiEnabled(t, orig) end) end
            SM.Core = {}
            stopHud()
        end
        if UI.setStreamer then pcall(UI.setStreamer, v) end
    end

    local StreamSection = CreateSection(VisualTab, "STREAMER MODE", false)
    CreateToggle(StreamSection, "Streamer Mode", false, function(v) setOn(v) end)
end, function(e) logQuiet("[TianHub] streamer mode error: " .. tostring(e)) end)


local VisualLighting = CreateSection(VisualTab, "LIGHTING", false)
-- Remove stale post-processing instances left by older TianHub RTX/Graphics builds.
for _, oldEffectName in ipairs({
    "TianHub_RTX_Color", "TianHub_RTX_Bloom", "TianHub_RTX_SunRays", "TianHub_RTX_Atmosphere",
    "TianHub_GraphicsColor", "TianHub_GraphicsBloom", "TianHub_GraphicsSunRays", "TianHub_GraphicsSoftFocus",
}) do
    local oldEffect = Lighting:FindFirstChild(oldEffectName)
    if oldEffect then pcall(function() oldEffect:Destroy() end) end
end
local TianHub_Visual = { Fullbright = false, NoFog = false,
    WhiteAmbient = false, AmbientColor = Color3.fromRGB(255, 255, 255), Brightness = 2, Exposure = 0 }
CreateSlider(VisualLighting, "Fullbright Brightness", 0, 10, 2, "", function(value)
    TianHub_Visual.Brightness = math.clamp(tonumber(value) or 2, 0, 10)
end, 1)
local originalLighting = {
    Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime,
    FogStart = Lighting.FogStart, FogEnd = Lighting.FogEnd,
    GlobalShadows = Lighting.GlobalShadows,
    OutdoorAmbient = Lighting.OutdoorAmbient, Ambient = Lighting.Ambient,
    ExposureCompensation = Lighting.ExposureCompensation,
    ColorShift_Top = Lighting.ColorShift_Top, ColorShift_Bottom = Lighting.ColorShift_Bottom,
    FogColor = Lighting.FogColor,
    EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
    EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
}

CreateToggle(VisualLighting, "Fullbright", false, function(state) TianHub_Visual.Fullbright = state end)

-- POTATO MODE: client-side map optimization with reversible property snapshots.
do
    local potatoEnabled = false
    local potatoOriginals = setmetatable({}, { __mode = "k" })
    local potatoConnections = {}
    local potatoGeneration = 0
    local terrainOriginals = nil

    local function potatoSaveAndSet(instance, property, value)
        local saved = potatoOriginals[instance]
        if not saved then
            saved = {}
            potatoOriginals[instance] = saved
        end
        if saved[property] == nil then
            local ok, original = pcall(function() return instance[property] end)
            if not ok then return end
            saved[property] = original
        end
        pcall(function() instance[property] = value end)
    end

    local function potatoIsCharacterPart(instance)
        local ancestor = instance
        while ancestor and ancestor ~= workspace do
            if ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") then
                return true
            end
            ancestor = ancestor.Parent
        end
        return false
    end

    local function potatoApply(instance)
        if not potatoEnabled or not instance then return end
        if potatoIsCharacterPart(instance) then return end

        -- Reduce expensive map materials, reflections, shadows and texture rendering.
        if instance:IsA("BasePart") then
            potatoSaveAndSet(instance, "Material", Enum.Material.Plastic)
            potatoSaveAndSet(instance, "Reflectance", 0)
            potatoSaveAndSet(instance, "CastShadow", false)
            if instance:IsA("MeshPart") then
                potatoSaveAndSet(instance, "TextureID", "")
            end
        elseif instance:IsA("Decal") or instance:IsA("Texture") then
            potatoSaveAndSet(instance, "Transparency", 1)
        elseif instance:IsA("SpecialMesh") then
            potatoSaveAndSet(instance, "TextureId", "")
        elseif instance:IsA("SurfaceAppearance") then
            potatoSaveAndSet(instance, "ColorMap", "")
            potatoSaveAndSet(instance, "MetalnessMap", "")
            potatoSaveAndSet(instance, "NormalMap", "")
            potatoSaveAndSet(instance, "RoughnessMap", "")
        elseif instance:IsA("ParticleEmitter") or instance:IsA("Trail") or instance:IsA("Beam")
            or instance:IsA("Fire") or instance:IsA("Smoke") or instance:IsA("Sparkles")
            or instance:IsA("Highlight") then
            potatoSaveAndSet(instance, "Enabled", false)
        elseif instance:IsA("PointLight") or instance:IsA("SpotLight") or instance:IsA("SurfaceLight") then
            potatoSaveAndSet(instance, "Shadows", false)
        elseif instance:IsA("PostEffect") then
            potatoSaveAndSet(instance, "Enabled", false)
        elseif instance:IsA("Atmosphere") then
            potatoSaveAndSet(instance, "Density", 0)
            potatoSaveAndSet(instance, "Haze", 0)
            potatoSaveAndSet(instance, "Glare", 0)
        elseif instance:IsA("Clouds") then
            potatoSaveAndSet(instance, "Cover", 0)
            potatoSaveAndSet(instance, "Density", 0)
        end
    end

    local function potatoDisconnectListeners()
        for _, connection in ipairs(potatoConnections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(potatoConnections)
    end

    local function potatoRestore()
        potatoDisconnectListeners()
        -- Restore even if an instance is temporarily unparented; property writes are protected.
        for instance, properties in pairs(potatoOriginals) do
            for property, original in pairs(properties) do
                pcall(function() instance[property] = original end)
            end
            potatoOriginals[instance] = nil
        end
        if terrainOriginals then
            local terrain = terrainOriginals.Instance
            if terrain then
                pcall(function() terrain.Decoration = terrainOriginals.Decoration end)
                pcall(function() terrain.WaterWaveSize = terrainOriginals.WaterWaveSize end)
                pcall(function() terrain.WaterWaveSpeed = terrainOriginals.WaterWaveSpeed end)
            end
            terrainOriginals = nil
        end
    end

    local function potatoScan(container, generation)
        task.spawn(function()
            local descendants = container:GetDescendants()
            for index, instance in ipairs(descendants) do
                if not potatoEnabled or generation ~= potatoGeneration then return end
                potatoApply(instance)
                -- Spread work over frames to avoid a large one-frame hitch on big maps.
                if index % 220 == 0 then task.wait() end
            end
        end)
    end

    local function setPotatoMode(enabled)
        enabled = enabled == true
        if potatoEnabled == enabled then return end
        potatoEnabled = enabled
        potatoGeneration = potatoGeneration + 1
        local generation = potatoGeneration

        -- Always clear old listeners before starting another pass (including repeated ON).
        potatoDisconnectListeners()
        if not potatoEnabled then
            potatoRestore()
            return
        end

        local terrain = workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            local okDecoration, decoration = pcall(function() return terrain.Decoration end)
            local okWaveSize, waveSize = pcall(function() return terrain.WaterWaveSize end)
            local okWaveSpeed, waveSpeed = pcall(function() return terrain.WaterWaveSpeed end)
            terrainOriginals = {
                Instance = terrain,
                Decoration = okDecoration and decoration or nil,
                WaterWaveSize = okWaveSize and waveSize or nil,
                WaterWaveSpeed = okWaveSpeed and waveSpeed or nil,
            }
            pcall(function() terrain.Decoration = false end)
            pcall(function() terrain.WaterWaveSize = 0 end)
            pcall(function() terrain.WaterWaveSpeed = 0 end)
        end

        -- Watch both world and Lighting so streamed-in/newly-created map content is optimized too.
        table.insert(potatoConnections, workspace.DescendantAdded:Connect(function(instance)
            if potatoEnabled then task.defer(potatoApply, instance) end
        end))
        table.insert(potatoConnections, Lighting.DescendantAdded:Connect(function(instance)
            if potatoEnabled then task.defer(potatoApply, instance) end
        end))

        potatoScan(workspace, generation)
        potatoScan(Lighting, generation)
    end

    CreateToggle(VisualLighting, "Potato Mode", false, setPotatoMode)
end

local cleanSkyPrevious = nil
CreateToggle(VisualLighting, "Clean Sky", false, function(state)
    if state then
        cleanSkyPrevious = {
            Fullbright = TianHub_Visual.Fullbright,
            NoFog = TianHub_Visual.NoFog,
        }
        TianHub_Visual.Fullbright = true
        TianHub_Visual.NoFog = true
    else
        if cleanSkyPrevious then
            TianHub_Visual.Fullbright = cleanSkyPrevious.Fullbright
            TianHub_Visual.NoFog = cleanSkyPrevious.NoFog
            cleanSkyPrevious = nil
        else
            TianHub_Visual.Fullbright = false
            TianHub_Visual.NoFog = false
        end
    end
end)
CreateToggle(VisualLighting, "No Fog", false, function(state) TianHub_Visual.NoFog = state end)
do
local TianHub_VisOrig = setmetatable({}, { __mode = "k" })
local TianHub_VisSig = ""
local function TianHub_VisSaveEffect(v)
    if TianHub_VisOrig[v] then return end
    local o = {}
    if v:IsA("Atmosphere") then
        o = { Density = v.Density, Offset = v.Offset, Glare = v.Glare, Haze = v.Haze }
    elseif v:IsA("BlurEffect") then
        o = { Size = v.Size, Enabled = v.Enabled }
    elseif v:IsA("ColorCorrectionEffect") or v:IsA("SunRaysEffect") or v:IsA("BloomEffect") then
        o = { Enabled = v.Enabled }
    elseif v:IsA("Clouds") then
        o = { Cover = v.Cover, Density = v.Density, Color = v.Color }
    end
    TianHub_VisOrig[v] = o
end
local function TianHub_VisRestore()
    for k, v in pairs(originalLighting) do pcall(function() Lighting[k] = v end) end
    for obj, o in pairs(TianHub_VisOrig) do
        if obj.Parent then
            pcall(function() for k, v in pairs(o) do obj[k] = v end end)
        end
    end
end
local visScan = 0

setConn("TianHub_VisualLoop", RunService.Heartbeat:Connect(function()
    local active = TianHub_Visual.Fullbright or TianHub_Visual.NoFog
    local sig = (TianHub_Visual.Fullbright and "F" or "-") .. (TianHub_Visual.NoFog and "G" or "-")
    if sig ~= TianHub_VisSig then
        TianHub_VisSig = sig
        TianHub_VisRestore()
    end
    if not active then return end

    if TianHub_Visual.Fullbright then
        Lighting.Brightness = math.clamp(tonumber(TianHub_Visual.Brightness) or 2, 0, 10)
        Lighting.ClockTime = 14
        Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
        Lighting.Ambient = Color3.fromRGB(128, 128, 128)
    end
    if TianHub_Visual.NoFog or TianHub_Visual.Fullbright then
        Lighting.FogStart = 0; Lighting.FogEnd = 100000
    end
    -- Pemindaian efek cukup 4x per detik (hemat FPS).
    local nowV = os.clock()
    if nowV - visScan < 0.25 then return end
    visScan = nowV

    for _, v in ipairs(Lighting:GetChildren()) do
        if v:IsA("Atmosphere") or v:IsA("BlurEffect") or v:IsA("ColorCorrectionEffect")
            or v:IsA("SunRaysEffect") or v:IsA("BloomEffect") then
            TianHub_VisSaveEffect(v)
            if TianHub_Visual.Fullbright then
                if v:IsA("Atmosphere") then
                    v.Density = 0; v.Offset = 0; v.Glare = 0; v.Haze = 0
                elseif v:IsA("BlurEffect") then v.Size = 0
                elseif v:IsA("ColorCorrectionEffect") or v:IsA("SunRaysEffect") then v.Enabled = false end
            end
            if TianHub_Visual.NoFog and v:IsA("Atmosphere") then v.Density = 0 end
        end
    end

    -- Clouds live under Workspace.Terrain, not Lighting.
    local terrain = workspace:FindFirstChildOfClass("Terrain")
    if terrain then
        for _, cloud in ipairs(terrain:GetChildren()) do
            if cloud:IsA("Clouds") then
                TianHub_VisSaveEffect(cloud)
                if TianHub_Visual.Fullbright then
                    cloud.Cover = 0
                    cloud.Density = 0
                end
            end
        end
    end
end))
end

-- ULTRA VISUAL BOOST: one lightweight camera-local ColorCorrectionEffect.
xpcall(function()
    local visual_state = {
        Enabled = false,
        Brightness = 0.04,
        Contrast = 0.25,
        Saturation = 0.30,
    }

    local visual_effect

    local function remove_visual_effect()
        if visual_effect then
            visual_effect:Destroy()
            visual_effect = nil
        end
    end

    local function apply_visual_values()
        if not visual_state.Enabled then
            remove_visual_effect()
            return
        end

        local camera = workspace.CurrentCamera
        if not camera then return end

        if not visual_effect or not visual_effect.Parent then
            visual_effect = Instance.new("ColorCorrectionEffect")
            visual_effect.Name = "TianHub_UltraVisualBoost"
            visual_effect.Parent = camera
        elseif visual_effect.Parent ~= camera then
            visual_effect.Parent = camera
        end

        visual_effect.Brightness = visual_state.Brightness
        visual_effect.Contrast = visual_state.Contrast
        visual_effect.Saturation = visual_state.Saturation
        visual_effect.Enabled = true
    end

    local old_lighting_effect = Lighting:FindFirstChild("TianHub_UltraVisualBoost")
    if old_lighting_effect then old_lighting_effect:Destroy() end

    local camera = workspace.CurrentCamera
    if camera then
        local old_camera_effect = camera:FindFirstChild("TianHub_UltraVisualBoost")
        if old_camera_effect then old_camera_effect:Destroy() end
    end

    workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        if visual_state.Enabled then
            apply_visual_values()
        end
    end)

    local ContrastSection = CreateSection(VisualTab, "CONTRAST", false)

    CreateToggle(ContrastSection, "Enable Contrast", false, function(enabled)
        visual_state.Enabled = enabled
        apply_visual_values()
    end)

    CreateSlider(ContrastSection, "Contrast", 0, 60, 25, "%", function(value)
        visual_state.Contrast = (tonumber(value) or 25) / 100
        apply_visual_values()
    end)

    CreateSlider(ContrastSection, "Saturation", 0, 80, 30, "%", function(value)
        visual_state.Saturation = (tonumber(value) or 30) / 100
        apply_visual_values()
    end)

    CreateSlider(ContrastSection, "Brightness", -20, 20, 4, "%", function(value)
        visual_state.Brightness = (tonumber(value) or 4) / 100
        apply_visual_values()
    end)

    CreateButton(ContrastSection, "Reset Visual Values", function()
        visual_state.Brightness = 0.04
        visual_state.Contrast = 0.25
        visual_state.Saturation = 0.30
        apply_visual_values()
    end, true)
end, function(error_message)
    logQuiet("[TianHub] contrast error: " .. tostring(error_message))
end)

xpcall(function()
    local function guiParent()
        local parent = CoreGui
        if gethui then
            local ok, hui = pcall(gethui)
            if ok and hui then parent = hui end
        end
        return parent
    end

    for _, name in ipairs({ "TianMapPredict", "TianNextKiller", "TianKillerPerks", "MapPredictUI", "NextKillerIndicator" }) do
        local old = guiParent():FindFirstChild(name)
        if old then pcall(function() old:Destroy() end) end
    end

    local function makePlainText(guiName, posY, initial)
        local gui = Instance.new("ScreenGui")
        gui.Name = guiName
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 50
        gui.Parent = guiParent()

        -- One independent compact card per prediction; existing toggles remain separate.
        local card = Instance.new("Frame")
        card.Name = "PredictionCard"
        card.AnchorPoint = Vector2.new(0.5, 0)
        card.Position = UDim2.new(0.5, 0, 0, posY)
        card.Size = UDim2.new(0, 170, 0, 30)
        card.BackgroundColor3 = Color3.fromRGB(12, 9, 18)
        card.BackgroundTransparency = 0.18
        card.BorderSizePixel = 0
        card.Active = false
        card.Parent = gui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 7)
        corner.Parent = card

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(151, 75, 220)
        stroke.Thickness = 1
        stroke.Transparency = 0.18
        stroke.Parent = card

        local label = Instance.new("TextLabel")
        label.Name = "PredictionText"
        label.BackgroundTransparency = 1
        label.Position = UDim2.new(0, 6, 0, 0)
        label.Size = UDim2.new(1, -12, 1, 0)
        label.Active = false
        label.Text = initial
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextStrokeTransparency = 1
        label.Font = Enum.Font.GothamBold
        label.TextSize = 12
        label.TextScaled = false
        label.TextWrapped = false
        label.TextTruncate = Enum.TextTruncate.AtEnd
        label.TextXAlignment = Enum.TextXAlignment.Center
        label.Parent = card
        return gui, label
    end

    -- Anonimus Next Map Prediction: detect map from Workspace.Map and show draggable status GUI.
    local Workspace = game:GetService("Workspace")
    local MapState = {
        Gui = nil,
        Thread = nil,
        Enabled = false,
        InputConnections = {},
    }

    local function detectAnonimusMapName(map)
        if not map then return nil end
        if map:FindFirstChild("random shakes") or map:FindFirstChild("SCP-173 Room") or map:FindFirstChild("SCP-205 Room") then
            return "Site 68"
        elseif map:FindFirstChild("HooksMeat") then
            return "BLOODBATH! Club"
        elseif map:FindFirstChild("Gate") and map.Gate:FindFirstChild("vfx") then
            return "Firelink Shrine"
        elseif map:FindFirstChild("Bldg_Addon_RooftopUnit_A") or map:FindFirstChild("Rooftop") then
            return "Mercy Hospital Rooftop"
        elseif map:FindFirstChild("White Armored Car") then
            return "Mount Massive Asylum"
        elseif map:FindFirstChild("Dumbster") then
            return "The Bay Harbor"
        elseif map:FindFirstChild("water pump") then
            return "Valdelobos Village"
        elseif map:FindFirstChild("LargeBoulder01") then
            return "Woodview Cabin"
        end
        return nil
    end

    local function clearMapPredict()
        if MapState.Thread then
            pcall(function() task.cancel(MapState.Thread) end)
            MapState.Thread = nil
        end
        for _, connection in ipairs(MapState.InputConnections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(MapState.InputConnections)
        if MapState.Gui then
            pcall(function() MapState.Gui:Destroy() end)
            MapState.Gui = nil
        end
    end

    local function stopMapPredict()
        MapState.Enabled = false
        clearMapPredict()
    end

    local function buildAnonimusMapGui()
        if MapState.Gui then pcall(function() MapState.Gui:Destroy() end) end

        local parent = guiParent()
        if not parent then return nil end

        local gui = Instance.new("ScreenGui")
        gui.Name = "TianMapPredict"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 50
        gui.Parent = parent

        local frame = Instance.new("Frame")
        frame.Name = "MainFrame"
        frame.AnchorPoint = Vector2.new(0.5, 0)
        frame.Size = UDim2.new(0, 170, 0, 42)
        frame.Position = UDim2.new(0.5, -89, 0, 110)
        frame.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
        frame.BackgroundTransparency = 0.2
        frame.BorderSizePixel = 0
        frame.Active = true
        frame.Parent = gui
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)

        local stroke = Instance.new("UIStroke", frame)
        stroke.Color = Color3.fromRGB(115, 155, 220)
        stroke.Thickness = 1
        stroke.Transparency = 0.35

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, -10, 0, 11)
        title.Position = UDim2.new(0, 5, 0, 3)
        title.BackgroundTransparency = 1
        title.Text = "NEXT MAP"
        title.TextColor3 = Color3.fromRGB(175, 195, 225)
        title.Font = Enum.Font.GothamMedium
        title.TextSize = 9
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Parent = frame

        local mapName = Instance.new("TextLabel")
        mapName.Name = "MapName"
        mapName.Size = UDim2.new(1, -10, 0, 14)
        mapName.Position = UDim2.new(0, 5, 0, 14)
        mapName.BackgroundTransparency = 1
        mapName.Text = "Scanning..."
        mapName.TextColor3 = Color3.fromRGB(255, 255, 255)
        mapName.Font = Enum.Font.GothamBold
        mapName.TextSize = 11
        mapName.TextXAlignment = Enum.TextXAlignment.Left
        mapName.TextTruncate = Enum.TextTruncate.AtEnd
        mapName.Parent = frame

        local status = Instance.new("TextLabel")
        status.Name = "StatusLabel"
        status.Size = UDim2.new(1, -10, 0, 10)
        status.Position = UDim2.new(0, 5, 0, 29)
        status.BackgroundTransparency = 1
        status.Text = "Waiting"
        status.TextColor3 = Color3.fromRGB(155, 155, 165)
        status.Font = Enum.Font.Gotham
        status.TextSize = 8
        status.TextXAlignment = Enum.TextXAlignment.Left
        status.Parent = frame

        local dragging, dragStart, startPos = false, nil, nil
        table.insert(MapState.InputConnections, frame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = frame.Position
            end
        end))
        table.insert(MapState.InputConnections, UserInputService.InputChanged:Connect(function(input)
            if not dragging then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                local delta = input.Position - dragStart
                frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end))
        table.insert(MapState.InputConnections, UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end))

        MapState.Gui = gui
        return gui
    end

    local function startMapPredict()
        if MapState.Enabled then return end
        MapState.Enabled = true
        local gui = buildAnonimusMapGui()
        if not gui then
            MapState.Enabled = false
            logQuiet("[TianHub] Gagal membuat GUI Next Map Prediction")
            return
        end

        MapState.Thread = task.spawn(function()
            local lastDetected, lastExisted = nil, false
            while MapState.Enabled and MapState.Gui == gui do
                local map = Workspace:FindFirstChild("Map")
                local mapExists = map ~= nil
                local detected = mapExists and detectAnonimusMapName(map) or nil
                local frame = gui:FindFirstChild("MainFrame")
                local nameLabel = frame and frame:FindFirstChild("MapName")
                local statusLabel = frame and frame:FindFirstChild("StatusLabel")

                if nameLabel and statusLabel then
                    if lastExisted and not mapExists then
                        nameLabel.Text = lastDetected or "Unknown"
                        statusLabel.Text = "Status: Loading next map..."
                        statusLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
                    elseif mapExists then
                        lastDetected = detected or "Unknown"
                        nameLabel.Text = detected or "Unknown"
                        statusLabel.Text = "Status: In-Game"
                        statusLabel.TextColor3 = Color3.fromRGB(120, 255, 120)
                    else
                        nameLabel.Text = "Waiting..."
                        statusLabel.Text = "Status: Lobby"
                        statusLabel.TextColor3 = Color3.fromRGB(150, 150, 160)
                    end
                end

                lastExisted = mapExists
                task.wait(0.5)
            end
        end)
    end

    local function setMapPredictEnabled(value)
        if value then
            startMapPredict()
        else
            stopMapPredict()
        end
    end

    -- VDT Next Killer Display: prefer eligible players, then highest KillerChance.
    local KillerNextState = { Gui = nil, Thread = nil, Enabled = false, InputConnections = {} }

    local function stopNextKiller()
        KillerNextState.Enabled = false
        if KillerNextState.Thread then
            pcall(function() task.cancel(KillerNextState.Thread) end)
            KillerNextState.Thread = nil
        end
        for _, connection in ipairs(KillerNextState.InputConnections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(KillerNextState.InputConnections)
        if KillerNextState.Gui then
            pcall(function() KillerNextState.Gui:Destroy() end)
            KillerNextState.Gui = nil
        end
    end

    local function startNextKiller()
        if KillerNextState.Enabled then return end
        KillerNextState.Enabled = true

        local screen = Instance.new("ScreenGui")
        screen.Name = "TianNextKiller"
        screen.ResetOnSpawn = false
        screen.IgnoreGuiInset = true
        screen.DisplayOrder = 50
        screen.Enabled = false
        screen.Parent = guiParent()
        KillerNextState.Gui = screen

        local card = Instance.new("Frame")
        card.Name = "NextKillerBox"
        card.AnchorPoint = Vector2.new(0.5, 0)
        card.Position = UDim2.new(0.5, 89, 0, 110)
        card.Size = UDim2.new(0, 170, 0, 42)
        card.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
        card.BackgroundTransparency = 0.2
        card.BorderSizePixel = 0
        card.Active = true
        card.Parent = screen
        Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(115, 155, 220)
        stroke.Thickness = 1
        stroke.Transparency = 0.35
        stroke.Parent = card

        local title = Instance.new("TextLabel")
        title.Name = "Title"
        title.BackgroundTransparency = 1
        title.Position = UDim2.new(0, 5, 0, 3)
        title.Size = UDim2.new(1, -10, 0, 11)
        title.Font = Enum.Font.GothamMedium
        title.TextSize = 9
        title.TextColor3 = Color3.fromRGB(175, 195, 225)
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Text = "NEXT KILLER"
        title.Parent = card

        local label = Instance.new("TextLabel")
        label.Name = "NextKillerDisplay"
        label.BackgroundTransparency = 1
        label.Position = UDim2.new(0, 5, 0, 15)
        label.Size = UDim2.new(1, -10, 0, 23)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 10
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.TextTruncate = Enum.TextTruncate.AtEnd
        label.RichText = false
        label.Text = "Waiting..."
        label.Parent = card

        local dragging, dragStart, startPos = false, nil, nil
        table.insert(KillerNextState.InputConnections, card.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = card.Position
            end
        end))
        table.insert(KillerNextState.InputConnections, UserInputService.InputChanged:Connect(function(input)
            if not dragging then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                local delta = input.Position - dragStart
                card.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end))
        table.insert(KillerNextState.InputConnections, UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end))

        KillerNextState.Thread = task.spawn(function()
            while KillerNextState.Enabled and KillerNextState.Gui == screen do
                local isSpectator = LocalPlayer.Team and LocalPlayer.Team.Name == "Spectator"
                screen.Enabled = isSpectator and true or false

                if isSpectator then
                    local bestChance = -1
                    local nextPlayer = nil

                    for _, player in ipairs(Players:GetPlayers()) do
                        local allowKiller = player:GetAttribute("AllowKiller")
                        local killerChance = player:GetAttribute("KillerChance")

                        if allowKiller == true and type(killerChance) == "number"
                            and killerChance > bestChance then
                            bestChance = killerChance
                            nextPlayer = player
                        end
                    end

                    if not nextPlayer then
                        bestChance = -1
                        for _, player in ipairs(Players:GetPlayers()) do
                            local killerChance = player:GetAttribute("KillerChance")
                            if type(killerChance) == "number" and killerChance > bestChance then
                                bestChance = killerChance
                                nextPlayer = player
                            end
                        end
                    end

                    if nextPlayer then
                        local selectedKiller = nextPlayer:FindFirstChild("SelectedKiller")
                        local killerName = selectedKiller and selectedKiller.Value
                            or nextPlayer:GetAttribute("SelectedKiller")
                            or "Unknown"
                        label.Text = string.format(
                            "Killer: %s (%s)",
                            nextPlayer.Name,
                            tostring(killerName)
                        )
                    else
                        label.Text = "Killer: Tidak ada data"
                    end
                end

                task.wait(1)
            end
        end)
    end

    local SpectatorState = { Enabled = false, Gui = nil, Label = nil, Thread = nil }

    local function createSpectatorCounter()
        if SpectatorState.Gui then
            SpectatorState.Gui:Destroy()
            SpectatorState.Gui = nil
        end

        local screen = Instance.new("ScreenGui")
        screen.Name = "SpectatorCounter"
        screen.ResetOnSpawn = false
        screen.Parent = LocalPlayer:WaitForChild("PlayerGui")
        SpectatorState.Gui = screen

        local frame = Instance.new("Frame")
        frame.Name = "MainBox"
        frame.AnchorPoint = Vector2.new(0.5, 0)
        frame.Position = UDim2.new(0.5, 0, 0, 38)
        frame.Size = UDim2.new(0, 68, 0, 22)
        frame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
        frame.BackgroundTransparency = 0.25
        frame.BorderSizePixel = 0
        frame.Parent = screen
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

        local gradient = Instance.new("UIGradient")
        gradient.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.3, 0.4),
            NumberSequenceKeypoint.new(1, 1),
        })
        gradient.Parent = frame

        local layout = Instance.new("UIListLayout")
        layout.FillDirection = Enum.FillDirection.Horizontal
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        layout.VerticalAlignment = Enum.VerticalAlignment.Center
        layout.Padding = UDim.new(0, 6)
        layout.Parent = frame

        local icon = Instance.new("ImageLabel")
        icon.Size = UDim2.new(0, 15, 0, 15)
        icon.BackgroundTransparency = 1
        icon.Image = "rbxassetid://13321848320"
        icon.ImageColor3 = Color3.fromRGB(180, 180, 255)
        icon.Parent = frame

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamMedium
        label.Text = "0"
        label.TextColor3 = Color3.fromRGB(240, 240, 240)
        label.TextSize = 13
        label.AutomaticSize = Enum.AutomaticSize.X
        label.Parent = frame
        SpectatorState.Label = label
    end

    local function updateSpectatorCount()
        if not SpectatorState.Enabled or not SpectatorState.Label then return end
        local count = 0
        for _, player in ipairs(Players:GetPlayers()) do
            if player.Team and player.Team.Name == "Spectator" then
                count = count + 1
            end
        end
        SpectatorState.Label.Text = tostring(count)
        local frame = SpectatorState.Gui and SpectatorState.Gui:FindFirstChild("MainBox")
        if frame then
            frame.Size = UDim2.new(0, 55 + (count >= 10 and 8 or 0) + (count >= 100 and 8 or 0), 0, 22)
        end
    end

    local function stopSpectatorCounter()
        SpectatorState.Enabled = false
        if SpectatorState.Thread then
            pcall(function() task.cancel(SpectatorState.Thread) end)
            SpectatorState.Thread = nil
        end
        if SpectatorState.Gui then
            SpectatorState.Gui:Destroy()
            SpectatorState.Gui = nil
        end
        SpectatorState.Label = nil
    end

    local function startSpectatorCounter()
        if SpectatorState.Enabled then return end
        SpectatorState.Enabled = true
        createSpectatorCounter()
        updateSpectatorCount()
        SpectatorState.Thread = task.spawn(function()
            while SpectatorState.Enabled do
                updateSpectatorCount()
                task.wait(1.5)
            end
        end)
    end

    local PerkState = { Gui = nil, Thread = nil, Enabled = false, Minimized = false, Conns = {} }

    local PerkNames = {
        KystInLine = "Kyst in Line", ["Kyst in Line"] = "Kyst in Line",
        EchoLocation = "Echo Location", ["Echo Location"] = "Echo Location",
        KingsScourge = "King's Scourge", KingScourge = "King's Scourge", ["King's Scourge"] = "King's Scourge",
    }

    local function formatPerkName(name)
        name = tostring(name or "")
        if PerkNames[name] then return PerkNames[name] end
        local clean = name:gsub("_", " "):gsub("-", " ")
        clean = clean:gsub("(%l)(%u)", "%1 %2")
        clean = clean:gsub("(%a)(%d)", "%1 %2")
        clean = clean:gsub("(%d)(%a)", "%1 %2")
        clean = clean:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        return clean ~= "" and clean or "Unknown Perk"
    end

    local excludedNames = {
        head = true, torso = true, humanoid = true, humanoidrootpart = true,
        ["left arm"] = true, ["right arm"] = true, ["left leg"] = true, ["right leg"] = true,
    }

    local function parsePerkName(name)
        local perkName, level = tostring(name or ""):match("^(.+)%s+(%d+)$")
        if not perkName then return nil end
        perkName = perkName:gsub("^%s+", ""):gsub("%s+$", "")
        if perkName == "" or excludedNames[perkName:lower()] then return nil end
        return perkName, level
    end

    local function isPerkContainer(inst)
        local n = inst.Name:lower()
        return n == "perks" or n == "killerperks" or n == "equippedperks" or n == "equippedkillerperks"
            or n:find("perkfolder") ~= nil or n:find("perklist") ~= nil
    end

    local function readPerks(plr)
        if not plr then return {} end
        local char = plr.Character or workspace:FindFirstChild(plr.Name) or workspace:FindFirstChild(plr.DisplayName)
        if not char then return {} end
        local result, seen = {}, {}
        local function addPerk(rawName, displayName, level)
            if not rawName then return end
            rawName = tostring(rawName)
            if rawName == "" or rawName == "nil" or rawName:lower():find("template") then return end
            if seen[rawName] then return end
            seen[rawName] = true
            result[#result + 1] = {
                Name = displayName and tostring(displayName) or formatPerkName(rawName),
                Level = level and tostring(level) or nil,
            }
        end
        local function scanAttrs(inst)
            for k, v in pairs(inst:GetAttributes()) do
                local lk = tostring(k):lower()
                if lk:find("perk") then
                    if type(v) == "string" then addPerk(v)
                    elseif v == true then addPerk(k)
                    elseif type(v) == "number" and lk:find("level") then
                        local bn = tostring(k):gsub("[Ll]evel", ""):gsub("[Pp]erk", "")
                        if bn ~= "" then addPerk(bn, nil, v) end
                    end
                end
            end
        end
        local function readValue(inst)
            if inst:IsA("StringValue") then return inst.Value end
            if inst:IsA("IntValue") or inst:IsA("NumberValue") then return inst.Name, inst.Value end
            if inst:IsA("BoolValue") and inst.Value == true then return inst.Name end
            return nil
        end
        scanAttrs(char)
        for _, child in ipairs(char:GetChildren()) do
            local pn, lv = parsePerkName(child.Name)
            if pn then addPerk(child.Name, pn, lv) end
        end
        for _, inst in ipairs(char:GetDescendants()) do
            scanAttrs(inst)
            if isPerkContainer(inst) then
                for _, child in ipairs(inst:GetChildren()) do
                    local value, level = readValue(child)
                    addPerk(value or child.Name, nil, level)
                end
            elseif inst.Name:lower():find("perk") then
                local value, level = readValue(inst)
                addPerk(value or inst.Name, nil, level)
            end
        end
        table.sort(result, function(x, y) return x.Name < y.Name end)
        return result
    end

    local function getKillerPlayer()
        for _, p in ipairs(Players:GetPlayers()) do
            local tn = p.Team and p.Team.Name
            if tn and tn:lower():find("killer") then return p end
        end
        return nil
    end

    local perkCache = { t = 0, v = false, n = "" }
    TianHubState.KillerHasPerk = function(perkName)
        local now = os.clock()
        if perkCache.n == perkName and now - perkCache.t < 2 then return perkCache.v end
        local has = false
        local killer = getKillerPlayer()
        if killer then
            for _, p in ipairs(readPerks(killer)) do
                if p.Name == perkName then has = true; break end
            end
        end
        perkCache.t, perkCache.v, perkCache.n = now, has, perkName
        return has
    end

    local function stopPerks()
        PerkState.Enabled = false
        if PerkState.Thread then pcall(function() task.cancel(PerkState.Thread) end); PerkState.Thread = nil end
        for _, c in ipairs(PerkState.Conns) do pcall(function() c:Disconnect() end) end
        PerkState.Conns = {}
        if PerkState.Gui then pcall(function() PerkState.Gui:Destroy() end); PerkState.Gui = nil end
    end

    local function startPerks()
        if PerkState.Enabled then return end
        PerkState.Enabled = true

        local PW = 200
        local gui = Instance.new("ScreenGui")
        gui.Name = "TianKillerPerks"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 50
        gui.Parent = guiParent()
        PerkState.Gui = gui

        local frame = Instance.new("Frame")
        frame.Name = "MainFrame"
        frame.Size = UDim2.new(0, PW, 0, 0)
        frame.AutomaticSize = Enum.AutomaticSize.Y
        frame.Position = UDim2.new(1, -PW - 16, 0, 130)
        frame.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
        frame.BackgroundTransparency = 0.1
        frame.BorderSizePixel = 0
        frame.Parent = gui
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
        local stroke = Instance.new("UIStroke", frame)
        stroke.Color = Color3.fromRGB(70, 70, 70)
        stroke.Thickness = 1
        local frameList = Instance.new("UIListLayout", frame)
        frameList.SortOrder = Enum.SortOrder.LayoutOrder

        local header = Instance.new("Frame")
        header.Name = "Header"
        header.Size = UDim2.new(1, 0, 0, 28)
        header.BackgroundTransparency = 1
        header.LayoutOrder = 1
        header.Active = true
        header.Parent = frame

        local killerName = Instance.new("TextLabel")
        killerName.BackgroundTransparency = 1
        killerName.Position = UDim2.fromOffset(10, 0)
        killerName.Size = UDim2.new(1, -56, 1, 0)
        killerName.Font = Enum.Font.GothamMedium
        killerName.Text = "Searching..."
        killerName.TextColor3 = Color3.fromRGB(255, 255, 255)
        killerName.TextSize = 12
        killerName.TextXAlignment = Enum.TextXAlignment.Left
        killerName.TextTruncate = Enum.TextTruncate.AtEnd
        killerName.Parent = header

        local function makeHeaderBtn(xOff, text)
            local b = Instance.new("TextButton")
            b.AnchorPoint = Vector2.new(1, 0.5)
            b.Position = UDim2.new(1, xOff, 0.5, 0)
            b.Size = UDim2.fromOffset(20, 20)
            b.BackgroundTransparency = 1
            b.AutoButtonColor = false
            b.Font = Enum.Font.GothamBold
            b.Text = text
            b.TextColor3 = Color3.fromRGB(170, 170, 176)
            b.TextSize = 14
            b.Parent = header
            return b
        end
        local closeBtn = makeHeaderBtn(-6, "x")
        local minBtn = makeHeaderBtn(-28, "-")

        local divider = Instance.new("Frame")
        divider.Size = UDim2.new(1, -16, 0, 1)
        divider.BackgroundColor3 = Color3.fromRGB(60, 60, 64)
        divider.BorderSizePixel = 0
        divider.LayoutOrder = 2
        divider.Parent = frame

        local body = Instance.new("Frame")
        body.Name = "Body"
        body.Size = UDim2.new(1, 0, 0, 0)
        body.AutomaticSize = Enum.AutomaticSize.Y
        body.BackgroundTransparency = 1
        body.LayoutOrder = 3
        body.Parent = frame
        local bodyPad = Instance.new("UIPadding", body)
        bodyPad.PaddingTop, bodyPad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
        bodyPad.PaddingLeft, bodyPad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
        local bodyList = Instance.new("UIListLayout", body)
        bodyList.SortOrder = Enum.SortOrder.LayoutOrder
        bodyList.Padding = UDim.new(0, 2)

        local function applyState()
            body.Visible = not PerkState.Minimized
            divider.Visible = not PerkState.Minimized
            minBtn.Text = PerkState.Minimized and "+" or "-"
        end
        applyState()
        minBtn.MouseButton1Click:Connect(function()
            PerkState.Minimized = not PerkState.Minimized
            applyState()
        end)
        closeBtn.MouseButton1Click:Connect(function()
            local okR, reg = pcall(function() return ToggleRegistry["killer_perks_display"] end)
            if okR and reg and reg.setState then
                reg.setState(false, true)
            else
                stopPerks()
            end
        end)

        local dragging, dragStart, startPos = false, nil, nil
        PerkState.Conns[#PerkState.Conns + 1] = header.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging, dragStart, startPos = true, input.Position, frame.Position
            end
        end)
        PerkState.Conns[#PerkState.Conns + 1] = UserInputService.InputChanged:Connect(function(input)
            if not dragging then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                local d = input.Position - dragStart
                frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end)
        PerkState.Conns[#PerkState.Conns + 1] = UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)

        local function addRow(text, level, order, dim)
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, 22)
            row.BackgroundTransparency = 1
            row.LayoutOrder = order
            row.Parent = body

            if not dim then
                local idx = Instance.new("TextLabel")
                idx.BackgroundTransparency = 1
                idx.Size = UDim2.fromOffset(14, 22)
                idx.Font = Enum.Font.GothamMedium
                idx.Text = tostring(order)
                idx.TextColor3 = Color3.fromRGB(110, 110, 116)
                idx.TextSize = 11
                idx.TextXAlignment = Enum.TextXAlignment.Left
                idx.Parent = row
            end

            local name = Instance.new("TextLabel")
            name.BackgroundTransparency = 1
            name.Position = UDim2.fromOffset(dim and 0 or 18, 0)
            name.Size = UDim2.new(1, (dim and 0 or -18) - (level and 36 or 0), 1, 0)
            name.Font = Enum.Font.GothamMedium
            name.Text = text
            name.TextColor3 = dim and Color3.fromRGB(150, 150, 156) or Color3.fromRGB(255, 255, 255)
            name.TextSize = 12
            name.TextXAlignment = Enum.TextXAlignment.Left
            name.TextTruncate = Enum.TextTruncate.AtEnd
            name.Parent = row

            if level then
                local lv = Instance.new("TextLabel")
                lv.AnchorPoint = Vector2.new(1, 0)
                lv.Position = UDim2.new(1, 0, 0, 0)
                lv.BackgroundTransparency = 1
                lv.Size = UDim2.fromOffset(34, 22)
                lv.Font = Enum.Font.GothamMedium
                lv.Text = "Lv " .. level
                lv.TextColor3 = Color3.fromRGB(150, 150, 156)
                lv.TextSize = 10
                lv.TextXAlignment = Enum.TextXAlignment.Right
                lv.Parent = row
            end
        end

        local lastSig
        local function refresh()
            local killer = getKillerPlayer()
            local perks = readPerks(killer)
            if #perks == 0 then
                for _, p in ipairs(Players:GetPlayers()) do
                    local cand = readPerks(p)
                    if #cand > 0 then killer, perks = p, cand; break end
                end
            end

            killerName.Text = killer and (TianHubState.PlrName and TianHubState.PlrName(killer) or (killer.DisplayName ~= "" and killer.DisplayName or killer.Name)) or "No killer found"

            local parts = { killer and (TianHubState.Streamer and "Killer" or killer.Name) or "-" }
            for _, p in ipairs(perks) do parts[#parts + 1] = p.Name .. (p.Level or "") end
            local sig = table.concat(parts, "|")
            if sig == lastSig then return end
            lastSig = sig

            for _, ch in ipairs(body:GetChildren()) do
                if ch:IsA("Frame") then ch:Destroy() end
            end
            if #perks == 0 then
                addRow(killer and "Waiting for perk data..." or "No killer in match", nil, 1, true)
                return
            end
            for i = 1, math.min(#perks, 6) do
                addRow(perks[i].Name, perks[i].Level, i, false)
            end
        end

        PerkState.Thread = task.spawn(function()
            while PerkState.Enabled do
                pcall(refresh)
                task.wait(1)
            end
        end)
    end

    local VisualInfo = CreateSection(VisualTab, "NEXT MAP", false)
    CreateToggle(VisualInfo, "Next Map Prediction", false, function(v)
        if v then startMapPredict() else stopMapPredict() end
    end)
    CreateToggle(VisualInfo, "Enable Spectator Counter", true, function(v)
        if v then startSpectatorCounter() else stopSpectatorCounter() end
    end)
    startSpectatorCounter()
    CreateButton(VisualInfo, "Refresh Count", function()
        if SpectatorState.Enabled then updateSpectatorCount() end
    end)
    VisualInfo = CreateSection(VisualTab, "NEXT KILLER", false)
    CreateToggle(VisualInfo, "Next Killer Display", false, function(v)
        if v then startNextKiller() else stopNextKiller() end
    end)
    VisualInfo = CreateSection(VisualTab, "KILLER PERKS", false)
    CreateToggle(VisualInfo, "Killer Perks Display", false, function(v)
        if v then startPerks() else stopPerks() end
    end)
end, function(e) logQuiet("[TianHub] feature block error: " .. tostring(e)) end)

xpcall(function()
    local CS = { On = false, Level = 3, Focus = nil }
    pcall(function() RunService:UnbindFromRenderStep("Tian_CameraStiffness") end)

    local function step(dt)
        if not CS.On then CS.Focus = nil; return end
        local cam = workspace.CurrentCamera
        if not cam then return end
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not hum or not root or hum.Health <= 0 then CS.Focus = nil; return end

        local focus = root.Position
        if not CS.Focus or (CS.Focus - focus).Magnitude > 20 then CS.Focus = focus; return end

        local tau = 0.04 + (CS.Level ^ 1.6) * 0.03
        local alpha = 1 - math.exp(-dt / tau)
        local smooth = CS.Focus:Lerp(focus, alpha)
        local lag = focus - smooth
        if lag.Magnitude > 10 then smooth = focus - lag.Unit * 10 end
        CS.Focus = smooth

        local c = cam.CFrame
        local offset = c.Position - focus
        cam.CFrame = CFrame.new(smooth + offset) * (c - c.Position)
    end
    RunService:BindToRenderStep("Tian_CameraStiffness", Enum.RenderPriority.Last.Value, step)

    local CamStiffSection = CreateSection(VisualTab, "CAMERA STIFFNESS", false)
    CreateToggle(CamStiffSection, "Camera Stiffness", false, function(v)
        CS.On = v
        CS.Focus = nil
    end)
    CreateSlider(CamStiffSection, "Stiffness", 1, 10, 3, "", function(v) CS.Level = tonumber(v) or 3 end)
end, function(e) logQuiet("[TianHub] camera stiffness error: " .. tostring(e)) end)

xpcall(function()
    local Lighting = game:GetService("Lighting")
    local genv = (getgenv and getgenv()) or _G
    local ORIGINAL = {
        Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime, FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart, FogColor = Lighting.FogColor, OutdoorAmbient = Lighting.OutdoorAmbient,
        Ambient = Lighting.Ambient, ExposureCompensation = Lighting.ExposureCompensation,
        ColorShift_Top = Lighting.ColorShift_Top, ColorShift_Bottom = Lighting.ColorShift_Bottom,
        EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale, EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
        GlobalShadows = Lighting.GlobalShadows,
    }
    local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
    local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

    local PRESETS = {
        ["Default"] = {},
        ["Christmas (Snow)"] = {
            Lighting = { FogColor = Color3.fromRGB(150, 180, 220), FogEnd = 200, ClockTime = 8, OutdoorAmbient = Color3.fromRGB(100, 120, 150) },
            Atmosphere = { Density = 0.5, Color = Color3.fromRGB(180, 200, 220), Decay = Color3.fromRGB(150, 180, 220), Haze = 5, Glare = 0 },
            Particle = { Texture = SPARK, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)), Size = NumberSequence.new(1.5), Rate = 150, Speed = NumberRange.new(15, 25), Lifetime = NumberRange.new(4, 6), EmissionDirection = Enum.NormalId.Bottom, RotSpeed = NumberRange.new(-45, 45) },
        },
        ["Heavy Rain (Storm)"] = {
            Lighting = { FogColor = Color3.fromRGB(50, 50, 60), FogEnd = 150, OutdoorAmbient = Color3.fromRGB(40, 40, 50), Brightness = 0.2, ClockTime = 12 },
            CC = { TintColor = Color3.fromRGB(150, 150, 180), Saturation = -0.5 },
            Particle = { Texture = SPARK, AnchorSize = Vector3.new(260, 1, 260), CameraOffset = Vector3.new(0, 38, -18), Squash = NumberSequence.new(16), Color = ColorSequence.new(Color3.fromRGB(235, 245, 255)), Size = NumberSequence.new(1.25), Rate = 2600, Speed = NumberRange.new(110, 145), Lifetime = NumberRange.new(0.85, 1.25), EmissionDirection = Enum.NormalId.Bottom, Transparency = NumberSequence.new(0), Acceleration = Vector3.new(-18, -75, 0), SpreadAngle = Vector2.new(3, 3), LightEmission = 1 },
        },
        ["Autumn (Musim Gugur)"] = {
            Lighting = { FogColor = Color3.fromRGB(200, 150, 80), FogEnd = 500, OutdoorAmbient = Color3.fromRGB(180, 140, 70), ClockTime = 16.5 },
            CC = { TintColor = Color3.fromRGB(255, 220, 180), Saturation = 0.2 },
            Particle = { Texture = SPARK, AnchorSize = Vector3.new(210, 1, 210), CameraOffset = Vector3.new(0, 28, -16), Squash = NumberSequence.new(3.2), Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 190, 45)), ColorSequenceKeypoint.new(0.45, Color3.fromRGB(235, 95, 20)), ColorSequenceKeypoint.new(1, Color3.fromRGB(135, 45, 10)) }), Size = NumberSequence.new(2.05), Rate = 360, Speed = NumberRange.new(8, 15), Lifetime = NumberRange.new(6, 10), EmissionDirection = Enum.NormalId.Bottom, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-220, 220), Transparency = NumberSequence.new(0), Acceleration = Vector3.new(18, -8, 6), SpreadAngle = Vector2.new(38, 38), LightEmission = 0.6 },
        },
        ["Cherry Blossom (Sakura)"] = {
            Lighting = { FogColor = Color3.fromRGB(255, 200, 220), FogEnd = 600, OutdoorAmbient = Color3.fromRGB(255, 180, 200), ClockTime = 9 },
            CC = { TintColor = Color3.fromRGB(255, 230, 240), Saturation = 0.3 },
            Particle = { Texture = SPARK, AnchorSize = Vector3.new(160, 1, 160), CameraOffset = Vector3.new(0, 25, -18), Squash = NumberSequence.new(1.2), Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 235)), ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 165, 205)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 120, 180)) }), Size = NumberSequence.new(1.25), Rate = 190, Speed = NumberRange.new(5, 10), Lifetime = NumberRange.new(7, 10), EmissionDirection = Enum.NormalId.Bottom, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-170, 170), Transparency = NumberSequence.new(0), Acceleration = Vector3.new(14, -5, 5), SpreadAngle = Vector2.new(32, 32), LightEmission = 0.55 },
        },
        ["Sunset (Golden Hour)"] = {
            Lighting = { FogColor = Color3.fromRGB(255, 120, 50), FogEnd = 1200, OutdoorAmbient = Color3.fromRGB(200, 100, 50), ClockTime = 17.5, Brightness = 1.5 },
            CC = { TintColor = Color3.fromRGB(255, 200, 150), Saturation = 0.4 },
        },
        ["Blood Moon (Spooky)"] = {
            Lighting = { FogColor = Color3.fromRGB(150, 10, 10), FogEnd = 500, OutdoorAmbient = Color3.fromRGB(80, 0, 0), ClockTime = 0, Brightness = 0.3 },
            CC = { TintColor = Color3.fromRGB(255, 50, 50), Saturation = 0.5 },
            Atmosphere = { Density = 0.35, Color = Color3.fromRGB(125, 125, 125), Decay = Color3.fromRGB(100, 0, 0), Haze = 5, Glare = 0 },
        },
        ["Toxic Wasteland"] = {
            Lighting = { FogColor = Color3.fromRGB(80, 150, 50), FogEnd = 250, OutdoorAmbient = Color3.fromRGB(50, 120, 40), ClockTime = 12, Brightness = 1 },
            CC = { TintColor = Color3.fromRGB(150, 255, 150), Saturation = 0.3 },
            Particle = { Texture = SPARK, Color = ColorSequence.new(Color3.fromRGB(100, 255, 50)), Size = NumberSequence.new(0.8), Rate = 200, Speed = NumberRange.new(50, 60), Lifetime = NumberRange.new(2, 3), EmissionDirection = Enum.NormalId.Bottom, Transparency = NumberSequence.new(0.5) },
        },
        ["Vaporwave (Synthwave)"] = {
            Lighting = { FogColor = Color3.fromRGB(200, 50, 255), FogEnd = 500, OutdoorAmbient = Color3.fromRGB(150, 0, 200), ClockTime = 20, Brightness = 1 },
            CC = { TintColor = Color3.fromRGB(255, 100, 255), Saturation = 0.5 },
        },
        ["Midnight (Pitch Black)"] = {
            Lighting = { FogColor = Color3.fromRGB(0, 0, 0), FogEnd = 100, OutdoorAmbient = Color3.fromRGB(0, 0, 0), Brightness = 0, ClockTime = 0 },
            CC = { TintColor = Color3.fromRGB(50, 50, 50), Saturation = -0.8 },
        },

        ["DBD (Misty Night)"] = {
            Lighting = {
                FogColor = Color3.fromRGB(70, 82, 100), FogStart = 5, FogEnd = 190,
                OutdoorAmbient = Color3.fromRGB(80, 92, 112), Ambient = Color3.fromRGB(62, 72, 90),
                Brightness = 0.95, ClockTime = 3.5, ExposureCompensation = 0.05,
                ColorShift_Top = Color3.fromRGB(70, 95, 140), ColorShift_Bottom = Color3.fromRGB(25, 32, 46),
                EnvironmentDiffuseScale = 0.5, EnvironmentSpecularScale = 0.3, GlobalShadows = true,
            },
            Atmosphere = { Density = 0.66, Offset = 0.2, Color = Color3.fromRGB(100, 114, 135), Decay = Color3.fromRGB(50, 60, 80), Haze = 6.5, Glare = 0 },
            CC = { TintColor = Color3.fromRGB(215, 225, 240), Saturation = -0.2, Brightness = 0.03 },
            Bloom = { Intensity = 0.3, Size = 24, Threshold = 1.1 },
            DOF = { FarIntensity = 0.2, FocusDistance = 55, InFocusRadius = 45, NearIntensity = 0 },
            Particle = { Texture = SMOKE, AnchorSize = Vector3.new(260, 1, 260), CameraOffset = Vector3.new(0, 9, -6), Color = ColorSequence.new(Color3.fromRGB(170, 185, 205)), Size = NumberSequence.new(20), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.74), NumberSequenceKeypoint.new(0.75, 0.78), NumberSequenceKeypoint.new(1, 1) }), Rate = 60, Speed = NumberRange.new(2, 5), Lifetime = NumberRange.new(10, 14), EmissionDirection = Enum.NormalId.Front, Acceleration = Vector3.new(3, 0, 1), SpreadAngle = Vector2.new(180, 180), RotSpeed = NumberRange.new(-8, 8), LightEmission = 0 },
            Extra = {
                { Texture = SPARK, Color = ColorSequence.new(Color3.fromRGB(190, 205, 225)), Size = NumberSequence.new(0.2), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.5), NumberSequenceKeypoint.new(0.8, 0.6), NumberSequenceKeypoint.new(1, 1) }), Rate = 28, Speed = NumberRange.new(1, 3), Lifetime = NumberRange.new(6, 10), EmissionDirection = Enum.NormalId.Front, Acceleration = Vector3.new(1.5, 0.6, 1), SpreadAngle = Vector2.new(180, 180), LightEmission = 0.4 },
            },
        },
    }
    local ORDER = {
        "Default", "Christmas (Snow)", "Heavy Rain (Storm)", "Autumn (Musim Gugur)", "Cherry Blossom (Sakura)",
        "Sunset (Golden Hour)", "Blood Moon (Spooky)", "Toxic Wasteland", "Vaporwave (Synthwave)",
        "Midnight (Pitch Black)", "DBD (Misty Night)",
    }

    local function addEmitter(anchor, name, props)
        local pe = Instance.new("ParticleEmitter")
        pe.Name = name
        pe.Enabled = true
        pe.EmissionDirection = Enum.NormalId.Bottom
        pe.LockedToPart = false
        pe.ZOffset = 2
        pe.LightEmission = 0.25
        pe.SpreadAngle = Vector2.new(10, 10)
        pcall(function() pe.Shape = Enum.ParticleEmitterShape.Box end)
        pcall(function() pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume end)
        for k, v in pairs(props) do
            if k ~= "AnchorSize" and k ~= "CameraOffset" then pcall(function() pe[k] = v end) end
        end
        pe.Parent = anchor
        return pe
    end

    local function clearWeather()
        for _, nm in ipairs({ "TianWeatherCC", "TianWeatherAtmosphere", "TianWeatherBloom", "TianWeatherDOF" }) do
            local o = Lighting:FindFirstChild(nm)
            if o then o:Destroy() end
        end
        local a = genv.TianWeatherAnchor
        if a and a.Parent then a:Destroy() end
        genv.TianWeatherAnchor = nil
    end

    local function applyWeather(themeName)
        clearWeather()
        local theme = PRESETS[themeName] or PRESETS["Default"]
        if theme.Atmosphere then
            local atm = Instance.new("Atmosphere")
            atm.Name = "TianWeatherAtmosphere"
            for k, v in pairs(theme.Atmosphere) do pcall(function() atm[k] = v end) end
            atm.Parent = Lighting
        end
        if theme.CC then
            local cc = Instance.new("ColorCorrectionEffect")
            cc.Name = "TianWeatherCC"
            for k, v in pairs(theme.CC) do pcall(function() cc[k] = v end) end
            cc.Parent = Lighting
        end
        if theme.Bloom then
            local bl = Instance.new("BloomEffect")
            bl.Name = "TianWeatherBloom"
            for k, v in pairs(theme.Bloom) do pcall(function() bl[k] = v end) end
            bl.Parent = Lighting
        end
        if theme.DOF then
            local df = Instance.new("DepthOfFieldEffect")
            df.Name = "TianWeatherDOF"
            for k, v in pairs(theme.DOF) do pcall(function() df[k] = v end) end
            df.Parent = Lighting
        end
        if theme.Lighting then
            for k, v in pairs(ORIGINAL) do pcall(function() Lighting[k] = v end) end
            for k, v in pairs(theme.Lighting) do pcall(function() Lighting[k] = v end) end
        else
            for k, v in pairs(ORIGINAL) do pcall(function() Lighting[k] = v end) end
        end
        if theme.Particle then
            local P = theme.Particle
            local anchor = Instance.new("Part")
            anchor.Name = "TianWeatherAnchor"
            anchor.Transparency = 1
            anchor.CanCollide = false
            anchor.CanQuery = false
            anchor.CanTouch = false
            anchor.Anchored = true
            anchor.Size = P.AnchorSize or Vector3.new(120, 1, 120)
            anchor:SetAttribute("OffX", P.CameraOffset and P.CameraOffset.X or 0)
            anchor:SetAttribute("OffY", P.CameraOffset and P.CameraOffset.Y or 30)
            anchor:SetAttribute("OffZ", P.CameraOffset and P.CameraOffset.Z or 0)
            addEmitter(anchor, "TianWeatherEmitter", P)
            if theme.Extra then
                for i, ex in ipairs(theme.Extra) do addEmitter(anchor, "TianExtra" .. i, ex) end
            end
            if themeName == "Heavy Rain (Storm)" then
                addEmitter(anchor, "TianRainNear", { Texture = SPARK, Color = ColorSequence.new(Color3.fromRGB(230, 240, 255)), Transparency = NumberSequence.new(0), Size = NumberSequence.new(1.65), Squash = NumberSequence.new(20), Rate = 1800, Speed = NumberRange.new(70, 95), Lifetime = NumberRange.new(0.75, 1.05), Acceleration = Vector3.new(-24, -90, 0), SpreadAngle = Vector2.new(2, 2), ZOffset = 6, LightEmission = 1 })
                addEmitter(anchor, "TianRainSheet", { Texture = SMOKE, Color = ColorSequence.new(Color3.fromRGB(170, 195, 225)), Transparency = NumberSequence.new(0.45), Size = NumberSequence.new(3.2), Squash = NumberSequence.new(7), Rate = 650, Speed = NumberRange.new(45, 65), Lifetime = NumberRange.new(1.0, 1.5), Acceleration = Vector3.new(-14, -55, 0), SpreadAngle = Vector2.new(8, 8), ZOffset = 3, LightEmission = 0.35 })
            elseif themeName == "Autumn (Musim Gugur)" then
                addEmitter(anchor, "TianBigLeaves", { Texture = SPARK, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 205, 55)), ColorSequenceKeypoint.new(0.35, Color3.fromRGB(230, 95, 25)), ColorSequenceKeypoint.new(0.7, Color3.fromRGB(165, 65, 20)), ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 40, 8)) }), Transparency = NumberSequence.new(0), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.4), NumberSequenceKeypoint.new(0.5, 3.1), NumberSequenceKeypoint.new(1, 1.8) }), Squash = NumberSequence.new(4.5), Rate = 150, Speed = NumberRange.new(5, 10), Lifetime = NumberRange.new(8, 12), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-280, 280), Acceleration = Vector3.new(24, -5, 10), SpreadAngle = Vector2.new(45, 45), ZOffset = 5, LightEmission = 0.65 })
            end
            anchor.Parent = workspace
            genv.TianWeatherAnchor = anchor
        end
    end

    setConn("Tian_WeatherAnchor", RunService.RenderStepped:Connect(function()
        local anchor = genv.TianWeatherAnchor
        local cam = workspace.CurrentCamera
        if not anchor or not anchor.Parent or not cam then return end
        local off = Vector3.new(anchor:GetAttribute("OffX") or 0, anchor:GetAttribute("OffY") or 30, anchor:GetAttribute("OffZ") or 0)
        anchor.CFrame = CFrame.new(cam.CFrame.Position + cam.CFrame.RightVector * off.X + Vector3.new(0, off.Y, 0) + cam.CFrame.LookVector * math.abs(off.Z))
    end))

    local function startTianSkyChanger()
        -- Sky Changer module integrated and styled for TianHub.
        local Players = game:GetService("Players")
        local HttpService = game:GetService("HttpService")
        local UserInputService = game:GetService("UserInputService")
        local RunService = game:GetService("RunService")
        local Lighting = game:GetService("Lighting")
        local CoreGui = game:GetService("CoreGui")
        
        local player = Players.LocalPlayer
        local playerGui = player:WaitForChild("PlayerGui")
        
        local GlobalConnections = {}
        
        local C_BG = Color3.fromRGB(9, 9, 15)
        local C_BG_LIGHT = Color3.fromRGB(17, 12, 28)
        local C_BG_ITEM = Color3.fromRGB(20, 16, 32)
        local C_NEON_CYAN = Color3.fromRGB(90, 145, 255)
        local C_TEXT = Color3.fromRGB(240, 240, 240)
        local C_STROKE = Color3.fromRGB(105, 65, 155)
        
        local guiName = "SkyChangerUI"
        if getgenv().RemoveSkyChanger then 
            pcall(getgenv().RemoveSkyChanger) 
        end
        
        -- Menggunakan CoreGui jika tersedia (lebih aman dari respawn/reset), jika tidak fallback ke PlayerGui
        local targetGuiParent = pcall(function() return CoreGui.Name end) and CoreGui or playerGui
        
        local studioGui = Instance.new("ScreenGui")
        studioGui.Name = guiName
        studioGui.ResetOnSpawn = false -- Memastikan GUI tidak hilang saat karakter mati/respawn
        studioGui.Parent = targetGuiParent
        
        local preMinSize = UDim2.new(0, 260, 0, 280) 
        local minSize = UDim2.new(0, 150, 0, 32) 
        
        local mainFrame = Instance.new("Frame", studioGui)
        mainFrame.Size = preMinSize
        mainFrame.AnchorPoint = Vector2.new(0.5, 0) 
        mainFrame.Position = UDim2.new(0.5, 0, 0.2, 0)
        mainFrame.BackgroundColor3 = Color3.new(1, 1, 1) 
        mainFrame.BorderSizePixel = 0
        mainFrame.ClipsDescendants = true
        
        local mainGradient = Instance.new("UIGradient", mainFrame)
        mainGradient.Color = ColorSequence.new{
            ColorSequenceKeypoint.new(0, C_BG),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(25, 25, 30))
        }
        mainGradient.Rotation = 90
        
        local mainCorner = Instance.new("UICorner", mainFrame)
        mainCorner.CornerRadius = UDim.new(0, 8)
        
        local mainStroke = Instance.new("UIStroke", mainFrame)
        mainStroke.Color = C_STROKE
        mainStroke.Thickness = 1.2
        mainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        
        local header = Instance.new("Frame", mainFrame)
        header.Size = UDim2.new(1, 0, 0, 32)
        header.BackgroundTransparency = 1 
        header.BorderSizePixel = 0
        
        local title = Instance.new("TextLabel", header)
        title.Size = UDim2.new(1, -30, 1, 0)
        title.Position = UDim2.new(0, 15, 0, 0)
        title.BackgroundTransparency = 1
        title.Text = "TianHub Sky Changer"
        title.TextColor3 = C_TEXT
        title.Font = Enum.Font.GothamBold
        title.TextSize = 12
        title.TextXAlignment = Enum.TextXAlignment.Center
        
        local minimizeBtn = Instance.new("TextButton", header)
        minimizeBtn.Size = UDim2.new(0, 32, 0, 32)
        minimizeBtn.Position = UDim2.new(1, -32, 0, 0)
        minimizeBtn.BackgroundTransparency = 1
        minimizeBtn.Text = "▬"
        minimizeBtn.TextColor3 = C_TEXT
        minimizeBtn.Font = Enum.Font.GothamBold
        minimizeBtn.TextSize = 14
        
        local searchFrame = Instance.new("Frame", mainFrame)
        local gridArea = Instance.new("ScrollingFrame", mainFrame)
        local loadingLabel = Instance.new("TextLabel", mainFrame)
        local ResizeHandle = Instance.new("TextButton", mainFrame)
        
        local isMinimized = false
        minimizeBtn.MouseButton1Click:Connect(function()
            isMinimized = not isMinimized
            if isMinimized then
                mainFrame.Size = minSize
                mainCorner.CornerRadius = UDim.new(1, 0) 
                searchFrame.Visible = false
                gridArea.Visible = false
                ResizeHandle.Visible = false
            else
                mainFrame.Size = preMinSize
                mainCorner.CornerRadius = UDim.new(0, 8)
                searchFrame.Visible = true
                gridArea.Visible = true
                ResizeHandle.Visible = true
            end
        end)
        
        local dragging, dragInput, dragStart, startPos
        header.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = mainFrame.Position
            end
        end)
        
        table.insert(GlobalConnections, UserInputService.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                dragInput = input
            end
        end))
        
        table.insert(GlobalConnections, RunService.RenderStepped:Connect(function()
            if dragging and dragInput then
                local delta = dragInput.Position - dragStart
                mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end))
        
        table.insert(GlobalConnections, UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end))
        
        ResizeHandle.Size = UDim2.new(0, 16, 0, 16)
        ResizeHandle.Position = UDim2.new(1, -16, 1, -16)
        ResizeHandle.BackgroundTransparency = 1
        ResizeHandle.Text = "↘"
        ResizeHandle.TextColor3 = Color3.fromRGB(120, 120, 120)
        ResizeHandle.Font = Enum.Font.GothamBold
        ResizeHandle.TextSize = 12
        ResizeHandle.ZIndex = 20
        
        local resizing = false
        local resizeStartPos, startSize
        ResizeHandle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                resizing = true
                resizeStartPos = input.Position
                startSize = mainFrame.AbsoluteSize
            end
        end)
        
        table.insert(GlobalConnections, UserInputService.InputChanged:Connect(function(input)
            if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                if not isMinimized then
                    local delta = input.Position - resizeStartPos
                    local newWidth = math.clamp(startSize.X + (delta.X * 2), 220, 450)
                    local newHeight = math.clamp(startSize.Y + delta.Y, 250, 550)
                    
                    mainFrame.Size = UDim2.new(0, newWidth, 0, newHeight)
                    preMinSize = mainFrame.Size 
                end
            end
        end))
        
        table.insert(GlobalConnections, UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                resizing = false
            end
        end))
        
        searchFrame.Size = UDim2.new(1, -20, 0, 30)
        searchFrame.Position = UDim2.new(0, 10, 0, 40)
        searchFrame.BackgroundColor3 = C_BG_LIGHT
        Instance.new("UICorner", searchFrame).CornerRadius = UDim.new(0, 6)
        
        local searchStroke = Instance.new("UIStroke", searchFrame)
        searchStroke.Color = Color3.fromRGB(70, 70, 80)
        searchStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        
        local searchBox = Instance.new("TextBox", searchFrame)
        searchBox.Size = UDim2.new(1, -40, 1, 0)
        searchBox.Position = UDim2.new(0, 10, 0, 0)
        searchBox.BackgroundTransparency = 1
        searchBox.TextColor3 = C_TEXT
        searchBox.PlaceholderText = "Search sky..."
        searchBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 160)
        searchBox.Text = "sky"
        searchBox.TextSize = 11
        searchBox.Font = Enum.Font.GothamMedium
        searchBox.TextXAlignment = Enum.TextXAlignment.Left
        searchBox.ClearTextOnFocus = false
        
        local searchBtn = Instance.new("TextButton", searchFrame)
        searchBtn.Size = UDim2.new(0, 30, 1, 0)
        searchBtn.Position = UDim2.new(1, -30, 0, 0)
        searchBtn.BackgroundTransparency = 1
        searchBtn.Text = "🔍"
        searchBtn.TextColor3 = C_NEON_CYAN
        
        loadingLabel.Size = UDim2.new(1, 0, 0, 20)
        loadingLabel.Position = UDim2.new(0, 0, 0, 75)
        loadingLabel.BackgroundTransparency = 1
        loadingLabel.Text = "Searching..."
        loadingLabel.TextColor3 = C_NEON_CYAN
        loadingLabel.Font = Enum.Font.Gotham
        loadingLabel.TextSize = 10
        loadingLabel.Visible = false
        
        task.spawn(function()
            while true do
                if loadingLabel.Visible then
                    loadingLabel.TextTransparency = 0.3; task.wait(0.4)
                    loadingLabel.TextTransparency = 0.8; task.wait(0.4)
                else
                    task.wait(0.2)
                end
            end
        end)
        
        gridArea.Size = UDim2.new(1, -16, 1, -85)
        gridArea.Position = UDim2.new(0, 8, 0, 80)
        gridArea.BackgroundTransparency = 1
        gridArea.ScrollBarThickness = 2
        gridArea.ScrollBarImageColor3 = Color3.fromRGB(120, 120, 130)
        gridArea.CanvasSize = UDim2.new(0, 0, 0, 0)
        
        local gridLayout = Instance.new("UIGridLayout", gridArea)
        gridLayout.CellSize = UDim2.new(0, 56, 0, 70)
        gridLayout.CellPadding = UDim2.new(0, 5, 0, 5)
        
        local function getAssetInfo(assetId)
            local success, response = pcall(function()
                if type(request) == "function" then
                    return request({Url = "https://economy.roblox.com/v2/assets/" .. assetId .. "/details", Method = "GET"}).Body
                else
                    return game:HttpGet("https://economy.roblox.com/v2/assets/" .. assetId .. "/details")
                end
            end)
            if success and response then
                local data = HttpService:JSONDecode(response)
                if data and data.Name then
                    return {id = assetId, name = data.Name, icon = assetId}
                end
            end
            return nil
        end
        
        local function shuffleTable(t)
            for i = #t, 2, -1 do
                local j = math.random(i)
                t[i], t[j] = t[j], t[i]
            end
        end
        
        local function fetchModels(keyword)
            local url = "https://apis.roblox.com/toolbox-service/v1/marketplace/10?limit=30&keyword=" .. HttpService:UrlEncode(keyword)
            local success, response = pcall(function()
                if type(request) == "function" then
                    return request({Url = url, Method = "GET"}).Body
                else
                    return game:HttpGet(url)
                end
            end)
            
            if success and response then
                local decoded = HttpService:JSONDecode(response)
                if decoded and decoded.data then
                    local allItems = {}
                    for _, item in ipairs(decoded.data) do
                        if item.id then table.insert(allItems, item) end
                    end
                    
                    shuffleTable(allItems)
                    
                    local res = {}
                    local validCount = 0
                    for i = 1, #allItems do
                        if validCount >= 10 then break end
                        local info = getAssetInfo(allItems[i].id)
                        if info then 
                            table.insert(res, info)
                            validCount = validCount + 1
                        end
                    end
                    return res
                end
            end
            return nil
        end
        
        local function displayGrid(items)
            for _, v in ipairs(gridArea:GetChildren()) do if v:IsA("TextButton") then v:Destroy() end end
            if not items then return end
            
            for _, item in ipairs(items) do
                local btn = Instance.new("TextButton", gridArea)
                btn.BackgroundColor3 = C_BG_ITEM; btn.Text = ""
                Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
                
                local btnStroke = Instance.new("UIStroke", btn)
                btnStroke.Color = Color3.fromRGB(80, 80, 90)
                btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                
                local thumb = Instance.new("ImageLabel", btn)
                thumb.Size = UDim2.new(1, -6, 0, 45); thumb.Position = UDim2.new(0, 3, 0, 3)
                thumb.Image = "rbxthumb://type=Asset&id=" .. item.id .. "&w=150&h=150"
                thumb.BackgroundTransparency = 1
                Instance.new("UICorner", thumb).CornerRadius = UDim.new(0, 4)
        
                local txt = Instance.new("TextLabel", btn)
                txt.Size = UDim2.new(1, -4, 0, 18); txt.Position = UDim2.new(0, 2, 1, -20)
                txt.Text = item.name; txt.TextColor3 = C_TEXT; txt.TextSize = 8
                txt.Font = Enum.Font.GothamMedium
                txt.BackgroundTransparency = 1; txt.TextWrapped = true
        
                btn.MouseButton1Click:Connect(function()
                    pcall(function()
                        local btnTextCache = txt.Text
                        txt.Text = "..."
                        txt.TextColor3 = C_NEON_CYAN
                        
                        task.spawn(function()
                            local success, result = pcall(function()
                                return game:GetObjects("rbxassetid://" .. item.id)
                            end)
                            
                            if success and result and #result > 0 then
                                local downloadedAsset = result[1]
                                
                                -- FUNGSI BARU: Menghapus Sky dari Lighting & workspace.Map
                                local function clearOldSkies()
                                    -- 1. Hapus Sky bawaan yang ada di Lighting
                                    for _, child in pairs(Lighting:GetChildren()) do
                                        if child:IsA("Sky") then child:Destroy() end
                                    end
                                    
                                    -- 2. Hapus semua Sky yang ada di dalam Map (seperti di gambar 14124.jpg)
                                    local mapFolder = workspace:FindFirstChild("Map")
                                    if mapFolder then
                                        for _, desc in pairs(mapFolder:GetDescendants()) do
                                            if desc:IsA("Sky") then
                                                desc:Destroy()
                                            end
                                        end
                                    end
                                end
                                
                                if downloadedAsset:IsA("Sky") then
                                    clearOldSkies()
                                    downloadedAsset.Parent = Lighting
                                else
                                    local skyObject = downloadedAsset:FindFirstChildOfClass("Sky", true)
                                    if skyObject then
                                        clearOldSkies()
                                        skyObject.Parent = Lighting
                                    end
                                end
                            end
                            
                            txt.Text = btnTextCache
                            txt.TextColor3 = C_TEXT
                        end)
                    end)
                end)
            end
            gridArea.CanvasSize = UDim2.new(0, 0, 0, gridLayout.AbsoluteContentSize.Y + 10)
        end
        
        local function doSearch()
            local query = searchBox.Text
            if query == "" then return end
            
            loadingLabel.Visible = true
            gridArea.Visible = false
            
            task.spawn(function()
                local res = fetchModels(query)
                displayGrid(res)
                
                loadingLabel.Visible = false
                gridArea.Visible = true
            end)
        end
        
        searchBtn.MouseButton1Click:Connect(doSearch)
        searchBox.FocusLost:Connect(function(enterPressed)
            if enterPressed then doSearch() end
        end)
        
        task.spawn(doSearch)
        
        getgenv().RemoveSkyChanger = function()
            for _, connection in pairs(GlobalConnections) do
                if connection.Disconnect then
                    connection:Disconnect()
                end
            end
            GlobalConnections = {}
            
            if studioGui then
                studioGui:Destroy()
            end
            
            getgenv().RemoveSkyChanger = nil
        end
    end

    local selected = "Default"
    local WeatherSection = CreateSection(VisualTab, "WEATHER & SKY", false)
    TianHubState.CreateDropdown(WeatherSection, "Theme", ORDER, "Default", function(v)
        selected = v
        applyWeather(v)
    end)

    local DbdSection = CreateSection(VisualTab, "DBD SKY", false)
    CreateToggle(DbdSection, "DBD Sky Effect", false, function(v)
        if v then
            applyWeather("DBD (Misty Night)")
        else
            applyWeather(selected == "DBD (Misty Night)" and "Default" or selected)
        end
    end)
    local TianSkyChangerEnabled = false
    CreateToggle(DbdSection, "Sky Changer", false, function(v)
        TianSkyChangerEnabled = v == true
        if TianSkyChangerEnabled then
            local ok, err = pcall(startTianSkyChanger)
            if not ok then
                TianSkyChangerEnabled = false
                if getgenv().RemoveSkyChanger then pcall(getgenv().RemoveSkyChanger) end
                logQuiet("[TianHub] TianHub Sky Changer error: " .. tostring(err))
            end
        elseif getgenv().RemoveSkyChanger then
            pcall(getgenv().RemoveSkyChanger)
        end
    end)
end, function(e) logQuiet("[TianHub] weather error: " .. tostring(e)) end)

xpcall(function()
    local emoteGui, emoteTrack, emoteSound
    local emoteInputConn, emoteRemovingConn
    local emoteEnabled = false

    local function stopEmote()
        if emoteTrack then
            pcall(function() emoteTrack:Stop(0.1) end)
            pcall(function() emoteTrack:Destroy() end)
            emoteTrack = nil
        end
        if emoteSound then
            pcall(function() emoteSound:Stop() end)
            pcall(function() emoteSound:Destroy() end)
            emoteSound = nil
        end
    end

    local function buildEmoteWheel()
        if emoteGui and emoteGui.Parent then return end

        local guiName = "TianHubEmoteWheel"
        local oldGui = CoreGui:FindFirstChild(guiName)
        if oldGui then oldGui:Destroy() end

        emoteGui = Instance.new("ScreenGui")
        emoteGui.Name = guiName
        emoteGui.ResetOnSpawn = false
        emoteGui.IgnoreGuiInset = true
        emoteGui.DisplayOrder = 90
        emoteGui.Parent = CoreGui

        local wheelFrame = Instance.new("Frame")
        wheelFrame.Name = "WheelFrame"
        wheelFrame.Size = UDim2.fromOffset(300, 300)
        wheelFrame.Position = UDim2.fromScale(0.5, 0.5)
        wheelFrame.AnchorPoint = Vector2.new(0.5, 0.5)
        wheelFrame.BackgroundTransparency = 1
        wheelFrame.Visible = false
        wheelFrame.Parent = emoteGui
        Instance.new("UIAspectRatioConstraint", wheelFrame).AspectRatio = 1

        local outerRing = Instance.new("Frame")
        outerRing.Name = "OuterRing"
        outerRing.Size = UDim2.fromScale(1, 1)
        outerRing.BackgroundColor3 = Color3.fromRGB(8, 12, 22)
        outerRing.BackgroundTransparency = 0.12
        outerRing.BorderSizePixel = 0
        outerRing.ZIndex = 1
        outerRing.Parent = wheelFrame
        Instance.new("UICorner", outerRing).CornerRadius = UDim.new(1, 0)

        local wheelArtwork = Instance.new("ImageLabel")
        wheelArtwork.Name = "TianHubMenuArtwork"
        wheelArtwork.Size = UDim2.fromScale(1, 1)
        wheelArtwork.Position = UDim2.fromScale(0, 0)
        wheelArtwork.BackgroundTransparency = 1
        wheelArtwork.BorderSizePixel = 0
        wheelArtwork.Image = "rbxassetid://80369014097246"
        wheelArtwork.ImageTransparency = 0.18
        wheelArtwork.ImageColor3 = Color3.fromRGB(225, 238, 255)
        wheelArtwork.ScaleType = Enum.ScaleType.Crop
        wheelArtwork.ZIndex = 2
        wheelArtwork.Parent = outerRing
        Instance.new("UICorner", wheelArtwork).CornerRadius = UDim.new(1, 0)

        local wheelShade = Instance.new("Frame")
        wheelShade.Name = "ArtworkReadabilityShade"
        wheelShade.Size = UDim2.fromScale(1, 1)
        wheelShade.BackgroundColor3 = Color3.fromRGB(3, 7, 16)
        wheelShade.BackgroundTransparency = 0.48
        wheelShade.BorderSizePixel = 0
        wheelShade.ZIndex = 2
        wheelShade.Parent = outerRing
        Instance.new("UICorner", wheelShade).CornerRadius = UDim.new(1, 0)

        local outerStroke = Instance.new("UIStroke", outerRing)
        outerStroke.Color = Color3.fromRGB(100, 100, 120)
        outerStroke.Thickness = 1.5
        outerStroke.Transparency = 0.4

        for i = 1, 8 do
            local lineContainer = Instance.new("Frame")
            lineContainer.Size = UDim2.fromScale(1, 1)
            lineContainer.BackgroundTransparency = 1
            lineContainer.Rotation = (i - 1) * 45 + 22.5
            lineContainer.ZIndex = 3
            lineContainer.Parent = wheelFrame
            local line = Instance.new("Frame")
            line.Size = UDim2.new(0, 1.5, 0.29, 0)
            line.Position = UDim2.new(0.5, 0, 0, 0)
            line.AnchorPoint = Vector2.new(0.5, 0)
            line.BackgroundColor3 = Color3.fromRGB(120, 120, 140)
            line.BackgroundTransparency = 0.6
            line.BorderSizePixel = 0
            line.Parent = lineContainer
        end

        local centerHole = Instance.new("Frame")
        centerHole.Name = "CenterHole"
        centerHole.Size = UDim2.fromScale(0.42, 0.42)
        centerHole.Position = UDim2.fromScale(0.5, 0.5)
        centerHole.AnchorPoint = Vector2.new(0.5, 0.5)
        centerHole.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
        centerHole.BackgroundTransparency = 0.15
        centerHole.BorderSizePixel = 0
        centerHole.ZIndex = 4
        centerHole.Parent = wheelFrame
        Instance.new("UICorner", centerHole).CornerRadius = UDim.new(1, 0)
        local centerStroke = Instance.new("UIStroke", centerHole)
        centerStroke.Color = Color3.fromRGB(100, 100, 120)
        centerStroke.Thickness = 1.5
        centerStroke.Transparency = 0.4

        local pageText = Instance.new("TextLabel")
        pageText.Size = UDim2.new(1, 0, 0.3, 0)
        pageText.Position = UDim2.new(0, 0, 0.2, 0)
        pageText.BackgroundTransparency = 1
        pageText.Text = "1 / 1"
        pageText.TextColor3 = Color3.fromRGB(230, 230, 240)
        pageText.Font = Enum.Font.GothamBold
        pageText.TextSize = 12
        pageText.ZIndex = 5
        pageText.Parent = centerHole

        local function makePageButton(name, text, x)
            local btn = Instance.new("TextButton")
            btn.Name = name
            btn.Size = UDim2.fromOffset(26, 22)
            btn.Position = UDim2.new(x, 0, 0.65, 0)
            btn.AnchorPoint = Vector2.new(0.5, 0.5)
            btn.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
            btn.Text = text
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            btn.Font = Enum.Font.GothamBold
            btn.TextSize = 12
            btn.ZIndex = 5
            btn.Parent = centerHole
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
            return btn
        end
        local prevBtn = makePageButton("PreviousPage", "<", 0.25)
        local nextBtn = makePageButton("NextPage", ">", 0.75)

        local wheelContainer = Instance.new("Frame")
        wheelContainer.Name = "WheelContainer"
        wheelContainer.Size = UDim2.fromScale(1, 1)
        wheelContainer.BackgroundTransparency = 1
        wheelContainer.ZIndex = 4
        wheelContainer.Parent = wheelFrame

        local emoteList, currentPage, currentDisplayedEmotes = {}, 1, {}
        local itemsPerPage = 8

        local function playEmote(animId, soundId)
            stopEmote()
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not hum then return end
            local animator = hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 2)
            if not animator then return end
            local animDigits = tostring(animId or ""):match("%d+")
            if not animDigits then return end
            local anim = Instance.new("Animation")
            anim.AnimationId = "rbxassetid://" .. animDigits
            local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
            if not ok or not track then anim:Destroy(); return end
            track.Looped = true
            track.Priority = Enum.AnimationPriority.Action
            track:Play()
            emoteTrack = track
            anim:Destroy()

            local soundDigits = tostring(soundId or ""):match("%d+")
            local root = char:FindFirstChild("HumanoidRootPart")
            if soundDigits and root then
                local sound = Instance.new("Sound")
                sound.SoundId = "rbxassetid://" .. soundDigits
                sound.Looped = true
                sound.Parent = root
                sound:Play()
                emoteSound = sound
            end
        end

        local function toggleWheel()
            wheelFrame.Visible = not wheelFrame.Visible
            if wheelFrame.Visible then stopEmote() end
        end

        local function renderPage(page)
            for _, child in ipairs(wheelContainer:GetChildren()) do
                if child.Name == "EmoteSlice" then child:Destroy() end
            end
            table.clear(currentDisplayedEmotes)
            local totalItems = #emoteList
            if totalItems == 0 then
                pageText.Text = "NO EMOTES"
                return
            end
            local totalPages = math.max(1, math.ceil(totalItems / itemsPerPage))
            currentPage = math.clamp(page, 1, totalPages)
            pageText.Text = currentPage .. " / " .. totalPages
            local startIndex = (currentPage - 1) * itemsPerPage + 1
            local endIndex = math.min(currentPage * itemsPerPage, totalItems)
            for i = 1, endIndex - startIndex + 1 do
                local emoteData = emoteList[startIndex + i - 1]
                currentDisplayedEmotes[i] = emoteData
                local angle = math.rad((i * 45) - 135)
                local posX = 0.5 + math.cos(angle) * 0.35
                local posY = 0.5 + math.sin(angle) * 0.35
                local btn = Instance.new("TextButton")
                btn.Name = "EmoteSlice"
                btn.Size = UDim2.fromScale(0.28, 0.28)
                btn.Position = UDim2.fromScale(posX, posY)
                btn.AnchorPoint = Vector2.new(0.5, 0.5)
                btn.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
                btn.BackgroundTransparency = 1
                btn.ZIndex = 5
                btn.Text = tostring(emoteData.name or "Emote") .. "\n" .. tostring(i)
                btn.TextColor3 = Color3.fromRGB(240, 240, 250)
                btn.Font = Enum.Font.GothamMedium
                btn.TextSize = 10
                btn.TextWrapped = true
                btn.AutoButtonColor = false
                btn.Parent = wheelContainer
                btn.Activated:Connect(function()
                    playEmote(emoteData.id, emoteData.song)
                    wheelFrame.Visible = false
                end)
            end
        end

        prevBtn.Activated:Connect(function() renderPage(currentPage - 1) end)
        nextBtn.Activated:Connect(function() renderPage(currentPage + 1) end)

        local numberKeys = {
            [Enum.KeyCode.One] = 1, [Enum.KeyCode.KeypadOne] = 1,
            [Enum.KeyCode.Two] = 2, [Enum.KeyCode.KeypadTwo] = 2,
            [Enum.KeyCode.Three] = 3, [Enum.KeyCode.KeypadThree] = 3,
            [Enum.KeyCode.Four] = 4, [Enum.KeyCode.KeypadFour] = 4,
            [Enum.KeyCode.Five] = 5, [Enum.KeyCode.KeypadFive] = 5,
            [Enum.KeyCode.Six] = 6, [Enum.KeyCode.KeypadSix] = 6,
            [Enum.KeyCode.Seven] = 7, [Enum.KeyCode.KeypadSeven] = 7,
            [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.KeypadEight] = 8,
        }
        emoteInputConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed or not emoteEnabled then return end
            if input.KeyCode == Enum.KeyCode.G then
                toggleWheel()
                return
            end
            if wheelFrame.Visible then
                if input.KeyCode == Enum.KeyCode.M then renderPage(currentPage + 1); return end
                if input.KeyCode == Enum.KeyCode.N then renderPage(currentPage - 1); return end
                local slot = numberKeys[input.KeyCode]
                local selected = slot and currentDisplayedEmotes[slot]
                if selected then
                    playEmote(selected.id, selected.song)
                    wheelFrame.Visible = false
                end
            end
        end)

        local floatingHolder = Instance.new("Frame")
        floatingHolder.Name = "EmoteWheelFloatingButton"
        floatingHolder.AnchorPoint = Vector2.new(1, 0)
        floatingHolder.Position = UDim2.new(0.94, 0, 0.009, 0)
        floatingHolder.Size = UDim2.new(0, 64, 0, 64)
        floatingHolder.BackgroundTransparency = 1
        floatingHolder.Parent = emoteGui
        -- Compact TianHub-style launcher: text replaces the old emote image.
        -- The holder and button dimensions stay unchanged.
        local floatingButton = Instance.new("TextButton")
        floatingButton.Name = "Emote"
        floatingButton.AnchorPoint = Vector2.new(0.5, 0.5)
        floatingButton.Position = UDim2.fromScale(0.5, 0.5)
        floatingButton.Size = UDim2.fromScale(0.72, 0.72)
        floatingButton.BackgroundColor3 = Color3.fromRGB(8, 12, 22)
        floatingButton.BackgroundTransparency = 0
        floatingButton.Text = ""
        floatingButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        floatingButton.Font = Enum.Font.GothamBold
        floatingButton.TextScaled = true
        floatingButton.TextWrapped = false
        floatingButton.AutoButtonColor = false
        floatingButton.Parent = floatingHolder
        Instance.new("UIAspectRatioConstraint", floatingButton).AspectRatio = 1
        Instance.new("UICorner", floatingButton).CornerRadius = UDim.new(1, 0)

        local wheelButtonArtwork = Instance.new("ImageLabel")
        wheelButtonArtwork.Name = "TianHubMenuButtonArtwork"
        wheelButtonArtwork.Size = UDim2.fromScale(1, 1)
        wheelButtonArtwork.BackgroundTransparency = 1
        wheelButtonArtwork.Image = "rbxassetid://80369014097246"
        wheelButtonArtwork.ImageTransparency = 0.12
        wheelButtonArtwork.ScaleType = Enum.ScaleType.Crop
        wheelButtonArtwork.ZIndex = floatingButton.ZIndex + 1
        wheelButtonArtwork.Parent = floatingButton
        Instance.new("UICorner", wheelButtonArtwork).CornerRadius = UDim.new(1, 0)

        local wheelButtonShade = Instance.new("Frame")
        wheelButtonShade.Name = "ArtworkShade"
        wheelButtonShade.Size = UDim2.fromScale(1, 1)
        wheelButtonShade.BackgroundColor3 = Color3.fromRGB(3, 7, 16)
        wheelButtonShade.BackgroundTransparency = 1
        wheelButtonShade.BorderSizePixel = 0
        wheelButtonShade.ZIndex = floatingButton.ZIndex + 2
        wheelButtonShade.Parent = floatingButton
        Instance.new("UICorner", wheelButtonShade).CornerRadius = UDim.new(1, 0)

        local wheelButtonText = Instance.new("TextLabel")
        wheelButtonText.Name = "EmoteLabel"
        wheelButtonText.Size = UDim2.fromScale(1, 1)
        wheelButtonText.BackgroundTransparency = 1
        wheelButtonText.Text = "EMOT"
        wheelButtonText.TextColor3 = Color3.fromRGB(255, 255, 255)
        wheelButtonText.Font = Enum.Font.GothamBold
        wheelButtonText.TextScaled = true
        wheelButtonText.ZIndex = floatingButton.ZIndex + 3
        wheelButtonText.Parent = floatingButton
        local wheelButtonTextLimit = Instance.new("UITextSizeConstraint")
        wheelButtonTextLimit.MinTextSize = 9
        wheelButtonTextLimit.MaxTextSize = 14
        wheelButtonTextLimit.Parent = wheelButtonText

        local textLimit = Instance.new("UITextSizeConstraint")
        textLimit.MinTextSize = 9
        textLimit.MaxTextSize = 14
        textLimit.Parent = floatingButton

        -- Purple-to-blue button fill; no image or external background.
        local btnGradient = Instance.new("UIGradient")
        btnGradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(145, 35, 255)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(70, 55, 245)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(25, 145, 255)),
        })
        btnGradient.Rotation = 25
        btnGradient.Parent = floatingButton

        -- White rounded outline with a subtle white/lilac/blue gradient.
        local btnStroke = Instance.new("UIStroke")
        btnStroke.Color = Color3.fromRGB(255, 255, 255)
        btnStroke.Thickness = 1.6
        btnStroke.Transparency = 0
        btnStroke.Parent = floatingButton

        local strokeGradient = Instance.new("UIGradient")
        strokeGradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(235, 232, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 245, 255)),
        })
        strokeGradient.Rotation = 25
        strokeGradient.Parent = btnStroke

        floatingButton.Activated:Connect(toggleWheel)

        emoteRemovingConn = LocalPlayer.CharacterRemoving:Connect(stopEmote)

        task.spawn(function()
            local ok, result = pcall(function()
                return game:HttpGet("https://pastebin.com/raw/DVUbsm3x")
            end)
            if not ok or not emoteEnabled or not emoteGui or not emoteGui.Parent then return end
            local decodedOk, data = pcall(function() return HttpService:JSONDecode(result) end)
            if not decodedOk or type(data) ~= "table" then
                pageText.Text = "LOAD FAILED"
                return
            end
            for _, item in pairs(data) do
                local validId = item.id and tostring(item.id) ~= "" and tostring(item.id) ~= "0"
                local nameLower = string.lower(tostring(item.name or ""))
                local excluded = string.find(nameLower, "emotold") or string.find(nameLower, "modelold")
                if validId and not excluded then table.insert(emoteList, item) end
            end
            table.sort(emoteList, function(a, b)
                return string.lower(tostring(a.name or "")) < string.lower(tostring(b.name or ""))
            end)
            renderPage(1)
        end)
    end

    local EmoteSection = CreateSection("Main", "EMOTE WHEEL", false)
    CreateToggle(EmoteSection, "Emote Wheel", false, function(enabled)
        emoteEnabled = enabled
        if enabled then
            buildEmoteWheel()
        else
            stopEmote()
            if emoteInputConn then emoteInputConn:Disconnect(); emoteInputConn = nil end
            if emoteRemovingConn then emoteRemovingConn:Disconnect(); emoteRemovingConn = nil end
            if emoteGui then emoteGui:Destroy(); emoteGui = nil end
        end
    end)
end, function(e) logQuiet("[TianHub] emote wheel error: " .. tostring(e)) end)

xpcall(function()
    local SK = { Conns = {} }

    local function clear()
        for _, c in ipairs(SK.Conns) do pcall(function() c:Disconnect() end) end
        SK.Conns = {}
    end

    local function apply(loadMode)
        clear()
        local cam = workspace.CurrentCamera

        pcall(function()
            local remotes = ReplicatedStorage:FindFirstChild("Remotes")
            if not remotes then return end
            local function killConns(ev)
                if ev and ev:IsA("RemoteEvent") and getconnections then
                    for _, c in ipairs(getconnections(ev.OnClientEvent)) do
                        pcall(function() c:Disable() end)
                        pcall(function() c:Disconnect() end)
                    end
                end
            end
            local g = remotes:FindFirstChild("Game")
            if g then
                for _, n in ipairs({ "cutscene", "cutsceneEnd", "cutsceneEnd2", "endscreencutscene", "cutsceneEndwithownchar", "shake" }) do
                    killConns(g:FindFirstChild(n))
                end
            end
            local k = remotes:FindFirstChild("Killers")
            if k then killConns(k:FindFirstChild("Startmori")) end
            if loadMode then killConns(remotes:FindFirstChild("Darkness2")) end
        end)

        local camBusy = false
        local function fixCam()
            if cam and cam.CameraType == Enum.CameraType.Scriptable then
                camBusy = true
                cam.CameraType = Enum.CameraType.Custom
                camBusy = false
            end
        end
        if cam then
            fixCam()
            table.insert(SK.Conns, cam:GetPropertyChangedSignal("CameraType"):Connect(function()
                if not camBusy then fixCam() end
            end))
        end
        table.insert(SK.Conns, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
            cam = workspace.CurrentCamera
            fixCam()
        end))

        local attrBusy = false
        for _, attr in ipairs({ "isspectating", "killerend" }) do
            table.insert(SK.Conns, LocalPlayer:GetAttributeChangedSignal(attr):Connect(function()
                if attrBusy then return end
                if LocalPlayer:GetAttribute(attr) then
                    attrBusy = true
                    LocalPlayer:SetAttribute(attr, false)
                    attrBusy = false
                end
            end))
        end

        local function stripWorld()
            local map = workspace:FindFirstChild("Map")
            local es = map and map:FindFirstChild("endscreen")
            if es then pcall(function() es.Parent = nil end) end
            local bs = workspace:FindFirstChild("BackgroundSounds")
            if bs then pcall(function() bs:Destroy() end) end
        end
        stripWorld()
        table.insert(SK.Conns, workspace.DescendantAdded:Connect(function(d)
            if d.Name == "endscreen" and d.Parent and d.Parent.Name == "Map" then
                task.wait(0.01)
                pcall(function() d.Parent = nil end)
            elseif d.Name == "BackgroundSounds" then
                pcall(function() d:Destroy() end)
            end
        end))

        local function processGui(g)
            if not g or not g.Parent then return end
            pcall(function()
                if loadMode and g.Name == "Darkness" and g:IsA("ScreenGui") then g.Enabled = false end
                for _, d in ipairs(g:GetDescendants()) do
                    if d:IsA("VideoFrame") then
                        d:Destroy()
                    elseif d:IsA("Frame") and (d.Name == "Frame2" or d.Name == "blackout") then
                        d.BackgroundTransparency = 1
                        if loadMode then
                            d.Visible = false
                            d:GetPropertyChangedSignal("BackgroundTransparency"):Connect(function()
                                if d.BackgroundTransparency < 1 then d.BackgroundTransparency = 1 end
                            end)
                            d:GetPropertyChangedSignal("Visible"):Connect(function()
                                if d.Visible then d.Visible = false end
                            end)
                        end
                    elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
                        d.Enabled = false
                    end
                end
            end)
        end
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui")
        local function isTarget(n) return n == "Darkness" or n == "EndScreen" or n == "Cutscene" or n == "Results" end
        for _, g in ipairs(pg:GetChildren()) do
            if isTarget(g.Name) then processGui(g) end
        end
        table.insert(SK.Conns, pg.ChildAdded:Connect(function(g)
            if isTarget(g.Name) then
                task.wait(0.05)
                processGui(g)
            end
        end))
    end

    local SkipSection = CreateSection(VisualTab, "SKIP CUTSCENE", false)
    CreateToggle(SkipSection, "Skip End Screen", false, function(v)
        if v then
            local other = ToggleRegistry["skip_loading_&_end_screen"]
            if other and other.getState() then other.setState(false, true) end
            apply(false)
        else
            clear()
        end
    end)
    CreateToggle(SkipSection, "Skip Loading & End Screen", false, function(v)
        if v then
            local other = ToggleRegistry["skip_end_screen"]
            if other and other.getState() then other.setState(false, true) end
            apply(true)
        else
            clear()
        end
    end)
end, function(e) logQuiet("[TianHub] skip cutscene error: " .. tostring(e)) end)

xpcall(function()
    -- TIANHUB FAKE AVATAR — includes 15 avatar presets.
    local FakeAvatarSection = CreateSection(VisualTab, "FAKE AVATAR", false)
    local FakeAvatarEnabled = false
    local SelectedFakeAva = LocalPlayer.UserId
    local UsernameInput = ""
    local FakeAvatarPresets = {
        "Self Avatar", "xn1vyu", "nurblomst2013", "kino_yk", "nvratee",
        "Sakaryle", "Grouchy1400", "Kill_xsu", "Jahxure", "IIIlIIllIlIIIlII",
        "LordTherion", "xKami3D", "116vv", "444jamesss", "kiicaine",
        "fluvvvvy", "laikaa116", "d4vourz", "penyihirkoji", "itzSannz",
        "cinhsi", "ausenndipity", "GatoVeZ77", "y0urchocoo", "REZZ_MODEO",
        "Rev_Z6p", "4Dliii", "EDENinabobo", "farrooy", "judann_7",
        "ottawa4321", "kazeewww", "erxzha", "lakotree_Doang", "ybvarrr",
        "ba1mmms", "Anett_oooo",
    }
    local FakeAvatarUserIdCache = { ["Self Avatar"] = LocalPlayer.UserId }
    local function GetFakeAvatarUserId(name)
        if name == "Self Avatar" then return LocalPlayer.UserId end
        local cached = FakeAvatarUserIdCache[name]
        if cached then return cached end
        local userId = Players:GetUserIdFromNameAsync(name)
        FakeAvatarUserIdCache[name] = userId
        return userId
    end

    local function LoadAppearanceIntoChar(appearance, character, head)
        local items = appearance:GetChildren()
        local function applyMesh(obj)
            if obj:IsA("CharacterMesh") or obj:IsA("BodyColors") or obj:IsA("Shirt") or obj:IsA("Pants") then
                local existing = character:FindFirstChild(obj.Name)
                if existing and existing.ClassName == obj.ClassName then existing:Destroy() end
                obj:Clone().Parent = character
            end
        end
        for _, item in pairs(items) do
            if item:IsA("Folder") or item:IsA("Model") then
                for _, subItem in pairs(item:GetChildren()) do applyMesh(subItem) end
            else
                applyMesh(item)
            end
        end
        for _, item in pairs(items) do
            if item:IsA("SpecialMesh") and head then
                local targetMesh = head:FindFirstChildOfClass("SpecialMesh") or Instance.new("SpecialMesh", head)
                targetMesh.MeshType = Enum.MeshType.FileMesh
                targetMesh.MeshId = item.MeshId
                targetMesh.TextureId = item.TextureId
            elseif item:IsA("Decal") and item.Name == "face" and head then
                if head:FindFirstChild("face") then head.face:Destroy() end
                item:Clone().Parent = head
            end
        end
        for _, item in pairs(items) do
            if item:IsA("Accessory") then
                local clone = item:Clone()
                local handle = clone:FindFirstChild("Handle")
                if handle then
                    local att = handle:FindFirstChildOfClass("Attachment")
                    if att then
                        local targetAtt = character:FindFirstChild(att.Name, true)
                        if targetAtt then
                            local weld = Instance.new("Weld")
                            weld.Part0 = handle
                            weld.Part1 = targetAtt.Parent
                            weld.C0 = att.CFrame
                            weld.C1 = targetAtt.CFrame
                            weld.Parent = handle
                        end
                    end
                    handle.CanCollide = false
                    handle.Massless = true
                    clone.Parent = character
                else
                    clone:Destroy()
                end
            end
        end
    end

    local function ApplyFakeAvatar()
        local character = LocalPlayer.Character
        if not character or not SelectedFakeAva then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid then return end
        local requestedUserId = SelectedFakeAva
        task.spawn(function()
            local success, appearance = pcall(function()
                return Players:GetCharacterAppearanceAsync(requestedUserId)
            end)
            if not success or not appearance then
                ShowToast("Fake Avatar", "Gagal load data avatar!")
                return
            end
            if LocalPlayer.Character ~= character then return end
            for _, obj in pairs(character:GetChildren()) do
                if obj:IsA("Accessory") or obj:IsA("Shirt") or obj:IsA("Pants")
                    or obj:IsA("BodyColors") or obj:IsA("CharacterMesh") or obj:IsA("ShirtGraphic") then
                    obj:Destroy()
                end
            end
            local head = character:FindFirstChild("Head")
            if head then
                for _, hObj in pairs(head:GetChildren()) do
                    if hObj:IsA("SpecialMesh") or hObj:IsA("Decal") then hObj:Destroy() end
                end
                local mesh = Instance.new("SpecialMesh", head)
                mesh.MeshType = Enum.MeshType.Head
                mesh.Scale = Vector3.new(1, 1, 1)
            end
            local scaleDefaults = { BodyDepthScale = 1, BodyHeightScale = 1, BodyWidthScale = 1, HeadScale = 1, BodyTypeScale = 0, BodyProportionScale = 0 }
            for scaleName, value in pairs(scaleDefaults) do
                local scale = humanoid:FindFirstChild(scaleName)
                if scale then scale.Value = value end
            end
            task.wait(0.1)
            LoadAppearanceIntoChar(appearance, character, head)
            pcall(function()
                local info = Players:GetCharacterAppearanceInfoAsync(requestedUserId)
                if head and info and info.assets then
                    for _, asset in pairs(info.assets) do
                        if asset.assetType and asset.assetType.name == "Face" then
                            if head:FindFirstChild("face") then head.face:Destroy() end
                            local face = Instance.new("Decal", head)
                            face.Name = "face"
                            face.Texture = "rbxassetid://" .. tostring(asset.id)
                            break
                        end
                    end
                end
            end)
            ShowToast("Fake Avatar", "Preset berhasil diterapkan")
        end)
    end

    local function resolveFakeAvatarName(name)
        if name == "Self Avatar" then
            SelectedFakeAva = LocalPlayer.UserId
            if FakeAvatarEnabled then ApplyFakeAvatar() end
            return
        end
        task.spawn(function()
            local ok, userId = pcall(function() return GetFakeAvatarUserId(name) end)
            if not ok or not userId then
                ShowToast("Fake Avatar", "Username tidak ditemukan: " .. tostring(name))
                return
            end
            SelectedFakeAva = userId
            if FakeAvatarEnabled then ApplyFakeAvatar() end
        end)
    end

    TianHubState.CreateDropdown(FakeAvatarSection, "Fake Avatar Preset", FakeAvatarPresets, "Self Avatar", function(option)
        local name = type(option) == "table" and option[1] or option
        if name then resolveFakeAvatarName(name) end
    end, function(name)
        return GetFakeAvatarUserId(name)
    end)
    CreateToggle(FakeAvatarSection, "Enable Fake Avatar", false, function(state)
        FakeAvatarEnabled = state
        if state then ApplyFakeAvatar() end
    end)
    CreateTextBox(FakeAvatarSection, "Fake Avatar Via Username", "username (tanpa @)", function(value)
        UsernameInput = tostring(value or ""):gsub("^@", "")
    end)
    CreateButton(FakeAvatarSection, "Apply From Username", function()
        if UsernameInput == "" then
            ShowToast("Fake Avatar", "Masukkan username dulu!")
            return
        end
        task.spawn(function()
            local ok, userId = pcall(function() return GetFakeAvatarUserId(UsernameInput) end)
            if not ok or not userId then
                ShowToast("Fake Avatar", "Username tidak ditemukan: " .. UsernameInput)
                return
            end
            SelectedFakeAva = userId
            FakeAvatarEnabled = true
            ApplyFakeAvatar()
            ShowToast("Fake Avatar", "Applied: @" .. UsernameInput)
        end)
    end, true)
    LocalPlayer.CharacterAdded:Connect(function()
        if FakeAvatarEnabled then task.wait(1); ApplyFakeAvatar() end
    end)



--====================================================--
-- TIANHUB FAKE AKSESORIS 8BIT SYSTEM (11 ITEMS)
-- TianHub accessory system; toggle labels only, no descriptions.
--====================================================--
xpcall(function()
    local Aks = {
        List = {
            {"8 Bit Royal Crown", 10159600649},
            {"Verdant Crown", 13241836994},
            {"Extra Domino Top Hat", 17266399676},
            {"Frozen Horns", 74891470},
            {"Poisoned Horns", 1744060292},
            {"Fiery Horns of the Netherworld", 215718515},
            {"Valkyrie Helm", 1365767},
            {"8-Bit HP Bar", 10159610478},
            {"8-Bit Tabby Cat", 10159617728},
            {"8-Bit Roblox Coin", 10159622004},
            {"Spring Fairy", 150381051},
        },
        Active = {},
        Enabled = {},
    }

    local function findAttachment(character, name)
        for _, d in ipairs(character:GetDescendants()) do
            if d:IsA("Attachment") and d.Name == name then
                local part = d.Parent
                if part and part:IsA("BasePart") and part.Parent == character then
                    return d
                end
            end
        end
    end

    local function attachAccessory(character, accessory)
        local head = character:FindFirstChild("Head")
        local handle = accessory:FindFirstChild("Handle") or accessory:FindFirstChild("Handle", true)
        if not handle or not head then return end
        for _, joint in ipairs(handle:GetChildren()) do
            if joint:IsA("Weld") or joint:IsA("WeldConstraint") or joint:IsA("Motor6D") then
                if joint.Part1 and joint.Part1.Parent == character then return end
                joint:Destroy()
            end
        end
        local attachment = handle:FindFirstChildOfClass("Attachment")
        local target = attachment and findAttachment(character, attachment.Name)
        local base = head
        if target then
            base = target.Parent
            handle.CFrame = target.WorldCFrame * attachment.CFrame:Inverse()
        else
            handle.CFrame = head.CFrame * CFrame.new(0, 0.7, 0)
        end
        local weld = Instance.new("Weld")
        weld.Name = "AccessoryWeld_TianHub"
        weld.Part0 = handle
        weld.Part1 = base
        weld.C0 = CFrame.new()
        weld.C1 = base.CFrame:ToObjectSpace(handle.CFrame)
        weld.Parent = handle
    end

    local function removeAccessory(id)
        local active = Aks.Active[id]
        if active then
            for _, object in ipairs(active) do
                pcall(function() object:Destroy() end)
            end
        end
        Aks.Active[id] = nil
        local character = LocalPlayer.Character
        if character then
            for _, d in ipairs(character:GetDescendants()) do
                if d:GetAttribute("TianHub_Accessory") == id then
                    pcall(function() d:Destroy() end)
                end
            end
        end
    end

    local function loadAccessory(id)
        local ok, object = pcall(function()
            return game:GetObjects("rbxassetid://" .. tostring(id))[1]
        end)
        if ok then return object end
        return nil
    end

    local function applyAccessory(id)
        removeAccessory(id)
        local character = LocalPlayer.Character
        if not character then return false end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid then return false end
        local object = loadAccessory(id)
        if not object then return false end
        local accessories = {}
        if object:IsA("Accoutrement") then table.insert(accessories, object) end
        for _, d in ipairs(object:GetDescendants()) do
            if d:IsA("Accoutrement") then table.insert(accessories, d) end
        end
        if #accessories == 0 then
            if not object:FindFirstChild("Handle", true) then
                pcall(function() object:Destroy() end)
                return false
            end
            table.insert(accessories, object)
        end
        local applied = {}
        for _, accessory in ipairs(accessories) do
            local handle = accessory:FindFirstChild("Handle") or accessory:FindFirstChild("Handle", true)
            if handle then
                handle.Anchored = false
                handle.CanCollide = false
                handle.Massless = true
                accessory:SetAttribute("TianHub_Accessory", id)
                handle:SetAttribute("TianHub_Accessory", id)
                if accessory:IsA("Accoutrement") then
                    pcall(function() humanoid:AddAccessory(accessory) end)
                else
                    accessory.Parent = character
                end
                table.insert(applied, accessory)
            end
        end
        if #applied == 0 then
            pcall(function() object:Destroy() end)
            return false
        end
        task.wait(0.3)
        for _, accessory in ipairs(applied) do
            if accessory.Parent ~= character then accessory.Parent = character end
            attachAccessory(character, accessory)
        end
        Aks.Active[id] = applied
        return true
    end

    local function setAccessory(id, enabled)
        Aks.Enabled[id] = enabled and true or false
        if enabled then
            return applyAccessory(id)
        end
        removeAccessory(id)
        return true
    end


    local accessorySection = CreateSection(VisualTab, "Fake Aksesoris 8Bit", false)
    for _, item in ipairs(Aks.List) do
        local itemName, itemId = item[1], item[2]
        CreateToggle(accessorySection, itemName, false, function(enabled)
            setAccessory(itemId, enabled)
            ShowToast("Aksesoris", itemName .. (enabled and " ON" or " OFF"))
        end)
    end

    LocalPlayer.CharacterAdded:Connect(function()
        task.wait(1.5)
        for _, item in ipairs(Aks.List) do
            local id = item[2]
            if Aks.Enabled[id] then
                task.spawn(function() applyAccessory(id) end)
                task.wait(0.35)
            end
        end
    end)
end, function(e)
    logQuiet("[TianHub] Fake Aksesoris 8Bit error: " .. tostring(e))
end)


end, function(e) logQuiet("[TianHub] avatar copy error: " .. tostring(e)) end)


local VisualCamera = CreateSection(VisualTab, "FIELD OF VIEW", false)

-- Infinity Zoom: TianHub behavior.
CreateToggle(VisualCamera, "Unlimited Zoom", false, function(enabled)
    pcall(function()
        if enabled then
            LocalPlayer.CameraMaxZoomDistance = math.huge
            LocalPlayer.CameraMinZoomDistance = 0
        else
            LocalPlayer.CameraMaxZoomDistance = 12
            LocalPlayer.CameraMinZoomDistance = 0.5
        end
    end)
end)

-- Custom FOV and Lock FOV are independent toggles; Lock FOV takes priority.
local cameraFovState = {
    CustomEnabled = false,
    CustomValue = 70,
    LockEnabled = false,
    LockValue = 80,
    OriginalByCamera = setmetatable({}, { __mode = "k" }),
}

CreateToggle(VisualCamera, "Custom FOV", false, function(enabled)
    cameraFovState.CustomEnabled = enabled and true or false
end)
CreateSlider(VisualCamera, "FOV", 40, 120, 70, " deg", function(v)
    cameraFovState.CustomValue = math.clamp(tonumber(v) or 70, 40, 120)
end)

CreateToggle(VisualCamera, "Lock FOV", false, function(enabled)
    cameraFovState.LockEnabled = enabled and true or false
end)
CreateSlider(VisualCamera, "Lock FOV Value", 40, 120, 80, " deg", function(v)
    cameraFovState.LockValue = math.clamp(tonumber(v) or 80, 40, 120)
end)

-- Re-apply camera settings each frame because some games overwrite them.
pcall(function() RunService:UnbindFromRenderStep("Tian_CameraControls") end)
RunService:BindToRenderStep("Tian_CameraControls", Enum.RenderPriority.Last.Value + 2, function()
    local cam = workspace.CurrentCamera
    if not cam then return end

    local targetFov
    if cameraFovState.LockEnabled then
        targetFov = cameraFovState.LockValue
    elseif cameraFovState.CustomEnabled then
        targetFov = cameraFovState.CustomValue
    end

    if targetFov then
        if cameraFovState.OriginalByCamera[cam] == nil then
            cameraFovState.OriginalByCamera[cam] = cam.FieldOfView
        end
        if math.abs(cam.FieldOfView - targetFov) > 0.05 then
            cam.FieldOfView = targetFov
        end
    elseif next(cameraFovState.OriginalByCamera) ~= nil then
        for savedCamera, originalFov in pairs(cameraFovState.OriginalByCamera) do
            if savedCamera then
                pcall(function() savedCamera.FieldOfView = originalFov end)
            end
            cameraFovState.OriginalByCamera[savedCamera] = nil
        end
    end
end)

-- Crosshair overlay with compact controls, styled to match TianHub.
xpcall(function()
    local Crosshair = { Enabled = false, Style = "Dot", Size = 8, Thickness = 2, OffsetX = 0, OffsetY = 0, Color = Color3.fromRGB(255, 255, 255), Gui = nil, Parts = {} }
    local function clearCrosshair()
        if Crosshair.Gui then pcall(function() Crosshair.Gui:Destroy() end) end
        Crosshair.Gui = nil
        Crosshair.Parts = {}
    end
    local function makeCrosshair()
        clearCrosshair()
        if not Crosshair.Enabled then return end
        local gui = Instance.new("ScreenGui")
        gui.Name = "TianCrosshairUI"
        gui.IgnoreGuiInset = true
        gui.ResetOnSpawn = false
        gui.DisplayOrder = 999
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        gui.Parent = CoreGui
        Crosshair.Gui = gui
        local function frame(size, position)
            local f = Instance.new("Frame")
            f.BorderSizePixel = 0
            f.BackgroundColor3 = Crosshair.Color
            f.AnchorPoint = Vector2.new(0.5, 0.5)
            f.Size = size
            f.Position = position
            f.ZIndex = 999
            f.Parent = gui
            table.insert(Crosshair.Parts, f)
            return f
        end
        local center = UDim2.new(0.5, Crosshair.OffsetX, 0.5, Crosshair.OffsetY)
        if Crosshair.Style == "Plus" then
            frame(UDim2.fromOffset(Crosshair.Size * 2, Crosshair.Thickness), center)
            frame(UDim2.fromOffset(Crosshair.Thickness, Crosshair.Size * 2), center)
        elseif Crosshair.Style == "Circle" then
            local f = frame(UDim2.fromOffset(Crosshair.Size * 2, Crosshair.Size * 2), center)
            f.BackgroundTransparency = 1
            local stroke = Instance.new("UIStroke")
            stroke.Color = Crosshair.Color
            stroke.Thickness = Crosshair.Thickness
            stroke.Parent = f
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(1, 0)
            corner.Parent = f
        else
            local f = frame(UDim2.fromOffset(Crosshair.Size, Crosshair.Size), center)
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(1, 0)
            corner.Parent = f
        end
    end
    local function refreshCrosshair()
        if not Crosshair.Enabled then clearCrosshair(); return end
        makeCrosshair()
    end
    local CrosshairSection = CreateSection(VisualTab, "CROSSHAIR", false)
    CreateToggle(CrosshairSection, "Enable Crosshair", false, function(v)
        Crosshair.Enabled = v
        refreshCrosshair()
    end)
    TianHubState.CreateDropdown(CrosshairSection, "Crosshair Style", {"Dot", "Plus", "Circle"}, "Dot", function(v)
        Crosshair.Style = v
        refreshCrosshair()
    end)
    CreateSlider(CrosshairSection, "Crosshair Size", 2, 30, 8, " px", function(v)
        Crosshair.Size = tonumber(v) or 8
        refreshCrosshair()
    end)
    CreateSlider(CrosshairSection, "Crosshair Thickness", 1, 8, 2, " px", function(v)
        Crosshair.Thickness = tonumber(v) or 2
        refreshCrosshair()
    end)
    CreateSlider(CrosshairSection, "Crosshair Offset X", -300, 300, 0, " px", function(v)
        Crosshair.OffsetX = tonumber(v) or 0
        refreshCrosshair()
    end)
    CreateSlider(CrosshairSection, "Crosshair Offset Y", -300, 300, 0, " px", function(v)
        Crosshair.OffsetY = tonumber(v) or 0
        refreshCrosshair()
    end)
    CreateColorPicker(CrosshairSection, "Crosshair Color", Crosshair.Color, function(c)
        Crosshair.Color = c
        refreshCrosshair()
    end)
    setConn("Tian_CrosshairCleanup", LocalPlayer.CharacterAdded:Connect(function()
        task.delay(0.5, function() if Crosshair.Enabled then refreshCrosshair() end end)
    end))
end, function(e) logQuiet("[TianHub] crosshair error: " .. tostring(e)) end)


-- ============================================================
-- TIANHUB KILLER INTEGRATION - STAGE 1: AUTO ATTACK + INFINITE LUNGE
-- Native TianHub controls for the Killer backend.
-- ============================================================
do
    local KillerCombatState = getgenv().TianHub_KillerCombat or {}
    getgenv().TianHub_KillerCombat = KillerCombatState
    KillerCombatState.AutoAttack = KillerCombatState.AutoAttack == true
    KillerCombatState.AttackRange = math.clamp(tonumber(KillerCombatState.AttackRange) or 12, 5, 30)
    KillerCombatState.AttackCooldown = math.clamp(tonumber(KillerCombatState.AttackCooldown) or 0.15, 0.05, 1)
    KillerCombatState.InfiniteLunge = KillerCombatState.InfiniteLunge == true

    local lastAutoAttack = 0
    local lungeOriginal = nil
    local lungeCharacter = nil

    local function isTianHubKiller()
        return LocalPlayer and LocalPlayer.Team and string.lower(LocalPlayer.Team.Name) == "killer"
    end

    local function restoreLunge()
        if lungeCharacter and lungeCharacter.Parent and lungeOriginal ~= nil then
            pcall(function() lungeCharacter:SetAttribute("lungeboost", lungeOriginal) end)
        end
        lungeOriginal = nil
        lungeCharacter = nil
    end

    local function updateInfiniteLunge()
        local character = LocalPlayer.Character
        if not character then restoreLunge(); return end
        if not isTianHubKiller() or not KillerCombatState.InfiniteLunge then
            restoreLunge()
            return
        end
        if lungeCharacter ~= character then
            restoreLunge()
            lungeCharacter = character
            lungeOriginal = character:GetAttribute("lungeboost")
            if lungeOriginal == nil then lungeOriginal = 1 end
        end
        if character:GetAttribute("lungeboost") ~= 999999 then
            pcall(function() character:SetAttribute("lungeboost", 999999) end)
        end
    end

    local function runAutoAttack()
        if not KillerCombatState.AutoAttack or not isTianHubKiller() then return end
        local now = os.clock()
        if now - lastAutoAttack < KillerCombatState.AttackCooldown then return end
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local closest, shortest = nil, KillerCombatState.AttackRange
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Team and string.find(string.lower(player.Team.Name), "survivor", 1, true) and player.Character then
                local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
                local targetRoot = player.Character:FindFirstChild("HumanoidRootPart")
                if humanoid and targetRoot and humanoid.Health > 35 then
                    local distance = (targetRoot.Position - root.Position).Magnitude
                    if distance <= shortest then shortest, closest = distance, player end
                end
            end
        end
        if not closest then return end
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local attacks = remotes and remotes:FindFirstChild("Attacks")
        local basicAttack = attacks and attacks:FindFirstChild("BasicAttack")
        if basicAttack and basicAttack:IsA("RemoteEvent") then
            lastAutoAttack = now
            pcall(function() basicAttack:FireServer(false) end)
        end
    end

    local combatSection = CreateSection(KillerTab, "KILLER COMBAT", false)
    CreateToggle(combatSection, "Enable Auto Attack", KillerCombatState.AutoAttack, function(value)
        KillerCombatState.AutoAttack = value == true
        if value then TianHub_Notify("Auto Attack", "Enabled", 2) end
    end)
    CreateSlider(combatSection, "Attack Range", 5, 30, KillerCombatState.AttackRange, " studs", function(value)
        KillerCombatState.AttackRange = math.clamp(tonumber(value) or 12, 5, 30)
    end, 0)
    CreateSlider(combatSection, "Attack Cooldown", 0.05, 1, KillerCombatState.AttackCooldown, "s", function(value)
        KillerCombatState.AttackCooldown = math.clamp(tonumber(value) or 0.15, 0.05, 1)
    end, 2)
    CreateToggle(combatSection, "Infinite Lunge (Basic Attack)", KillerCombatState.InfiniteLunge, function(value)
        KillerCombatState.InfiniteLunge = value == true
        if not value then restoreLunge() end
    end)

    setConn("TianHub_KillerCombatStage1", RunService.Heartbeat:Connect(function()
        local ok, err = pcall(function()
            runAutoAttack()
            updateInfiniteLunge()
        end)
        if not ok then logQuiet("[TianHub Killer Stage 1] " .. tostring(err)) end
    end))
    setConn("TianHub_KillerCombatCharacter", LocalPlayer.CharacterRemoving:Connect(function(character)
        if lungeCharacter == character then restoreLunge() end
    end))
end

-- ============================================================
-- TIANHUB KILLER INTEGRATION - STAGE 2: COUNTER AUTO PARRY
-- Adapted from the integrated animation set and behavior.
-- Uses native TianHub controls; does not create a second GUI.
-- ============================================================
do
    local CounterState = getgenv().TianHub_KillerCounter or {}
    getgenv().TianHub_KillerCounter = CounterState
    CounterState.Enabled = CounterState.Enabled == true

    -- Exact attack animation IDs used by TianHub Counter Auto Parry.
    local CounterParryAnimIds = {
        "78432063483146", "121216847022485", "74968262036854",
        "132817836308238", "82666958311998", "111920872708571",
        "106871536134254", "109402730355822", "130593238885843",
        "138720291317243", "139369275981139", "133963973694098",
        "78935059863801", "118907603246885", "135002183282873",
        "113255068724446", "129784271201071", "105374834496520",
        "117070354890871", "115244153053858", "110355011987939",
        "117042998468241", "122812055447896",
    }

    local function isCounterKiller()
        local team = LocalPlayer and LocalPlayer.Team
        return team ~= nil and string.find(string.lower(team.Name), "killer", 1, true) ~= nil
    end

    local function hasNearbySurvivor(root)
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Team
                and string.find(string.lower(player.Team.Name), "survivor", 1, true) then
                local character = player.Character
                local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
                if targetRoot and (root.Position - targetRoot.Position).Magnitude <= 15 then
                    return true
                end
            end
        end
        return false
    end

    local function playCounterAnimation()
        local character = LocalPlayer.Character
        if not character then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
        if not animator then return end

        local id = CounterParryAnimIds[math.random(1, #CounterParryAnimIds)]
        local animation = Instance.new("Animation")
        animation.AnimationId = "rbxassetid://" .. id

        local track
        local ok = pcall(function()
            track = animator:LoadAnimation(animation)
            track:Play(0)
            track:AdjustWeight(0)
            task.wait(0.05)
            track:Stop(0)
        end)
        if track then pcall(function() track:Destroy() end) end
        animation:Destroy()
        if not ok then return end
    end

    local counterSection = CreateSection(KillerTab, "COUNTER AUTO PARRY", false)
    CreateToggle(counterSection, "Counter Auto Parry", CounterState.Enabled, function(value)
        CounterState.Enabled = value == true
        if CounterState.Enabled then
            TianHub_Notify("Counter Auto Parry", "Enabled", 2)
        end
    end)

    -- One persistent worker prevents duplicate loops if the script is re-executed.
    if not CounterState.WorkerStarted then
        CounterState.WorkerStarted = true
        task.spawn(function()
            while true do
                task.wait(0.5)
                if CounterState.Enabled and isCounterKiller() then
                    local character = LocalPlayer.Character
                    local root = character and character:FindFirstChild("HumanoidRootPart")
                    if root and hasNearbySurvivor(root) then
                        playCounterAnimation()
                    end
                end
            end
        end)
    end
end

-- ============================================================
-- TIANHUB KILLER INTEGRATION - STAGE 3
-- Ported Killer modules from the integrated source.
-- Stage 1 Auto Attack / Infinite Lunge and Stage 2 Counter Auto Parry
-- remain single-instance and are intentionally not recreated here.
-- ============================================================
do
    local State = getgenv().TianHub_KillerStage3 or {}
    getgenv().TianHub_KillerStage3 = State
    State.AntiBlind = State.AntiBlind == true
    State.DestroyPallets = State.DestroyPallets == true
    State.UnlockCarry = State.UnlockCarry == true
    State.AutoStalk = State.AutoStalk == true
    State.AutoHook = State.AutoHook == true
    State.DropAllPallet = State.DropAllPallet == true
    State.BlockAllVault = State.BlockAllVault == true
    State.AutoStalkRange = math.clamp(tonumber(State.AutoStalkRange) or 150, 20, 500)
    State.MaskedPower = State.MaskedPower or "Cobra"

    local function isKiller()
        return TianHub_IsKiller(LocalPlayer)
    end
    local function notify(title, message)
        pcall(function() TianHub_Notify(title, message, 2) end)
    end
    local function findRemote(...)
        local node = ReplicatedStorage:FindFirstChild("Remotes")
        for _, name in ipairs({...}) do
            node = node and node:FindFirstChild(name)
        end
        return node
    end

    -- Anti Blind: preserve the existing GotBlinded remote interception behavior.
    local function setupAntiBlind()
        if State.AntiBlindHooked or type(getrawmetatable) ~= "function"
            or type(newcclosure) ~= "function" or type(getnamecallmethod) ~= "function"
            or type(checkcaller) ~= "function" then return end
        local gotBlinded = findRemote("Items", "Flashlight", "GotBlinded")
        if not gotBlinded then return end
        local ok, mt = pcall(getrawmetatable, game)
        if not ok or not mt then return end
        pcall(function()
            if setreadonly then setreadonly(mt, false) end
            local old = mt.__namecall
            mt.__namecall = newcclosure(function(self, ...)
                if State.AntiBlind and not checkcaller() and self == gotBlinded
                    and getnamecallmethod() == "FireServer" and isKiller() then
                    return nil
                end
                return old(self, ...)
            end)
            if setreadonly then setreadonly(mt, true) end
            State.AntiBlindHooked = true
        end)
    end

    -- Destroy Pallet: preserving the existing tagged-point and remote sequence.
    local breakingPallet = false
    local CollectionService = game:GetService("CollectionService")
    local function destroyNearestPallet()
        if not State.DestroyPallets or not isKiller() or breakingPallet then return end
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        if char:GetAttribute("IsStunned") or char:GetAttribute("isStunned")
            or char:GetAttribute("Immobile") or char:GetAttribute("immobile")
            or char:GetAttribute("IsCarrying") or char:GetAttribute("isCarrying") then return end
        local check = char:FindFirstChild("CheckInterractable")
        if check and (check:GetAttribute("action") or check:GetAttribute("Action")) then return end
        local nearest, nearestDistance
        for _, point in ipairs(CollectionService:GetTagged("PalletPointSlide")) do
            if point:IsA("BasePart") and not CollectionService:HasTag(point, "doing action") then
                local distance = (point.Position - root.Position).Magnitude
                if distance <= 6 and (not nearestDistance or distance < nearestDistance) then
                    nearest, nearestDistance = point, distance
                end
            end
        end
        if not nearest then return end
        breakingPallet = true
        task.spawn(function()
            pcall(function()
                local remotes = ReplicatedStorage:FindFirstChild("Remotes")
                local jason = remotes and remotes:FindFirstChild("Pallet") and remotes.Pallet:FindFirstChild("Jason")
                local destroy = jason and jason:FindFirstChild("Destroy-Global")
                local commit = jason and jason:FindFirstChild("PalletBreakCommit")
                if destroy and destroy:IsA("RemoteEvent") then destroy:FireServer(nearest) end
                if commit and commit:IsA("RemoteEvent") then commit:FireServer(nearest) end
            end)
            task.wait(0.2)
            local started = os.clock()
            while char.Parent and (char:GetAttribute("Immobile") or char:GetAttribute("immobile")) do
                if os.clock() - started > 3 then break end
                task.wait(0.1)
            end
            breakingPallet = false
        end)
    end

    -- Unlock skill while carrying: original IsCarrying attribute override.
    local function setupCarryHook()
        if State.CarryHooked or type(getrawmetatable) ~= "function"
            or type(newcclosure) ~= "function" or type(getnamecallmethod) ~= "function"
            or type(checkcaller) ~= "function" then return end
        local ok, mt = pcall(getrawmetatable, game)
        if not ok or not mt then return end
        pcall(function()
            if setreadonly then setreadonly(mt, false) end
            local old = mt.__namecall
            mt.__namecall = newcclosure(function(self, ...)
                local method = getnamecallmethod()
                local args = {...}
                if State.UnlockCarry and not checkcaller() and method == "GetAttribute"
                    and args[1] == "IsCarrying" then return false end
                return old(self, ...)
            end)
            if setreadonly then setreadonly(mt, true) end
            State.CarryHooked = true
        end)
    end

    -- Masked Power selector and actions use the existing game remote names.
    local maskedPowers = {"Cobra", "Richter", "Brandon", "Rabbit", "Alex", "Tony"}
    local function maskedAction(action)
        local event = findRemote("Killers", "Masked", action)
        if not event then notify("Select Masked Power", action .. " remote not found"); return end
        pcall(function()
            if action == "Activatepower" then event:FireServer(State.MaskedPower)
            else event:FireServer() end
        end)
        notify("Select Masked Power", action == "Activatepower" and ("Activated: " .. State.MaskedPower) or "Deactivated")
    end

    -- Killer ability: Auto Stalk (Myers), matching the original remote contract.
    local stalkConnection
    local function setAutoStalk(enabled)
        State.AutoStalk = enabled == true
        if stalkConnection then stalkConnection:Disconnect(); stalkConnection = nil end
        if not State.AutoStalk then return end
        stalkConnection = RunService.Heartbeat:Connect(function()
            if not State.AutoStalk or not isKiller() then return end
            local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not myRoot then return end
            local target, bestDistance
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Team and string.find(string.lower(player.Team.Name), "survivor", 1, true) and player.Character then
                    local hum = player.Character:FindFirstChildOfClass("Humanoid")
                    local root = player.Character:FindFirstChild("HumanoidRootPart")
                    if hum and root and hum.Health > 30 then
                        local distance = (root.Position - myRoot.Position).Magnitude
                        if distance <= State.AutoStalkRange and (not bestDistance or distance < bestDistance) then
                            target, bestDistance = player, distance
                        end
                    end
                end
            end
            if target then
                local event = ReplicatedStorage:FindFirstChild("Remotes", true)
                    and ReplicatedStorage.Remotes:FindFirstChild("Killers", true)
                    and ReplicatedStorage.Remotes.Killers:FindFirstChild("Stalker", true)
                    and ReplicatedStorage.Remotes.Killers.Stalker:FindFirstChild("StartStalking")
                if event then pcall(function() event:FireServer(target) end) end
            end
        end)
    end

    local function dropAllPallets()
        if not State.DropAllPallet or not isKiller() then return end
        local event = findRemote("Pallet", "PalletDropEvent")
        local map = workspace:FindFirstChild("Map")
        if not event or not map then return end
        for _, obj in ipairs(map:GetDescendants()) do
            if obj.Name == "Palletwrong" and (obj:IsA("Model") or obj:IsA("Folder")) then
                local point = obj:FindFirstChild("PalletPointSlide") or obj:FindFirstChild("PalletPoint")
                if point then pcall(function() event:FireServer(point) end) end
            end
        end
    end
    local function blockAllVaults()
        if not State.BlockAllVault or not isKiller() then return end
        local event = findRemote("Window", "VaultEvent")
        local map = workspace:FindFirstChild("Map")
        if not event or not map then return end
        for _, trigger in ipairs(map:GetDescendants()) do
            if trigger.Name == "VaultTrigger" then
                pcall(function() event:FireServer(trigger, true) end)
            end
        end
    end

    -- Auto Hook: retain original target/hook discovery and remote sequence.
    local autoHookBusy = false
    local function doAutoHook()
        if not State.AutoHook or not isKiller() or autoHookBusy then return end
        local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not myRoot then return end
        local map = workspace:FindFirstChild("Map")
        if not map then return end
        local hooks = {}
        for _, obj in ipairs(map:GetDescendants()) do
            if obj:IsA("Model") and obj.Name == "Hook" then
                local part = obj:FindFirstChild("HookPoint") or obj:FindFirstChild("HookHitbox") or obj:FindFirstChildWhichIsA("BasePart", true)
                if part then hooks[#hooks + 1] = {model = obj, part = part} end
            end
        end
        if #hooks == 0 then return end
        local targetRoot, targetChar, targetDistance
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Team and string.find(string.lower(player.Team.Name), "survivor", 1, true) and player.Character then
                local char = player.Character
                local root = char:FindFirstChild("HumanoidRootPart")
                local hum = char:FindFirstChildOfClass("Humanoid")
                local pct = hum and hum.MaxHealth > 0 and hum.Health / hum.MaxHealth or 1
                if root and hum and pct > 0 and pct <= 0.25 and char:GetAttribute("IsCarried") ~= true then
                    local onHook = false
                    for _, hook in ipairs(hooks) do
                        if (hook.part.Position - root.Position).Magnitude < 6 then onHook = true; break end
                    end
                    local distance = (root.Position - myRoot.Position).Magnitude
                    if not onHook and (not targetDistance or distance < targetDistance) then
                        targetRoot, targetChar, targetDistance = root, char, distance
                    end
                end
            end
        end
        if not targetRoot then return end
        local nearestHook, hookDistance
        for _, hook in ipairs(hooks) do
            local distance = (hook.part.Position - targetRoot.Position).Magnitude
            if not hookDistance or distance < hookDistance then nearestHook, hookDistance = hook, distance end
        end
        if not nearestHook then return end
        autoHookBusy = true
        task.spawn(function()
            local carry = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("Carry")
            local carryEvent = carry and carry:FindFirstChild("CarrySurvivorEvent")
            local hookEvent = carry and carry:FindFirstChild("HookEvent")
            local hookCommit = carry and carry:FindFirstChild("HookCommit")
            pcall(function() myRoot.CFrame = CFrame.new(targetRoot.Position + Vector3.new(0, 3, 0), targetRoot.Position) end)
            task.wait(0.2)
            pcall(function() if carryEvent then carryEvent:FireServer(targetChar) end end)
            task.wait(0.5)
            local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if root then
                pcall(function() root.CFrame = CFrame.new(nearestHook.part.Position + Vector3.new(0, 3, 0)) end)
                task.wait(0.3)
                local point = nearestHook.model:FindFirstChild("HookPoint") or nearestHook.model:FindFirstChild("HookHitbox") or nearestHook.part
                pcall(function() if hookEvent then hookEvent:FireServer(point) end; if hookCommit then hookCommit:FireServer(point) end end)
            end
            task.wait(1)
            autoHookBusy = false
        end)
    end

    local antiBlindSection = CreateSection(KillerTab, "ANTI BLIND", false)
    CreateToggle(antiBlindSection, "Anti Blind (Flashlight)", State.AntiBlind, function(value)
        State.AntiBlind = value == true
        if State.AntiBlind then setupAntiBlind(); notify("Anti Blind", "Enabled") end
    end)

    local palletSection = CreateSection(KillerTab, "DESTROY PALLET", false)
    CreateToggle(palletSection, "Auto Destroy Pallet", State.DestroyPallets, function(value)
        State.DestroyPallets = value == true
        if value then notify("Destroy Pallet", "Enabled") end
    end)

    local maskedSection = CreateSection(KillerTab, "SELECT MASKED POWER", false)
    TianHubState.CreateDropdown(maskedSection, "Masked Power", maskedPowers, State.MaskedPower, function(value)
        State.MaskedPower = type(value) == "table" and value[1] or value
    end)
    CreateButton(maskedSection, "Activate Power", function() maskedAction("Activatepower") end)
    CreateButton(maskedSection, "Deactivate Power", function() maskedAction("Deactivatepower") end)

    local carrySection = CreateSection(KillerTab, "UNLOCK SKILL WHILE CARRYING", false)
    CreateToggle(carrySection, "Unlock Skill While Carrying", State.UnlockCarry, function(value)
        State.UnlockCarry = value == true
        if State.UnlockCarry then setupCarryHook() end
        notify("Unlock Skill While Carrying", State.UnlockCarry and "Enabled" or "Disabled")
    end)

    local abilitySection = CreateSection(KillerTab, "KILLER ABILITIES", false)
    CreateToggle(abilitySection, "Auto Stalk (Myers)", State.AutoStalk, function(value)
        setAutoStalk(value)
        notify("Auto Stalk", value and "Enabled" or "Disabled")
    end)
    CreateSlider(abilitySection, "Auto Stalk Range", 20, 500, State.AutoStalkRange, " studs", function(value)
        State.AutoStalkRange = math.clamp(tonumber(value) or 150, 20, 500)
    end, 0)
    CreateToggle(abilitySection, "Drop All Pallet", State.DropAllPallet, function(value)
        State.DropAllPallet = value == true
    end)
    CreateButton(abilitySection, "Instant Drop All Pallet (1x)", function()
        local previous = State.DropAllPallet
        State.DropAllPallet = true
        dropAllPallets()
        State.DropAllPallet = previous
    end)
    CreateToggle(abilitySection, "Block All Vault", State.BlockAllVault, function(value)
        State.BlockAllVault = value == true
    end)
    CreateButton(abilitySection, "Instant Block All Vault (1x)", function()
        local previous = State.BlockAllVault
        State.BlockAllVault = true
        blockAllVaults()
        State.BlockAllVault = previous
    end)
    CreateButton(abilitySection, "Unblock All Vault (1x)", function()
        local event = findRemote("Window", "VaultCompleteEvent")
        local map = workspace:FindFirstChild("Map")
        if not event or not map then return end
        local count = 0
        for _, trigger in ipairs(map:GetDescendants()) do
            if trigger.Name == "VaultPointInUse" and trigger.Parent then
                pcall(function() event:FireServer(trigger.Parent, false); count += 1 end)
            end
        end
        notify("Block Vault", "Unblocked " .. tostring(count) .. " vaults")
    end)

    local hookSection = CreateSection(KillerTab, "AUTO HOOK", false)
    CreateToggle(hookSection, "Auto Hook", State.AutoHook, function(value)
        State.AutoHook = value == true
        notify("Auto Hook", State.AutoHook and "Enabled" or "Disabled")
    end)

    -- One shared worker for Stage 3 toggles; no extra per-feature infinite loops.
    setConn("TianHub_KillerStage3Worker", RunService.Heartbeat:Connect(function()
        if not isKiller() then return end
        if State.DestroyPallets then pcall(destroyNearestPallet) end
        if State.DropAllPallet then
            local now = os.clock()
            if not State.LastDrop or now - State.LastDrop >= 2 then
                State.LastDrop = now
                pcall(dropAllPallets)
            end
        end
        if State.BlockAllVault then
            local now = os.clock()
            if not State.LastVault or now - State.LastVault >= 2 then
                State.LastVault = now
                pcall(blockAllVaults)
            end
        end
        if State.AutoHook then
            local now = os.clock()
            if not State.LastHook or now - State.LastHook >= 1 then
                State.LastHook = now
                pcall(doAutoHook)
            end
        end
    end))
end

-- ============================================================
-- TIANHUB KILLER STAGE 4 - REMAINING TIANHUB MODULES
-- Stage 1/2/3 systems above remain the only instances of existing features.
-- New modules below are sourced from the supplied source script.
-- ============================================================
local Stage4IntegrationOK, Stage4IntegrationError = xpcall(function()
    local W = getgenv()
    local VD = W.TianHubKillerState or {}
    W.TianHubKillerState = VD
    local Workspace = workspace
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = Players.LocalPlayer
    local function TeamIs(plr, role)
        local name = plr and plr.Team and string.lower(plr.Team.Name or "") or ""
        return string.find(name, string.lower(role), 1, true) ~= nil
    end
    local function GetRole()
        if TeamIs(LocalPlayer, "Killer") then return "Killer" end
        if TeamIs(LocalPlayer, "Survivor") then return "Survivor" end
        return nil
    end
    local function VD_Notify(title, content, duration)
        TianHub_Notify(title, content, duration or 2)
    end

    -- TianHub Aimlock Attack (hold MouseButton1 / Attack).
    -- Only camera rotation is adjusted; releasing Attack immediately stops the lock.
    do
        VD.AimlockAttack_Holding = false
        VD.AimlockAttack_Target = nil
        VD.AimlockAttack_Active = false
        VD.AimlockAttack_Smoothness = math.clamp(tonumber(VD.AimlockAttack_Smoothness) or 0, 0, 10)
        VD.AimlockAttack_MaxDist = math.clamp(tonumber(VD.AimlockAttack_MaxDist) or 15, 1, 500)
        VD.AimlockAttack_AimPart = VD.AimlockAttack_AimPart or "HumanoidRootPart"

        local function AA_IsDowned(char)
            if not char then return true end
            if char:GetAttribute("Knocked") == true
                or char:GetAttribute("IsHooked") == true
                or char:GetAttribute("State") == "Hooked" then
                return true
            end
            local hum = char:FindFirstChildOfClass("Humanoid")
            return not hum or hum.Health <= 0
        end

        function W.AimlockAttack_GetTarget()
            local localChar = LocalPlayer.Character
            local root = localChar and localChar:FindFirstChild("HumanoidRootPart")
            if not root then return nil end

            local closest, shortest = nil, math.huge
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer and TeamIs(plr, "Survivor") and plr.Character then
                    local char = plr.Character
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    local part = char:FindFirstChild(VD.AimlockAttack_AimPart)
                        or char:FindFirstChild("HumanoidRootPart")
                    if hum and hum.Health > 0 and part and not AA_IsDowned(char) then
                        local dist = (part.Position - root.Position).Magnitude
                        if dist <= VD.AimlockAttack_MaxDist and dist < shortest then
                            shortest = dist
                            closest = part
                        end
                    end
                end
            end
            return closest
        end

        local AA_Conn
        local function AA_StartLock()
            if AA_Conn then return end
            AA_Conn = RunService.RenderStepped:Connect(function()
                if not VD.AimlockAttack_Active or not VD.AimlockAttack_Holding
                    or GetRole() ~= "Killer" then
                    return
                end

                local localChar = LocalPlayer.Character
                local root = localChar and localChar:FindFirstChild("HumanoidRootPart")
                local cam = Workspace.CurrentCamera
                if not root or not cam then
                    VD.AimlockAttack_Target = nil
                    return
                end

                local target = VD.AimlockAttack_Target
                local targetChar = target and target.Parent
                local targetHum = targetChar and targetChar:FindFirstChildOfClass("Humanoid")
                local targetDistance = target and (target.Position - root.Position).Magnitude or math.huge

                local targetPlayer = targetChar and Players:GetPlayerFromCharacter(targetChar)
                if not target or not target.Parent or not targetHum or targetHum.Health <= 0
                    or AA_IsDowned(targetChar) or targetDistance > VD.AimlockAttack_MaxDist
                    or not targetPlayer or not TeamIs(targetPlayer, "Survivor") then
                    VD.AimlockAttack_Target = W.AimlockAttack_GetTarget()
                    target = VD.AimlockAttack_Target
                end

                if not target or not target.Parent then return end

                -- Smoothness 0 = instant; larger values = progressively smoother.
                local smoothValue = math.clamp(tonumber(VD.AimlockAttack_Smoothness) or 0, 0, 10)
                local alpha = (smoothValue == 0) and 1 or (1 / (1 + smoothValue * 0.8))
                local desired = CFrame.lookAt(cam.CFrame.Position, target.Position)
                cam.CFrame = cam.CFrame:Lerp(desired, alpha)
            end)
        end

        function W.AimlockAttack_SetActive(value)
            VD.AimlockAttack_Active = value == true
            if VD.AimlockAttack_Active then
                AA_StartLock()
            else
                VD.AimlockAttack_Holding = false
                VD.AimlockAttack_Target = nil
            end
        end

        -- Hold input sources: PC mouse, equipped Roblox Tools, and the game's
        -- mobile Attack GuiButton. The lock exists only while at least one source
        -- is physically held; releasing all sources immediately frees the camera.
        local AA_HoldSources = {}
        local AA_MobileTouchInput = nil
        local AA_InputConnections = {}
        local AA_ToolConnections = {}
        local AA_BoundTools = setmetatable({}, { __mode = "k" })
        local AA_BoundButtons = setmetatable({}, { __mode = "k" })

        local function AA_SetHoldSource(source, isDown)
            local wasHolding = VD.AimlockAttack_Holding == true
            AA_HoldSources[source] = isDown == true or nil

            local nowHolding = false
            for _, held in pairs(AA_HoldSources) do
                if held then nowHolding = true; break end
            end

            VD.AimlockAttack_Holding = VD.AimlockAttack_Active
                and GetRole() == "Killer" and nowHolding
            if VD.AimlockAttack_Holding and not wasHolding then
                VD.AimlockAttack_Target = W.AimlockAttack_GetTarget()
            elseif not VD.AimlockAttack_Holding then
                VD.AimlockAttack_Target = nil
            end
        end

        local function AA_IsTianHubGui(guiObject)
            local node = guiObject
            while node do
                if node:IsA("ScreenGui") and string.find(string.lower(node.Name), "tianhub", 1, true) then
                    return true
                end
                node = node.Parent
            end
            return false
        end

        local function AA_IsMobileAttackButton(guiObject)
            if not guiObject:IsA("GuiButton") or AA_IsTianHubGui(guiObject) then return false end
            local name = string.lower(tostring(guiObject.Name or "")):gsub("[^%w]", "")
            local label = ""
            pcall(function() label = string.lower(tostring(guiObject.Text or "")) end)
            label = label:gsub("[^%w]", "")
            local function matches(value)
                return value == "attack" or string.find(value, "attack", 1, true) ~= nil
            end
            return matches(name) or matches(label)
        end

        local function AA_BindMobileAttackButton(guiObject)
            if not AA_IsMobileAttackButton(guiObject) or AA_BoundButtons[guiObject] then return end
            AA_BoundButtons[guiObject] = true
            guiObject.InputBegan:Connect(function(input)
                if input.UserInputType ~= Enum.UserInputType.Touch then return end
                if UserInputService:GetFocusedTextBox() then return end
                if not VD.AimlockAttack_Active or GetRole() ~= "Killer" then return end
                AA_MobileTouchInput = input
                AA_SetHoldSource("MobileAttackButton", true)
            end)
        end

        local function AA_BindTool(tool)
            if not tool:IsA("Tool") or AA_BoundTools[tool] then return end
            AA_BoundTools[tool] = true
            AA_ToolConnections[#AA_ToolConnections + 1] = tool.Activated:Connect(function()
                if not VD.AimlockAttack_Active or GetRole() ~= "Killer" then return end
                AA_SetHoldSource(tool, true)
            end)
            AA_ToolConnections[#AA_ToolConnections + 1] = tool.Deactivated:Connect(function()
                AA_SetHoldSource(tool, false)
            end)
            AA_ToolConnections[#AA_ToolConnections + 1] = tool.Unequipped:Connect(function()
                AA_SetHoldSource(tool, false)
            end)
        end

        UserInputService.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            if UserInputService:GetFocusedTextBox() then return end
            if not VD.AimlockAttack_Active or GetRole() ~= "Killer" then return end
            AA_SetHoldSource("Mouse", true)
        end)

        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                AA_SetHoldSource("Mouse", false)
            elseif input.UserInputType == Enum.UserInputType.Touch and AA_MobileTouchInput == input then
                AA_MobileTouchInput = nil
                AA_SetHoldSource("MobileAttackButton", false)
            end
        end)

        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if playerGui then
            for _, item in ipairs(playerGui:GetDescendants()) do AA_BindMobileAttackButton(item) end
            AA_InputConnections[#AA_InputConnections + 1] = playerGui.DescendantAdded:Connect(AA_BindMobileAttackButton)
        end

        local function AA_BindCharacterTools(character)
            for _, item in ipairs(character:GetChildren()) do AA_BindTool(item) end
            AA_InputConnections[#AA_InputConnections + 1] = character.ChildAdded:Connect(AA_BindTool)
            AA_InputConnections[#AA_InputConnections + 1] = character.ChildRemoved:Connect(function(item)
                if item:IsA("Tool") then AA_SetHoldSource(item, false) end
            end)
        end
        if LocalPlayer.Character then AA_BindCharacterTools(LocalPlayer.Character) end
        AA_InputConnections[#AA_InputConnections + 1] = LocalPlayer.CharacterAdded:Connect(AA_BindCharacterTools)

        W.AimlockAttack_Cfg = setmetatable({}, {
            __index = function(_, key)
                if key == "Holding" then return VD.AimlockAttack_Holding end
                if key == "Active" then return VD.AimlockAttack_Active end
                return nil
            end,
        })
    end

    -- Integrated Silent Flask and Spear Aimbot backends.
            do
            VD.FLASK_SilentAim    = VD.FLASK_SilentAim    or false
            VD.FLASK_ShowBeam     = VD.FLASK_ShowBeam     ~= false
            VD.FLASK_ShowLanding  = VD.FLASK_ShowLanding  ~= false
            VD.FLASK_Predict      = VD.FLASK_Predict      ~= false
            VD.FLASK_Speed        = VD.FLASK_Speed        or 90
            VD.FLASK_Gravity      = VD.FLASK_Gravity      or 196
            VD.FLASK_LeadMult     = VD.FLASK_LeadMult     or 1.0
            VD.FLASK_Range        = VD.FLASK_Range        or 200
            VD.FLASK_BeamColor    = VD.FLASK_BeamColor    or Color3.fromRGB(255, 255, 255)
            VD.FLASK_AccentColor  = VD.FLASK_AccentColor  or Color3.fromRGB(25, 25, 25)
            local FlaskState = { Target = nil, PredictedPos = nil, BeamPart = nil, AccentPart = nil, LandingRing = nil }
            local function Flask_GetTarget()
                local myChar = LocalPlayer.Character
                local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
                if not myRoot then return nil end
                local maxR = tonumber(VD.FLASK_Range) or 200
                local best, bd = nil, math.huge
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= LocalPlayer and TeamIs(p, "Survivor") and p.Character then
                        local hum = p.Character:FindFirstChildOfClass("Humanoid")
                        local root = p.Character:FindFirstChild("HumanoidRootPart")
                        if hum and hum.Health > 0 and root then
                            local d = (root.Position - myRoot.Position).Magnitude
                            if d <= maxR and d < bd then
                                bd = d; best = { Player = p, Root = root, Char = p.Character }
                            end
                        end
                    end
                end
                return best
            end
            local function Flask_GetHandOrigin()
                local c = LocalPlayer.Character
                if not c then return nil end
                return c:FindFirstChild("LeftHand") or c:FindFirstChild("Left Arm")
                    or c:FindFirstChild("RightHand") or c:FindFirstChild("Right Arm")
                    or c:FindFirstChild("HumanoidRootPart")
            end
            local function Flask_PredictLanding(origin, targetRoot)
                local targetPos = targetRoot.Position
                local speed   = tonumber(VD.FLASK_Speed)   or 90
                local gravity = tonumber(VD.FLASK_Gravity) or 196
                local lead    = tonumber(VD.FLASK_LeadMult) or 1.0
                if not VD.FLASK_Predict then return targetPos end
                local tv = targetRoot.AssemblyLinearVelocity or Vector3.zero
                local horizVel = Vector3.new(tv.X, 0, tv.Z)
                local dist = (targetPos - origin).Magnitude
                local time = dist / speed
                local predicted = targetPos
                for _ = 1, 3 do
                    predicted = targetPos + horizVel * time * lead
                    local nd = (predicted - origin).Magnitude
                    time = nd / speed
                end
                local drop = 0.5 * gravity * (time * time)
                return predicted + Vector3.new(0, drop, 0)
            end
            local function Flask_ClearVisuals()
                if FlaskState.BeamPart then pcall(function() FlaskState.BeamPart:Destroy() end); FlaskState.BeamPart = nil end
                if FlaskState.AccentPart then pcall(function() FlaskState.AccentPart:Destroy() end); FlaskState.AccentPart = nil end
                if FlaskState.LandingRing then pcall(function() FlaskState.LandingRing:Destroy() end); FlaskState.LandingRing = nil end
            end
            local function Flask_HideVisuals()
                if FlaskState.BeamPart then FlaskState.BeamPart.Transparency = 1 end
                if FlaskState.AccentPart then FlaskState.AccentPart.Transparency = 1 end
                if FlaskState.LandingRing then FlaskState.LandingRing.Transparency = 1 end
            end
            local function Flask_EnsureBeamParts()
                if not FlaskState.BeamPart or not FlaskState.BeamPart.Parent then
                    local beam = Instance.new("Part")
                    beam.Name = "GlutoFlaskBeam"
                    beam.Anchored = true
                    beam.CanCollide = false
                    beam.CanTouch = false
                    beam.CanQuery = false
                    beam.CastShadow = false
                    beam.Material = Enum.Material.Neon
                    beam.Color = VD.FLASK_BeamColor or Color3.fromRGB(255, 255, 255)
                    beam.Transparency = 0.2
                    beam.Parent = Workspace
                    FlaskState.BeamPart = beam
                end
                if not FlaskState.AccentPart or not FlaskState.AccentPart.Parent then
                    local accent = Instance.new("Part")
                    accent.Name = "GlutoFlaskBeamAccent"
                    accent.Anchored = true
                    accent.CanCollide = false
                    accent.CanTouch = false
                    accent.CanQuery = false
                    accent.CastShadow = false
                    accent.Material = Enum.Material.SmoothPlastic
                    accent.Color = VD.FLASK_AccentColor or Color3.fromRGB(25, 25, 25)
                    accent.Transparency = 0.35
                    accent.Parent = Workspace
                    FlaskState.AccentPart = accent
                end
                if FlaskState.BeamPart then FlaskState.BeamPart.Color = VD.FLASK_BeamColor or Color3.fromRGB(255, 255, 255) end
                if FlaskState.AccentPart then FlaskState.AccentPart.Color = VD.FLASK_AccentColor or Color3.fromRGB(25, 25, 25) end
            end
            local function Flask_UpdateBeam(origin, landing)
                Flask_EnsureBeamParts()
                local dir = landing - origin
                local dist = dir.Magnitude
                if dist < 0.1 then return end
                local mid = (origin + landing) / 2
                local cf = CFrame.lookAt(mid, landing)
                FlaskState.BeamPart.Size = Vector3.new(0.12, 0.12, dist)
                FlaskState.BeamPart.CFrame = cf
                FlaskState.BeamPart.Transparency = 0.2
                FlaskState.AccentPart.Size = Vector3.new(0.22, 0.22, dist)
                FlaskState.AccentPart.CFrame = cf
                FlaskState.AccentPart.Transparency = 0.35
            end
            local function Flask_UpdateLanding(pos)
                if not VD.FLASK_ShowLanding then
                    if FlaskState.LandingRing then FlaskState.LandingRing.Transparency = 1 end
                    return
                end
                if not FlaskState.LandingRing or not FlaskState.LandingRing.Parent then
                    local ring = Instance.new("Part")
                    ring.Name = "GlutoFlaskLanding"
                    ring.Shape = Enum.PartType.Cylinder
                    ring.Anchored = true
                    ring.CanCollide = false
                    ring.CanTouch = false
                    ring.CanQuery = false
                    ring.CastShadow = false
                    ring.Material = Enum.Material.Neon
                    ring.Color = VD.FLASK_BeamColor or Color3.fromRGB(255, 255, 255)
                    ring.Size = Vector3.new(0.2, 5, 5)
                    ring.Parent = Workspace
                    FlaskState.LandingRing = ring
                end
                FlaskState.LandingRing.Color = VD.FLASK_BeamColor or Color3.fromRGB(255, 255, 255)
                FlaskState.LandingRing.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
                FlaskState.LandingRing.Transparency = 0.35
            end
            RunService.RenderStepped:Connect(function()
                if not VD.FLASK_SilentAim then
                    Flask_HideVisuals()
                    FlaskState.Target = nil
                    FlaskState.PredictedPos = nil
                    return
                end
                if GetRole() ~= "Killer" then Flask_HideVisuals(); return end
                local target = Flask_GetTarget()
                if not target or not target.Root then
                    Flask_HideVisuals(); FlaskState.Target = nil; FlaskState.PredictedPos = nil; return
                end
                local hand = Flask_GetHandOrigin()
                if not hand then return end
                local landing = Flask_PredictLanding(hand.Position, target.Root)
                FlaskState.Target = target
                FlaskState.PredictedPos = landing
                if VD.FLASK_ShowBeam then pcall(Flask_UpdateBeam, hand.Position, landing)
                else
                    if FlaskState.BeamPart then FlaskState.BeamPart.Transparency = 1 end
                    if FlaskState.AccentPart then FlaskState.AccentPart.Transparency = 1 end
                end
                pcall(Flask_UpdateLanding, landing)
            end)
            task.spawn(function()
                pcall(function()
                    local oldNC
                    oldNC = hookmetamethod(game, "__namecall", function(self, ...)
                        if getnamecallmethod() == "FireServer"
                           and self.Name == "ThrowFlask"
                           and VD.FLASK_SilentAim
                           and GetRole() == "Killer"
                           and FlaskState.PredictedPos then
                            local args = {...}
                            if typeof(args[2]) == "Vector3" then
                                local origin = args[2]
                                local aimDir = (FlaskState.PredictedPos - origin)
                                if aimDir.Magnitude > 0.1 then
                                    args[1] = aimDir.Unit
                                    return oldNC(self, unpack(args))
                                end
                            elseif typeof(args[1]) == "Vector3" then
                                local hand = Flask_GetHandOrigin()
                                if hand then
                                    local aimDir = (FlaskState.PredictedPos - hand.Position)
                                    if aimDir.Magnitude > 0.1 then
                                        args[1] = aimDir.Unit
                                        return oldNC(self, unpack(args))
                                    end
                                end
                            end
                        end
                        return oldNC(self, ...)
                    end)
                end)
            end)
            W.Flask_SetEnabled = function(v) VD.FLASK_SilentAim = v and true or false; if not v then Flask_ClearVisuals() end end
            W.Flask_SetBeamColor   = function(c) VD.FLASK_BeamColor = c end
            W.Flask_SetAccentColor = function(c) VD.FLASK_AccentColor = c end
            W.Flask_SetSpeed       = function(v) VD.FLASK_Speed = tonumber(v) or 90 end
            W.Flask_SetGravity     = function(v) VD.FLASK_Gravity = tonumber(v) or 196 end
            W.Flask_SetLead        = function(v) VD.FLASK_LeadMult = tonumber(v) or 1.0 end
            W.Flask_SetRange       = function(v) VD.FLASK_Range = tonumber(v) or 200 end
        end

        do
            VD.SPEAR_Aimbot = VD.SPEAR_Aimbot or false
            VD.SPEAR_Gravity = VD.SPEAR_Gravity or 50
            VD.SPEAR_Speed = VD.SPEAR_Speed or 100
            local SpearBtnData = {
                UI = nil, Button = nil, Active = true, DragLocked = false,
                Dragging = false, DragStart = nil, DragStartPos = nil,
                ManualTarget = nil, TargetIndex = 0,
                TargetLabel = nil, LeftArrow = nil, RightArrow = nil,
            }
            local function SpearAimbotCalc(targetPos)
                if not VD.SPEAR_Aimbot or GetRole() ~= "Killer" then return nil end
                local char = LocalPlayer.Character
                if not char then return nil end
                local root = char:FindFirstChild("HumanoidRootPart")
                if not root then return nil end
                local startPos = root.Position + Vector3.new(0, 2, 0)
                local distance = (targetPos - startPos).Magnitude
                local gravity  = VD.SPEAR_Gravity or 50
                local speed    = VD.SPEAR_Speed or 100
                local time     = distance / speed
                local drop     = 0.5 * gravity * time * time
                return targetPos + Vector3.new(0, drop, 0)
            end
            local function Spear_GetTargetList()
                local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                local list = {}
                if not root then return list end
                for _, player in ipairs(Players:GetPlayers()) do
                    if player ~= LocalPlayer and TeamIs(player, "Survivor") and player.Character then
                        local tr = player.Character:FindFirstChild("HumanoidRootPart")
                        local th = player.Character:FindFirstChildOfClass("Humanoid")
                        if tr and th and th.MaxHealth > 0 and (th.Health / th.MaxHealth) > 0.25 then
                            local dist = (tr.Position - root.Position).Magnitude
                            table.insert(list, { Player = player, Dist = dist })
                        end
                    end
                end
                table.sort(list, function(a, b) return a.Dist < b.Dist end)
                local players = {}
                for _, v in ipairs(list) do table.insert(players, v.Player) end
                return players
            end
            local function Spear_UpdateTargetLabel()
                if not (SpearBtnData and SpearBtnData.TargetLabel) then return end
                if SpearBtnData.ManualTarget and SpearBtnData.ManualTarget.Parent then
                    SpearBtnData.TargetLabel.Text = SpearBtnData.ManualTarget.Name
                else
                    SpearBtnData.TargetLabel.Text = "AUTO"
                end
                SpearBtnData.TargetLabel.Visible = true
            end
            local function Spear_CycleTarget(direction)
                local list = Spear_GetTargetList()
                if #list == 0 then
                    SpearBtnData.ManualTarget = nil; SpearBtnData.TargetIndex = 0
                    VD_Notify("Spear Aimbot", "Tidak ada target survivor.", 2)
                    return
                end
                local curIdx = nil
                if SpearBtnData.ManualTarget then
                    for i, p in ipairs(list) do
                        if p == SpearBtnData.ManualTarget then curIdx = i; break end
                    end
                end
                local nextIdx
                if curIdx then
                    nextIdx = curIdx + direction
                    if nextIdx > #list then nextIdx = 1 end
                    if nextIdx < 1 then nextIdx = #list end
                else nextIdx = 1 end
                SpearBtnData.TargetIndex  = nextIdx
                SpearBtnData.ManualTarget = list[nextIdx]
                VD_Notify("Spear Aimbot", "Target: " .. SpearBtnData.ManualTarget.Name, 2)
                Spear_UpdateTargetLabel()
            end
            local function Spear_UpdateAim()
                if not VD.SPEAR_Aimbot then return end
                if SpearBtnData and not SpearBtnData.Active then return end
                if GetRole() ~= "Killer" then return end
                local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if not root then return end
                local target = nil
                if SpearBtnData.ManualTarget then
                    local p = SpearBtnData.ManualTarget
                    local valid = p.Parent and TeamIs(p, "Survivor") and p.Character
                    if valid then
                        local tr = p.Character:FindFirstChild("HumanoidRootPart")
                        local th = p.Character:FindFirstChildOfClass("Humanoid")
                        valid = tr and th and th.MaxHealth > 0 and (th.Health / th.MaxHealth) > 0.25
                    end
                    if valid then target = p
                    else SpearBtnData.ManualTarget = nil; Spear_UpdateTargetLabel() end
                end
                if not target then
                    local closest, closestDist = nil, math.huge
                    for _, player in ipairs(Players:GetPlayers()) do
                        if player ~= LocalPlayer and TeamIs(player, "Survivor") and player.Character then
                            local tr = player.Character:FindFirstChild("HumanoidRootPart")
                            local th = player.Character:FindFirstChildOfClass("Humanoid")
                            if tr and th and th.MaxHealth > 0 and (th.Health / th.MaxHealth) > 0.25 then
                                local dist = (tr.Position - root.Position).Magnitude
                                if dist < closestDist then closestDist = dist; closest = player end
                            end
                        end
                    end
                    target = closest
                end
                if target and target.Character then
                    local tr = target.Character:FindFirstChild("HumanoidRootPart")
                    if tr then
                        local aimPos = SpearAimbotCalc(tr.Position)
                        if aimPos then
                            local cam = Workspace.CurrentCamera
                            if cam then cam.CFrame = CFrame.new(cam.CFrame.Position, aimPos) end
                        end
                    end
                end
            end
            local function Spear_SetupButton()
                if SpearBtnData.UI then pcall(function() SpearBtnData.UI:Destroy() end) end
                local pg = LocalPlayer:FindFirstChild("PlayerGui")
                if not pg then return end
                SpearBtnData.UI = Instance.new("ScreenGui")
                SpearBtnData.UI.Name = "GlutoSpearAimbotUI"
                SpearBtnData.UI.ResetOnSpawn = false
                SpearBtnData.UI.IgnoreGuiInset = true
                SpearBtnData.UI.Parent = pg
                SpearBtnData.Button = Instance.new("TextButton")
                SpearBtnData.Button.Name = "SpearAimbotButton"
                SpearBtnData.Button.Size = UDim2.new(0, 65, 0, 65)
                SpearBtnData.Button.Position = UDim2.new(0.15, 0, 0.75, 0)
                SpearBtnData.Button.AnchorPoint = Vector2.new(0.5, 0.5)
                SpearBtnData.Button.BackgroundColor3 = Color3.fromRGB(30, 10, 10)
                SpearBtnData.Button.BackgroundTransparency = 0.15
                SpearBtnData.Button.AutoButtonColor = true
                SpearBtnData.Button.Text = "SPEAR\nAIM"
                SpearBtnData.Button.TextColor3 = Color3.fromRGB(255, 100, 100)
                SpearBtnData.Button.TextSize = 11
                SpearBtnData.Button.Font = Enum.Font.GothamBold
                SpearBtnData.Button.Visible = false
                SpearBtnData.Button.ZIndex = 10
                SpearBtnData.Button.Parent = SpearBtnData.UI
                Instance.new("UICorner", SpearBtnData.Button).CornerRadius = UDim.new(1, 0)
                local spearStk = Instance.new("UIStroke", SpearBtnData.Button)
                spearStk.Color = Color3.fromRGB(255, 80, 80)
                spearStk.Thickness = 2
                spearStk.Transparency = 0.2
                local lockBtn = Instance.new("TextButton")
                lockBtn.Name = "LockDrag"
                lockBtn.Size = UDim2.new(0, 22, 0, 22)
                lockBtn.Position = UDim2.new(1, -5, 0, -5)
                lockBtn.AnchorPoint = Vector2.new(1, 0)
                lockBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
                lockBtn.BackgroundTransparency = 0.3
                lockBtn.Text = "L"
                lockBtn.TextSize = 10
                lockBtn.Font = Enum.Font.GothamBold
                lockBtn.TextColor3 = Color3.new(1, 1, 1)
                lockBtn.ZIndex = 11
                lockBtn.Parent = SpearBtnData.Button
                Instance.new("UICorner", lockBtn).CornerRadius = UDim.new(1, 0)
                lockBtn.MouseButton1Click:Connect(function()
                    SpearBtnData.DragLocked = not SpearBtnData.DragLocked
                    lockBtn.Text = SpearBtnData.DragLocked and "X" or "L"
                    lockBtn.BackgroundColor3 = SpearBtnData.DragLocked and Color3.fromRGB(200, 50, 50) or Color3.fromRGB(60, 60, 60)
                end)
                local targetLabel = Instance.new("TextLabel")
                targetLabel.Name = "SpearTargetLabel"
                targetLabel.Size = UDim2.new(0, 90, 0, 18)
                targetLabel.Position = UDim2.new(0.5, 0, 0, -22)
                targetLabel.AnchorPoint = Vector2.new(0.5, 0)
                targetLabel.BackgroundTransparency = 1
                targetLabel.Text = "AUTO"
                targetLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                targetLabel.TextSize = 12
                targetLabel.Font = Enum.Font.GothamBold
                targetLabel.TextTruncate = Enum.TextTruncate.AtEnd
                targetLabel.ZIndex = 11
                targetLabel.Visible = false
                targetLabel.Parent = SpearBtnData.Button
                SpearBtnData.TargetLabel = targetLabel
                local leftArrow = Instance.new("TextButton")
                leftArrow.Name = "SpearTargetLeft"
                leftArrow.Size = UDim2.new(0, 28, 0, 28)
                leftArrow.Position = UDim2.new(0, -34, 0.5, 0)
                leftArrow.AnchorPoint = Vector2.new(0.5, 0.5)
                leftArrow.BackgroundColor3 = Color3.fromRGB(30, 10, 10)
                leftArrow.BackgroundTransparency = 0.15
                leftArrow.Text = "<"
                leftArrow.TextColor3 = Color3.fromRGB(158, 158, 158)
                leftArrow.TextSize = 16
                leftArrow.Font = Enum.Font.GothamBold
                leftArrow.ZIndex = 10
                leftArrow.Parent = SpearBtnData.Button
                Instance.new("UICorner", leftArrow).CornerRadius = UDim.new(1, 0)
                local leftStk = Instance.new("UIStroke", leftArrow)
                leftStk.Color = Color3.fromRGB(255, 80, 80)
                leftStk.Thickness = 1.5
                leftStk.Transparency = 0.3
                SpearBtnData.LeftArrow = leftArrow
                leftArrow.MouseButton1Click:Connect(function() Spear_CycleTarget(-1) end)
                local rightArrow = Instance.new("TextButton")
                rightArrow.Name = "SpearTargetRight"
                rightArrow.Size = UDim2.new(0, 28, 0, 28)
                rightArrow.Position = UDim2.new(1, 34, 0.5, 0)
                rightArrow.AnchorPoint = Vector2.new(0.5, 0.5)
                rightArrow.BackgroundColor3 = Color3.fromRGB(30, 10, 10)
                rightArrow.BackgroundTransparency = 0.15
                rightArrow.Text = ">"
                rightArrow.TextColor3 = Color3.fromRGB(255, 150, 150)
                rightArrow.TextSize = 16
                rightArrow.Font = Enum.Font.GothamBold
                rightArrow.ZIndex = 10
                rightArrow.Parent = SpearBtnData.Button
                Instance.new("UICorner", rightArrow).CornerRadius = UDim.new(1, 0)
                local rightStk = Instance.new("UIStroke", rightArrow)
                rightStk.Color = Color3.fromRGB(255, 80, 80)
                rightStk.Thickness = 1.5
                rightStk.Transparency = 0.3
                SpearBtnData.RightArrow = rightArrow
                rightArrow.MouseButton1Click:Connect(function() Spear_CycleTarget(1) end)
                SpearBtnData.Button.InputBegan:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        if SpearBtnData.DragLocked then return end
                        SpearBtnData.Dragging = true
                        SpearBtnData.DragStart = input.Position
                        SpearBtnData.DragStartPos = SpearBtnData.Button.Position
                    end
                end)
                UserInputService.InputChanged:Connect(function(input)
                    if SpearBtnData.Dragging and not SpearBtnData.DragLocked and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                        local delta = input.Position - SpearBtnData.DragStart
                        SpearBtnData.Button.Position = UDim2.new(
                            SpearBtnData.DragStartPos.X.Scale, SpearBtnData.DragStartPos.X.Offset + delta.X,
                            SpearBtnData.DragStartPos.Y.Scale, SpearBtnData.DragStartPos.Y.Offset + delta.Y
                        )
                    end
                end)
                SpearBtnData.Button.InputEnded:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        SpearBtnData.Dragging = false
                    end
                end)
                SpearBtnData.Button.MouseButton1Click:Connect(function()
                    SpearBtnData.Active = not SpearBtnData.Active
                    if SpearBtnData.Active then
                        SpearBtnData.Button.BackgroundColor3 = Color3.fromRGB(10, 40, 10)
                        SpearBtnData.Button.TextColor3 = Color3.fromRGB(80, 255, 120)
                        spearStk.Color = Color3.fromRGB(80, 255, 120)
                        VD_Notify("Spear Aimbot", "Spear Aimbot AKTIF!", 3)
                    else
                        SpearBtnData.Button.BackgroundColor3 = Color3.fromRGB(30, 10, 10)
                        SpearBtnData.Button.TextColor3 = Color3.fromRGB(255, 100, 100)
                        spearStk.Color = Color3.fromRGB(255, 80, 80)
                        VD_Notify("Spear Aimbot", "Spear Aimbot NONAKTIF", 3)
                    end
                end)
            end
            RunService.RenderStepped:Connect(function() pcall(Spear_UpdateAim) end)
            RunService.Heartbeat:Connect(function()
                if SpearBtnData and SpearBtnData.Button then
                    local shouldShow = VD.SPEAR_Aimbot and GetRole() == "Killer"
                    SpearBtnData.Button.Visible = shouldShow
                    if shouldShow then pcall(Spear_UpdateTargetLabel) end
                end
            end)
            LocalPlayer.CharacterAdded:Connect(function()
                task.wait(0.5)
                if VD.SPEAR_Aimbot then pcall(Spear_SetupButton) end
            end)
            W.SpearAimbot_SetEnabled = function(v)
                VD.SPEAR_Aimbot = v and true or false
                if v then SpearBtnData.Active = true; Spear_SetupButton()
                else
                    if SpearBtnData.UI then pcall(function() SpearBtnData.UI:Destroy() end); SpearBtnData.UI = nil end
                    SpearBtnData.Button = nil
                end
            end
            W.SpearAimbot_SetGravity = function(v) VD.SPEAR_Gravity = tonumber(v) or 50 end
            W.SpearAimbot_SetSpeed   = function(v) VD.SPEAR_Speed   = tonumber(v) or 100 end
            W.SpearAimbot_CycleTarget = Spear_CycleTarget
        end

    -- TianHub Silent Veil: original TianHub module with a TianHub state/UI adapter.
    do
        local Players = game:GetService("Players")
        local RunService = game:GetService("RunService")
        local LP = Players.LocalPlayer
        local unloaded = false

        -- Compatibility surface required by the supplied module.
        -- Marker calls are no-ops because the module already owns its target line/ring visuals.
        local State = {
            Motion = {
                Regress = function(samples, now, window, minSpan)
                    if type(samples) ~= "table" or #samples < 2 then return nil end
                    local first = math.max(1, #samples - 12)
                    local sumT, sumX, sumY, sumZ, count = 0, 0, 0, 0, 0
                    for i = first, #samples do
                        local sample = samples[i]
                        if sample and sample.t and sample.p and now - sample.t <= (window or 0.25) then
                            sumT = sumT + sample.t
                            sumX = sumX + sample.p.X
                            sumY = sumY + sample.p.Y
                            sumZ = sumZ + sample.p.Z
                            count = count + 1
                        end
                    end
                    if count < 2 then return nil end
                    local meanT = sumT / count
                    local meanX, meanY, meanZ = sumX / count, sumY / count, sumZ / count
                    local denom, vx, vy, vz = 0, 0, 0, 0
                    for i = first, #samples do
                        local sample = samples[i]
                        if sample and sample.t and sample.p and now - sample.t <= (window or 0.25) then
                            local dt = sample.t - meanT
                            denom = denom + dt * dt
                            vx = vx + dt * (sample.p.X - meanX)
                            vy = vy + dt * (sample.p.Y - meanY)
                            vz = vz + dt * (sample.p.Z - meanZ)
                        end
                    end
                    if denom <= 1e-6 then return nil end
                    return Vector3.new(vx / denom, vy / denom, vz / denom)
                end,
            },
            ClearMark = function() end,
            SetMark = function() end,
        }

        if type(_G.TianHubSilentSpearStandaloneUnload) == "function" then
            pcall(_G.TianHubSilentSpearStandaloneUnload)
        end

        local G = (getgenv and getgenv()) or _G
        if G.TianHubSilentSpearV4 and G.TianHubSilentSpearV4.Installed then
            G.TianHubSilentSpearV4.Installed.namecall = nil
        end

State.SpearObj = (function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local G = (getgenv and getgenv()) or _G

	for _, key in ipairs({ "KinonSpearState", "KinonSpearState2", "KinonSpearState3" }) do
		if G[key] then G[key].Enabled = false end
	end

	local V = G.TianHubSilentSpearV4
	if V and V.Destroy then pcall(V.Destroy) end
	V = V or { Installed = {} }
	V.Installed = V.Installed or {}
	G.TianHubSilentSpearV4 = V

	V.Enabled, V.UseDeep = false, false
	V.FOV, V.MaxRange, V.FovAim = 240, 500, true
	V.SpearSpeed, V.Drop, V.Predict = 180, 0.5, true
	V.Dead = false
	V.CurPart, V.CurPoint, V.CurOrigin = nil, nil, nil
	V.TargetChar = nil

	local wrap = newcclosure or function(f) return f end

	local BAL = {
		SpawnOffset    = 3,
		MinChargeTime  = 0.3,
		FullChargeTime = 1,
		YVelClamp      = 14,
		VelMagCap      = 32,
	}

	local function getGravity()
		local g = math.max(0, tonumber(workspace.Gravity) or 196.2)
		return Vector3.new(0, -g * math.clamp(tonumber(V.Drop) or 0.5, 0, 1), 0)
	end

	local function getPingHalf()
		local ok, ping = pcall(function() return LP:GetNetworkPing() end)
		if ok and type(ping) == "number" and ping > 0 then
			return math.clamp(ping * 0.5, 0, 0.25)
		end
		return 0.035
	end

	local function getLatencyLead()
		local ok, ping = pcall(function() return LP:GetNetworkPing() end)
		local oneWay = (ok and type(ping) == "number" and ping > 0) and math.clamp(ping, 0.01, 0.2) or 0.05
		return math.clamp(oneWay * 1.5 + 0.04, 0.06, 0.32)
	end

	local velCache = setmetatable({}, { __mode = "k" })

	local function getSmoothedVelocity(char, hrp)
		local now = tick()
		local c = velCache[char]
		local raw
		if c and c.lastPos and now - c.time > 0.03 and now - c.time < 0.5 then
			raw = (hrp.Position - c.lastPos) / (now - c.time)
			local live = hrp.AssemblyLinearVelocity or Vector3.zero
			if raw.Magnitude > 60 then raw = live end
			local smoothed = c.velocity:Lerp(raw, 0.5)
			if smoothed.Magnitude > BAL.VelMagCap then
				smoothed = smoothed.Unit * BAL.VelMagCap
			end
			velCache[char] = { velocity = smoothed, time = now, lastPos = hrp.Position }
			return smoothed
		end
		raw = hrp.AssemblyLinearVelocity or Vector3.zero
		if raw.Magnitude > BAL.VelMagCap then raw = raw.Unit * BAL.VelMagCap end
		velCache[char] = { velocity = raw, time = now, lastPos = hrp.Position }
		return raw
	end

	local function clampVelY(v)
		return Vector3.new(v.X, math.clamp(v.Y, -BAL.YVelClamp, BAL.YVelClamp), v.Z)
	end

	local function isKillerTeam(char)
		local plr = Players:GetPlayerFromCharacter(char)
		if plr and plr.Team and plr.Team.Name == "Killer" then return true end
		if char:GetAttribute("Role") == "Killer" then return true end
		if char:GetAttribute("IsKiller") == true then return true end
		return false
	end

	local function candidates()
		local list = {}
		local camera = workspace.CurrentCamera
		if not camera then return list end
		local center = camera.ViewportSize / 2
		local myChar = LP.Character
		local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
		if not myHRP then return list end

		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LP and plr.Character and plr.Character ~= myChar then
				local char = plr.Character
				if not isKillerTeam(char) then
					local hum = char:FindFirstChildOfClass("Humanoid")
					local hrp = char:FindFirstChild("HumanoidRootPart")
					if hum and hum.Health > 0 and hrp
					   and not char:GetAttribute("Immobile")
					   and not char:GetAttribute("IsHooked")
					   and not char:GetAttribute("Knocked") then
						local dist = (hrp.Position - myHRP.Position).Magnitude
						if dist <= V.MaxRange then
							local s, onScreen = camera:WorldToViewportPoint(hrp.Position)
							if onScreen and s.Z > 0 then
								local px = (Vector2.new(s.X, s.Y) - center).Magnitude
								if (not V.FovAim) or px <= V.FOV then
									table.insert(list, {
										char = char, hrp = hrp, hum = hum,
										px = px, dist = dist,
										health = hum.Health,
									})
								end
							end
						end
					end
				end
			end
		end
		return list
	end

	local function pick(list)
		if #list == 0 then return nil end
		table.sort(list, function(a, b) return a.px < b.px end)
		local cur = V.TargetChar
		if cur then
			for _, c in ipairs(list) do
				if c.char == cur then
					if c.px <= list[1].px + 18 then return c end
					break
				end
			end
		end
		return list[1]
	end

	local tracker = { char = nil, samples = {} }

	local function trackTarget(char, hrp)
		local now = os.clock()
		if tracker.char ~= char then tracker.char, tracker.samples = char, {} end
		local smp = tracker.samples
		smp[#smp + 1] = { t = now, p = hrp.Position }
		while #smp > 2 and now - smp[1].t > 0.9 do table.remove(smp, 1) end
	end

	local function windowVelocity(smp, window)
		local last = smp[#smp]
		local first = smp[1]
		for i = #smp, 1, -1 do
			if last.t - smp[i].t >= window then first = smp[i]; break end
		end
		local dt = last.t - first.t
		if dt < 0.03 then return nil end
		return (last.p - first.p) / dt
	end

	local INTERACT_ATTR = { "repair", "generator", "heal", "unhook", "rescu", "gate", "interact", "opening", "working", "search", "chest", "sabotage", "cleanse", "totem", "pickup" }
	local INTERACT_ANIM = { "repair", "generator", "heal", "unhook", "rescue", "gate", "search", "chest", "sabotage", "cleanse", "totem", "pickup" }

	local function isInteracting(char)
		local okA, attrs = pcall(function() return char:GetAttributes() end)
		if okA and type(attrs) == "table" then
			for name, value in pairs(attrs) do
				if value == true then
					local n = string.lower(tostring(name))
					if not (n:find("^can") or n:find("^has") or n:find("^allow")) then
						for _, key in ipairs(INTERACT_ATTR) do
							if n:find(key, 1, true) then return true end
						end
					end
				end
			end
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if animator then
			local okT, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
			if okT and tracks then
				for _, tr in ipairs(tracks) do
					local label = ""
					pcall(function()
						label = string.lower(tostring(tr.Name) .. " " .. tostring(tr.Animation and tr.Animation.Name or ""))
					end)
					if label ~= "" then
						for _, key in ipairs(INTERACT_ANIM) do
							if label:find(key, 1, true) then return true end
						end
					end
				end
			end
		end
		return false
	end

	local function stationaryByHistory(char)
		local smp = tracker.samples
		if tracker.char ~= char or #smp < 6 then return false end
		local last = smp[#smp]
		local first
		for i = #smp, 1, -1 do
			if last.t - smp[i].t >= 0.5 then first = smp[i]; break end
		end
		if not first then return false end
		local d = last.p - first.p
		return Vector3.new(d.X, 0, d.Z).Magnitude < 0.9
	end

	-- Movement prediction adapted from the supplied TianHub Instant script.
	-- Combines short/long position-history windows with live assembly velocity.
	local function estimateVelocity(char, hrp)
		local live = hrp.AssemblyLinearVelocity or Vector3.zero
		local liveFlat = Vector3.new(live.X, 0, live.Z)
		local smp = tracker.samples

		if tracker.char == char and #smp >= 4 then
			local vLong = windowVelocity(smp, 0.30)
			local vShort = windowVelocity(smp, 0.14)
			local vNow = windowVelocity(smp, 0.10) or vShort

			if vLong and vShort and vNow then
				local flatLong = Vector3.new(vLong.X, 0, vLong.Z)
				local flatShort = Vector3.new(vShort.X, 0, vShort.Z)
				local flatNow = Vector3.new(vNow.X, 0, vNow.Z)

				local noInput = false
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum then
					pcall(function()
						noInput = hum.MoveDirection.Magnitude < 0.05
					end)
				end

				local vel
				if flatNow.Magnitude < 1.2 and liveFlat.Magnitude < 2 then
					vel = Vector3.zero
				elseif noInput and flatShort.Magnitude < 4 and liveFlat.Magnitude < 4 then
					vel = Vector3.zero
				elseif flatShort.Magnitude < flatLong.Magnitude * 0.45
					and liveFlat.Magnitude < flatLong.Magnitude * 0.6 then
					vel = (vNow + live) * 0.5
				else
					local cosA = 1
					if flatLong.Magnitude > 1 and flatShort.Magnitude > 1 then
						cosA = flatLong.Unit:Dot(flatShort.Unit)
					end

					if cosA < 0.5 and liveFlat.Magnitude > 1
						and flatShort.Unit:Dot(liveFlat.Unit) > 0.5 then
						vel = (vNow + live) * 0.5
					else
						vel = vLong * 0.3 + vShort * 0.7
						if liveFlat.Magnitude > 2 then
							vel = vel * 0.6 + live * 0.4
						end
					end
				end

				if vel.Magnitude > BAL.VelMagCap then
					vel = vel.Unit * BAL.VelMagCap
				end
				return vel
			end
		end

		local fallback = live
		if fallback.Magnitude > BAL.VelMagCap then
			fallback = fallback.Unit * BAL.VelMagCap
		end
		return fallback
	end

	local function isAuraMode(char)
		if not char then return false end
		if char:GetAttribute("special") == true or char:GetAttribute("Aura") == true then return true end
		return char:FindFirstChild("Aura") ~= nil
	end

	local function solveThrow(targetChar, origin, chargeTime)
		local hrp = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
		if not hrp then return nil end

		local dist = (hrp.Position - origin).Magnitude
		local farFactor = math.clamp((dist - 45) / 35, 0, 1)
		local baseSpeed = math.clamp(tonumber(V.SpearSpeed) or 180, 60, 180)
		local speed = baseSpeed + (math.min(150, baseSpeed) - baseSpeed) * farFactor
		local launchSpeed = math.clamp((chargeTime or BAL.FullChargeTime) * speed, 1, speed)
		local gVec = getGravity()
		local gMag = math.abs(gVec.Y)
		local latency = getPingHalf() + 0.07 + 0.07 * farFactor
		local aimPoint = hrp.Position + Vector3.new(0, 0.2, 0)

		local vel = Vector3.zero
		if V.Predict ~= false and not (isInteracting(targetChar) or stationaryByHistory(targetChar)) then
			vel = clampVelY(estimateVelocity(targetChar, hrp))
			if vel.Magnitude > BAL.VelMagCap then
				vel = vel.Unit * BAL.VelMagCap
			end
		end
		local predVel = vel * (1.1 + 0.3 * farFactor)

		local rel = aimPoint + predVel * latency - origin
		local t = math.max(0.04, rel.Magnitude / launchSpeed)
		local ballisticOK = true

		for _ = 1, 5 do
			local toTarget = aimPoint + predVel * (t + latency) - origin
			local hMag = Vector3.new(toTarget.X, 0, toTarget.Z).Magnitude
			local yOff = toTarget.Y
			local a = 0.25 * gMag * gMag
			local b = yOff * gMag - launchSpeed * launchSpeed
			local c = hMag * hMag + yOff * yOff
			local disc = b * b - 4 * a * c
			if gMag < 0.001 then
				t = math.max(0.04, toTarget.Magnitude / launchSpeed)
			elseif disc >= 0 then
				local r = (-b - math.sqrt(disc)) / (2 * a)
				if r > 0 then t = math.sqrt(r) else t = math.max(0.04, toTarget.Magnitude / launchSpeed) end
			else
				ballisticOK = false
				t = math.max(0.04, toTarget.Magnitude / launchSpeed)
				break
			end
		end

		local finalAim = aimPoint + predVel * (t + latency)
		local finalRel = finalAim - origin

		if not ballisticOK and gMag > 0.001 then
			local flat = Vector3.new(finalRel.X, 0, finalRel.Z)
			local flatDir = flat.Magnitude > 0.001 and flat.Unit or Vector3.new(0, 0, -1)
			local num = launchSpeed * launchSpeed - 2 * gMag * finalRel.Y
			local angle = num > 0 and math.atan(launchSpeed / math.sqrt(num)) or math.rad(45)
			local dir = (flatDir * math.cos(angle) + Vector3.new(0, math.sin(angle), 0)).Unit
			return dir, dir * launchSpeed, launchSpeed, finalAim
		end

		local dirVec = (finalRel - 0.5 * gVec * t * t) / t
		return dirVec.Unit, dirVec, launchSpeed, finalAim
	end

	local function isSpearActive(char)
		if not char then return false end
		local morph = char:GetAttribute("MorphedKiller")
		if morph == "Veil" or char:GetAttribute("Veil") == true then return true end
		if char:GetAttribute("spearmode") == true then return true end
		if char:GetAttribute("VeilSpearEquipped") == true then return true end
		local spear = char:FindFirstChild("Spear")
		if spear then
			local inner = spear:FindFirstChild("Spear")
			if inner and inner:IsA("BasePart") then return inner.Transparency < 0.5 end
			return true
		end
		return false
	end

	local endAttackCache, endAttackAnims, endAttackSearched = nil, nil, false

	local function ensureChargeFn()
		local char = LP.Character
		local anims = char and char:FindFirstChild("Animations")
		if not anims then return end
		if type(getgc) ~= "function" or type(getupvalues) ~= "function" then return end
		if endAttackAnims ~= anims then
			endAttackAnims, endAttackCache, endAttackSearched = anims, nil, false
		end
		if endAttackCache or endAttackSearched then return end
		endAttackSearched = true
		pcall(function()
			for _, fn in ipairs(getgc()) do
				if type(fn) == "function" and (not islclosure or islclosure(fn)) then
					if debug.info(fn, "n") == "endAttack" and getfenv(fn).script == anims then
						endAttackCache = fn
						break
					end
				end
			end
		end)
	end

	local function getChargeTime()
		if not endAttackCache then return BAL.FullChargeTime end
		local ok, ups = pcall(getupvalues, endAttackCache)
		if ok and ups then
			local isThrown = ups[2] == true
			local startTime = tonumber(ups[9]) or 0
			if isThrown and startTime > 0 then
				return math.max(BAL.MinChargeTime, workspace:GetServerTimeNow() - startTime)
			end
		end
		return BAL.FullChargeTime
	end

	local viewDelayFn = nil
	task.spawn(function()
		for _ = 1, 40 do
			if unloaded or V.Dead or viewDelayFn then return end
			pcall(function()
				local mods = ReplicatedStorage:FindFirstChild("Modules")
				local world = mods and mods:FindFirstChild("World")
				local vis = world and world:FindFirstChild("ProjectileVisualsClient")
				if vis and vis:IsA("ModuleScript") then
					local m = require(vis)
					if m and type(m.viewDelay) == "function" then viewDelayFn = m.viewDelay end
				end
			end)
			task.wait(0.25)
		end
	end)
	task.spawn(function()
		while not unloaded and not V.Dead do
			if V.Enabled then pcall(ensureChargeFn) end
			task.wait(0.5)
		end
	end)

	local TRAIL_LIFETIME = 1.5
	local function showTrail(origin, dir, speed)
		if typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" or dir.Magnitude < 0.01 then return end
		speed = tonumber(speed) or 180
		task.spawn(function()
			local gravity = getGravity()
			local v0 = dir.Unit * speed
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.RespectCanCollide = true
			local ignore = {}
			if LP.Character then table.insert(ignore, LP.Character) end
			params.FilterDescendantsInstances = ignore

			local points = { origin }
			local prev = origin
			local steps, dt = 160, 0.0175
			for i = 1, steps do
				local tt = i * dt
				local nxt = origin + v0 * tt + 0.5 * gravity * tt * tt
				local delta = nxt - prev
				local stop = false
				if delta.Magnitude > 0.01 then
					local hit = workspace:Raycast(prev, delta, params)
					if hit then nxt = hit.Position; stop = true end
				end
				table.insert(points, nxt)
				prev = nxt
				if stop then break end
			end
			if #points < 2 then return end

			-- Build one continuous cubic-Bezier Beam per layer. This removes
			-- the visible joints caused by hundreds of tiny Beam instances.
			local folder = Instance.new("Folder")
			folder.Name = "TianHub_SpearTrail"
			folder.Parent = workspace

			local terrain = workspace.Terrain
			local p0, p3 = points[1], points[#points]
			local totalTime = (#points - 1) * dt
			local quadraticControl = origin + v0 * (totalTime * 0.5)
			local control0 = p0 + (quadraticControl - p0) * (2 / 3)
			local control1 = p3 + (quadraticControl - p3) * (2 / 3)

			local function makeRightFacingFrame(position, direction)
				local right = direction.Magnitude > 0.001 and direction.Unit or Vector3.xAxis
				local referenceUp = math.abs(right:Dot(Vector3.yAxis)) > 0.98 and Vector3.xAxis or Vector3.yAxis
				local back = right:Cross(referenceUp).Unit
				local up = back:Cross(right).Unit
				return CFrame.fromMatrix(position, right, up, back)
			end

			local startAttachment = Instance.new("Attachment")
			startAttachment.Name = "TrailStart"
			startAttachment.Parent = terrain
			startAttachment.WorldCFrame = makeRightFacingFrame(p0, control0 - p0)

			local endAttachment = Instance.new("Attachment")
			endAttachment.Name = "TrailEnd"
			endAttachment.Parent = terrain
			endAttachment.WorldCFrame = makeRightFacingFrame(p3, control1 - p3)

			local cam = workspace.CurrentCamera
			local camPos = cam and cam.CFrame.Position or origin
			local k0 = math.clamp((p0 - camPos).Magnitude / 40, 1, 5)
			local k1 = math.clamp((p3 - camPos).Magnitude / 40, 1, 5)

			local function makeBeam(name, color, width0, width1, transparency, emission)
				local b = Instance.new("Beam")
				b.Name = name
				b.Attachment0, b.Attachment1 = startAttachment, endAttachment
				b.CurveSize0 = (control0 - p0).Magnitude
				b.CurveSize1 = (control1 - p3).Magnitude
				b.Color = ColorSequence.new(color)
				b.LightEmission = emission
				b.LightInfluence = 0
				b.FaceCamera = true
				b.Segments = 64
				b.Width0, b.Width1 = width0, width1
				b.Transparency = NumberSequence.new(transparency)
				b.Parent = folder
				return b
			end

			-- Two soft purple halo layers create a broad light bloom around
			-- the solid core, while the thin dark layer keeps the trail defined.
			local outerGlow = makeBeam(
				"WidePurpleLightBloom",
				Color3.fromRGB(135, 55, 255),
				2.75 * k0, 1.80 * k1, 0.62, 1
			)
			local innerGlow = makeBeam(
				"SoftPurpleInnerGlow",
				Color3.fromRGB(190, 105, 255),
				1.95 * k0, 1.28 * k1, 0.38, 1
			)
			local outline = makeBeam(
				"DarkSmoothOutline",
				Color3.fromRGB(8, 6, 14),
				1.48 * k0, 0.96 * k1, 0.08, 0.7
			)
			local beam = makeBeam(
				"ContinuousPurpleCore",
				Color3.fromRGB(205, 135, 255),
				1.38 * k0, 0.90 * k1, 0.02, 1
			)

			local start = os.clock()
			while folder.Parent and not unloaded do
				local alpha = (os.clock() - start) / TRAIL_LIFETIME
				if alpha >= 1 then break end
				local function fadeFrom(base)
					return NumberSequence.new(math.clamp(base + alpha * (1 - base), 0, 1))
				end
				outerGlow.Transparency = fadeFrom(0.62)
				innerGlow.Transparency = fadeFrom(0.38)
				outline.Transparency = fadeFrom(0.08)
				beam.Transparency = fadeFrom(0.02)
				RunService.Heartbeat:Wait()
			end
			if folder.Parent then folder:Destroy() end
			startAttachment:Destroy()
			endAttachment:Destroy()
		end)
	end

	local function applyPayload(payload, origin, dir, speed)
		payload.Origin = origin
		payload.Direction = dir
		if payload.Velocity ~= nil then payload.Velocity = dir * speed end
		if viewDelayFn then
			pcall(function() payload.ViewDelay = viewDelayFn(origin, dir) end)
		end
	end

	V.NamecallHandler = function(old, self, ...)
		local method = getnamecallmethod()
		if not V.Enabled or (method ~= "FireServer" and method ~= "fireServer") then
			return old(self, ...)
		end
		local isSpear = false
		pcall(function()
			isSpear = typeof(self) == "Instance" and string.lower(self.Name) == "spearthrow"
		end)
		if not isSpear then
			if setnamecallmethod then pcall(setnamecallmethod, method) end
			return old(self, ...)
		end
		if checkcaller and checkcaller() then
			if setnamecallmethod then pcall(setnamecallmethod, method) end
			return old(self, ...)
		end

		local args = table.pack(...)
		local trailOrigin, trailDir, trailSpeed

		pcall(function()
			local char = LP.Character
			if not char or not isSpearActive(char) then return end
			local camera = workspace.CurrentCamera
			if not camera then return end
			local payload = type(args[1]) == "table" and args[1] or nil

			local origin
			if payload and typeof(payload.Origin) == "Vector3" then
				origin = payload.Origin
			elseif typeof(args[1]) == "Vector3" and typeof(args[2]) == "Vector3" then
				origin = args[1]
			elseif typeof(args[1]) == "Vector3" and type(args[2]) == "number" and typeof(args[3]) == "Vector3" then
				origin = args[3]
			else
				origin = camera.CFrame.Position + camera.CFrame.LookVector * BAL.SpawnOffset
			end

			local speedForm = payload == nil and typeof(args[1]) == "Vector3" and type(args[2]) == "number"
			local charge = speedForm and BAL.FullChargeTime or getChargeTime()
			local target = V.TargetChar
			local redirected = false

			if target and target.Parent then
				local dir, _, speed = solveThrow(target, origin, charge)
				if dir then
					trailOrigin, trailDir, trailSpeed = origin, dir, speed
					if payload then
						local ok = pcall(applyPayload, payload, origin, dir, speed)
						if ok then redirected = true
						else
							local clone = table.clone and table.clone(payload) or nil
							if clone and pcall(applyPayload, clone, origin, dir, speed) then
								args[1] = clone
								redirected = true
							end
						end
					elseif typeof(args[1]) == "Vector3" and typeof(args[2]) == "Vector3" then
						args[1], args[2] = origin, dir
						redirected = true
					elseif speedForm then
						args[1], args[2] = dir, speed
						redirected = true
					elseif typeof(args[1]) == "Vector3" then
						args[1] = dir
						redirected = true
					end
				end
			end

			if not redirected then
				trailOrigin, trailDir, trailSpeed = nil, nil, nil
				if payload and typeof(payload.Direction) == "Vector3" then
					trailOrigin = origin
					trailDir = payload.Direction
					trailSpeed = typeof(payload.Velocity) == "Vector3" and payload.Velocity.Magnitude
						or math.clamp(charge * (tonumber(V.SpearSpeed) or 180), 1, 200)
				elseif typeof(args[1]) == "Vector3" and typeof(args[2]) == "Vector3" then
					trailOrigin, trailDir = args[1], args[2]
					trailSpeed = math.clamp(charge * (tonumber(V.SpearSpeed) or 180), 1, 200)
				end
			end
		end)

		if setnamecallmethod then pcall(setnamecallmethod, method) end
		if setnamecallmethod then pcall(setnamecallmethod, method) end
		local ret = old(self, unpack(args, 1, args.n))
		if trailOrigin then task.defer(showTrail, trailOrigin, trailDir, trailSpeed) end
		return ret
	end

	local function guiParent()
		local parent
		pcall(function() parent = (gethui and gethui()) or game:GetService("CoreGui") end)
		return parent or LP:WaitForChild("PlayerGui")
	end

	local sg = Instance.new("ScreenGui")
	sg.Name = "TianHubSilentSpear"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Parent = guiParent()

	local targetHighlight

	local function clearTargetIndicator()
		if targetHighlight then targetHighlight:Destroy(); targetHighlight = nil end
	end

	local function showTargetIndicator(char)
		if not char or not char.Parent then
			clearTargetIndicator()
			return
		end

		if not targetHighlight or targetHighlight.Parent ~= char then
			clearTargetIndicator()
			targetHighlight = Instance.new("Highlight")
			targetHighlight.Name = "TianHub_Veil_FOV_Target"
			targetHighlight.Adornee = char
			targetHighlight.FillColor = Color3.fromRGB(255, 35, 35)
			targetHighlight.OutlineColor = Color3.fromRGB(255, 35, 35)
			targetHighlight.FillTransparency = 0.78
			targetHighlight.OutlineTransparency = 0
			targetHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			targetHighlight.Parent = char
		end
	end

	local function hideVisuals()
		clearTargetIndicator()
		pcall(State.ClearMark, "spear")
	end

	V.DestroyEsp = function()
		V.TargetChar = nil
		rawset(_G, "TianHub_SilentVeilFOVTarget", nil)
		V.CurPart, V.CurPoint, V.CurOrigin = nil, nil, nil
		hideVisuals()
		tracker.char, tracker.samples = nil, {}
	end

	V.RenderConn = RunService.RenderStepped:Connect(function()
		if unloaded or not V.Enabled then
			rawset(_G, "TianHub_SilentVeilFOVTarget", nil)
			if V.TargetChar then V.DestroyEsp() end
			return
		end

		local t = pick(candidates())
		local nowC = os.clock()
		if t then
			V.LastT, V.LastSeen = t, nowC
		elseif V.LastT and nowC - (V.LastSeen or 0) < 0.3 then
			local lt = V.LastT
			local lh = lt.hum
			if lt.hrp and lt.hrp.Parent and lh and lh.Parent and lh.Health > 0 then t = lt end
		end
		V.TargetChar = t and t.char or nil
		V.CurPart = t and t.hrp or nil
		rawset(_G, "TianHub_SilentVeilFOVTarget", (t and t.px <= (tonumber(V.FOV) or 240)) and t.char or nil)

		if not (LP.Team and LP.Team.Name == "Killer") then
			rawset(_G, "TianHub_SilentVeilFOVTarget", nil)
			hideVisuals()
			return
		end

		if V.TargetChar then
			trackTarget(V.TargetChar, t.hrp)
			-- The red marker is strictly limited to the configured FOV radius,
			-- even when FOV filtering for aim selection is switched off.
			if t.px <= (tonumber(V.FOV) or 240) then
				showTargetIndicator(V.TargetChar)
			else
				clearTargetIndicator()
			end
		else
			hideVisuals()
			tracker.char, tracker.samples = nil, {}
		end
	end)

	V.Destroy = function()
		V.Enabled = false
		V.Dead = true
		if V.RenderConn then pcall(function() V.RenderConn:Disconnect() end); V.RenderConn = nil end
		paintName(lastNamed, false)
		pcall(State.ClearMark, "spear")
		clearTargetIndicator()
		pcall(function() ring:Destroy() end)
		pcall(function() sg:Destroy() end)
		V.TargetChar = nil
		V.CurPart, V.CurPoint, V.CurOrigin = nil, nil, nil
	end

	if not V.Installed.namecall and hookmetamethod and getnamecallmethod then
		pcall(function()
			local old
			old = hookmetamethod(game, "__namecall", wrap(function(self, ...)
				local method = getnamecallmethod()
				if method == "FireServer" or method == "fireServer" then
					local fr = State.FlashRemote
					if fr and self == fr and State.FlashSetActive then
						local fa = { ... }
						pcall(State.FlashSetActive, fa[2] == true, fa[1])
						if setnamecallmethod then pcall(setnamecallmethod, method) end
					end
					if State.AntiBlindOn and not (checkcaller and checkcaller()) and State.IsKillerNow and State.IsKillerNow() then
						local blockBlind = false
						pcall(function()
							local n = string.lower(tostring(self:GetFullName()))
							if n:find("blind", 1, true) then blockBlind = true end
						end)
						if blockBlind then return nil end
						if setnamecallmethod then pcall(setnamecallmethod, method) end
					end
					local ns = State.NoSlow
					if ns and (ns.K or ns.S) and not (checkcaller and checkcaller()) then
						local block = false
						pcall(function()
							if self.Name == "Fall" and self.Parent and self.Parent.Name == "Mechanics" then
								block = true
							end
						end)
						if block then return nil end
						if setnamecallmethod then pcall(setnamecallmethod, method) end
					end
				end
				local handler = V.NamecallHandler
				if handler then return handler(old, self, ...) end
				return old(self, ...)
			end))
			V.Installed.namecall = true
		end)
	end
	V.HookOk = V.Installed.namecall == true

	return V
end)()

        local V = G.TianHubSilentSpearV4

        -- Additive Silent Veil FOV overlay; target-selection code remains untouched.
        if V then
            V.ShowFOVCircle = V.ShowFOVCircle == true
            local overlayParent
            pcall(function()
                if type(gethui) == "function" then overlayParent = gethui() end
            end)
            overlayParent = overlayParent or LP:WaitForChild("PlayerGui")

            local oldOverlay = overlayParent:FindFirstChild("TianHub_SilentVeil_FOV")
            if oldOverlay then oldOverlay:Destroy() end

            local overlayGui = Instance.new("ScreenGui")
            overlayGui.Name = "TianHub_SilentVeil_FOV"
            overlayGui.ResetOnSpawn = false
            overlayGui.IgnoreGuiInset = true
            overlayGui.DisplayOrder = 20
            overlayGui.Parent = overlayParent

            local fovCircle = Instance.new("Frame")
            fovCircle.Name = "FOVCircle"
            fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
            fovCircle.Position = UDim2.fromScale(0.5, 0.5)
            fovCircle.Size = UDim2.fromOffset((tonumber(V.FOV) or 240) * 2, (tonumber(V.FOV) or 240) * 2)
            fovCircle.BackgroundTransparency = 1
            fovCircle.BorderSizePixel = 0
            fovCircle.Visible = false
            fovCircle.Parent = overlayGui

            local fovCorner = Instance.new("UICorner")
            fovCorner.CornerRadius = UDim.new(1, 0)
            fovCorner.Parent = fovCircle

            local fovStroke = Instance.new("UIStroke")
            fovStroke.Color = Color3.fromRGB(8, 6, 14)
            fovStroke.Thickness = 1.15
            fovStroke.Transparency = 0
            fovStroke.Parent = fovCircle

            local fovInner = Instance.new("Frame")
            fovInner.Name = "PurpleInnerRing"
            fovInner.AnchorPoint = Vector2.new(0.5, 0.5)
            fovInner.Position = UDim2.fromScale(0.5, 0.5)
            fovInner.Size = UDim2.new(1, -4, 1, -4)
            fovInner.BackgroundTransparency = 1
            fovInner.BorderSizePixel = 0
            fovInner.Parent = fovCircle
            Instance.new("UICorner", fovInner).CornerRadius = UDim.new(1, 0)
            local fovInnerStroke = Instance.new("UIStroke")
            fovInnerStroke.Color = Color3.fromRGB(190, 115, 255)
            fovInnerStroke.Thickness = 2.5
            fovInnerStroke.Transparency = 0
            fovInnerStroke.Parent = fovInner

            local fovRender
            fovRender = RunService.RenderStepped:Connect(function()
                if not overlayGui.Parent then
                    if fovRender then fovRender:Disconnect() end
                    return
                end
                local camera = workspace.CurrentCamera
                if camera then
                    local radius = math.clamp(tonumber(V.FOV) or 240, 30, 600)
                    fovCircle.Position = UDim2.fromOffset(
                        camera.ViewportSize.X / 2,
                        camera.ViewportSize.Y / 2
                    )
                    fovCircle.Size = UDim2.fromOffset(radius * 2, radius * 2)
                    fovCircle.Visible = V.ShowFOVCircle == true
                else
                    fovCircle.Visible = false
                end
            end)

            V.SetShowFOVCircle = function(enabled)
                V.ShowFOVCircle = enabled == true
                fovCircle.Visible = V.ShowFOVCircle
            end
            V.DestroyFOVCircle = function()
                if fovRender then fovRender:Disconnect(); fovRender = nil end
                if overlayGui then overlayGui:Destroy() end
            end
        end

        if V then
            local Settings = setmetatable({}, {
                __index = function(_, key)
                    if key == "Enabled" then return V.Enabled end
                    if key == "FOVRadius" then return V.FOV end
                    if key == "ShowFOV" then return V.FovAim end
                    if key == "TargetHighlightEnabled" then return true end
                    if key == "Priority" then return "Nearest" end
                end,
                __newindex = function(_, key, value)
                    if key == "Enabled" then
                        V.Enabled = value == true
                    elseif key == "FOVRadius" then
                        V.FOV = math.clamp(tonumber(value) or 240, 30, 600)
                    elseif key == "ShowFOV" then
                        V.FovAim = value == true
                    end
                end,
            })
            W.TianHubSilentVeilSettings = Settings
            W.TianHubSilentSpearSettings = V

            _G.TianHubSilentSpearStandaloneUnload = function()
                if V then
                    V.Enabled = false
                    if type(V.Destroy) == "function" then pcall(V.Destroy) end
                end
            end
        end
    end

    -- TianHub Dash Lock module loader, invoked only when enabled by the user.
                -- Dash Lock module is also loaded only on demand; failures leave the toggle off.
            local dashLockModule = nil
            local function GetDashLockModule()
                if dashLockModule then return dashLockModule end
                if type(loadstring) ~= "function" then return nil, "loadstring tidak tersedia pada executor ini" end
                local ok, result = pcall(function()
                    local source = game:HttpGet("https://pastefy.app/Pu94U00g/raw")
                    local compile = loadstring(source)
                    assert(type(compile) == "function", "gagal compile Dash Lock")
                    return compile()
                end)
                if not ok or type(result) ~= "table" then
                    return nil, tostring(result or "module Dash Lock tidak valid")
                end
                dashLockModule = result
                return dashLockModule
            end
            local dashLockState = false
            local function SetDashLock(enabled)
                enabled = enabled == true
                if enabled == dashLockState then return end
                if enabled then
                    local module, err = GetDashLockModule()
                    if not module then
                        VD_Notify("Dash Lock", "Gagal memuat: " .. tostring(err), 4)
                        dashLockState = false
                        VD.DashLockEnabled = false
                        return
                    end
                    local ok = pcall(function()
                        assert(type(module.Enable) == "function", "module tidak memiliki Enable()")
                        module.Enable()
                    end)
                    if not ok then
                        VD_Notify("Dash Lock", "Module gagal diaktifkan.", 3)
                        VD.DashLockEnabled = false
                        dashLockState = false
                        return
                    end
                    dashLockState = true
                    VD.DashLockEnabled = true
                    VD_Notify("Dash Lock", "Enabled — klik kanan untuk lock", 3)
                else
                    if dashLockModule then
                        pcall(function() if type(dashLockModule.HideGUI) == "function" then dashLockModule.HideGUI() end end)
                        pcall(function() if type(dashLockModule.Disable) == "function" then dashLockModule.Disable() end end)
                    end
                    dashLockState = false
                    VD.DashLockEnabled = false
                    VD_Notify("Dash Lock", "Disabled", 2)
                end
            end

    -- Auto Kill All: existing target-follow and BasicAttack remote behavior.
    local AutoKillAll = false
    local KillAllTarget = nil
    local function getClosestSurvivor(range, minHealth)
        local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not root then return nil end
        local closest, shortest = nil, range or math.huge
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character and TeamIs(plr, "Survivor") then
                local hum = plr.Character:FindFirstChildOfClass("Humanoid")
                local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
                if hum and hrp and hum.Health > (minHealth or 30) then
                    local d = (hrp.Position - root.Position).Magnitude
                    if d <= shortest then shortest, closest = d, plr end
                end
            end
        end
        return closest
    end
    local function updateAutoKillAll()
        if not AutoKillAll or GetRole() ~= "Killer" then KillAllTarget = nil; return end
        local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local tChar = KillAllTarget and KillAllTarget.Character
        local hum = tChar and tChar:FindFirstChildOfClass("Humanoid")
        if not KillAllTarget or not tChar or not tChar.Parent or not hum or hum.Health <= 35 then
            KillAllTarget = getClosestSurvivor(math.huge, 30)
            tChar = KillAllTarget and KillAllTarget.Character
        end
        if not tChar then return end
        local targetRoot = tChar:FindFirstChild("HumanoidRootPart")
        if targetRoot then
            local targetPos = targetRoot.Position + targetRoot.AssemblyLinearVelocity * 0.15
            local behind = targetRoot.CFrame.LookVector * -3
            root.CFrame = CFrame.new(targetPos + behind, targetPos)
        end
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local attacks = remotes and remotes:FindFirstChild("Attacks")
        local basic = attacks and attacks:FindFirstChild("BasicAttack")
        if basic then pcall(function() basic:FireServer(false) end) end
    end

    -- TianHub Aimlock Attack controls.
    local aimSection = CreateSection(KillerTab, "AIMLOCK ATTACK", false)
    CreateToggle(aimSection, "Aimlock Attack", false, function(v)
        if W.AimlockAttack_SetActive then
            W.AimlockAttack_SetActive(v == true)
        end
    end)
    CreateSlider(aimSection, "Smooth Lock", 0, 10, VD.AimlockAttack_Smoothness or 0, "", function(v)
        VD.AimlockAttack_Smoothness = math.clamp(tonumber(v) or 0, 0, 10)
    end, 1)
    CreateSlider(aimSection, "Lock Distance", 1, 500, VD.AimlockAttack_MaxDist or 15, " studs", function(v)
        VD.AimlockAttack_MaxDist = math.clamp(tonumber(v) or 15, 1, 500)
    end, 0)

    local veilSection = CreateSection(KillerTab, "SILENT VEIL SPEAR AIM", false)
    local veilSettings = W.TianHubSilentVeilSettings
    if veilSettings then
        local kinon = W.TianHubSilentSpearSettings
        -- Hidden defaults: target highlight/lock stays enabled and target priority stays Nearest.
        veilSettings.Priority = "Nearest"

        CreateToggle(veilSection, "Enable Veil", veilSettings.Enabled, function(v)
            veilSettings.Enabled = v == true
            if v then
                veilSettings.Priority = "Nearest"
            end
        end)
        CreateToggle(veilSection, "FOV Check", veilSettings.ShowFOV, function(v) veilSettings.ShowFOV = v == true end)
        CreateToggle(veilSection, "Show FOV", false, function(v)
            if kinon and type(kinon.SetShowFOVCircle) == "function" then
                kinon.SetShowFOVCircle(v == true)
            end
        end)
        CreateSlider(veilSection, "FOV Size", 30, 600, veilSettings.FOVRadius, " px", function(v) veilSettings.FOVRadius = math.clamp(tonumber(v) or 240, 30, 600) end, 0)
        CreateSlider(veilSection, "Max Range", 50, 1000, kinon.MaxRange, " studs", function(v) kinon.MaxRange = math.clamp(tonumber(v) or 500, 50, 1000) end, 0)
        CreateSlider(veilSection, "Shot Speed", 60, 180, kinon.SpearSpeed, "", function(v) kinon.SpearSpeed = math.clamp(tonumber(v) or 180, 60, 180) end, 0)
        CreateSlider(veilSection, "Shot Drop", 0, 1, kinon.Drop, "", function(v) kinon.Drop = math.clamp(tonumber(v) or 0.5, 0, 1) end, 2)
        CreateToggle(veilSection, "Aim Prediction", kinon.Predict, function(v) kinon.Predict = v == true end)
    end


    -- Silent Aim Butcher integration (core logic preserved; TianHub toggle replaces standalone UI).
    do
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local CollectionService = game:GetService("CollectionService")
    local Teams = game:GetService("Teams")
    local LocalPlayer = Players.LocalPlayer


    local ChainCfg = {
        Enabled = false,
        Debug = true,
        Range = 50,
        Speed = 140,
        PredMultiplier = 1.0,
        Prediction = true,
        Highlight = true,
        AimHeightOffset = 0.5,
        HookOK = false,
    }


    local function chainLog(msg)
        if ChainCfg.Debug then print("[ChainAim] " .. tostring(msg)) end
    end


    -- ========== UTIL ==========
    local velCache = setmetatable({}, {__mode = "k"})
    local function getSmoothVel(hrp)
        if not hrp then return Vector3.zero end
        local raw = hrp.AssemblyLinearVelocity or hrp.Velocity or Vector3.zero
        local flat = Vector3.new(raw.X, 0, raw.Z)
        if flat.Magnitude > 50 then flat = flat.Unit * 50 end
        local cache = velCache[hrp]
        if not cache then
            velCache[hrp] = {v = flat}
            return flat
        end
        local lerped = cache.v:Lerp(flat, 0.5)
        if lerped.Magnitude < 0.5 then lerped = Vector3.zero end
        cache.v = lerped
        return lerped
    end


    local function CanLatch(char)
        if not char or not char.Parent then return false end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return false end
        if char:GetAttribute("Knocked") then return false end
        if char:GetAttribute("IsHooked") or char:GetAttribute("IsCarried") or char:GetAttribute("IsCarrying") then return false end
        if char:GetAttribute("Trapped") then return false end
        return true
    end


    local function IsSurvivor(plr)
        if plr == LocalPlayer then return false end
        local team = plr.Team
        if team then
            local n = team.Name:lower()
            for _, p in ipairs({"killer","murderer","hunter","assassin","slasher","psycho","enemy"}) do
                if n:find(p, 1, true) then return false end
            end
            return true
        end
        return #Teams:GetTeams() > 0
    end


    -- ========== TARGET ==========
    local function GetChainTarget()
        local myChar = LocalPlayer.Character
        if not myChar then return nil end
        local myRoot = myChar:FindFirstChild("HumanoidRootPart")
        if not myRoot then return nil end


        local bestTarget, bestDist = nil, ChainCfg.Range
        local function check(char)
            if not char or char == myChar then return end
            if not CanLatch(char) then return end
            local root = char:FindFirstChild("HumanoidRootPart")
            if not root then return end
            local d = (root.Position - myRoot.Position).Magnitude
            if d <= ChainCfg.Range and d < bestDist then
                bestDist = d; bestTarget = root
            end
        end
        for _, plr in ipairs(Players:GetPlayers()) do
            if IsSurvivor(plr) then check(plr.Character) end
        end
        for _, bot in ipairs(CollectionService:GetTagged("SurvivorBot")) do
            check(bot)
        end
        return bestTarget
    end


    -- ========== HIGHLIGHT (putih) ==========
    local ChainHighlight = Instance.new("Highlight")
    ChainHighlight.Name = "N3K0P01_ChainAimHighlight"
    ChainHighlight.FillColor = Color3.fromRGB(255, 255, 255)
    ChainHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    ChainHighlight.FillTransparency = 0.6
    ChainHighlight.OutlineTransparency = 0
    ChainHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    ChainHighlight.Adornee = nil
    ChainHighlight.Parent = workspace.CurrentCamera


    task.spawn(function()
        while ChainHighlight and ChainHighlight.Parent do
            if ChainCfg.Enabled and ChainCfg.Highlight then
                local t = GetChainTarget()
                ChainHighlight.Adornee = t and t.Parent or nil
            else
                ChainHighlight.Adornee = nil
            end
            RunService.RenderStepped:Wait()
        end
    end)


    -- ========== REDIRECT LOGIC ==========
    local function TryRedirect(args)
        local target = GetChainTarget()
        if not target then return false end
        local char = LocalPlayer.Character
        local head = char and char:FindFirstChild("Head")
        if not head then return false end


        local origin = head.Position
        local aimPoint = target.Position + Vector3.new(0, ChainCfg.AimHeightOffset, 0)


        if ChainCfg.Prediction and ChainCfg.PredMultiplier > 0 then
            local vel = getSmoothVel(target)
            local dist = (aimPoint - origin).Magnitude
            local travelTime = dist / math.max(ChainCfg.Speed, 1)
            travelTime = math.min(travelTime, 0.8)
            local leadVec = vel * travelTime * ChainCfg.PredMultiplier
            aimPoint = aimPoint + leadVec
        end


        local dirVec = aimPoint - origin
        local dist = dirVec.Magnitude
        if dist < 0.001 then return false end
        local dir = dirVec.Unit


        chainLog(string.format("dir set | dist=%.1f | spd=%d", dist, ChainCfg.Speed))


        if typeof(args[1]) == "Vector3" then
            args[1] = dir
            return true
        end
        if type(args[3]) == "table" then
            if typeof(args[3].Origin) == "Vector3" then
                args[3].Origin = origin
            end
            if typeof(args[3].Direction) == "Vector3" then
                args[3].Direction = dir
                return true
            end
        end
        return false
    end


    -- ========== INSTALL HOOK ==========
    local function InstallChainHook()
        if ChainCfg.HookOK then return true end
        if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
            return false
        end
        local wrap = newcclosure or function(f) return f end
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", wrap(function(self, ...)
            local method = getnamecallmethod()
            if method == "FireServer"
               and typeof(self) == "Instance"
               and self.ClassName == "RemoteEvent"
               and self.Name == "ChainThrow"
               and ChainCfg.Enabled then
                local args = table.pack(...)
                local ok, changed = pcall(TryRedirect, args)
                if ok and changed then
                    if setnamecallmethod then setnamecallmethod(method) end
                    return oldNamecall(self, table.unpack(args, 1, args.n))
                end
            end
            if setnamecallmethod then setnamecallmethod(method) end
            return oldNamecall(self, ...)
        end))
        ChainCfg.HookOK = true
        return true
    end

        local function setEnabled(state)
            ChainCfg.Enabled = state == true
            if ChainCfg.Enabled and not ChainCfg.HookOK then
                InstallChainHook()
            end
            print("[ChainAim]", ChainCfg.Enabled and "Enabled" or "Disabled")
        end

        local butcherSection = CreateSection(KillerTab, "SILENT AIM BUTCHER", false) -- Separate groupbox directly below Silent Veil.
        CreateToggle(butcherSection, "Enable Silent Aim Butcher", ChainCfg.Enabled, function(v)
            setEnabled(v)
        end)
        CreateToggle(butcherSection, "Prediction", ChainCfg.Prediction, function(v)
            ChainCfg.Prediction = v == true
        end)
        CreateSlider(butcherSection, "Prediction Multiplier", 0, 3, ChainCfg.PredMultiplier, "x", function(v)
            ChainCfg.PredMultiplier = math.clamp(tonumber(v) or 1.0, 0, 3)
        end, 1)
        CreateSlider(butcherSection, "Target Range", 10, 200, ChainCfg.Range, " studs", function(v)
            ChainCfg.Range = math.clamp(tonumber(v) or 50, 10, 200)
        end, 0)
        CreateSlider(butcherSection, "Projectile Speed", 50, 300, ChainCfg.Speed, "", function(v)
            ChainCfg.Speed = math.clamp(tonumber(v) or 140, 50, 300)
        end, 0)
        CreateToggle(butcherSection, "Target Highlight", ChainCfg.Highlight, function(v)
            ChainCfg.Highlight = v == true
            if not ChainCfg.Highlight then ChainHighlight.Adornee = nil end
        end)
        CreateSlider(butcherSection, "Aim Height Offset", -2, 3, ChainCfg.AimHeightOffset, " studs", function(v)
            ChainCfg.AimHeightOffset = math.clamp(tonumber(v) or 0.5, -2, 3)
        end, 1)

        UserInputService.InputBegan:Connect(function(input, processed)
            if processed then return end
            if input.KeyCode == Enum.KeyCode.H then
                setEnabled(not ChainCfg.Enabled)
            end
        end)

        task.spawn(function() pcall(InstallChainHook) end)

        _G.N3K0P01_ChainAim = ChainCfg
        _G.N3K0P01_ChainAim_SetEnabled = setEnabled
        _G.N3K0P01_ChainAim_Destroy = function()
            ChainCfg.Enabled = false
            ChainHighlight.Adornee = nil
            if ChainHighlight then pcall(function() ChainHighlight:Destroy() end) end
            print("[ChainAim] Destroyed")
        end
    end

    local dashSection = CreateSection(KillerTab, "DASH LOCK (HIDDEN)", false)
    CreateToggle(dashSection, "Dash Lock (Hidden)", false, function(v) SetDashLock(v) end)
    UserInputService.InputBegan:Connect(function(input, processed)
        if processed or UserInputService:GetFocusedTextBox() then return end
        if input.KeyCode == Enum.KeyCode.V then SetDashLock(not dashLockState) end
    end)

    local spearSection = CreateSection(KillerTab, "SPEAR AIMBOT", false)
    CreateToggle(spearSection, "Enable Spear Aimbot", false, function(v)
        if W.SpearAimbot_SetEnabled then W.SpearAimbot_SetEnabled(v) end
    end)
    CreateSlider(spearSection, "Spear Gravity", 10, 200, tonumber(VD.SPEAR_Gravity) or 50, "", function(v)
        if W.SpearAimbot_SetGravity then W.SpearAimbot_SetGravity(v) end
    end, 0)
    CreateSlider(spearSection, "Spear Speed", 50, 300, tonumber(VD.SPEAR_Speed) or 100, "", function(v)
        if W.SpearAimbot_SetSpeed then W.SpearAimbot_SetSpeed(v) end
    end, 0)

    local flaskSection = CreateSection(KillerTab, "SILENT FLASK (THE CURE)", false)
    CreateToggle(flaskSection, "Enable Silent Flask", false, function(v)
        if W.Flask_SetEnabled then W.Flask_SetEnabled(v) end
    end)
    CreateToggle(flaskSection, "Show Flask Beam", false, function(v) VD.FLASK_ShowBeam = v == true end)
    CreateToggle(flaskSection, "Show Landing Marker", false, function(v) VD.FLASK_ShowLanding = v == true end)
    CreateToggle(flaskSection, "Enable Flask Prediction", false, function(v) VD.FLASK_Predict = v == true end)
    CreateSlider(flaskSection, "Flask Speed", 30, 200, tonumber(VD.FLASK_Speed) or 90, "", function(v) if W.Flask_SetSpeed then W.Flask_SetSpeed(v) end end, 0)
    CreateSlider(flaskSection, "Flask Gravity", 50, 400, tonumber(VD.FLASK_Gravity) or 196, "", function(v) if W.Flask_SetGravity then W.Flask_SetGravity(v) end end, 0)
    CreateSlider(flaskSection, "Flask Lead Multiplier", 0, 3, tonumber(VD.FLASK_LeadMult) or 1, "", function(v) if W.Flask_SetLead then W.Flask_SetLead(v) end end, 1)
    CreateSlider(flaskSection, "Flask Max Range", 50, 500, tonumber(VD.FLASK_Range) or 200, " studs", function(v) if W.Flask_SetRange then W.Flask_SetRange(v) end end, 0)
    CreateColorPicker(flaskSection, "Flask Beam Color", VD.FLASK_BeamColor or Color3.new(1, 1, 1), function(c) if W.Flask_SetBeamColor then W.Flask_SetBeamColor(c) end end)
    CreateColorPicker(flaskSection, "Flask Accent Color", VD.FLASK_AccentColor or Color3.fromRGB(25, 25, 25), function(c) if W.Flask_SetAccentColor then W.Flask_SetAccentColor(c) end end)

    local autoKillSection = CreateSection(KillerTab, "AUTO KILL ALL", false)
    CreateToggle(autoKillSection, "Auto Kill All", false, function(v)
        AutoKillAll = v == true
        if not AutoKillAll then KillAllTarget = nil end
        VD_Notify("Auto Kill All", v and "Enabled" or "Disabled", 2)
    end)
    CreateButton(autoKillSection, "Instant Auto Kill (1x)", function()
        local old = AutoKillAll
        AutoKillAll = true
        task.spawn(function()
            pcall(updateAutoKillAll)
            task.wait(0.3)
            AutoKillAll = old
        end)
    end)

    -- Veil Target Priority is intentionally hidden; it is fixed to Nearest.


    setConn("TianHubAimAndKillerWorker", RunService.Heartbeat:Connect(function()
        if AutoKillAll then pcall(updateAutoKillAll) end
    end))
end, function(err)
    return tostring(err)
end)
if not Stage4IntegrationOK then
    pcall(function() warn("[TianHub Stage 4 integration] " .. tostring(Stage4IntegrationError)) end)
end



-- Auto Run: PC keeps LeftShift held; mobile toggles the in-game sprint button while moving.
do
    local MovementSection = CreateSection("Main", "MOVEMENT", false)
    local AutoRunPCEnabled, AutoRunMobileEnabled = false, false
    local AutoRunPCThread, AutoRunMobileThread
    local AutoRunVIM = game:GetService("VirtualInputManager")
    local AutoRunGuiService = game:GetService("GuiService")

    local function AutoRunPCStart()
        if AutoRunPCThread then return end
        AutoRunPCThread = task.spawn(function()
            while AutoRunPCEnabled do
                pcall(function()
                    AutoRunVIM:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, LocalPlayer:GetMouse())
                end)
                task.wait(0.1)
            end
            pcall(function()
                AutoRunVIM:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, LocalPlayer:GetMouse())
            end)
            AutoRunPCThread = nil
        end)
    end
    local function AutoRunPCStop()
        AutoRunPCEnabled = false
        if AutoRunPCThread then task.cancel(AutoRunPCThread); AutoRunPCThread = nil end
        pcall(function() AutoRunVIM:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, LocalPlayer:GetMouse()) end)
    end
    local function AutoRunMobilePress()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        local mob = pg and pg:FindFirstChild("Survivor-mob")
        local controls = mob and mob:FindFirstChild("Controls")
        local sprint = controls and controls:FindFirstChild("sprint")
        if not sprint then return false end
        local btn = sprint:IsA("GuiButton") and sprint or sprint:FindFirstChildWhichIsA("GuiButton", true)
        if not btn then return false end
        pcall(function()
            if type(firesignal) == "function" then
                firesignal(btn.MouseButton1Click)
                firesignal(btn.MouseButton1Down)
                task.wait(0.04)
                firesignal(btn.MouseButton1Up)
            else
                local pos, size = btn.AbsolutePosition, btn.AbsoluteSize
                local inset = AutoRunGuiService:GetGuiInset()
                local id = 9901
                AutoRunVIM:SendTouchEvent(id, 0, pos.X + size.X/2 + inset.X, pos.Y + size.Y/2 + inset.Y)
                task.wait(0.04)
                AutoRunVIM:SendTouchEvent(id, 2, pos.X + size.X/2 + inset.X, pos.Y + size.Y/2 + inset.Y)
            end
        end)
        return true
    end
    local function AutoRunMobileStep()
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        local moving = hum.MoveDirection.Magnitude > 0.12
        if root then
            local velocity = root.AssemblyLinearVelocity
            moving = moving or Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 1.5
        end
        local crouching = char:GetAttribute("Crouching") == true or char:GetAttribute("Crouchingserver") == true
        local sprinting = char:GetAttribute("Sprinting") == true or char:GetAttribute("IsRunning") == true
        if crouching then
            if sprinting then AutoRunMobilePress() end
        elseif moving and not sprinting then
            AutoRunMobilePress()
        elseif not moving and sprinting then
            AutoRunMobilePress()
        end
    end
    local function AutoRunMobileStart()
        if AutoRunMobileThread then return end
        AutoRunMobileThread = task.spawn(function()
            while AutoRunMobileEnabled do
                pcall(AutoRunMobileStep)
                task.wait(0.12)
            end
            AutoRunMobileThread = nil
        end)
    end

    CreateToggle(MovementSection, "Auto Run [PC]", false, function(v)
        AutoRunPCEnabled = v
        if v then AutoRunPCStart() else AutoRunPCStop() end
    end)
    CreateToggle(MovementSection, "Auto Run [Mobile]", false, function(v)
        AutoRunMobileEnabled = v
        if v then AutoRunMobileStart() end
    end)

    -- TianHub Speed Boost; kept inside the existing MOVEMENT GroupBox.
    local SpeedBoostEnabled = false
    local SpeedBoostValue = 30
    local SpeedBoostConnection = nil
    local SpeedBoostAttackAnimations = {
        ["78432063483146"] = true, ["121216847022485"] = true, ["74968262036854"] = true,
        ["132817836308238"] = true, ["82666958311998"] = true, ["111920872708571"] = true,
        ["106871536134254"] = true, ["109402730355822"] = true, ["130593238885843"] = true,
        ["138720291317243"] = true, ["139369275981139"] = true, ["133963973694098"] = true,
        ["78935059863801"] = true, ["118907603246885"] = true, ["135002183282873"] = true,
        ["113255068724446"] = true, ["129784271201071"] = true, ["105374834496520"] = true,
        ["117070354890871"] = true, ["115244153053858"] = true, ["110355011987939"] = true,
        ["117042998468241"] = true, ["122812055447896"] = true,
    }

    local function ShouldDisableTianSpeedBoost()
        local char = LocalPlayer.Character
        if not char then return true end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            local animator = hum:FindFirstChildOfClass("Animator")
            if animator then
                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                    local anim = track.Animation
                    if anim and anim.AnimationId then
                        local animId = anim.AnimationId
                        if animId == "rbxassetid://127096285501517"
                            or animId == "rbxassetid://112166042383605"
                            or animId == "http://www.roblox.com/asset/?id=126965695851149"
                            or animId == "http://www.roblox.com/asset/?id=135084204086504"
                            or animId == "rbxassetid://123047897844134" then
                            return true
                        end
                        local id = animId:match("%d+")
                        if id and SpeedBoostAttackAnimations[id] then return true end
                    end
                end
            end
            if hum.Health <= 0 or hum.Health < 2
                or char:GetAttribute("Downed") == true
                or char:GetAttribute("IsDown") == true
                or char:GetAttribute("Knocked") == true then
                return true
            end
        end
        return false
    end

    local function SetTianSpeedBoost(enabled)
        SpeedBoostEnabled = enabled and true or false
        if SpeedBoostConnection then
            SpeedBoostConnection:Disconnect()
            SpeedBoostConnection = nil
        end
        if not SpeedBoostEnabled then
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then pcall(function() hum.WalkSpeed = 16 end) end
            return
        end
        SpeedBoostConnection = RunService.Heartbeat:Connect(function()
            if not SpeedBoostEnabled or ShouldDisableTianSpeedBoost() then return end
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and hum.WalkSpeed ~= SpeedBoostValue then
                pcall(function() hum.WalkSpeed = SpeedBoostValue end)
            end
        end)
    end

    CreateToggle(MovementSection, "Speed Boost", false, function(v)
        SetTianSpeedBoost(v)
    end)
    CreateSlider(MovementSection, "Speed Value", 16, 100, SpeedBoostValue, "", function(v)
        SpeedBoostValue = tonumber(v) or 30
    end)

    setConn("Tian_AutoRun_Respawn", LocalPlayer.CharacterAdded:Connect(function()
        task.wait(1)
        if AutoRunPCEnabled then AutoRunPCStart() end
        if AutoRunMobileEnabled then AutoRunMobileThread = nil; AutoRunMobileStart() end
        if SpeedBoostEnabled then SetTianSpeedBoost(true) end
    end))
end


-- TianHub Fast Bandage backend.
do
    local BANDAGE_URL = "https://raw.githubusercontent.com/pandu-hub1/Autofarm/refs/heads/main/Boostbandage.lua"
    local bandageAPI = nil
    local bandageLoaded = false
    local bandageMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    local bandageSpeed = tonumber(_G.TianHubBandageSpeed) or 50

    local function loadTianHubBandage()
        if bandageLoaded and bandageAPI then
            return true
        end
        local ok, result = pcall(function()
            return loadstring(game:HttpGet(BANDAGE_URL))()
        end)
        if not ok or type(result) ~= "table" then
            logQuiet("[TianHub] TianHub Fast Bandage load failed: " .. tostring(result))
            return false
        end
        bandageAPI = result
        bandageLoaded = true
        if bandageAPI.Config then
            bandageAPI.Config.PreClicksCount = bandageSpeed
        end
        return true
    end

    local function setTianHubBandageSpeed(value)
        bandageSpeed = math.clamp(math.floor(tonumber(value) or 50), 10, 200)
        _G.TianHubBandageSpeed = bandageSpeed
        if bandageAPI and bandageAPI.Config then
            bandageAPI.Config.PreClicksCount = bandageSpeed
        end
    end

    local function setTianHubBandageEnabled(enabled)
        if enabled then
            if not bandageLoaded and not loadTianHubBandage() then
                ShowToast("Fast Bandage", "Gagal memuat TianHub Bandage.")
                return false
            end
            if not bandageAPI then return false end
            if bandageAPI.Config then
                bandageAPI.Config.PreClicksCount = bandageSpeed
            end
            if bandageMobile then
                if type(bandageAPI.ShowGUI) == "function" then
                    pcall(bandageAPI.ShowGUI)
                end
            elseif type(bandageAPI.Start) == "function" then
                local ok, result = pcall(bandageAPI.Start)
                if not ok or result == false then
                    ShowToast("Fast Bandage", "TianHub Bandage gagal dimulai.")
                    return false
                end
            end
            return true
        end

        if bandageAPI then
            if bandageMobile and type(bandageAPI.HideGUI) == "function" then
                pcall(bandageAPI.HideGUI)
            end
            if type(bandageAPI.Stop) == "function" then
                pcall(bandageAPI.Stop)
            end
        end
        return true
    end

    _G.TianHub_FastBandage = {
        FB_SetEnabled = setTianHubBandageEnabled,
        FB_SetSpeed = setTianHubBandageSpeed,
        FB_Load = loadTianHubBandage,
    }

    setTianHubBandageSpeed(bandageSpeed)
    task.spawn(function()
        task.wait(2)
        loadTianHubBandage()
    end)
end


-- TIANHUB: Infinite Zoom, Killer Break Speed, Third Person Camera and Profile Spoofer.
do
    local MainCameraSection = CreateSection("Main", "CAMERA SETTINGS", false)
    local FakeAvatarProfileSection = CreateSection("Main", "FAKE AVATAR", false)
    local KillerCombatSection = CreateSection("Killer", "KILLER COMBAT", false)

    -- Infinite Zoom: maintain CameraMaxZoomDistance while enabled and restore its prior value.
    local TH_InfiniteZoom = false
    local TH_ZoomConn = nil
    local TH_ZoomPrevious = nil
    local function TH_SetInfiniteZoom(enabled)
        TH_InfiniteZoom = enabled == true
        if TH_ZoomConn then
            TH_ZoomConn:Disconnect()
            TH_ZoomConn = nil
        end
        if TH_InfiniteZoom then
            if TH_ZoomPrevious == nil then
                TH_ZoomPrevious = LocalPlayer.CameraMaxZoomDistance
            end
            pcall(function() LocalPlayer.CameraMaxZoomDistance = math.huge end)
            TH_ZoomConn = LocalPlayer:GetPropertyChangedSignal("CameraMaxZoomDistance"):Connect(function()
                if TH_InfiniteZoom and LocalPlayer.CameraMaxZoomDistance ~= math.huge then
                    pcall(function() LocalPlayer.CameraMaxZoomDistance = math.huge end)
                end
            end)
        else
            local restore = TH_ZoomPrevious
            TH_ZoomPrevious = nil
            if restore ~= nil then
                pcall(function() LocalPlayer.CameraMaxZoomDistance = restore end)
            end
        end
    end
    CreateToggle(MainCameraSection, "Infinite Zoom", false, TH_SetInfiniteZoom)

    -- Profile spoofing: restore original text and attributes when the toggles are disabled.
    local TH_FakeNameEnabled = false
    local TH_FakeProfileEnabled = false
    local TH_FakeDisplayName = "TianHub"
    local TH_FakeLevel = tonumber(LocalPlayer:GetAttribute("Level")) or 1
    local TH_FakeGears = tonumber(LocalPlayer:GetAttribute("Gears")) or 0
    local TH_FakeScrews = tonumber(LocalPlayer:GetAttribute("Screws")) or 0
    local TH_ProfileOriginal = {
        Level = LocalPlayer:GetAttribute("Level"),
        Gears = LocalPlayer:GetAttribute("Gears"),
        Screws = LocalPlayer:GetAttribute("Screws"),
    }
    local TH_ProfileHasOriginal = {
        Level = TH_ProfileOriginal.Level ~= nil,
        Gears = TH_ProfileOriginal.Gears ~= nil,
        Screws = TH_ProfileOriginal.Screws ~= nil,
    }
    local TH_FakeNameConnections = {}
    local function TH_DisconnectFakeName()
        for _, connection in ipairs(TH_FakeNameConnections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(TH_FakeNameConnections)
    end
    local function TH_RestoreFakeNameText(root)
        if not root then return end
        for _, obj in ipairs(root:GetDescendants()) do
            if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                local original = obj:GetAttribute("TianHubOriginalText")
                if original ~= nil then
                    pcall(function()
                        obj.Text = tostring(original)
                        obj:SetAttribute("TianHubOriginalText", nil)
                    end)
                end
            end
        end
    end
    local function TH_ApplyFakeNameToObject(obj)
        if not TH_FakeNameEnabled or not obj then return end
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            local textNow = obj.Text
            if obj:GetAttribute("TianHubOriginalText") == nil then
                obj:SetAttribute("TianHubOriginalText", textNow)
            end
            local changed = textNow
            local matched = false
            for _, player in ipairs(Players:GetPlayers()) do
                if player.Name ~= "" and string.find(changed, player.Name, 1, true) then
                    changed = string.gsub(changed, player.Name, TH_FakeDisplayName)
                    matched = true
                end
                if player.DisplayName ~= "" and string.find(changed, player.DisplayName, 1, true) then
                    changed = string.gsub(changed, player.DisplayName, TH_FakeDisplayName)
                    matched = true
                end
            end
            if matched and changed ~= textNow then
                pcall(function() obj.Text = changed end)
            end
            local conn = obj:GetPropertyChangedSignal("Text"):Connect(function()
                if TH_FakeNameEnabled then
                    task.defer(function()
                        if TH_FakeNameEnabled and obj.Parent then
                            local latest = obj.Text
                            local replaced = latest
                            local didMatch = false
                            for _, player in ipairs(Players:GetPlayers()) do
                                if player.Name ~= "" and string.find(replaced, player.Name, 1, true) then
                                    replaced = string.gsub(replaced, player.Name, TH_FakeDisplayName)
                                    didMatch = true
                                end
                                if player.DisplayName ~= "" and string.find(replaced, player.DisplayName, 1, true) then
                                    replaced = string.gsub(replaced, player.DisplayName, TH_FakeDisplayName)
                                    didMatch = true
                                end
                            end
                            if didMatch and replaced ~= latest then pcall(function() obj.Text = replaced end) end
                        end
                    end)
                end
            end)
            table.insert(TH_FakeNameConnections, conn)
        end
    end
    local function TH_SetFakeName(enabled)
        TH_FakeNameEnabled = enabled == true
        TH_DisconnectFakeName()
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not playerGui then return end
        if TH_FakeNameEnabled then
            for _, obj in ipairs(playerGui:GetDescendants()) do
                TH_ApplyFakeNameToObject(obj)
            end
            table.insert(TH_FakeNameConnections, playerGui.DescendantAdded:Connect(function(obj)
                task.defer(function()
                    if TH_FakeNameEnabled then TH_ApplyFakeNameToObject(obj) end
                end)
            end))
        else
            TH_RestoreFakeNameText(playerGui)
        end
    end
    local function TH_SetFakeProfile(enabled)
        TH_FakeProfileEnabled = enabled == true
        if TH_FakeProfileEnabled then
            pcall(function() LocalPlayer:SetAttribute("Level", TH_FakeLevel) end)
            pcall(function() LocalPlayer:SetAttribute("Gears", TH_FakeGears) end)
            pcall(function() LocalPlayer:SetAttribute("Screws", TH_FakeScrews) end)
        else
            for _, key in ipairs({"Level", "Gears", "Screws"}) do
                pcall(function()
                    if TH_ProfileHasOriginal[key] then
                        LocalPlayer:SetAttribute(key, TH_ProfileOriginal[key])
                    else
                        LocalPlayer:SetAttribute(key, nil)
                    end
                end)
            end
        end
    end
    CreateToggle(FakeAvatarProfileSection, "TianHub Fake Name", false, TH_SetFakeName)
    CreateToggle(FakeAvatarProfileSection, "TianHub Fake Profile", false, TH_SetFakeProfile)
    CreateTextBox(FakeAvatarProfileSection, "Profile Display Name", "TianHub", function(value)
        local cleaned = tostring(value or ""):sub(1, 32)
        if cleaned ~= "" then
            TH_FakeDisplayName = cleaned
            if TH_FakeNameEnabled then TH_SetFakeName(true) end
        end
    end)
    CreateTextBox(FakeAvatarProfileSection, "Profile Level", tostring(TH_FakeLevel), function(value)
        local n = tonumber(value)
        if n then TH_FakeLevel = math.clamp(math.floor(n), 0, 1000000000); if TH_FakeProfileEnabled then TH_SetFakeProfile(true) end end
    end)
    CreateTextBox(FakeAvatarProfileSection, "Profile Gears", tostring(TH_FakeGears), function(value)
        local n = tonumber(value)
        if n then TH_FakeGears = math.clamp(math.floor(n), 0, 1000000000); if TH_FakeProfileEnabled then TH_SetFakeProfile(true) end end
    end)
    CreateTextBox(FakeAvatarProfileSection, "Profile Screws", tostring(TH_FakeScrews), function(value)
        local n = tonumber(value)
        if n then TH_FakeScrews = math.clamp(math.floor(n), 0, 1000000000); if TH_FakeProfileEnabled then TH_SetFakeProfile(true) end end
    end)

    -- Killer-only role check follows the game's Team/Role attributes.
    local function TH_IsLocalKiller()
        local char = LocalPlayer.Character
        local function roleIsKiller(inst)
            if not inst then return false end
            local role = tostring(inst:GetAttribute("Role") or ""):lower()
            return role == "killer" or inst:GetAttribute("IsKiller") == true
        end
        if roleIsKiller(LocalPlayer) or roleIsKiller(char) then return true end
        local teamName = LocalPlayer.Team and tostring(LocalPlayer.Team.Name):lower() or ""
        return teamName:find("killer", 1, true) ~= nil
    end

    local TH_BreakSpeed = 1
    CreateSlider(KillerCombatSection, "Break Speed", 1, 10, 1, "x", function(value)
        TH_BreakSpeed = math.clamp(math.floor(tonumber(value) or 1), 1, 10)
    end, 0)
    local TH_ThirdPersonEnabled = false
    local TH_ThirdPersonMode = "Classic"
    local TH_ThirdPersonConn = nil
    local TH_CameraOriginal = nil
    local function TH_ApplyThirdPerson()
        if not TH_ThirdPersonEnabled or not TH_IsLocalKiller() then return end
        pcall(function()
            LocalPlayer.CameraMode = Enum.CameraMode.Classic
            LocalPlayer.CameraMinZoomDistance = 7
            LocalPlayer.CameraMaxZoomDistance = TH_InfiniteZoom and math.huge or 40
            LocalPlayer.DevComputerCameraMode = Enum.DevComputerCameraMovementMode[TH_ThirdPersonMode] or Enum.DevComputerCameraMovementMode.Classic
            LocalPlayer.DevTouchCameraMode = Enum.DevTouchCameraMovementMode[TH_ThirdPersonMode] or Enum.DevTouchCameraMovementMode.Classic
        end)
    end
    local function TH_SetThirdPerson(enabled)
        TH_ThirdPersonEnabled = enabled == true
        if TH_ThirdPersonConn then
            TH_ThirdPersonConn:Disconnect()
            TH_ThirdPersonConn = nil
        end
        if TH_ThirdPersonEnabled then
            if not TH_CameraOriginal then
                TH_CameraOriginal = {
                    CameraMode = LocalPlayer.CameraMode,
                    MinZoom = LocalPlayer.CameraMinZoomDistance,
                    MaxZoom = LocalPlayer.CameraMaxZoomDistance,
                    DevComputer = LocalPlayer.DevComputerCameraMode,
                    DevTouch = LocalPlayer.DevTouchCameraMode,
                }
            end
            TH_ApplyThirdPerson()
            TH_ThirdPersonConn = RunService.RenderStepped:Connect(TH_ApplyThirdPerson)
        elseif TH_CameraOriginal then
            local original = TH_CameraOriginal
            TH_CameraOriginal = nil
            pcall(function()
                LocalPlayer.CameraMode = original.CameraMode
                LocalPlayer.CameraMinZoomDistance = original.MinZoom
                LocalPlayer.CameraMaxZoomDistance = TH_InfiniteZoom and math.huge or original.MaxZoom
                LocalPlayer.DevComputerCameraMode = original.DevComputer
                LocalPlayer.DevTouchCameraMode = original.DevTouch
            end)
        end
    end
    CreateToggle(KillerCombatSection, "3rd Person Camera", false, TH_SetThirdPerson)
    TianHubState.CreateDropdown(KillerCombatSection, "3rd Person Mode", {"Classic", "Follow"}, TH_ThirdPersonMode, function(value)
        if type(value) == "table" then value = value[1] end
        if value == "Classic" or value == "Follow" then
            TH_ThirdPersonMode = value
            TH_ApplyThirdPerson()
        end
    end)

    local TH_BreakSpeedConn = RunService.Heartbeat:Connect(function()
        if TH_IsLocalKiller() then
            local character = LocalPlayer.Character
            if character and character:GetAttribute("breakspeed") ~= TH_BreakSpeed then
                pcall(function() character:SetAttribute("breakspeed", TH_BreakSpeed) end)
            end
        end
    end)

    -- Keep the camera modes and profile values clean on script teardown/re-execution.
    table.insert(TianHubState.Connections or {}, TH_BreakSpeedConn)
    LocalPlayer.CharacterAdded:Connect(function()
        task.wait(0.5)
        if TH_FakeProfileEnabled then TH_SetFakeProfile(true) end
        if TH_FakeNameEnabled then TH_SetFakeName(true) end
        if TH_ThirdPersonEnabled then TH_ApplyThirdPerson() end
    end)
end


-- TianHub UI is finalized without a legacy loading renderer.
task.wait()
xpcall(function()
    local function arrange(tab, left, right)
        local entries = CardList[tab] or {}
        local byTitle = {}
        for _, entry in ipairs(entries) do byTitle[entry.title] = entry end
        local used = {}
        local function place(column, titles)
            for order, title in ipairs(titles) do
                local entry = byTitle[title]
                if entry then
                    entry.card.Parent = UI.pages[tab].columns[column]
                    entry.card.LayoutOrder = order
                    used[title] = true
                end
            end
        end
        place(1, left)
        place(2, right)
        -- Preserve any unlisted existing sections instead of dropping them.
        local leftOrder, rightOrder = #left + 1, #right + 1
        for _, entry in ipairs(entries) do
            if not used[entry.title] then
                local column = (#UI.pages[tab].columns[1]:GetChildren() <= #UI.pages[tab].columns[2]:GetChildren()) and 1 or 2
                entry.card.Parent = UI.pages[tab].columns[column]
                if column == 1 then
                    entry.card.LayoutOrder = leftOrder
                    leftOrder += 1
                else
                    entry.card.LayoutOrder = rightOrder
                    rightOrder += 1
                end
            end
        end
    end


    -- TIANHUB STUN INDICATOR (isolated module)
    -- Its controls are merged into the existing ESP > INFORMATION GroupBox.
    do
        local THS = {
            Enabled = false,
            Range = 500,
            SoundEnabled = true,
            SoundVolume = 5,
            SelectedSound = "Default",
            Cache = {},
            Conn = nil,
            Sounds = {
                ["an anime"]="128090092396552",
                ["Default"]="18843924331",
                ["Clash Royale"]="114072050006157",
                ["Blash"]="89068385567682",
                ["antek asing"]="129760109847577",
                ["hidup Jokowi"]="116121992738402",
                ["Kururin Kuru"]="119896940405402",
                ["Spongebob"]="6835794541",
                ["Fahhhh"]="123562480982353",
                ["Aughhh"]="9095205664",
                ["iPhone"]="4203251375",
                ["Siren"]="130677853589923",
            },
        }

        local function THS_IsKiller(player, character)
            if not player or player == LocalPlayer or not character then return false end
            local function hasRole(inst)
                if not inst then return false end
                local role = tostring(inst:GetAttribute("Role") or ""):lower()
                return role == "killer" or inst:GetAttribute("IsKiller") == true
            end
            if hasRole(player) or hasRole(character) then return true end
            if player.Team then
                local teamName = player.Team.Name:lower()
                if teamName:find("killer") or teamName:find("slasher")
                    or teamName:find("hunter") or teamName:find("monster") then
                    return true
                end
            end
            local killersFolder = workspace:FindFirstChild("Killers")
            if killersFolder and character:IsDescendantOf(killersFolder) then return true end
            return false
        end

        local function THS_IsStunned(character)
            if not character then return false end
            for _, attribute in ipairs({"IsStunned", "isStunned", "Stunned", "stunned", "IsStun", "Stun"}) do
                if character:GetAttribute(attribute) == true then return true end
            end
            local check = character:FindFirstChild("CheckInterractable")
            if check and (check:GetAttribute("isStunned") == true or check:GetAttribute("Stunned") == true) then
                return true
            end
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            local stunValue = humanoid and humanoid:FindFirstChild("StunValue")
            return stunValue ~= nil and tonumber(stunValue.Value) ~= nil and stunValue.Value > 0
        end

        local function THS_Remove(character, instant)
            local data = THS.Cache[character]
            if not data then return end
            THS.Cache[character] = nil
            if data.Stop then data.Stop() end
            if data.Gui then
                if instant then
                    pcall(function() data.Gui:Destroy() end)
                else
                    task.delay(0.22, function()
                        pcall(function() if data.Gui then data.Gui:Destroy() end end)
                    end)
                end
            end
        end

        local function THS_PlaySound(character)
            if not THS.SoundEnabled then return end
            local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
            if not head then return end
            pcall(function()
                local sound = Instance.new("Sound")
                sound.Name = "TianHubStunAlert"
                sound.SoundId = "rbxassetid://" .. tostring(THS.Sounds[THS.SelectedSound] or THS.Sounds.Default)
                sound.Volume = THS.SoundVolume
                sound.RollOffMaxDistance = 500
                sound.RollOffMinDistance = 10
                sound.RollOffMode = Enum.RollOffMode.InverseTapered
                sound.Parent = head
                sound:Play()
                sound.Ended:Connect(function() pcall(function() sound:Destroy() end) end)
                task.delay(6, function() pcall(function() if sound.Parent then sound:Destroy() end end) end)
            end)
        end

        local function THS_CreateIndicator(character)
            if THS.Cache[character] then return end
            local head = character and character:FindFirstChild("Head")
            if not head then return end

            local billboard = Instance.new("BillboardGui")
            billboard.Name = "TianHubStunIndicator"
            billboard.Size = UDim2.fromOffset(136, 40)
            billboard.StudsOffset = Vector3.new(0, 3, 0)
            billboard.AlwaysOnTop = true
            billboard.LightInfluence = 0
            billboard.MaxDistance = 2000
            billboard.Adornee = head
            billboard.Parent = character

            -- Reuse the exact artwork ID used by TianHub's floating menu button.
            local background = Instance.new("ImageLabel")
            background.Name = "TianHubMenuBackground"
            background.Size = UDim2.fromScale(1, 1)
            background.Position = UDim2.fromScale(0, 0)
            background.BackgroundColor3 = Color3.fromRGB(17, 10, 32)
            background.BackgroundTransparency = 0
            background.BorderSizePixel = 0
            background.ClipsDescendants = true
            background.Image = "rbxassetid://134541569123256"
            background.ImageColor3 = Color3.fromRGB(190, 190, 190)
            background.ImageTransparency = 0.12
            background.ScaleType = Enum.ScaleType.Crop
            background.Parent = billboard
            Instance.new("UICorner", background).CornerRadius = UDim.new(0, 9)

            local shade = Instance.new("Frame")
            shade.Name = "ReadabilityOverlay"
            shade.Size = UDim2.fromScale(1, 1)
            shade.BackgroundColor3 = Color3.fromRGB(5, 5, 10)
            shade.BackgroundTransparency = 0.38
            shade.BorderSizePixel = 0
            shade.Parent = background
            Instance.new("UICorner", shade).CornerRadius = UDim.new(0, 9)

            local stroke = Instance.new("UIStroke")
            stroke.Color = Color3.fromRGB(255, 255, 255)
            stroke.Thickness = 1
            stroke.Transparency = 0.28
            stroke.Parent = background

            local title = Instance.new("TextLabel")
            title.Name = "StunText"
            title.BackgroundTransparency = 1
            title.Size = UDim2.fromScale(1, 1)
            title.Position = UDim2.fromScale(0, 0)
            title.Font = Enum.Font.GothamBlack
            title.Text = "STUNNED!"
            title.TextColor3 = Color3.new(1, 1, 1)
            title.TextSize = 15
            title.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
            title.TextStrokeTransparency = 0.55
            title.TextXAlignment = Enum.TextXAlignment.Center
            title.TextYAlignment = Enum.TextYAlignment.Center
            title.Parent = background

            background.Size = UDim2.fromOffset(0, 0)
            TweenService:Create(background, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                Size = UDim2.fromScale(1, 1)
            }):Play()

            THS.Cache[character] = {
                Gui = billboard,
                Stop = function() end,
            }
            return THS.Cache[character]
        end

        local function THS_SetEnabled(value)
            THS.Enabled = value == true
            if THS.Conn then
                THS.Conn:Disconnect()
                THS.Conn = nil
            end
            if not THS.Enabled then
                for character in pairs(THS.Cache) do THS_Remove(character, true) end
                return
            end

            THS.Conn = RunService.Heartbeat:Connect(function()
                local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if not myRoot then return end
                local seen = {}
                for _, player in ipairs(Players:GetPlayers()) do
                    local character = player.Character
                    if character and THS_IsKiller(player, character) then
                        local root = character:FindFirstChild("HumanoidRootPart")
                        if root then
                            local distance = (root.Position - myRoot.Position).Magnitude
                            local stunned = distance <= THS.Range and THS_IsStunned(character)
                            seen[character] = true
                            local existing = THS.Cache[character]
                            if stunned and not existing then
                                local created = THS_CreateIndicator(character)
                                if created then THS_PlaySound(character) end
                            elseif not stunned and existing then
                                THS_Remove(character, false)
                            end
                        end
                    end
                end
                for character in pairs(THS.Cache) do
                    if not seen[character] or not character.Parent then
                        THS_Remove(character, true)
                    end
                end
            end)
        end

        -- Audio-only VDT stun alert. No BillboardGui, text, Highlight, or ESP is created.
        local DBDStunPistol = { Enabled = false, Seen = {}, Conn = nil, LastScan = 0 }
        local function DBDStunPistol_Play(character)
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if not root then return end
            pcall(function()
                local sound = Instance.new("Sound")
                sound.Name = "DBDStunPistolSound"
                sound.Volume = 5
                sound.SoundId = "rbxassetid://140209514807090"
                sound.Parent = root
                sound:Play()
                sound.Ended:Connect(function() pcall(function() sound:Destroy() end) end)
                task.delay(6, function()
                    pcall(function() if sound.Parent then sound:Destroy() end end)
                end)
            end)
        end

        local function DBDStunPistol_SetEnabled(value)
            DBDStunPistol.Enabled = value == true
            if DBDStunPistol.Conn then
                DBDStunPistol.Conn:Disconnect()
                DBDStunPistol.Conn = nil
            end
            table.clear(DBDStunPistol.Seen)
            if not DBDStunPistol.Enabled then return end

            DBDStunPistol.Conn = RunService.Heartbeat:Connect(function()
                if os.clock() - DBDStunPistol.LastScan < 0.12 then return end
                DBDStunPistol.LastScan = os.clock()
                local active = {}
                for _, player in ipairs(Players:GetPlayers()) do
                    local character = player.Character
                    if character and THS_IsKiller(player, character) then
                        local stunned = character:GetAttribute("IsStunned") == true
                        if stunned then
                            active[character] = true
                            if not DBDStunPistol.Seen[character] then
                                DBDStunPistol_Play(character)
                            end
                        end
                    end
                end
                for character in pairs(DBDStunPistol.Seen) do
                    if not active[character] then
                        DBDStunPistol.Seen[character] = nil
                    end
                end
                for character in pairs(active) do
                    DBDStunPistol.Seen[character] = true
                end
            end)
        end

        CreateToggle(ToFSection, "DBD Stun Pistol", false, DBDStunPistol_SetEnabled)

        local stunSection = CreateSection(VisualTab, "STUN INDICATOR")
        CreateToggle(stunSection, "Enable Stun Indicator", false, THS_SetEnabled)
        TianHubState.CreateDropdown(stunSection, "Stun Sound", {
            "an anime", "Default", "Clash Royale", "Blash", "antek asing", "hidup Jokowi",
            "Kururin Kuru", "Spongebob", "Fahhhh", "Aughhh", "iPhone", "Siren"
        }, "Default", function(value)
            THS.SelectedSound = value
        end)
        CreateToggle(stunSection, "Stun Sound Alert", true, function(value)
            THS.SoundEnabled = value == true
        end)
        CreateButton(stunSection, "Preview Sound", function()
            pcall(function()
                local sound = Instance.new("Sound")
                sound.SoundId = "rbxassetid://" .. tostring(THS.Sounds[THS.SelectedSound] or THS.Sounds.Default)
                sound.Volume = THS.SoundVolume
                sound.Parent = LocalPlayer:FindFirstChildOfClass("PlayerGui") or workspace
                sound:Play()
                sound.Ended:Connect(function() pcall(function() sound:Destroy() end) end)
                task.delay(6, function() pcall(function() if sound.Parent then sound:Destroy() end end) end)
            end)
        end)
    end

    arrange("Main",
        { "MOVEMENT", "CAMERA SETTINGS", "CROSSHAIR", "WEATHER & SKY", "SKIP CUTSCENE", "STREAMER MODE" },
        { "FAKE AKSESORIS 8BIT", "FAKE AVATAR", "LIGHTING", "TREE & GRASS", "EMOTE WHEEL" }
    )
    arrange("ESP",
        { "PLAYER ESP", "KILLER ESP", "INFORMATION" },
        { "OBJECT ESP" }
    )
    arrange("Survivor",
        { "AUTO PARRY", "AUTO SKILL CHECK", "AUTO SKILL CHECK TRAP", "FLOWSTATE", "FAKE PERKS", "TWIST OF FATE", "ESCAPE" },
        { "SILENT AIM TOF", "AIMBOT SURVIVOR", "SILENT FLASHLIGHT", "SELF HEAL", "FAST BANDAGE", "ANTI SLOW VAULT", "SURVIVAL", "AUTO DODGE CROUCH", "AUTO DODGE SPEAR", "MOONWALK", "GOD MODE", "NO CLIP" }
    )
    arrange("Killer",
        { "SILENT VEIL SPEAR AIM", "SPEAR AIMBOT", "SILENT AIM BUTCHER", "SILENT FLASK (THE CURE)", "SELECT MASKED POWER" },
        { "KILLER ABILITIES", "AUTO KILL ALL", "DASH LOCK (HIDDEN)", "KILLER COMBAT" }
    )
    arrange("Music",
        { "MINI MUSIC PLAYER", "MUSIC LIBRARY", "CUSTOM SOUND ID" },
        { "PLAYBACK", "SOUND SETTINGS" }
    )

    -- Settings cards are created directly by the UI builder, so order them here.
    local settingsLeft = { "GeneralCard", "AccentColorCard", "PlayerCard", "ServerCard" }
    local settingsRight = { "PreferencesCard", "ActionsCard", "AboutCard" }
    for column, names in ipairs({ settingsLeft, settingsRight }) do
        for order, name in ipairs(names) do
            local card = UI.pages.Settings.columns[column]:FindFirstChild(name, true)
            if card then
                card.Parent = UI.pages.Settings.columns[column]
                card.LayoutOrder = order
            end
        end
    end
end, function(e) logQuiet("[TianHub] arrange error: " .. tostring(e)) end)


--====================================================--
-- TIANHUB CONFIG MANAGER (ported from supplied Anonimus.lua)
-- Native TianHub Settings card; keeps existing feature code untouched.
--====================================================--
do
    local ConfigSection = CreateSection("Settings", "CONFIG MANAGER", false)
    local ConfigDir = "TianHub/Configs"
    local configName = ""
    local selectedConfig = nil
    local configDropdown = nil
    local autoLoadEnabled = false
    local autoLoadPath = ConfigDir .. "/_autoload.json"

    local function configNotify(message)
        pcall(function()
            if UI.toast then UI.toast("[CONFIG] " .. tostring(message)) end
        end)
    end

    local function ensureConfigDir()
        if type(isfolder) == "function" and type(makefolder) == "function" then
            pcall(function() if not isfolder("TianHub") then makefolder("TianHub") end end)
            pcall(function() if not isfolder(ConfigDir) then makefolder(ConfigDir) end end)
        end
    end

    local function getConfigFiles()
        local names = {}
        ensureConfigDir()
        if type(listfiles) == "function" then
            local ok, files = pcall(listfiles, ConfigDir)
            if ok and type(files) == "table" then
                for _, filePath in ipairs(files) do
                    local name = tostring(filePath):match("([^/\\]+)%.json$")
                    if name and name ~= "_autoload" then
                        table.insert(names, name)
                    end
                end
            end
        end
        table.sort(names)
        return names
    end

    local function refreshConfigDropdown()
        local names = getConfigFiles()
        if configDropdown and configDropdown.Holder then
            pcall(function() configDropdown.Holder:Destroy() end)
        end
        if #names == 0 then names = {"No saved configs"} end
        if not table.find(names, selectedConfig) then selectedConfig = nil end
        configDropdown = UI.makeDropdown(ConfigSection, "SAVED CONFIGS", names,
            selectedConfig or names[1], function(value)
                selectedConfig = value ~= "No saved configs" and value or nil
            end)
        return names
    end

    local function buildConfigSnapshot()
        local snapshot = {
            _version = 1,
            _timestamp = os.time(),
            _name = configName,
            _controls = {},
        }
        local keys = {}
        for key, control in pairs(UI.controls) do
            if type(control) == "table" and type(control.Get) == "function" and type(control.Set) == "function" then
                table.insert(keys, key)
            end
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
            local control = UI.controls[key]
            local ok, value = pcall(control.Get)
            if ok and (type(value) == "boolean" or type(value) == "number"
                or type(value) == "string" or type(value) == "table") then
                local encodedOK = pcall(function() HttpService:JSONEncode(value) end)
                if encodedOK then snapshot._controls[key] = value end
            end
        end
        return snapshot
    end

    local function saveConfig(name)
        name = tostring(name or ""):gsub("[\\/:*?\"<>|]", "_"):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then return false, "Isi nama config terlebih dahulu" end
        if type(writefile) ~= "function" then return false, "Executor tidak mendukung writefile" end
        ensureConfigDir()
        local snapshot = buildConfigSnapshot()
        snapshot._name = name
        local okEncode, encoded = pcall(function() return HttpService:JSONEncode(snapshot) end)
        if not okEncode then return false, "Gagal membuat data config" end
        local path = ConfigDir .. "/" .. name .. ".json"
        local okWrite = pcall(writefile, path, encoded)
        if not okWrite then return false, "Gagal menyimpan config" end
        configName, selectedConfig = name, name
        refreshConfigDropdown()
        return true, "Config tersimpan: " .. name
    end

    local function loadConfig(name, quiet)
        name = tostring(name or "")
        if name == "" or name == "No saved configs" then return false, "Pilih config terlebih dahulu" end
        if type(readfile) ~= "function" or type(isfile) ~= "function" then
            return false, "Executor tidak mendukung readfile/isfile"
        end
        local path = ConfigDir .. "/" .. name .. ".json"
        if not isfile(path) then return false, "Config tidak ditemukan: " .. name end
        local okRead, raw = pcall(readfile, path)
        if not okRead or type(raw) ~= "string" then return false, "Gagal membaca config" end
        local okDecode, snapshot = pcall(function() return HttpService:JSONDecode(raw) end)
        if not okDecode or type(snapshot) ~= "table" or type(snapshot._controls) ~= "table" then
            return false, "Format config tidak valid"
        end

        local applied, failed = 0, 0
        for key, value in pairs(snapshot._controls) do
            local control = UI.controls[key]
            if control and type(control.Set) == "function" then
                local okSet = pcall(function() control.Set(value, true) end)
                if okSet then applied = applied + 1 else failed = failed + 1 end
            else
                failed = failed + 1
            end
        end
        configName, selectedConfig = name, name
        if not quiet then
            configNotify("Loaded " .. name .. " • " .. applied .. " setting" .. (failed > 0 and (" • " .. failed .. " gagal") or ""))
        end
        return true, "Config dimuat: " .. name
    end

    CreateTextBox(ConfigSection, "CONFIG NAME", "Masukkan nama config", function(value)
        configName = value
    end)

    CreateButton(ConfigSection, "SAVE CONFIG", function()
        local ok, message = saveConfig(configName)
        configNotify(message)
    end)

    refreshConfigDropdown()

    CreateButton(ConfigSection, "LOAD CONFIG", function()
        local ok, message = loadConfig(selectedConfig or configName, false)
        if not ok then configNotify(message) end
    end)

    CreateButton(ConfigSection, "DELETE CONFIG", function()
        local name = selectedConfig
        if not name then configNotify("Pilih config terlebih dahulu"); return end
        local path = ConfigDir .. "/" .. name .. ".json"
        if type(isfile) == "function" and type(delfile) == "function" and isfile(path) then
            local ok = pcall(delfile, path)
            if ok then
                selectedConfig = nil
                refreshConfigDropdown()
                configNotify("Config dihapus: " .. name)
            else
                configNotify("Gagal menghapus config")
            end
        else
            configNotify("File config tidak ditemukan atau executor tidak mendukung delfile")
        end
    end)

    CreateButton(ConfigSection, "REFRESH CONFIG LIST", function()
        refreshConfigDropdown()
        configNotify("Daftar config diperbarui")
    end)

    CreateToggle(ConfigSection, "AUTO LOAD LAST CONFIG", false, function(enabled)
        autoLoadEnabled = enabled == true
        ensureConfigDir()
        if type(writefile) == "function" then
            local ok, encoded = pcall(function()
                return HttpService:JSONEncode({Enabled = autoLoadEnabled, Name = selectedConfig or configName})
            end)
            if ok then pcall(writefile, autoLoadPath, encoded) end
        end
    end)

    -- Restore the auto-load preference and last selected config after controls exist.
    task.defer(function()
        ensureConfigDir()
        if type(readfile) == "function" and type(isfile) == "function" and isfile(autoLoadPath) then
            local ok, raw = pcall(readfile, autoLoadPath)
            if ok and type(raw) == "string" then
                local decodedOK, data = pcall(function() return HttpService:JSONDecode(raw) end)
                if decodedOK and type(data) == "table" then
                    autoLoadEnabled = data.Enabled == true
                    local rememberedName = tostring(data.Name or "")
                    if autoLoadEnabled and rememberedName ~= "" then
                        task.wait(0.35)
                        local loaded, err = loadConfig(rememberedName, true)
                        if loaded then
                            configNotify("Auto loaded: " .. rememberedName)
                        else
                            warn("[TianHub Config] Auto load failed: " .. tostring(err))
                        end
                    end
                end
            end
        end
    end)
end

-- INFO CONFIG: adapted from the Config Info paragraph in the supplied Anonimus.lua.
do
    local InfoConfigSection = CreateSection("Settings", "INFO CONFIG", false)
    local info = Instance.new("TextLabel")
    info.Name = "ConfigUsageInfo"
    info.BackgroundTransparency = 1
    info.BorderSizePixel = 0
    info.Size = UDim2.new(1, -8, 0, 0)
    info.AutomaticSize = Enum.AutomaticSize.Y
    info.Font = Enum.Font.Gotham
    info.TextSize = 12
    info.TextColor3 = C.muted
    info.TextXAlignment = Enum.TextXAlignment.Left
    info.TextYAlignment = Enum.TextYAlignment.Top
    info.TextWrapped = true
    info.RichText = false
    info.Text = "CARA PAKAI CONFIG\n• Save: tulis nama config, klik Save\n• Load: pilih Saved Configs, klik Load\n• Load akan menerapkan kembali setting fitur yang tersimpan\n• Auto Load: config terakhir dapat dipulihkan saat script start\n• Delete: hapus config yang dipilih"
    info.Parent = InfoConfigSection
end

-- Show the TianHub interface even if an optional Killer integration fails.
-- Keep logo resolution isolated so it cannot prevent the menu from opening.
UI.gui.Enabled = true
pcall(function() UI.startLogoResolver(UI.gui) end)
pcall(function() UI.openUI() end)
originalPrint("TianHub loaded")
