--[[
	LeaderboardService - global "Top Tycoons" board by total cash earned,
	shown on a billboard in the lobby. Uses an OrderedDataStore.
]]
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Game = require(game.ReplicatedStorage.Shared.Config.Game)
local Format = require(game.ReplicatedStorage.Shared.Util.Format)

local LeaderboardService = {}
local DataService

local REFRESH = 120
local ROWS = 10

local function buildBoard()
	local board = Instance.new("Part")
	board.Name = "GlobalLeaderboard"
	board.Anchored = true
	board.Size = Vector3.new(26, 32, 1)
	board.CFrame = CFrame.new(0, 17, -14) * CFrame.Angles(0, math.pi, 0)
	board.Color = Color3.fromRGB(25, 28, 36)
	board.Parent = workspace:WaitForChild("Map")
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.PixelsPerStud = 25
	sg.Parent = board
	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.Size = UDim2.fromScale(1, 1)
	list.Parent = sg
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local title = Instance.new("TextLabel")
	title.LayoutOrder = 0
	title.Size = UDim2.new(1, 0, 0.12, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 210, 80)
	title.Text = "TOP AIR TYCOONS"
	title.Parent = list
	for i = 1, ROWS do
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. i
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0.085, 0)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.GothamBold
		row.TextScaled = true
		row.TextColor3 = Color3.new(1, 1, 1)
		row.Text = ""
		row.Parent = list
	end
	return list
end

function LeaderboardService.Init(deps)
	DataService = deps.DataService
	local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, Game.LeaderboardStoreName)
	if not ok then
		return
	end
	local list = buildBoard()
	local names = {}
	task.spawn(function()
		while true do
			-- push current players' scores (stored as log-scaled ints so huge numbers fit)
			for _, p in ipairs(Players:GetPlayers()) do
				local data = DataService.Get(p)
				if data and data.totalEarned > 0 then
					pcall(store.SetAsync, store, tostring(p.UserId), math.floor(math.log10(data.totalEarned + 1) * 1e6))
				end
			end
			local okPage, pages = pcall(store.GetSortedAsync, store, false, ROWS)
			if okPage then
				for i, entry in ipairs(pages:GetCurrentPage()) do
					local uid = tonumber(entry.key)
					if uid and not names[uid] then
						local okName, n = pcall(Players.GetNameFromUserIdAsync, Players, uid)
						names[uid] = okName and n or ("Pilot " .. uid)
					end
					list["Row" .. i].Text = string.format("%d. %s  %s", i, names[uid] or "?",
						Format.Money(10 ^ (entry.value / 1e6)))
				end
			end
			task.wait(REFRESH)
		end
	end)
end

return LeaderboardService
