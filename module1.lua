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
    local tracerFrom = Vector2.new(screenSize.X / 2, screenSize.Y)

    for player, data in pairs(self.Active) do
        local root = data.RootPart
        if not root or not data.Character or not data.Character.Parent then
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

        local headPos, headOnScreen = CurrentCamera:WorldToViewportPoint(data.Head.Position + Vector3.new(0, 0.5, 0))
        local feetPos, feetOnScreen  = CurrentCamera:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))
        local torsoScreen, _         = CurrentCamera:WorldToViewportPoint(root.Position)

        if not (headOnScreen or feetOnScreen) then
            self:_hideDrawings(player)
            continue
        end

        -- Better box sizing
        local boxHeight = math.abs(headPos.Y - feetPos.Y)
        local boxWidth  = boxHeight * 0.55
        local centerX   = torsoScreen.X
        local topY      = math.min(headPos.Y, feetPos.Y)
        local bottomY   = math.max(headPos.Y, feetPos.Y)

        local topLeft     = Vector2.new(centerX - boxWidth/2, topY)
        local topRight    = Vector2.new(centerX + boxWidth/2, topY)
        local bottomLeft  = Vector2.new(centerX - boxWidth/2, bottomY)
        local bottomRight = Vector2.new(centerX + boxWidth/2, bottomY)

        -- Box
        local box = self.Drawings[player].Box
        box.Visible     = self.Settings.BoxEnabled
        if box.Visible then
            box.PointA = bottomRight
            box.PointB = bottomLeft
            box.PointC = topLeft
            box.PointD = topRight
        end

        -- Name
        local name = self.Drawings[player].Name
        name.Visible = self.Settings.NameEnabled
        if name.Visible then
            local distStr = self.Settings.DistanceEnabled and (" ["..math.floor(distance).."]") or ""
            name.Text = player.Name .. distStr
            name.Position = Vector2.new(centerX, topY - name.Size - 4)
        end

        -- Health bar
        local healthBG  = self.Drawings[player].HealthBG
        local healthBar = self.Drawings[player].Health
        if self.Settings.HealthBarEnabled and data.Humanoid then
            local percent = math.clamp(data.Humanoid.Health / data.Humanoid.MaxHealth, 0, 1)

            healthBG.From    = Vector2.new(topLeft.X - 6, topY)
            healthBG.To      = Vector2.new(topLeft.X - 6, bottomY)
            healthBG.Visible = true

            healthBar.From   = healthBG.From
            healthBar.To     = healthBG.From + Vector2.new(0, (healthBG.To.Y - healthBG.From.Y) * percent)
            healthBar.Color  = self.Settings.HealthLow:Lerp(self.Settings.HealthHigh, percent)
            healthBar.Visible = true
        else
            healthBG.Visible  = false
            healthBar.Visible = false
        end

        -- Tracer
        local tracer = self.Drawings[player].Tracer
        tracer.Visible = self.Settings.TracerEnabled
        if tracer.Visible then
            tracer.From = tracerFrom
            tracer.To   = Vector2.new(centerX, bottomY)
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
