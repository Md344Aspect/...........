--// Professional

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInput = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

local ESP = {}
ESP.__index = ESP

local DEFAULT_SETTINGS = {
    Enabled = true,
    MaxDistance = 5000,

    TeamCheck = true,
    UseTeamColor = false,

    -- Visuals
    BoxEnabled = true,
    BoxType = "Corner", -- "Full", "Corner"
    SkeletonEnabled = true,
    HeadDotEnabled = true,
    NameEnabled = true,
    DistanceEnabled = true,
    HealthBarEnabled = true,
    TracerEnabled = true,
    ChamsEnabled = true, -- New: Model highlights
    OutOfViewArrows = true, -- New: Arrows for off-screen
    HeadSnaplines = false, -- New: Lines to head
    FOVCircle = false, -- New: FOV indicator

    -- Colors
    EnemyColor = Color3.fromRGB(255, 50, 50),
    AllyColor = Color3.fromRGB(50, 180, 255),
    ChamsColor = Color3.fromRGB(255, 50, 50, 0.4), -- With alpha

    -- Styles
    BoxThickness = 1.5,
    TracerThickness = 1.4,
    SkeletonThickness = 1.2,
    HealthBarThickness = 4,
    ArrowSize = 12,
    FOVRadius = 200,
    FOVColor = Color3.fromRGB(255, 255, 255),

    TextSize = 14,
    TextFont = Drawing.Fonts.UI,
}

function ESP.new(settings)
    local self = setmetatable({}, ESP)

    self.Settings = table.clone(DEFAULT_SETTINGS)
    if settings then for k, v in settings do self.Settings[k] = v end end

    self.Active = {}
    self.Drawings = {}
    self.Connections = {}
    self.Chams = {} -- For highlights

    self:_init()
    return self
end

function ESP:_init()
    for _, plr in Players:GetPlayers() do
        if plr ~= LocalPlayer then task.spawn(self.TrackPlayer, self, plr) end
    end

    self.Connections.PlayerAdded = Players.PlayerAdded:Connect(function(plr)
        task.spawn(self.TrackPlayer, self, plr)
    end)

    self.Connections.PlayerRemoving = Players.PlayerRemoving:Connect(function(plr)
        self:RemovePlayer(plr)
    end)

    self.Connections.RenderStepped = RunService.RenderStepped:Connect(function()
        self:_update()
    end)
end

function ESP:TrackPlayer(plr)
    local conn = plr.CharacterAdded:Connect(function(char)
        task.delay(0.5, function() self:_setupPlayer(plr, char) end)
    end)
    table.insert(self.Connections, conn)

    if plr.Character then
        task.delay(0.5, function() self:_setupPlayer(plr, plr.Character) end)
    end
end

function ESP:_setupPlayer(plr, char)
    self:RemovePlayer(plr)

    local root = char:WaitForChild("HumanoidRootPart", 6)
    local head = char:WaitForChild("Head", 6)
    local humanoid = char:WaitForChild("Humanoid", 6)
    if not (root and head and humanoid) then return end

    self.Active[plr] = { RootPart = root, Head = head, Humanoid = humanoid, Character = char }

    self.Drawings[plr] = self:_createDrawings()
    if self.Settings.ChamsEnabled then self:_createChams(plr, char) end
end

