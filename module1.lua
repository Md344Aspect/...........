local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

local ESP = {}
ESP.__index = ESP

local DEFAULT_SETTINGS = {
    Enabled = true,
    MaxDistance = 4000,

    TeamCheck = true,
    UseTeamColor = false,       -- If true, uses player's TeamColor

    -- Visual Toggles
    BoxEnabled = true,
    BoxType = "Corner",         -- "Full", "Corner"
    SkeletonEnabled = true,
    HeadDotEnabled = true,
    NameEnabled = true,
    DistanceEnabled = true,
    HealthBarEnabled = true,
    TracerEnabled = true,

    -- Colors
    EnemyColor = Color3.fromRGB(255, 45, 45),
    AllyColor = Color3.fromRGB(45, 170, 255),

    -- Style
    BoxThickness = 1.4,
    TracerThickness = 1.3,
    SkeletonThickness = 1.1,
    HealthBarThickness = 3.5,

    TextSize = 13,
    TextFont = Drawing.Fonts.UI,
}

function ESP.new(settings)
    local self = setmetatable({}, ESP)

    self.Settings = table.clone(DEFAULT_SETTINGS)
    self.Active = {}
    self.Drawings = {}
    self.Connections = {}

    if settings then
        for k, v in pairs(settings) do
            self.Settings[k] = v
        end
    end

    self:_init()
    return self
end

function ESP:_init()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            task.spawn(self.TrackPlayer, self, plr)
        end
    end

    table.insert(self.Connections, Players.PlayerAdded:Connect(function(plr)
        task.spawn(self.TrackPlayer, self, plr)
    end))

    table.insert(self.Connections, Players.PlayerRemoving:Connect(function(plr)
        self:RemovePlayer(plr)
    end))

    self.RenderConnection = RunService.RenderStepped:Connect(function()
        self:_update()
    end)
end

function ESP:TrackPlayer(plr)
    plr.CharacterAdded:Connect(function(char)
        task.delay(0.4, function() self:_createESP(plr, char) end)
    end)

    if plr.Character then
        task.delay(0.4, function() self:_createESP(plr, plr.Character) end)
    end
end

function ESP:_createESP(plr, character)
    self:RemovePlayer(plr)

    local root = character:WaitForChild("HumanoidRootPart", 5)
    local head = character:WaitForChild("Head", 5)
    local humanoid = character:WaitForChild("Humanoid", 5)

    if not (root and head and humanoid) then return end

    self.Active[plr] = {
        RootPart = root,
        Head = head,
        Humanoid = humanoid,
        Character = character,
    }

    self.Drawings[plr] = self:_createDrawings()
end

function ESP:_createDrawings()
    local drawings = {}

    -- Box
    drawings.Box = {}
    for i = 1, 4 do
        drawings.Box[i] = Drawing.new("Line")
        drawings.Box[i].Thickness = DEFAULT_SETTINGS.BoxThickness
        drawings.Box[i].Visible = false
    end

    -- Skeleton
    drawings.Skeleton = {}
    for i = 1, 6 do
        drawings.Skeleton[i] = Drawing.new("Line")
        drawings.Skeleton[i].Thickness = DEFAULT_SETTINGS.SkeletonThickness
        drawings.Skeleton[i].Visible = false
    end

    -- Health Bar
    drawings.HealthBG = Drawing.new("Line")
    drawings.HealthFill = Drawing.new("Line")
    drawings.HealthOutline = Drawing.new("Line")

    drawings.HealthBG.Thickness = DEFAULT_SETTINGS.HealthBarThickness + 2
    drawings.HealthFill.Thickness = DEFAULT_SETTINGS.HealthBarThickness
    drawings.HealthOutline.Thickness = 1

    -- Other
    drawings.Name = Drawing.new("Text")
    drawings.Name.Center = true
    drawings.Name.Outline = true
    drawings.Name.Size = DEFAULT_SETTINGS.TextSize
    drawings.Name.Font = DEFAULT_SETTINGS.TextFont

    drawings.HeadDot = Drawing.new("Circle")
    drawings.HeadDot.Radius = 2.5
    drawings.HeadDot.Filled = true
    drawings.HeadDot.NumSides = 20

    drawings.Tracer = Drawing.new("Line")

    return drawings
end

