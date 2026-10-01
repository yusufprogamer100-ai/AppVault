--[[
    Nuke Simulator 4 - Advanced WindUI Hub (No Cooldown & Volcano Level System)
    Created by Antigravity
--]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local lp = Players.LocalPlayer

-- Load WindUI
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

-- State Configuration
local Config = {
    PlacingDelay = 0.03,
    AutoExplodeAll = false,
    AutoRefill = false,
    ServerNoDelay = true,
    ExplosionMultiplier = 1,
    VolcanoLevel = 500,
    AutoApplyVolcanoLevel = true,
    AntiFlash = true,
    AntiShake = true,
}

-- Ensure Server No Delay is fired
local function toggleServerDelay()
    local toggleRemote = ReplicatedStorage:FindFirstChild("ToggleNoTime")
    if toggleRemote and toggleRemote:IsA("RemoteEvent") then
        toggleRemote:FireServer()
    end
end

-- Automatically fire ToggleNoTime at start
task.spawn(function()
    toggleServerDelay()
end)

-- Anti-Flash / Anti-Lag
local function applyAntiFlash()
    local pg = lp:FindFirstChild("PlayerGui")
    if not pg then return end
    
    local flashGuis = {"FireballBrightness", "ImpactFrames", "Black", "EAS", "Static", "Pim"}
    for _, name in ipairs(flashGuis) do
        local g = pg:FindFirstChild(name)
        if g and g:IsA("ScreenGui") then
            g.Enabled = not Config.AntiFlash
        end
    end
end

-- Volcano Growth modifier: sets Growth.Value on any Volcano tool
local function applyVolcanoLevelToTool(tool)
    if not tool or not tool:IsA("Tool") then return end
    if tool.Name:find("Volcano") then
        local growth = tool:FindFirstChild("Growth", true)
        if growth and growth:IsA("NumberValue") then
            growth.Value = Config.VolcanoLevel
        end
    end
end

-- Check inventory & workspace for Volcanoes
local function scanAndApplyVolcanoLevels()
    if not Config.AutoApplyVolcanoLevel then return end
    
    -- In Backpack
    local bp = lp:FindFirstChild("Backpack")
    if bp then
        for _, item in ipairs(bp:GetChildren()) do
            applyVolcanoLevelToTool(item)
        end
    end
    -- In Character
    local char = lp.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            applyVolcanoLevelToTool(item)
        end
    end
    -- In Workspace (spawned volcanoes)
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj.Name:find("Volcano") then
            local g = obj:FindFirstChild("Growth", true)
            if g and g:IsA("NumberValue") then
                g.Value = Config.VolcanoLevel
            end
        end
    end
end

-- Explosion multiplier
Workspace.DescendantAdded:Connect(function(desc)
    if desc:IsA("Explosion") and Config.ExplosionMultiplier > 1 then
        pcall(function()
            desc.BlastRadius = desc.BlastRadius * Config.ExplosionMultiplier
            desc.BlastPressure = desc.BlastPressure * Config.ExplosionMultiplier
        end)
    elseif desc.Name == "Growth" and desc:IsA("NumberValue") and Config.AutoApplyVolcanoLevel then
        pcall(function()
            desc.Value = Config.VolcanoLevel
        end)
    end
end)

-- Explode All
local function explodeAll()
    local char = lp.Character
    if not char then return 0 end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return 0 end

    local backpack = lp:FindFirstChild("Backpack")
    if not backpack then return 0 end

    local tools = {}
    for _, item in ipairs(backpack:GetChildren()) do
        if item:IsA("Tool") and item.Name ~= "Rainbow Coil" and item.Name ~= "RarityTrophy" and item.Name ~= "CrashTrophy" then
            table.insert(tools, item)
        end
    end

    for _, tool in ipairs(tools) do
        if not hum or hum.Health <= 0 then break end
        if tool.Parent == backpack then
            applyVolcanoLevelToTool(tool)
            hum:EquipTool(tool)
            task.wait(Config.PlacingDelay)
            pcall(function()
                tool:Activate()
            end)
        end
    end

    return #tools
end

-- Fast Refill (Ghost Respawn trick)
local function fastRefill()
    local char = lp.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end

    local savedCF = hrp.CFrame
    hum.Health = 0

    local newChar = lp.CharacterAdded:Wait()
    local newHrp = newChar:WaitForChild("HumanoidRootPart", 5)
    if newHrp then
        task.wait(0.15)
        newHrp.CFrame = savedCF
    end
    applyAntiFlash()
    scanAndApplyVolcanoLevels()
end

-- Main background thread
task.spawn(function()
    while true do
        task.wait(0.1)
        if Config.AntiFlash then
            applyAntiFlash()
        end
        scanAndApplyVolcanoLevels()
        if Config.AutoExplodeAll then
            local count = explodeAll()
            if count == 0 and Config.AutoRefill then
                fastRefill()
                task.wait(0.6)
            else
                task.wait(0.4)
            end
        end
    end
end)

-- Create WindUI Window
local Window = WindUI:CreateWindow({
    Title = "Nuke Simulator 4 Pro Hub",
    Icon = "bomb",
    Author = "by Antigravity",
    Folder = "NukeSim4Hub",
    Size = UDim2.fromOffset(600, 480),
    Theme = "Dark",
    Resizable = true,
})

-- TAB 1: Nukes & Explode
local TabNukes = Window:Tab({
    Title = "Nukes & Explode",
    Icon = "flame",
})

TabNukes:Button({
    Title = "💥 Explode All (Tüm Envanteri Bırak)",
    Desc = "Çantandaki tüm nükleer bombaları anında sırayla kuşanıp yere koyar!",
    Callback = function()
        local count = explodeAll()
        WindUI:Notify({
            Title = "Patlatıldı!",
            Content = count .. " adet nükleer bomba başarıyla serildi.",
            Duration = 3,
            Icon = "bomb"
        })
    end
})

TabNukes:Button({
    Title = "⚡ Server Cooldown Toggle (Toggle Bomb Delay)",
    Desc = "Sunucunun resmi no-delay modunu tetikler!",
    Callback = function()
        toggleServerDelay()
        WindUI:Notify({
            Title = "Sunucu Cooldown Tetiklendi",
            Content = "ToggleNoTime sunucuya gönderildi!",
            Duration = 2,
            Icon = "zap"
        })
    end
})

TabNukes:Toggle({
    Title = "🔄 Auto Explode All (Sürekli Dök)",
    Desc = "Çantana gelen bombaları durmaksızın otomatik yere koyar.",
    Value = false,
    Callback = function(state)
        Config.AutoExplodeAll = state
    end
})

TabNukes:Toggle({
    Title = "♾️ Sınırsız Bomba Döngüsü (Auto Refill / Fast Respawn)",
    Desc = "Bombalar bitince saniyesinde yenilenip aynı koordinata geri döner ve durmaksızın koyar.",
    Value = false,
    Callback = function(state)
        Config.AutoRefill = state
    end
})

TabNukes:Slider({
    Title = "Bomba Bırakma Hızı (sn)",
    Desc = "Bombaların bırakılma hızı (daha düşük = anında bırakış).",
    Step = 0.01,
    Value = {
        Min = 0.01,
        Max = 0.15,
        Default = 0.03,
    },
    Callback = function(val)
        Config.PlacingDelay = val
    end
})

TabNukes:Slider({
    Title = "🔥 Nuke Blast Radius Multiplier",
    Desc = "Patlama yarıçapını ve gücünü çarparak katlar (x1 - x10).",
    Step = 1,
    Value = {
        Min = 1,
        Max = 10,
        Default = 1,
    },
    Callback = function(val)
        Config.ExplosionMultiplier = val
    end
})

-- TAB 2: Volcano (Özel Yanardağ Seviyesi)
local TabVolcano = Window:Tab({
    Title = "Volcano & VEI",
    Icon = "mountain",
})

TabVolcano:Slider({
    Title = "🌋 Volcano Level (Growth / VEI Değeri)",
    Desc = "Yanardağın büyüme ve patlama gücünü belirler (Örn: 500).",
    Step = 10,
    Value = {
        Min = 1,
        Max = 1000,
        Default = 500,
    },
    Callback = function(val)
        Config.VolcanoLevel = val
        scanAndApplyVolcanoLevels()
    end
})

TabVolcano:Toggle({
    Title = "✨ Auto Apply Volcano Level",
    Desc = "Eline aldığın veya yere koyduğun her volkanın seviyesini otomatik bu değere eşitler.",
    Value = true,
    Callback = function(state)
        Config.AutoApplyVolcanoLevel = state
        if state then scanAndApplyVolcanoLevels() end
    end
})

TabVolcano:Button({
    Title = "🌋 Özel Seviyeli Volkanı Yere Koy (Place Volcano)",
    Desc = "Envanterindeki volkanı ayarlanmış özel seviyede (örn: 500) yere koyar!",
    Callback = function()
        local char = lp.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local bp = lp:FindFirstChild("Backpack")
        if not hum or not bp then return end
        
        local volcano = bp:FindFirstChild("Huge Volcano") or bp:FindFirstChild("Small Volcano")
        if volcano then
            applyVolcanoLevelToTool(volcano)
            hum:EquipTool(volcano)
            task.wait(0.05)
            volcano:Activate()
            WindUI:Notify({
                Title = "Volkan Konuldu!",
                Content = "Volkan Seviye " .. Config.VolcanoLevel .. " olarak aktif edildi!",
                Duration = 3,
                Icon = "flame"
            })
        else
            WindUI:Notify({
                Title = "Volkan Bulunamadı",
                Content = "Çantanda volkan yok. Fast Refill ile yenileyebilirsin.",
                Duration = 3,
                Icon = "alert-circle"
            })
        end
    end
})

TabVolcano:Button({
    Title = "💥 Trigger VEI 9+ Mega Event",
    Desc = "Sunucudaki devasa VEI 9+ volkanik felaket Remote'unu tetikler!",
    Callback = function()
        local r1 = ReplicatedStorage:FindFirstChild("vei9plusremote")
        local r2 = ReplicatedStorage:FindFirstChild("vei9remote")
        if r1 then r1:FireServer() end
        if r2 then r2:FireServer() end
        WindUI:Notify({
            Title = "VEI 9+ Tetiklendi!",
            Content = "Volkan kıyamet eventi başlatıldı!",
            Duration = 3,
            Icon = "zap"
        })
    end
})

-- TAB 3: Koruma & Seyir
local TabProtection = Window:Tab({
    Title = "Koruma & Seyir",
    Icon = "shield-check",
})

TabProtection:Toggle({
    Title = "🛡️ Anti-Flash (Beyaz Ekran Kapatıcı)",
    Desc = "Büyük patlamalardaki kör edici beyaz flaşları engeller.",
    Value = true,
    Callback = function(state)
        Config.AntiFlash = state
        applyAntiFlash()
    end
})

local safePlatform = nil
TabProtection:Button({
    Title = "☁️ Güvenli Seyir Tepesine Işınlan (Sky Platform)",
    Desc = "Gökyüzünde güvenli bir platform oluşturup seni oraya taşır.",
    Callback = function()
        local char = lp.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            if not safePlatform or not safePlatform.Parent then
                safePlatform = Instance.new("Part")
                safePlatform.Size = Vector3.new(40, 2, 40)
                safePlatform.Anchored = true
                safePlatform.Transparency = 0.3
                safePlatform.BrickColor = BrickColor.new("Cyan")
                safePlatform.Material = Enum.Material.ForceField
                safePlatform.Parent = Workspace
            end
            local targetPos = Vector3.new(hrp.Position.X, 380, hrp.Position.Z)
            safePlatform.Position = targetPos - Vector3.new(0, 3, 0)
            hrp.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))
            
            WindUI:Notify({
                Title = "Güvenli Bölge",
                Content = "Gökyüzü platformuna ışınlandınız!",
                Duration = 2,
                Icon = "check"
            })
        end
    end
})

WindUI:Notify({
    Title = "Nuke Hub Pro Yüklendi!",
    Content = "No Cooldown & Volcano Level sistemi hazır!",
    Duration = 4,
    Icon = "sparkles"
})
