--[[
	Effects controller (local only, so it costs the server nothing):
	- guide beam from the player to the next item they can buy
	- floating "+$" popups over your aircraft bays (the "production line")
	- purchase / collect bursts and sounds
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local Format = require(Shared.Util.Format)

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local Effects = {}

-- Paste audio asset IDs from the Creator Store here (e.g. "rbxassetid://123").
-- Left blank, no sound is played.
Effects.Sounds = { Purchase = "", Collect = "" }

local function myPlot()
	local idx = player:GetAttribute("PlotIndex")
	local plots = workspace:FindFirstChild("Plots")
	return idx and plots and plots:FindFirstChild("Plot" .. idx)
end

local function sound(id, volume)
	if not id or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.5
	s.Parent = workspace.CurrentCamera
	s:Play()
	s.Ended:Once(function() s:Destroy() end)
end

local function floatText(adornee: BasePart, msg: string, color: Color3, offset: number)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(160, 40)
	bb.StudsOffset = Vector3.new(0, offset or 6, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 120
	bb.Adornee = adornee
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.2
	t.Text = msg
	t.Parent = bb
	bb.Parent = player.PlayerGui
	TweenService:Create(bb, TweenInfo.new(1.4), { StudsOffset = Vector3.new(0, (offset or 6) + 6, 0) }):Play()
	TweenService:Create(t, TweenInfo.new(1.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.5, function() bb:Destroy() end)
end

-- guide beam --------------------------------------------------------------
local beam, a0, a1
local function updateGuide()
	local plot = myPlot()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local nextId = player:GetAttribute("NextItem")
	local pad = plot and nextId and nextId ~= "" and plot.Pads:FindFirstChild(nextId)
	local affordable = pad and (player:GetAttribute("Cash") or 0) >= (player:GetAttribute("NextCost") or math.huge)
	if not (hrp and pad and affordable) then
		if beam then beam.Enabled = false end
		return
	end
	if not beam then
		a0 = Instance.new("Attachment")
		a1 = Instance.new("Attachment")
		beam = Instance.new("Beam")
		beam.Width0, beam.Width1 = 0.6, 0.6
		beam.FaceCamera = true
		beam.Color = ColorSequence.new(Color3.fromRGB(90, 255, 120))
		beam.LightEmission = 1
		beam.Transparency = NumberSequence.new(0.2)
		beam.Attachment0, beam.Attachment1 = a0, a1
		beam.Parent = workspace.Terrain
	end
	a0.Parent = hrp
	a1.Parent = pad
	beam.Enabled = true
end

-- production popups ---------------------------------------------------------
local function productionLoop()
	while true do
		task.wait(2.5)
		local plot = myPlot()
		if plot and plot:FindFirstChild("Built") then
			local mult = player:GetAttribute("Multiplier") or 1
			for _, m in ipairs(plot.Built:GetChildren()) do
				local it = Items.ById[m.Name]
				local root = m:IsA("Model") and m.PrimaryPart
				if root and it and it.kind == "aircraft" and math.random() < 0.35 then
					floatText(root, "+" .. Format.Money(it.income * mult * 2.5), Color3.fromRGB(120, 255, 140), 5)
				end
			end
		end
	end
end

function Effects.Init()
	task.spawn(productionLoop)
	task.spawn(function()
		while true do
			pcall(updateGuide)
			task.wait(0.5)
		end
	end)
	Remotes.Purchased.OnClientEvent:Connect(function(id)
		sound(Effects.Sounds.Purchase, 0.6)
		local plot = myPlot()
		local built = plot and plot.Built:FindFirstChild(id)
		local adornee = built and (built:IsA("Model") and (built.PrimaryPart or built:FindFirstChildWhichIsA("BasePart")))
		if adornee then
			local it = Items.ById[id]
			floatText(adornee, "UNLOCKED!", Color3.fromRGB(255, 210, 70), 8)
			if it and it.kind == "aircraft" then
				local fx = Instance.new("ParticleEmitter")
				fx.Texture = "rbxasset://textures/particles/sparkles_main.dds"
				fx.Rate = 0
				fx.Speed = NumberRange.new(10, 20)
				fx.Lifetime = NumberRange.new(0.6, 1)
				fx.SpreadAngle = Vector2.new(180, 180)
				fx.Parent = adornee
				fx:Emit(60)
				task.delay(2, function() fx:Destroy() end)
			end
		end
	end)
	Remotes.Collected.OnClientEvent:Connect(function(amount)
		sound(Effects.Sounds.Collect, 0.5)
		local plot = myPlot()
		if plot then
			floatText(plot.Collector, "+" .. Format.Money(amount), Color3.fromRGB(120, 255, 140), 8)
		end
	end)
end

return Effects
