local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local LocalPlayer    = Players.LocalPlayer
local Workspace      = game:GetService("Workspace")
local CurrentCamera  = Workspace.CurrentCamera

local ESP = {}
ESP.__index = ESP
local DEFAULT_SETTINGS = {
    Enabled          = true,
    MaxDistance      = 3000,

    TeamCheck        = true,
    VisibleCheck     = false,      -- requires raycast / canSee check

    BoxEnabled       = true,
    NameEnabled      = true,
    DistanceEnabled  = true,
    HealthBarEnabled = true,
    TracerEnabled    = false,      -- optional future feature

    BoxColor         = Color3.fromRGB(220, 30, 30),
    TextColor        = Color3.fromRGB(255, 255, 255),
    HealthHigh       = Color3.fromRGB(60, 255, 80),
    HealthLow        = Color3.fromRGB(220, 40, 40),

    NameFont         = Enum.Font.SourceSansBold,
    NameTextSize     = 14,
    DistanceTextSize = 12,
}

function ESP.new(customSettings)
    local self = setmetatable({}, ESP)

    self.Settings  = table.clone(DEFAULT_SETTINGS)
    self.Active    = {}
    self.Connections = {}
    self.UpdateConnection = nil

    if customSettings then
        for k, v in pairs(customSettings) do
            if self.Settings[k] ~= nil then
                self.Settings[k] = v
            end
        end
    end

    self:_setup()
    return self
end

function ESP:_setup()
    -- Initial players
    for _, player in Players:GetPlayers() do
        if player ~= LocalPlayer then
            task.spawn(self._tryTrackPlayer, self, player)
        end
    end

    -- Player events
    table.insert(self.Connections, Players.PlayerAdded:Connect(function(player)
        task.spawn(self._tryTrackPlayer, self, player)
    end))

    table.insert(self.Connections, Players.PlayerRemoving:Connect(function(player)
        self:_destroyESP(player)
    end))

    -- Main update loop (single connection – better performance)
    self.UpdateConnection = RunService.RenderStepped:Connect(function()
        self:_updateAll()
    end)
end

function ESP:_tryTrackPlayer(player)
    if player.Character then
        task.spawn(self._onCharacterAdded, self, player, player.Character)
    end

    player.CharacterAdded:Connect(function(char)
        task.delay(0.1, function()
            self:_onCharacterAdded(player, char)
        end)
    end)
end

function ESP:_onCharacterAdded(player, character)
    local root    = character:WaitForChild("HumanoidRootPart", 8)
    local humanoid = character:WaitForChild("Humanoid", 8)

    if not (root and humanoid) then
        return
    end

    self:_createESP(player, root, humanoid)
end

function ESP:_createESP(player, rootPart, humanoid)
    self:_destroyESP(player) -- clean previous if exists

    local billboard = Instance.new("BillboardGui")
    billboard.Name              = "ESP"
    billboard.Adornee           = rootPart
    billboard.AlwaysOnTop       = true
    billboard.Size              = UDim2.new(5, 0, 6, 0)
    billboard.StudsOffset       = Vector3.new(0, 3.2, 0)
    billboard.LightInfluence    = 0
    billboard.Parent            = rootPart

    -- Box
    local boxFrame = Instance.new("Frame")
    boxFrame.Size               = UDim2.fromScale(1,1)
    boxFrame.BackgroundTransparency = 1
    boxFrame.BorderSizePixel    = 0
    boxFrame.Parent             = billboard

    local uiStroke = Instance.new("UIStroke")
    uiStroke.Color              = self.Settings.BoxColor
    uiStroke.Thickness          = 1.6
    uiStroke.Transparency       = 0.1
    uiStroke.ApplyStrokeMode    = Enum.ApplyStrokeMode.Border
    uiStroke.Parent             = boxFrame

    -- Name
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size              = UDim2.new(1,0,0.22,0)
    nameLabel.Position          = UDim2.new(0,0,-0.28,0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3        = self.Settings.TextColor
    nameLabel.TextStrokeTransparency = 0.7
    nameLabel.TextStrokeColor3  = Color3.new(0,0,0)
    nameLabel.Font              = self.Settings.NameFont
    nameLabel.TextSize          = self.Settings.NameTextSize
    nameLabel.TextScaled        = true
    nameLabel.TextXAlignment    = Enum.TextXAlignment.Center
    nameLabel.Parent            = billboard

    -- Health bar background
    local healthBG = Instance.new("Frame")
    healthBG.Size               = UDim2.new(0.06, 0, 0.9, 0)
    healthBG.Position           = UDim2.new(-0.12, 0, 0.05, 0)
    healthBG.BackgroundColor3   = Color3.new(0.08, 0.08, 0.08)
    healthBG.BorderSizePixel    = 0
    healthBG.Parent             = billboard

    local healthFill = Instance.new("Frame")
    healthFill.Size             = UDim2.new(1,0,1,0)
    healthFill.BorderSizePixel  = 0
    healthFill.Parent           = healthBG

    self.Active[player] = {
        Billboard   = billboard,
        NameLabel   = nameLabel,
        HealthFill  = healthFill,
        Stroke      = uiStroke,
        Humanoid    = humanoid,
        RootPart    = rootPart,
    }
end

function ESP:_updateAll()
    if not self.Settings.Enabled then
        for _, data in pairs(self.Active) do
            data.Billboard.Enabled = false
        end
        return
    end

    local lpPos = CurrentCamera.CFrame.Position

    for player, data in pairs(self.Active) do
        local root = data.RootPart
        if not root or not root.Parent then
            self:_destroyESP(player)
            continue
        end

        local distance = (root.Position - lpPos).Magnitude
        if distance > self.Settings.MaxDistance then
            data.Billboard.Enabled = false
            continue
        end

        if self.Settings.TeamCheck and player.Team == LocalPlayer.Team then
            data.Billboard.Enabled = false
            continue
        end

        -- Visible check (optional – can be expanded later)
        -- if self.Settings.VisibleCheck and not self:_isVisible(root) then ...

        data.Billboard.Enabled = true

        -- Name + distance
        if self.Settings.NameEnabled then
            local distStr = self.Settings.DistanceEnabled and (" [" .. math.floor(distance) .. "]") or ""
            data.NameLabel.Text = player.Name .. distStr
        else
            data.NameLabel.Text = ""
        end

        -- Health
        if self.Settings.HealthBarEnabled and data.Humanoid then
            local hp  = data.Humanoid.Health
            local max = data.Humanoid.MaxHealth
            local percent = math.clamp(hp / max, 0, 1)

            data.HealthFill.Size = UDim2.new(1, 0, percent, 0)
            data.HealthFill.BackgroundColor3 = self.Settings.HealthLow:Lerp(
                self.Settings.HealthHigh,
                percent
            )
        end
    end
end

function ESP:_destroyESP(player)
    local data = self.Active[player]
    if data then
        if data.Billboard then
            data.Billboard:Destroy()
        end
        self.Active[player] = nil
    end
end

function ESP:Destroy()
    if self.UpdateConnection then
        self.UpdateConnection:Disconnect()
        self.UpdateConnection = nil
    end

    for _, conn in ipairs(self.Connections) do
        conn:Disconnect()
    end
    self.Connections = {}

    for player in pairs(self.Active) do
        self:_destroyESP(player)
    end
    self.Active = {}
end

-- Optional: toggle visibility
function ESP:Toggle(enabled)
    self.Settings.Enabled = enabled ~= false
end

return ESP
