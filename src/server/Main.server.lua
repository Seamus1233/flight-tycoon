--[[
	SkyForge Tycoon - server entry point.
	Creates remotes, builds the world, and starts every service.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Parent.Services
local DataService = require(Services.DataService)
local WorldBuilder = require(Services.WorldBuilder)
local TycoonService = require(Services.TycoonService)
local MonetizationService = require(Services.MonetizationService)
local FlightService = require(Services.FlightService)
local LeaderboardService = require(Services.LeaderboardService)

-- remotes
local remotesFolder = Instance.new("Folder")
remotesFolder.Name = "Remotes"
local Remotes = {}
for _, name in ipairs({ "Notify", "Action", "OpenUI", "Purchased", "Collected" }) do
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotesFolder
	Remotes[name] = r
end
remotesFolder.Parent = ReplicatedStorage

WorldBuilder.Environment()

local deps = {
	DataService = DataService,
	TycoonService = TycoonService,
	MonetizationService = MonetizationService,
	FlightService = FlightService,
	Remotes = Remotes,
}
DataService.Init()
MonetizationService.Init(deps)
FlightService.Init(deps)
TycoonService.Init(deps)
LeaderboardService.Init(deps)

-- client -> server actions, rate limited
local lastAction: { [Player]: number } = {}
local ACTIONS = {
	Rebirth = function(player) TycoonService.Rebirth(player) end,
	ClaimDaily = function(player) TycoonService.ClaimDaily(player) end,
	Fly = function(player, id) FlightService.Fly(player, id) end,
	Land = function(player) FlightService.Despawn(player) end,
	BuyPass = function(player, key)
		if typeof(key) == "string" then MonetizationService.PromptPass(player, key) end
	end,
	BuyProduct = function(player, key)
		if typeof(key) == "string" then MonetizationService.PromptProduct(player, key) end
	end,
}
Remotes.Action.OnServerEvent:Connect(function(player, action, ...)
	local now = os.clock()
	if (lastAction[player] or 0) > now then
		return
	end
	lastAction[player] = now + 0.25
	local fn = typeof(action) == "string" and ACTIONS[action]
	if fn then
		fn(player, ...)
	end
end)
Players.PlayerRemoving:Connect(function(p)
	lastAction[p] = nil
end)