function ESP:_update()
    if not self.Settings.Enabled then
        self:_hideAll()
        return
    end

    local camPos = Camera.CFrame.Position
    local viewport = Camera.ViewportSize
    local tracerOrigin = Vector2.new(viewport.X / 2, viewport.Y - 30)

    for player, data in pairs(self.Active) do
        if not data.RootPart or not data.RootPart.Parent then
            self:RemovePlayer(player)
            continue
        end

        local distance = (data.RootPart.Position - camPos).Magnitude
        if distance > self.Settings.MaxDistance then
            self:_hidePlayer(player)
            continue
        end

        if self.Settings.TeamCheck and player.Team == LocalPlayer.Team then
            self:_hidePlayer(player)
            continue
        end

        local color = self.Settings.UseTeamColor and player.TeamColor.Color or
                      (player.Team == LocalPlayer.Team and self.Settings.AllyColor or self.Settings.EnemyColor)

        local headPos, headVis = Camera:WorldToViewportPoint(data.Head.Position)
        local rootPos, rootVis = Camera:WorldToViewportPoint(data.RootPart.Position)

        if not (headVis or rootVis) then
            self:_hidePlayer(player)
            continue
        end

        local charSize = (data.Head.Position.Y - (data.RootPart.Position.Y - 3.5))
        local boxHeight = (charSize * 650) / distance
        local boxWidth = boxHeight * 0.55

        local centerX = rootPos.X
        local topY = headPos.Y - (boxHeight * 0.1)
        local bottomY = rootPos.Y + (boxHeight * 0.6)

        local tl = Vector2.new(centerX - boxWidth/2, topY)
        local tr = Vector2.new(centerX + boxWidth/2, topY)
        local bl = Vector2.new(centerX - boxWidth/2, bottomY)
        local br = Vector2.new(centerX + boxWidth/2, bottomY)

        -- Box
        local boxVis = self.Settings.BoxEnabled
        local lines = self.Drawings[player].Box
        if boxVis then
            lines[1].From = tl; lines[1].To = tr
            lines[2].From = tr; lines[2].To = br
            lines[3].From = br; lines[3].To = bl
            lines[4].From = bl; lines[4].To = tl

            for _, line in ipairs(lines) do
                line.Color = color
                line.Thickness = self.Settings.BoxThickness
                line.Visible = true
            end
        else
            for _, line in ipairs(lines) do line.Visible = false end
        end

        -- Name + Distance
        local name = self.Drawings[player].Name
        name.Visible = self.Settings.NameEnabled
        if name.Visible then
            local dist = self.Settings.DistanceEnabled and " ["..math.floor(distance).."]" or ""
            name.Text = player.Name .. dist
            name.Position = Vector2.new(centerX, topY - 18)
            name.Color = color
            name.Size = self.Settings.TextSize
        end

        -- Health Bar
        local hp = data.Humanoid.Health / data.Humanoid.MaxHealth
        local hbg = self.Drawings[player].HealthBG
        local hfill = self.Drawings[player].HealthFill
        local hout = self.Drawings[player].HealthOutline

        if self.Settings.HealthBarEnabled then
            local barLeft = tl.X - 7
            hbg.From = Vector2.new(barLeft, topY)
            hbg.To = Vector2.new(barLeft, bottomY)
            hbg.Color = Color3.new(0.05, 0.05, 0.05)
            hbg.Visible = true

            hfill.From = Vector2.new(barLeft, bottomY)
            hfill.To = Vector2.new(barLeft, bottomY - (bottomY - topY) * hp)
            hfill.Color = Color3.fromRGB(255, 45, 45):Lerp(Color3.fromRGB(80, 255, 80), hp)
            hfill.Visible = true

            hout.From = hbg.From - Vector2.new(1,0)
            hout.To = hbg.To + Vector2.new(1,0)
            hout.Visible = true
        else
            hbg.Visible = false
            hfill.Visible = false
            hout.Visible = false
        end

        -- Head Dot
        local dot = self.Drawings[player].HeadDot
        dot.Visible = self.Settings.HeadDotEnabled
        if dot.Visible then
            dot.Position = Vector2.new(headPos.X, headPos.Y)
            dot.Color = color
        end

        -- Tracer
        local tracer = self.Drawings[player].Tracer
        tracer.Visible = self.Settings.TracerEnabled
        if tracer.Visible then
            tracer.From = tracerOrigin
            tracer.To = Vector2.new(centerX, bottomY)
            tracer.Color = color
            tracer.Thickness = self.Settings.TracerThickness
        end
    end
end

function ESP:_hidePlayer(plr)
    if not self.Drawings[plr] then return end
    for _, obj in pairs(self.Drawings[plr]) do
        if typeof(obj) == "table" then
            for _, line in pairs(obj) do line.Visible = false end
        else
            obj.Visible = false
        end
    end
end

function ESP:_hideAll()
    for plr in pairs(self.Drawings) do
        self:_hidePlayer(plr)
    end
end

function ESP:RemovePlayer(plr)
    if self.Drawings[plr] then
        for _, v in pairs(self.Drawings[plr]) do
            if typeof(v) == "table" then
                for _, line in pairs(v) do line:Remove() end
            else
                v:Remove()
            end
        end
        self.Drawings[plr] = nil
    end
    self.Active[plr] = nil
end

function ESP:Destroy()
    if self.RenderConnection then self.RenderConnection:Disconnect() end
    for _, conn in ipairs(self.Connections) do conn:Disconnect() end

    for plr in pairs(self.Active) do
        self:RemovePlayer(plr)
    end
end

return ESP
