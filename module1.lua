local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Workspace = game:GetService("Workspace")
local CurrentCamera = Workspace.CurrentCamera

local ESP = {}
ESP.__index = ESP

-- ──────────────────────────────────────────────────────────────
-- Configuration
-- ──────────────────────────────────────────────────────────────
local DEFAULT_SETTINGS = {
    Enabled = true,
    MaxDistance = 3000,

    TeamCheck = true,
    VisibleCheck = false, -- Add raycast if enabled later

    BoxEnabled = true,
    BoxType = "2D", -- "2D" for outlines, "Corner" for corners, "3D" for parts (less perf)
    NameEnabled = true,
    DistanceEnabled = true,
    HealthBarEnabled = true,
    TracerEnabled = true,
    SkeletonEnabled = false, -- Optional

    BoxColor = Color3.fromRGB(220, 30, 30),
    TextColor = Color3.fromRGB(255, 255, 255),
    HealthHigh = Color3.fromRGB(60, 255, 80),
    HealthLow = Color3.fromRGB(220, 40, 40),
    TracerColor = Color3.fromRGB(220, 30, 30),

    NameFont = Enum.Font.SourceSansBold,
    NameTextSize = 14,
}

-- ──────────────────────────────────────────────────────────────
-- Constructor
-- ──────────────────────────────────────────────────────────────
function ESP.new(customSettings)
    local self = setmetatable({}, ESP)

    self.Settings = table.clone(DEFAULT_SETTINGS)
    self.Active = {}
    self.Connections = {}
    self.UpdateConnection = nil
    self.Drawings = {} -- For 2D elements

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

-- ──────────────────────────────────────────────────────────────
-- Setup
-- ──────────────────────────────────────────────────────────────
function ESP:_setup()
    for _, player in Players:GetPlayers() do
        if player ~= LocalPlayer then
            task.spawn(self._tryTrackPlayer, self, player)
        end
    end

    table.insert(self.Connections, Players.PlayerAdded:Connect(function(player)
        task.spawn(self._tryTrackPlayer, self, player)
    end))

    table.insert(self.Connections, Players.PlayerRemoving:Connect(function(player)
        self:_destroyESP(player)
    end))

    self.UpdateConnection = RunService.RenderStepped:Connect(function()
        self:_updateAll()
    end)
end

function ESP:_tryTrackPlayer(player)
    if player.Character then
        task.spawn(self._onCharacterAdded, self, player, player.Character)
    end

    table.insert(self.Connections, player.CharacterAdded:Connect(function(char)
        task.delay(0.1, self._onCharacterAdded, self, player, char)
    end))
end

function ESP:_onCharacterAdded(player, character)
    local root = character:WaitForChild("HumanoidRootPart", 8)
    local humanoid = character:WaitForChild("Humanoid", 8)
    local head = character:WaitForChild("Head", 8)

    if not (root and humanoid and head) then return end

    self.Active[player] = {
        Character = character,
        RootPart = root,
        Head = head,
        Humanoid = humanoid,
    }

    self:_createDrawings(player)
end

-- ──────────────────────────────────────────────────────────────
-- 2D Drawings Creation
-- ──────────────────────────────────────────────────────────────
function ESP:_createDrawings(player)
    self.Drawings[player] = {}

    -- Box (Quad for 2D outline)
    local box = Drawing.new("Quad")
    box.Visible = false
    box.Color = self.Settings.BoxColor
    box.Thickness = 1.5
    box.Transparency = 1
    box.Filled = false
    self.Drawings[player].Box = box

    -- Name Text
    local nameText = Drawing.new("Text")
    nameText.Visible = false
    nameText.Color = self.Settings.TextColor
    nameText.Size = self.Settings.NameTextSize
    nameText.Center = true
    nameText.Outline = true
    nameText.Font = Drawing.Fonts.UI
    self.Drawings[player].Name = nameText

    -- Health Bar (Line + BG)
    local healthBG = Drawing.new("Line")
    healthBG.Visible = false
    healthBG.Color = Color3.new(0.1, 0.1, 0.1)
    healthBG.Thickness = 3
    self.Drawings[player].HealthBG = healthBG

    local healthLine = Drawing.new("Line")
    healthLine.Visible = false
    healthLine.Thickness = 1.5
    self.Drawings[player].Health = healthLine

    -- Tracer
    local tracer = Drawing.new("Line")
    tracer.Visible = false
    tracer.Color = self.Settings.TracerColor
    tracer.Thickness = 1.5
    self.Drawings[player].Tracer = tracer
end

