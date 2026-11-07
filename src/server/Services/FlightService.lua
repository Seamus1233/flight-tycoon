--[[
	FlightService - spawns a flyable copy of an owned aircraft on the player's
	runway. Physics are client-owned (network ownership) and driven by the
	client FlightController through LinearVelocity + AlignOrientation.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Game = require(Shared.Config.Game)
local Aircraft = require(Shared.Config.Aircraft)
local Layout = require(Shared.Layout)
local AircraftBuilder = require(Shared.AircraftBuilder)

local FlightService = {}
local DataService, TycoonService, MonetizationService

local active: { [Player]: Model } = {}
local cooldown: { [Player]: number } = {}

local function despawn(player: Player)
	local m = active[player]
	active[player] = nil
	if m then
		m:Destroy()
	end
end
FlightService.Despawn = despawn

local function owns(player: Player, id: string): boolean
	local list = player:GetAttribute("OwnedAircraft") or ""
	for owned in string.gmatch(list, "[^,]+") do
		if owned == id then
			return true
		end
	end
	return false
end

function FlightService.Fly(player: Player, id: string)
	if typeof(id) ~= "string" then
		return
	end
	local spec = Aircraft.ById[id]
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not spec or not hum or hum.Health <= 0 or not owns(player, id) then
		return
	end
	if (cooldown[player] or 0) > os.clock() then
		return
	end
	cooldown[player] = os.clock() + 3
	local plot = TycoonService.GetPlot(player)
	if not plot then
		return
	end
	despawn(player)

	local size = math.min(math.max(spec.L, spec.S) * Game.FlightStudsPerMetre, Game.FlightMaxStuds)
	local model = AircraftBuilder.Build(spec, size)
	local root = model.PrimaryPart
	local extents: Vector3 = model:GetAttribute("Extents")
	root.Size = Vector3.new(math.max(2, extents.X * 0.25), 2, math.max(4, extents.Z * 0.7))
	root.CanCollide = true
	root.Massless = false
	root.CustomPhysicalProperties = PhysicalProperties.new(1, 0.3, 0.1)

	-- pilot seat just behind the canopy
	local seat = Instance.new("Seat")
	seat.Name = "PilotSeat"
	seat.Size = Vector3.new(2, 1, 2)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.Massless = true
	seat.CFrame = root.CFrame * CFrame.new(0, extents.Y * 0.18, -extents.Z * 0.18)
	seat:SetAttribute("AircraftSeat", true)
	seat.Parent = model
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = seat
	w.Parent = seat

	local att = Instance.new("Attachment")
	att.Name = "FlightAttachment"
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Name = "Thrust"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 1e9
	lv.VectorVelocity = Vector3.zero
	lv.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Name = "Steer"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = 1e9
	ao.Responsiveness = 25
	ao.CFrame = CFrame.new()
	ao.Parent = root

	local maxSpeed = math.clamp(spec.speed * Game.FlightSpeedScale, Game.FlightMinSpeed, Game.FlightMaxSpeed)
	if MonetizationService.HasPass(player, "Afterburner") then
		maxSpeed *= 1.5
	end
	model:SetAttribute("MaxSpeed", maxSpeed)
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("DisplayName", spec.name)
	model.Name = player.Name .. "_Flight"

	local start = plot.Base.CFrame * CFrame.new(0, 0.5, 0) * Layout.RunwayStart
	model:PivotTo(start * CFrame.new(0, extents.Y / 2 + 1.5, 0))
	model.Parent = workspace
	active[player] = model
	root:SetNetworkOwner(player)

	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if not seat.Occupant then
			task.delay(1, function()
				if active[player] == model then
					despawn(player)
				end
			end)
		end
	end)
	task.wait(0.2)
	seat:Sit(hum)

	local data = DataService.Get(player)
	if data then
		data.flights += 1
	end
end

function FlightService.Init(deps)
	DataService = deps.DataService
	TycoonService = deps.TycoonService
	MonetizationService = deps.MonetizationService
	Players.PlayerRemoving:Connect(function(p)
		despawn(p)
		cooldown[p] = nil
	end)
	Players.PlayerAdded:Connect(function(p)
		p.CharacterRemoving:Connect(function()
			despawn(p)
		end)
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		p.CharacterRemoving:Connect(function()
			despawn(p)
		end)
	end
end

return FlightService
