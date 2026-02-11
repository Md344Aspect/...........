local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local ESP = {}
ESP.__index = ESP

ESP.DefaultSettings = {
	Enabled = true,
	ShowBoxes = true,
	ShowNames = true,
	ShowDistance = true,
	ShowHealthBar = true,

	MaxDistance = 2500,
	TeamCheck = false,

	BoxColor = Color3.fromRGB(255, 0, 0),
	TextColor = Color3.fromRGB(255, 255, 255),
	HealthHighColor = Color3.fromRGB(0, 255, 0),
	HealthLowColor = Color3.fromRGB(255, 0, 0),
}

function ESP.new(settings)
	local self = setmetatable({}, ESP)

	self.Settings = settings or ESP.DefaultSettings
	self.Objects = {}
	self.Connections = {}

	self:_init()

	return self
end

function ESP:_init()
	for _, player in pairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			self:_trackPlayer(player)
		end
	end

	table.insert(self.Connections,
		Players.PlayerAdded:Connect(function(player)
			self:_trackPlayer(player)
		end)
	)

	table.insert(self.Connections,
		Players.PlayerRemoving:Connect(function(player)
			self:_removePlayer(player)
		end)
	)
end

function ESP:_createESP(player)
	local container = Instance.new("BillboardGui")
	container.Name = "ESPContainer"
	container.AlwaysOnTop = true
	container.Size = UDim2.new(4, 0, 5, 0)
	container.StudsOffset = Vector3.new(0, 3, 0)

	local box = Instance.new("Frame")
	box.Size = UDim2.fromScale(1, 1)
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.Parent = container

	local stroke = Instance.new("UIStroke")
	stroke.Color = self.Settings.BoxColor
	stroke.Thickness = 2
	stroke.Parent = box

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0.25, 0)
	nameLabel.Position = UDim2.new(0, 0, -0.25, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = self.Settings.TextColor
	nameLabel.Font = Enum.Font.SourceSansBold
	nameLabel.Parent = container

	local healthBarBG = Instance.new("Frame")
	healthBarBG.Size = UDim2.new(0.05, 0, 1, 0)
	healthBarBG.Position = UDim2.new(-0.08, 0, 0, 0)
	healthBarBG.BackgroundColor3 = Color3.new(0, 0, 0)
	healthBarBG.BorderSizePixel = 0
	healthBarBG.Parent = container

	local healthBar = Instance.new("Frame")
	healthBar.Size = UDim2.new(1, 0, 1, 0)
	healthBar.BorderSizePixel = 0
	healthBar.Parent = healthBarBG

	self.Objects[player] = {
		GUI = container,
		NameLabel = nameLabel,
		HealthBar = healthBar,
		Stroke = stroke,
	}

	return container
end

function ESP:_trackPlayer(player)
	player.CharacterAdded:Connect(function(char)
		self:_attachToCharacter(player, char)
	end)

	if player.Character then
		self:_attachToCharacter(player, player.Character)
	end
end

function ESP:_attachToCharacter(player, character)
	local root = character:WaitForChild("HumanoidRootPart", 5)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not root or not humanoid then return end

	local gui = self:_createESP(player)
	gui.Adornee = root
	gui.Parent = root

	self:_startUpdating(player, humanoid)
end

function ESP:_startUpdating(player, humanoid)
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if not self.Settings.Enabled then
			if self.Objects[player] then
				self.Objects[player].GUI.Enabled = false
			end
			return
		end

		if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
			return
		end

		local root = player.Character.HumanoidRootPart
		local distance = (root.Position - Camera.CFrame.Position).Magnitude

		if distance > self.Settings.MaxDistance then
			self.Objects[player].GUI.Enabled = false
			return
		end

		if self.Settings.TeamCheck and player.Team == LocalPlayer.Team then
			self.Objects[player].GUI.Enabled = false
			return
		end

		local obj = self.Objects[player]
		obj.GUI.Enabled = true

		if self.Settings.ShowNames then
			obj.NameLabel.Text = player.Name .. " [" .. math.floor(distance) .. "]"
		else
			obj.NameLabel.Text = ""
		end

		if self.Settings.ShowHealthBar then
			local healthPercent = humanoid.Health / humanoid.MaxHealth
			obj.HealthBar.Size = UDim2.new(1, 0, healthPercent, 0)

			obj.HealthBar.BackgroundColor3 =
				self.Settings.HealthLowColor:Lerp(
					self.Settings.HealthHighColor,
					healthPercent
				)
		end
	end)

	table.insert(self.Connections, connection)
end

function ESP:_removePlayer(player)
	if self.Objects[player] then
		self.Objects[player].GUI:Destroy()
		self.Objects[player] = nil
	end
end


function ESP:Destroy()
	for _, connection in ipairs(self.Connections) do
		connection:Disconnect()
	end

	for _, obj in pairs(self.Objects) do
		obj.GUI:Destroy()
	end

	self.Objects = {}
	self.Connections = {}
end

return ESP