-- ──────────────────────────────────────────────────────────────
-- Update Loop
-- ──────────────────────────────────────────────────────────────
function ESP:_updateAll()
    if not self.Settings.Enabled then
        for _, drawings in pairs(self.Drawings) do
            for _, obj in pairs(drawings) do
                obj.Visible = false
            end
        end
        return
    end

    local camCFrame = CurrentCamera.CFrame
    local camPos = camCFrame.Position
    local screenSize = CurrentCamera.ViewportSize
    local tracerFrom = Vector2.new(screenSize.X / 2, screenSize.Y) -- Bottom center

    for player, data in pairs(self.Active) do
        local root = data.RootPart
        if not root or not data.Character.Parent then
            self:_hideDrawings(player)
            continue
        end

        local distance = (root.Position - camPos).Magnitude
        if distance > self.Settings.MaxDistance then
            self:_hideDrawings(player)
            continue
        end

        if self.Settings.TeamCheck and player.Team == LocalPlayer.Team then
            self:_hideDrawings(player)
            continue
        end

        -- Get screen positions
        local headPos, headOnScreen = CurrentCamera:WorldToViewportPoint(data.Head.Position)
        local torsoPos = root.Position
        local torsoScreen, torsoOnScreen = CurrentCamera:WorldToViewportPoint(torsoPos)

        if not (headOnScreen or torsoOnScreen) then
            self:_hideDrawings(player)
            continue
        end

        -- Calculate box size (approximate character bounds)
        local charSize = (data.Head.Position - (torsoPos - Vector3.new(0, 3, 0))).Magnitude
        local boxHeight = math.clamp(charSize * (500 / distance), 10, 500)
        local boxWidth = boxHeight / 2

        local top = Vector2.new(torsoScreen.X, torsoScreen.Y) - Vector2.new(0, boxHeight / 2)
        local bottom = top + Vector2.new(0, boxHeight)
        local left = top - Vector2.new(boxWidth / 2, 0)
        local right = top + Vector2.new(boxWidth / 2, 0)

        -- Box
        if self.Settings.BoxEnabled then
            local box = self.Drawings[player].Box
            box.PointA = bottom + Vector2.new(boxWidth / 2, 0) -- BR
            box.PointB = bottom - Vector2.new(boxWidth / 2, 0) -- BL
            box.PointC = top - Vector2.new(boxWidth / 2, 0) -- TL
            box.PointD = top + Vector2.new(boxWidth / 2, 0) -- TR
            box.Visible = true
        end

        -- Name + Distance
        if self.Settings.NameEnabled then
            local name = self.Drawings[player].Name
            local distStr = self.Settings.DistanceEnabled and (" [" .. math.floor(distance) .. "]") or ""
            name.Text = player.Name .. distStr
            name.Position = top - Vector2.new(0, name.TextBounds.Y + 2)
            name.Visible = true
        end

        -- Health Bar
        if self.Settings.HealthBarEnabled and data.Humanoid then
            local hp = data.Humanoid.Health
            local max = data.Humanoid.MaxHealth
            local percent = math.clamp(hp / max, 0, 1)

            local healthBG = self.Drawings[player].HealthBG
            healthBG.From = left - Vector2.new(6, 0)
            healthBG.To = left - Vector2.new(6, -boxHeight)
            healthBG.Visible = true

            local healthLine = self.Drawings[player].Health
            healthLine.Color = self.Settings.HealthLow:Lerp(self.Settings.HealthHigh, percent)
            healthLine.From = healthBG.From
            healthLine.To = healthBG.From + (healthBG.To - healthBG.From) * percent
            healthLine.Visible = true
        end

        -- Tracer
        if self.Settings.TracerEnabled then
            local tracer = self.Drawings[player].Tracer
            tracer.From = tracerFrom
            tracer.To = Vector2.new(torsoScreen.X, torsoScreen.Y)
            tracer.Visible = true
        end
    end
end

function ESP:_hideDrawings(player)
    if self.Drawings[player] then
        for _, obj in pairs(self.Drawings[player]) do
            obj.Visible = false
        end
    end
end

-- ──────────────────────────────────────────────────────────────
-- Cleanup
-- ──────────────────────────────────────────────────────────────
function ESP:_destroyESP(player)
    if self.Active[player] then
        self.Active[player] = nil
    end
    if self.Drawings[player] then
        for _, obj in pairs(self.Drawings[player]) do
            obj:Remove()
        end
        self.Drawings[player] = nil
    end
end

function ESP:Destroy()
    if self.UpdateConnection then
        self.UpdateConnection:Disconnect()
    end
    for _, conn in self.Connections do
        conn:Disconnect()
    end
    self.Connections = {}
    for player in pairs(self.Active) do
        self:_destroyESP(player)
    end
    self.Active = {}
    self.Drawings = {}
end

function ESP:Toggle(enabled)
    self.Settings.Enabled = enabled ~= false
end

return ESP