function ESP:_createDrawings()
    local d = {}

    -- Box Lines (4 for full/corner)
    d.BoxLines = {}
    for i = 1, 8 do -- Extra for corners
        local line = Drawing.new("Line")
        line.Thickness = self.Settings.BoxThickness
        line.Visible = false
        d.BoxLines[i] = line
    end

    -- Skeleton Lines
    d.SkeletonLines = {}
    for i = 1, 10 do -- More for full skeleton
        local line = Drawing.new("Line")
        line.Thickness = self.Settings.SkeletonThickness
        line.Visible = false
        d.SkeletonLines[i] = line
    end

    -- Health
    d.HealthBG = Drawing.new("Line")
    d.HealthFill = Drawing.new("Line")
    d.HealthOutline = Drawing.new("Line")
    d.HealthBG.Thickness = self.Settings.HealthBarThickness + 2
    d.HealthFill.Thickness = self.Settings.HealthBarThickness
    d.HealthOutline.Thickness = 1

    -- Text
    d.Name = Drawing.new("Text")
    d.Name.Center = true
    d.Name.Outline = true
    d.Name.Size = self.Settings.TextSize
    d.Name.Font = self.Settings.TextFont
    d.Name.Visible = false

    -- Head Dot
    d.HeadDot = Drawing.new("Circle")
    d.HeadDot.Radius = 3
    d.HeadDot.Filled = true
    d.HeadDot.NumSides = 24
    d.HeadDot.Visible = false

    -- Tracer
    d.Tracer = Drawing.new("Line")
    d.Tracer.Thickness = self.Settings.TracerThickness
    d.Tracer.Visible = false

    -- Arrow (Triangle for out-of-view)
    d.Arrow = Drawing.new("Triangle")
    d.Arrow.Filled = true
    d.Arrow.Visible = false

    -- Snapline
    d.Snapline = Drawing.new("Line")
    d.Snapline.Thickness = 1.6
    d.Snapline.Visible = false

    return d
end

function ESP:_createChams(plr, char)
    local highlight = Instance.new("Highlight")
    highlight.Name = "ESPChams"
    highlight.FillTransparency = 0.6
    highlight.OutlineTransparency = 0
    highlight.Parent = char
    highlight.Enabled = false
    self.Chams[plr] = highlight
end

