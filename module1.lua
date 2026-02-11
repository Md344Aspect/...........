local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local Overlay = {}
Overlay.__index = Overlay

Overlay.DefaultSettings = {
    Enabled = false,
    MaxDistance = 2000,
    TeamCheck = false,
    UseLineOfSight = false,

    ShowBox = true,
    ShowName = true,
    ShowDistance = true,
    ShowHealth = true,

    BoxColor = Color3.fromRGB(0,170,255),
    TextColor = Color3.fromRGB(255,255,255),
}

-- Utility: merge defaults
local function merge(defaults, custom)
    local result = {}
    for k,v in pairs(defaults) do
        result[k] = v
    end
    if custom then
        for k,v in pairs(custom) do
            result[k] = v
        end
    end
    return result
end

function Overlay.new(settings)
    local self = setmetatable({}, Overlay)
    self.Settings = merge(Overlay.DefaultSettings, settings)
    self.Objects = {}
    self.Connection = nil
    self:_init()
    return self
end

-- Create UI container once per player
function Overlay:_createObject(player)
    local frame = Instance.new("Frame")
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    frame.Visible = false
    frame.Parent = game.CoreGui

    local box = Instance.new("Frame")
    box.BorderSizePixel = 2
    box.BackgroundTransparency = 1
    box.Parent = frame

    local nameLabel = Instance.new("TextLabel")
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.SourceSansBold
    nameLabel.Parent = frame

    self.Objects[player] = {
        Frame = frame,
        Box = box,
        Name = nameLabel,
    }
end

function Overlay:_removeObject(player)
    if self.Objects[player] then
        self.Objects[player].Frame:Destroy()
        self.Objects[player] = nil
    end
end

function Overlay:_isVisible(root)
    if not self.Settings.UseLineOfSight then
        return true
    end

    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {LocalPlayer.Character}
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist

    local direction = (root.Position - Camera.CFrame.Position)
    local result = Workspace:Raycast(Camera.CFrame.Position, direction, rayParams)

    return not result or result.Instance:IsDescendantOf(root.Parent)
end

function Overlay:_update()
    if not self.Settings.Enabled then
        for _, obj in pairs(self.Objects) do
            obj.Frame.Visible = false
        end
        return
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then

            if not self.Objects[player] then
                self:_createObject(player)
            end

            local obj = self.Objects[player]
            local char = player.Character
            local humanoid = char and char:FindFirstChildOfClass("Humanoid")
            local root = char and char:FindFirstChild("HumanoidRootPart")

            if not char or not root or not humanoid then
                obj.Frame.Visible = false
                continue
            end

            if self.Settings.TeamCheck and player.Team == LocalPlayer.Team then
                obj.Frame.Visible = false
                continue
            end

            local distance = (root.Position - Camera.CFrame.Position).Magnitude
            if distance > self.Settings.MaxDistance then
                obj.Frame.Visible = false
                continue
            end

            if not self:_isVisible(root) then
                obj.Frame.Visible = false
                continue
            end

            local screenPos, onScreen = Camera:WorldToViewportPoint(root.Position)
            if not onScreen then
                obj.Frame.Visible = false
                continue
            end

            -- Dynamic scaling
            local scale = math.clamp(1 / (distance / 600), 0.5, 2)
            local width = 60 * scale
            local height = 100 * scale

            obj.Frame.Size = UDim2.fromOffset(width, height)
            obj.Frame.Position = UDim2.fromOffset(screenPos.X - width/2, screenPos.Y - height/2)
            obj.Frame.Visible = true

            -- Box
            obj.Box.Size = UDim2.fromScale(1,1)
            obj.Box.BorderColor3 = self.Settings.BoxColor
            obj.Box.Visible = self.Settings.ShowBox

            -- Name
            obj.Name.Size = UDim2.new(1,0,0.2,0)
            obj.Name.Position = UDim2.new(0,0,-0.2,0)
            obj.Name.TextColor3 = self.Settings.TextColor
            obj.Name.Visible = self.Settings.ShowName
            obj.Name.Text = player.Name
        end
    end
end

function Overlay:_init()
    self.Connection = RunService.RenderStepped:Connect(function()
        self:_update()
    end)

    Players.PlayerRemoving:Connect(function(player)
        self:_removeObject(player)
    end)
end

function Overlay:Destroy()
    if self.Connection then
        self.Connection:Disconnect()
    end
    for _, obj in pairs(self.Objects) do
        obj.Frame:Destroy()
    end
    self.Objects = {}
end

return Overlay
