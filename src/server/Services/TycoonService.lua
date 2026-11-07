--[[
	TycoonService - plots, purchases, income, vault, rebirths, daily rewards,
	offline earnings. All money logic is server-authoritative.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Game = require(Shared.Config.Game)
local Items = require(Shared.Config.Items)
local Aircraft = require(Shared.Config.Aircraft)
local Monetization = require(Shared.Config.Monetization)
local Format = require(Shared.Util.Format)
local AircraftBuilder = require(Shared.AircraftBuilder)
local WorldBuilder = require(script.Parent.WorldBuilder)

local TycoonService = {}
local DataService, MonetizationService, Remotes

type State = {
	plot: Model,
	pads: { [string]: BasePart },
	friends: number,
	ready: boolean,
}
local states: { [Player]: State } = {}
local plotOwners: { [number]: Player } = {}
local plots: { [number]: Model } = {}
local touchDebounce: { [Player]: number } = {}

-- ------------------------------------------------------------------ helpers
function TycoonService.Notify(player: Player, text: string, style: string?)
	Remotes.Notify:FireClient(player, text, style or "info")
end

local function ownsPremiumAircraft(player: Player, id: string): boolean
	for key, p in pairs(Monetization.Passes) do
		if p.aircraft == id then
			return MonetizationService.HasPass(player, key)
		end
	end
	return false
end

local function bestFreeIncome(data): number
	local best = 0
	for id in pairs(data.owned) do
		local it = Items.ById[id]
		if it and it.kind == "aircraft" and it.income > best then
			best = it.income
		end
	end
	return best
end

function TycoonService.PremiumIncome(player: Player, data, id: string): number
	return math.max(Monetization.PremiumAircraftMinIncome,
		bestFreeIncome(data) * (Monetization.PremiumAircraftMult[id] or 1))
end

function TycoonService.Multiplier(player: Player): number
	local data = DataService.Get(player)
	if not data then
		return 1
	end
	local bonus = 0
	for id in pairs(data.owned) do
		local it = Items.ById[id]
		if it and it.kind == "facility" then
			bonus += it.bonus
		end
	end
	local m = (1 + bonus)
	m *= 1 + Items.RebirthBonus * (data.rebirths + data.bonusRebirths)
	m *= MonetizationService.PassMultiplier(player)
	if data.boostUntil > os.time() then
		m *= 2
	end
	if player.MembershipType == Enum.MembershipType.Premium then
		m *= 1 + Game.PremiumBonus
	end
	local st = states[player]
	if st then
		m *= 1 + math.min(Game.FriendBonusMax, st.friends * Game.FriendBonusEach)
	end
	return m
end

function TycoonService.BaseIncome(player: Player): number
	local data = DataService.Get(player)
	if not data then
		return 0
	end
	local base = Items.BaseIncome
	for id in pairs(data.owned) do
		local it = Items.ById[id]
		if it and it.kind == "aircraft" then
			base += it.income
		end
	end
	for _, a in ipairs(Aircraft.List) do
		if a.premium and ownsPremiumAircraft(player, a.id) then
			base += TycoonService.PremiumIncome(player, data, a.id)
		end
	end
	return base
end

function TycoonService.IncomePerSecond(player: Player): number
	return math.floor(TycoonService.BaseIncome(player) * TycoonService.Multiplier(player))
end

function TycoonService.AddCash(player: Player, amount: number, countsAsEarned: boolean?)
	local data = DataService.Get(player)
	if not data then
		return
	end
	data.cash += amount
	if countsAsEarned ~= false then
		data.totalEarned += amount
	end
	TycoonService.Refresh(player)
end

local function isVisible(data, it): boolean
	return not data.owned[it.id] and (it.requires == nil or data.owned[it.requires] == true)
end

local function nextItem(data)
	-- cheapest currently available item, used for the UI guide arrow
	local best
	for _, it in ipairs(Items.List) do
		if isVisible(data, it) and (not best or it.cost < best.cost) then
			best = it
		end
	end
	return best
end

function TycoonService.Refresh(player: Player)
	local data = DataService.Get(player)
	local st = states[player]
	if not data or not st then
		return
	end
	local income = TycoonService.IncomePerSecond(player)
	player:SetAttribute("Cash", data.cash)
	player:SetAttribute("Vault", data.vault)
	player:SetAttribute("VaultCap", income * 60 * Game.VaultCapMinutes)
	player:SetAttribute("Income", income)
	player:SetAttribute("Multiplier", TycoonService.Multiplier(player))
	player:SetAttribute("Rebirths", data.rebirths + data.bonusRebirths)
	player:SetAttribute("BoostUntil", data.boostUntil)
	player:SetAttribute("CanRebirth", data.owned[Items.FinalItemId] == true)
	player:SetAttribute("DailyReadyAt", data.lastDaily + 20 * 3600)
	player:SetAttribute("DailyStreak", data.dailyStreak)
	player:SetAttribute("TotalEarned", data.totalEarned)
	local n = nextItem(data)
	player:SetAttribute("NextItem", n and n.id or "")
	player:SetAttribute("NextCost", n and n.cost or 0)
	local ownedPlanes = {}
	for _, a in ipairs(Aircraft.List) do
		if data.owned[a.id] or (a.premium and ownsPremiumAircraft(player, a.id)) then
			table.insert(ownedPlanes, a.id)
		end
	end
	player:SetAttribute("OwnedAircraft", table.concat(ownedPlanes, ","))
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls.Cash.Value = Format.Money(data.cash)
		ls.Rebirths.Value = data.rebirths + data.bonusRebirths
	end
	local collector = st.plot:FindFirstChild("Collector")
	if collector and collector:FindFirstChild("Label") then
		collector.Label.Sub.Text = MonetizationService.HasPass(player, "AutoCollect") and "AUTO" or Format.Money(data.vault)
	end
end

-- ------------------------------------------------------------------ building
local function buildItem(player: Player, it)
	local st = states[player]
	if it.kind == "aircraft" then
		local spec = Aircraft.ById[it.id]
		local model = AircraftBuilder.Build(spec, Game.DisplayLength)
		WorldBuilder.DisplayAircraft(st.plot, spec, model)
	else
		WorldBuilder.Facility(st.plot, it)
	end
end

local function buildPremium(player: Player, spec)
	local st = states[player]
	if st.plot.Built:FindFirstChild(spec.id) then
		return
	end
	local model = AircraftBuilder.Build(spec, Game.DisplayLength)
	WorldBuilder.DisplayAircraft(st.plot, spec, model)
end

local function onPadTouched(pad: BasePart, hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	local st = states[player]
	if not st or st.plot ~= pad:FindFirstAncestorOfClass("Model") then
		return
	end
	local now = os.clock()
	if (touchDebounce[player] or 0) > now then
		return
	end
	touchDebounce[player] = now + 0.6
	local id = pad:GetAttribute("ItemId")
	local spec = Aircraft.ById[id]
	if spec and spec.premium then
		for key, p in pairs(Monetization.Passes) do
			if p.aircraft == id then
				MonetizationService.PromptPass(player, key)
			end
		end
		return
	end
	TycoonService.Purchase(player, id)
end

local function refreshPads(player: Player)
	local data = DataService.Get(player)
	local st = states[player]
	-- remove pads that are no longer valid
	for id, pad in pairs(st.pads) do
		local it = Items.ById[id]
		local spec = Aircraft.ById[id]
		local stillValid = (it and isVisible(data, it)) or (spec and spec.premium and not ownsPremiumAircraft(player, id))
		if not stillValid then
			pad:Destroy()
			st.pads[id] = nil
		end
	end
	for _, it in ipairs(Items.List) do
		if isVisible(data, it) and not st.pads[it.id] then
			local pad = WorldBuilder.Pad(st.plot, it.id, it.name, it.cost, false)
			pad.Touched:Connect(function(hit) onPadTouched(pad, hit) end)
			st.pads[it.id] = pad
		end
	end
	for _, a in ipairs(Aircraft.List) do
		if a.premium and not ownsPremiumAircraft(player, a.id) and not st.pads[a.id] then
			local pad = WorldBuilder.Pad(st.plot, a.id, a.name, nil, true)
			pad.Touched:Connect(function(hit) onPadTouched(pad, hit) end)
			st.pads[a.id] = pad
		end
	end
end

function TycoonService.Purchase(player: Player, id: string): boolean
	local data = DataService.Get(player)
	local st = states[player]
	local it = Items.ById[id]
	if not data or not st or not st.ready or not it or not isVisible(data, it) then
		return false
	end
	if data.cash < it.cost then
		TycoonService.Notify(player, "Need " .. Format.Money(it.cost - data.cash) .. " more for " .. it.name, "error")
		Remotes.OpenUI:FireClient(player, "NeedCash", it.cost - data.cash)
		return false
	end
	data.cash -= it.cost
	data.owned[id] = true
	buildItem(player, it)
	refreshPads(player)
	TycoonService.Refresh(player)
	Remotes.Purchased:FireClient(player, id)
	if id == Items.FinalItemId then
		TycoonService.Notify(player, "AIR SUPREMACY! Rebirth is now unlocked.", "gold")
	end
	return true
end

-- Used by the Skip Next Purchase product
function TycoonService.GrantNextItem(player: Player): boolean
	local data = DataService.Get(player)
	if not data or not states[player] then
		return false
	end
	local n = nextItem(data)
	if not n then
		-- nothing left to unlock: refund as 30 minutes of income so the purchase is never wasted
		TycoonService.AddCash(player, TycoonService.IncomePerSecond(player) * 1800, false)
		TycoonService.Notify(player, "Everything unlocked - converted to 30 min of income.", "gold")
		return true
	end
	data.owned[n.id] = true
	buildItem(player, n)
	refreshPads(player)
	TycoonService.Refresh(player)
	Remotes.Purchased:FireClient(player, n.id)
	TycoonService.Notify(player, "Skipped! " .. n.name .. " unlocked.", "gold")
	return true
end

function TycoonService.OnPassesChanged(player: Player)
	local st = states[player]
	if not st then
		return
	end
	for _, a in ipairs(Aircraft.List) do
		if a.premium and ownsPremiumAircraft(player, a.id) then
			buildPremium(player, a)
		end
	end
	refreshPads(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = MonetizationService.HasPass(player, "Afterburner") and 32 or 20
	end
	player:SetAttribute("VIP", MonetizationService.HasPass(player, "VIP"))
	TycoonService.Refresh(player)
end

-- ------------------------------------------------------------------ actions
function TycoonService.Collect(player: Player)
	local data = DataService.Get(player)
	if not data or data.vault <= 0 then
		return
	end
	local amount = data.vault
	data.vault = 0
	data.cash += amount
	TycoonService.Refresh(player)
	Remotes.Collected:FireClient(player, amount)
end

function TycoonService.Rebirth(player: Player)
	local data = DataService.Get(player)
	local st = states[player]
	if not data or not st or not data.owned[Items.FinalItemId] then
		return
	end
	data.rebirths += 1
	data.cash = 0
	data.vault = 0
	data.owned = {}
	for _, child in ipairs(st.plot.Built:GetChildren()) do
		local spec = Aircraft.ById[child.Name]
		if not (spec and spec.premium) then
			child:Destroy()
		end
	end
	refreshPads(player)
	TycoonService.Refresh(player)
	TycoonService.Notify(player, string.format("REBIRTH #%d! Permanent income x%.1f", data.rebirths + data.bonusRebirths,
		1 + Items.RebirthBonus * (data.rebirths + data.bonusRebirths)), "gold")
	DataService.Save(player, false)
end

function TycoonService.ClaimDaily(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local now = os.time()
	if now - data.lastDaily < 20 * 3600 then
		TycoonService.Notify(player, "Daily reward ready in " .. Format.Time(data.lastDaily + 20 * 3600 - now), "error")
		return
	end
	if now - data.lastDaily > 48 * 3600 then
		data.dailyStreak = 0
	end
	data.dailyStreak += 1
	data.lastDaily = now
	local idx = math.min(data.dailyStreak, #Game.DailyRewardMinutes)
	local amount = math.max(100, TycoonService.IncomePerSecond(player) * 60 * Game.DailyRewardMinutes[idx])
	TycoonService.AddCash(player, amount, false)
	TycoonService.Notify(player, string.format("Day %d reward: +%s", data.dailyStreak, Format.Money(amount)), "success")
end

-- ------------------------------------------------------------------ lifecycle
local function countFriends(player: Player)
	local n = 0
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local ok, isFriend = pcall(player.IsFriendsWith, player, other.UserId)
			if ok and isFriend then
				n += 1
			end
		end
	end
	return n
end

local function spawnAtPlot(player: Player, character: Model)
	local st = states[player]
	if not st then
		return
	end
	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if not hrp then
		return
	end
	task.wait()
	local pad = st.plot:FindFirstChild("SpawnPad")
	character:PivotTo(pad.CFrame * CFrame.new(0, 4, 0))
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = MonetizationService.HasPass(player, "Afterburner") and 32 or 20
	end
end

local function onPlayerAdded(player: Player)
	local index
	for i = 1, Game.MaxPlots do
		if not plotOwners[i] then
			index = i
			break
		end
	end
	if not index then
		player:Kick("This server is full of airbases. Please join another server!")
		return
	end
	plotOwners[index] = player
	local plot = plots[index]
	local st: State = { plot = plot, pads = {}, friends = 0, ready = false }
	states[player] = st
	player:SetAttribute("PlotIndex", index)
	plot.OwnerSign.SurfaceGui.Owner.Text = string.upper(player.DisplayName) .. "'S HANGAR"

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local cash = Instance.new("StringValue")
	cash.Name = "Cash"
	cash.Parent = ls
	local reb = Instance.new("IntValue")
	reb.Name = "Rebirths"
	reb.Parent = ls
	ls.Parent = player

	player.CharacterAdded:Connect(function(c) spawnAtPlot(player, c) end)
	if player.Character then
		task.spawn(spawnAtPlot, player, player.Character)
	end

	local data = DataService.Load(player)
	if not data or not player.Parent then
		return
	end
	MonetizationService.LoadPasses(player)

	for _, it in ipairs(Items.List) do
		if data.owned[it.id] then
			buildItem(player, it)
		end
	end
	refreshPads(player)
	st.friends = countFriends(player)
	st.ready = true
	MonetizationService.ApplyPassPerks(player)

	-- offline earnings
	if data.lastOnline > 0 then
		local elapsed = math.min(os.time() - data.lastOnline, Game.OfflineEarningsMaxHours * 3600)
		if elapsed > 60 then
			local rate = Game.OfflineEarningsRate + (MonetizationService.HasPass(player, "VIP") and 0.25 or 0)
			local amount = math.floor(TycoonService.IncomePerSecond(player) * elapsed * rate)
			if amount > 0 then
				TycoonService.AddCash(player, amount, true)
				Remotes.OpenUI:FireClient(player, "Offline", amount, elapsed)
			end
		end
	end
	data.lastOnline = os.time()
	TycoonService.Refresh(player)
end

local function onPlayerRemoving(player: Player)
	local st = states[player]
	if st then
		local index = st.plot:GetAttribute("Index")
		st.plot.Built:ClearAllChildren()
		st.plot.Pads:ClearAllChildren()
		st.plot.OwnerSign.SurfaceGui.Owner.Text = "VACANT HANGAR"
		plotOwners[index] = nil
	end
	states[player] = nil
	touchDebounce[player] = nil
	for _, other in ipairs(Players:GetPlayers()) do
		if states[other] then
			states[other].friends = countFriends(other)
		end
	end
end

function TycoonService.GetPlot(player: Player): Model?
	local st = states[player]
	return st and st.plot
end

function TycoonService.Init(deps)
	DataService = deps.DataService
	MonetizationService = deps.MonetizationService
	Remotes = deps.Remotes

	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = workspace
	for i = 1, Game.MaxPlots do
		plots[i] = WorldBuilder.Plot(i)
		local collector = plots[i].Collector
		collector.Touched:Connect(function(hit)
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			if player and plotOwners[i] == player then
				TycoonService.Collect(player)
			end
		end)
		plots[i].RebirthPad.Touched:Connect(function(hit)
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			if player and plotOwners[i] == player then
				local now = os.clock()
				if (touchDebounce[player] or 0) > now then
					return
				end
				touchDebounce[player] = now + 2
				Remotes.OpenUI:FireClient(player, "Rebirth")
			end
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, p)
	end

	-- income loop
	task.spawn(function()
		while true do
			task.wait(Game.IncomeTickSeconds)
			for player, st in pairs(states) do
				local data = st.ready and DataService.Get(player)
				if data then
					local inc = TycoonService.IncomePerSecond(player) * Game.IncomeTickSeconds
					data.totalEarned += inc
					data.playSeconds += Game.IncomeTickSeconds
					if MonetizationService.HasPass(player, "AutoCollect") then
						data.cash += inc
					else
						local cap = inc * 60 * Game.VaultCapMinutes / Game.IncomeTickSeconds
						data.vault = math.min(data.vault + inc, math.max(cap, data.vault))
					end
					TycoonService.Refresh(player)
				end
			end
		end
	end)
end

return TycoonService