function ESP:_update()
    if not self.Settings.Enabled then
        self:_hideAll()
        return
    end

    local camPos = Camera.CFrame.Position
    local viewport = Camera.ViewportSize
    local tracerOrigin = Vector2.new(viewport.X / 2, viewport.Y)
    local mousePos = UserInput:GetMouseLocation()

    if self.Settings.FOVCircle then
        local fov = Drawing.new("Circle")
        fov.Position = tracerOrigin - Vector2.new(0, viewport.Y / 2)
        fov.Radius = self.Settings.FOVRadius
        fov.Color = self.Settings.FOVColor
        fov.Visible = true
        fov.Thickness = 1.2
        -- Note: This is per-frame; optimize if needed
    end

    for plr, data in pairs(self.Active) do
        local rootPos = data.RootPart.Position
        local distance = (rootPos - camPos).Magnitude
        if distance > self.Settings.MaxDistance then self:_hidePlayer(plr) continue end

        if self.Settings.TeamCheck and plr.Team == LocalPlayer.Team then self:_hidePlayer(plr) continue end

        local color = self.Settings.UseTeamColor and (plr.TeamColor or BrickColor.White()).Color or
                      (plr.Team == LocalPlayer.Team and self.Settings.AllyColor or self.Settings.EnemyColor)

        local head3D = data.Head.Position + Vector3.new(0, 0.6, 0)
        local feet3D = rootPos - Vector3.new(0, 3.2, 0)

        local head2D, headVis = Camera:WorldToViewportPoint(head3D)
        local feet2D, feetVis = Camera:WorldToViewportPoint(feet3D)

        if not (headVis or feetVis) then
            if self.Settings.OutOfViewArrows then
                self:_drawArrow(plr, rootPos, color)
            else
                self:_hidePlayer(plr)
            end
            continue
        end

        local boxHeight = math.abs(head2D.Y - feet2D.Y)
        local boxWidth = boxHeight / 1.8

        local centerX = (head2D.X + feet2D.X) / 2
        local topY = math.min(head2D.Y, feet2D.Y)
        local bottomY = math.max(head2D.Y, feet2D.Y)

        local tl = Vector2.new(centerX - boxWidth/2, topY)
        local tr = Vector2.new(centerX + boxWidth/2, topY)
        local bl = Vector2.new(centerX - boxWidth/2, bottomY)
        local br = Vector2.new(centerX + boxWidth/2, bottomY)

        -- Box
        if self.Settings.BoxEnabled then
            self:_drawBox(plr, tl, tr, bl, br, color)
        end

        -- Skeleton
        if self.Settings.SkeletonEnabled then
            self:_drawSkeleton(plr, data.Character, color)
        end

        -- Name & Distance
        if self.Settings.NameEnabled then
            local name = self.Drawings[plr].Name
            local dist = self.Settings.DistanceEnabled and " [" .. math.floor(distance) .. "]" or ""
            name.Text = plr.Name .. dist
            name.Position = tl + Vector2.new(boxWidth/2, -name.Size - 2)
            name.Color = color
            name.Visible = true
        end

        -- Health Bar
        if self.Settings.HealthBarEnabled then
            local percent = data.Humanoid.Health / data.Humanoid.MaxHealth
            local hbg = self.Drawings[plr].HealthBG
            local hfill = self.Drawings[plr].HealthFill
            local hout = self.Drawings[plr].HealthOutline

            local barX = tl.X - 8
            hbg.From = Vector2.new(barX, topY)
            hbg.To = Vector2.new(barX, bottomY)
            hbg.Color = Color3.new(0.1, 0.1, 0.1)
            hbg.Visible = true

            hfill.From = hbg.To
            hfill.To = hbg.To + Vector2.new(0, -(bottomY - topY) * percent)
            hfill.Color = self.Settings.EnemyColor:Lerp(self.Settings.AllyColor, percent) -- Green to red
            hfill.Visible = true

            hout.From = hbg.From - Vector2.new(1, 0)
            hout.To = hbg.To + Vector2.new(1, 0)
            hout.Color = Color3.new(0, 0, 0)
            hout.Visible = true
        end

        -- Head Dot
        if self.Settings.HeadDotEnabled then
            local dot = self.Drawings[plr].HeadDot
            dot.Position = Vector2.new(head2D.X, head2D.Y)
            dot.Color = color
            dot.Visible = true
        end

        -- Tracer
        if self.Settings.TracerEnabled then
            local tracer = self.Drawings[plr].Tracer
            tracer.From = tracerOrigin
            tracer.To = br
            tracer.Color = color
            tracer.Visible = true
        end

        -- Snapline
        if self.Settings.HeadSnaplines then
            local snap = self.Drawings[plr].Snapline
            snap.From = mousePos
            snap.To = Vector2.new(head2D.X, head2D.Y)
            snap.Color = color
            snap.Visible = true
        end

        -- Chams
        if self.Settings.ChamsEnabled and self.Chams[plr] then
            local chams = self.Chams[plr]
            chams.FillColor = color
            chams.OutlineColor = color
            chams.Enabled = true
        end
    end
end

function ESP:_drawBox(plr, tl, tr, bl, br, color)
    local lines = self.Drawings[plr].BoxLines
    if self.Settings.BoxType == "Full" then
        lines[1].From = tl; lines[1].To = tr
        lines[2].From = tr; lines[2].To = br
        lines[3].From = br; lines[3].To = bl
        lines[4].From = bl; lines[4].To = tl
        for i = 5, 8 do lines[i].Visible = false end
    elseif self.Settings.BoxType == "Corner" then
        local len = 0.3
        -- Top left
        lines[1].From = tl; lines[1].To = tl + Vector2.new(0, boxHeight * len)
        lines[2].From = tl; lines[2].To = tl + Vector2.new(boxWidth * len, 0)
        -- Top right
        lines[3].From = tr; lines[3].To = tr + Vector2.new(0, boxHeight * len)
        lines[4].From = tr; lines[4].To = tr - Vector2.new(boxWidth * len, 0)
        -- Bottom left
        lines[5].From = bl; lines[5].To = bl - Vector2.new(0, boxHeight * len)
        lines[6].From = bl; lines[6].To = bl + Vector2.new(boxWidth * len, 0)
        -- Bottom right
        lines[7].From = br; lines[7].To = br - Vector2.new(0, boxHeight * len)
        lines[8].From = br; lines[8].To = br - Vector2.new(boxWidth * len, 0)
    end
    for _, line in lines do
        line.Color = color
        line.Visible = true
    end
