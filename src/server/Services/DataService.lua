--[[
	DataService - player persistence with session locking.

	- Profiles are loaded with UpdateAsync and stamped with this server's JobId,
	  so a player rejoining quickly can't load stale data on another server.
	- Autosave every Game.AutosaveSeconds, on leave, and on shutdown.
	- Save(player) is callable at any time (MonetizationService saves right
	  after granting a Robux purchase).
]]
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Game = require(game.ReplicatedStorage.Shared.Config.Game)

local DataService = {}

local LOCK_EXPIRE = 1800 -- seconds; a lock older than this is considered abandoned
local store
local okStore = pcall(function()
	store = DataStoreService:GetDataStore(Game.DataStoreName)
end)

local profiles: { [Player]: any } = {}
local loadedEvent = Instance.new("BindableEvent")
DataService.ProfileLoaded = loadedEvent.Event

local function defaultData()
	return {
		version = 1,
		cash = Game.StartingCash,
		vault = 0,
		totalEarned = 0,
		owned = {},           -- [itemId] = true
		rebirths = 0,
		bonusRebirths = 0,    -- from Rebirth Tokens
		boostUntil = 0,
		receipts = {},        -- [purchaseId] = os.time()
		receiptOrder = {},
		claimedOnce = {},     -- one-time grants (e.g. Starter Pack cash)
		lastOnline = 0,
		dailyStreak = 0,
		lastDaily = 0,
		flights = 0,
		playSeconds = 0,
	}
end

local function reconcile(data)
	local def = defaultData()
	for k, v in pairs(def) do
		if data[k] == nil then
			data[k] = v
		end
	end
	return data
end

local function key(player)
	return "u_" .. player.UserId
end

local function retry(fn, attempts)
	local lastErr
	for i = 1, attempts do
		local ok, a, b = pcall(fn)
		if ok then
			return true, a, b
		end
		lastErr = a
		task.wait(math.min(2 ^ i, 10))
	end
	return false, lastErr
end

function DataService.Load(player: Player)
	if not okStore or not store then
		warn("[Data] DataStore unavailable (enable Studio API access). Using a temporary profile.")
		profiles[player] = { data = defaultData(), temporary = true }
		loadedEvent:Fire(player, profiles[player].data)
		return profiles[player].data
	end

	local loaded
	for attempt = 1, 6 do
		local ok, result = retry(function()
			return store:UpdateAsync(key(player), function(old)
				old = old or defaultData()
				local lock = old.lock
				if lock and lock.jobId ~= game.JobId and os.time() - lock.time < LOCK_EXPIRE and attempt < 6 then
					return nil -- someone else holds it; abort without writing
				end
				old.lock = { jobId = game.JobId, time = os.time() }
				return old
			end)
		end, 3)
		if ok and result and result.lock and result.lock.jobId == game.JobId then
			loaded = result
			break
		end
		if not player.Parent then
			return nil
		end
		task.wait(5) -- previous server is still saving; wait for it to release the lock
	end

	if not player.Parent then
		return nil
	end
	if not loaded then
		player:Kick("Could not load your save data. Please rejoin in a moment.")
		return nil
	end
	loaded.lock = nil
	profiles[player] = { data = reconcile(loaded) }
	loadedEvent:Fire(player, profiles[player].data)
	return profiles[player].data
end

function DataService.Get(player: Player)
	local p = profiles[player]
	return p and p.data
end

function DataService.Save(player: Player, release: boolean?)
	local p = profiles[player]
	if not p or p.temporary or not store then
		return true
	end
	p.data.lastOnline = os.time()
	local snapshot = table.clone(p.data)
	local ok, err = retry(function()
		return store:UpdateAsync(key(player), function(old)
			if old and old.lock and old.lock.jobId ~= game.JobId and os.time() - old.lock.time < LOCK_EXPIRE then
				return nil -- another server took over; never overwrite its data
			end
			snapshot.lock = (not release) and { jobId = game.JobId, time = os.time() } or nil
			return snapshot
		end)
	end, 3)
	if not ok then
		warn("[Data] Save failed for", player.Name, err)
	end
	return ok
end

function DataService.Init()
	Players.PlayerRemoving:Connect(function(player)
		if profiles[player] then
			DataService.Save(player, true)
			profiles[player] = nil
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Game.AutosaveSeconds)
			for player in pairs(profiles) do
				task.spawn(DataService.Save, player, false)
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and not okStore then
			return
		end
		local pending = 0
		for player in pairs(profiles) do
			pending += 1
			task.spawn(function()
				DataService.Save(player, true)
				pending -= 1
			end)
		end
		local start = os.clock()
		while pending > 0 and os.clock() - start < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