end

function ESP:_drawSkeleton(plr, char, color)
    local lines = self.Drawings[plr].SkeletonLines
    local parts = { "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }
    local positions = {}
    for _, partName in parts do
        local part = char:FindFirstChild(partName)
        if part then
            local pos, vis = Camera:WorldToViewportPoint(part.Position)
            positions[partName] = Vector2.new(pos.X, pos.Y)
        end
    end

    -- Connections (example)
    local i = 1
    local function connect(a, b)
        if positions[a] and positions[b] then
            lines[i].From = positions[a]
            lines[i].To = positions[b]
            lines[i].Color = color
            lines[i].Visible = true
            i = i + 1
        end
    end

    connect("Head", "UpperTorso")
    connect("UpperTorso", "LowerTorso")
    connect("UpperTorso", "LeftUpperArm")
    connect("UpperTorso", "RightUpperArm")
    connect("LeftUpperArm", "LeftLowerArm")
    connect("RightUpperArm", "RightLowerArm")
    connect("LowerTorso", "LeftUpperLeg")
    connect("LowerTorso", "RightUpperLeg")
    connect("LeftUpperLeg", "LeftLowerLeg")
    connect("RightUpperLeg", "RightLowerLeg")

    for j = i, #lines do lines[j].Visible = false end
end

function ESP:_drawArrow(plr, pos3D, color)
    local arrow = self.Drawings[plr].Arrow
    local pos2D, vis = Camera:WorldToViewportPoint(pos3D)
    if vis then arrow.Visible = false return end

    local dir = (pos2D - Camera.ViewportSize / 2).Unit
    local edgePos = Camera.ViewportSize / 2 + dir * (math.min(Camera.ViewportSize.X, Camera.ViewportSize.Y) / 2 - self.Settings.ArrowSize - 10)

    arrow.PointA = edgePos
    arrow.PointB = edgePos - dir * self.Settings.ArrowSize + dir:Cross(Vector2.new(0, 1)) * self.Settings.ArrowSize / 2
    arrow.PointC = edgePos - dir * self.Settings.ArrowSize - dir:Cross(Vector2.new(0, 1)) * self.Settings.ArrowSize / 2
    arrow.Color = color
    arrow.Visible = true
end

function ESP:_hidePlayer(plr)
    if not self.Drawings[plr] then return end
    for _, obj in pairs(self.Drawings[plr]) do
        if typeof(obj) == "table" then for _, v in obj do v.Visible = false end
        else obj.Visible = false end
    end
    if self.Chams[plr] then self.Chams[plr].Enabled = false end
end

function ESP:_hideAll()
    for plr in self.Drawings do self:_hidePlayer(plr) end
end

function ESP:RemovePlayer(plr)
    if self.Drawings[plr] then
        for _, obj in pairs(self.Drawings[plr]) do
            if typeof(obj) == "table" then for _, v in obj do v:Remove() end
            else obj:Remove() end
        end
        self.Drawings[plr] = nil
    end
    if self.Chams[plr] then self.Chams[plr]:Destroy() self.Chams[plr] = nil end
    self.Active[plr] = nil
end

function ESP:Destroy()
    for _, conn in self.Connections do if conn then conn:Disconnect() end end
    self.Connections = {}
    for plr in self.Active do self:RemovePlayer(plr) end
    self.Active = {}
    self.Drawings = {}
    self.Chams = {}
end

return ESP
