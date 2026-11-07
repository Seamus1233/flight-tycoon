--[[
	MonetizationService - game passes and developer products.

	ProcessReceipt is idempotent: every PurchaseId is recorded in the player's
	profile and the profile is saved BEFORE PurchaseGranted is returned, so a
	purchase is never lost or granted twice.
]]
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Monetization = require(game.ReplicatedStorage.Shared.Config.Monetization)

local MonetizationService = {}
local DataService, TycoonService -- injected in Init

local passCache: { [Player]: { [string]: boolean } } = {}
local MAX_RECEIPTS = 200

function MonetizationService.HasPass(player: Player, key: string): boolean
	local c = passCache[player]
	return c ~= nil and c[key] == true
end

local function refreshPass(player: Player, key: string)
	local p = Monetization.Passes[key]
	if p.id == 0 then
		return
	end
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, p.id)
	if ok and owns then
		passCache[player] = passCache[player] or {}
		passCache[player][key] = true
	end
end

function MonetizationService.LoadPasses(player: Player)
	passCache[player] = passCache[player] or {}
	local threads = {}
	for key in pairs(Monetization.Passes) do
		table.insert(threads, task.spawn(refreshPass, player, key))
	end
	-- wait (bounded) for the checks to finish
	local t0 = os.clock()
	while os.clock() - t0 < 6 do
		local running = false
		for _, th in ipairs(threads) do
			if coroutine.status(th) ~= "dead" then
				running = true
				break
			end
		end
		if not running then
			break
		end
		task.wait(0.1)
	end
	MonetizationService.ApplyPassPerks(player)
end

function MonetizationService.ApplyPassPerks(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local owned = {}
	for key in pairs(passCache[player] or {}) do
		table.insert(owned, key)
	end
	player:SetAttribute("Passes", table.concat(owned, ","))
	-- one-time Starter Pack cash
	if MonetizationService.HasPass(player, "StarterPack") and not data.claimedOnce.StarterPack then
		data.claimedOnce.StarterPack = true
		data.cash += Monetization.Passes.StarterPack.oneTimeCash
		TycoonService.Notify(player, "Starter Pack claimed! +$2,500", "gold")
	end
	TycoonService.OnPassesChanged(player)
end

function MonetizationService.PassMultiplier(player: Player): number
	local m = 1
	for key, p in pairs(Monetization.Passes) do
		if p.incomeMult and MonetizationService.HasPass(player, key) then
			m *= p.incomeMult
		end
	end
	return m
end

function MonetizationService.PromptPass(player: Player, key: string)
	local p = Monetization.Passes[key]
	if not p then
		return
	end
	if p.id == 0 then
		TycoonService.Notify(player, p.name .. " isn't on sale yet (game pass ID not configured).", "error")
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, p.id)
end

function MonetizationService.PromptProduct(player: Player, key: string)
	local p = Monetization.Products[key]
	if not p then
		return
	end
	if p.id == 0 then
		TycoonService.Notify(player, p.name .. " isn't on sale yet (product ID not configured).", "error")
		return
	end
	MarketplaceService:PromptProductPurchase(player, p.id)
end

-- Product handlers: return true if granted.
local handlers = {}
local function cashPack(player, product)
	local income = TycoonService.IncomePerSecond(player)
	local amount = math.max(product.minCash, income * 60 * product.incomeMinutes)
	TycoonService.AddCash(player, amount, false)
	TycoonService.Notify(player, string.format("%s delivered! +%s", product.name,
		require(game.ReplicatedStorage.Shared.Util.Format).Money(amount)), "gold")
	return true
end
handlers.CashSmall = cashPack
handlers.CashMedium = cashPack
handlers.CashLarge = cashPack
handlers.CashHuge = cashPack
handlers.Boost2x30 = function(player, product)
	local data = DataService.Get(player)
	data.boostUntil = math.max(data.boostUntil, os.time()) + product.boostSeconds
	TycoonService.Refresh(player)
	TycoonService.Notify(player, "2x income boost active!", "gold")
	return true
end
handlers.SkipNext = function(player)
	return TycoonService.GrantNextItem(player)
end
handlers.RebirthToken = function(player)
	local data = DataService.Get(player)
	data.bonusRebirths += 1
	TycoonService.Refresh(player)
	TycoonService.Notify(player, "Rebirth Token used! Permanent multiplier increased.", "gold")
	return true
end

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = DataService.Get(player)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if data.receipts[receipt.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local key = Monetization.ProductKeyById[receipt.ProductId]
	local product = key and Monetization.Products[key]
	if not product then
		warn("[Monetization] Unknown product", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(handlers[key], player, product)
	if not ok or not granted then
		warn("[Monetization] grant failed", key, granted)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	data.receipts[receipt.PurchaseId] = os.time()
	table.insert(data.receiptOrder, receipt.PurchaseId)
	while #data.receiptOrder > MAX_RECEIPTS do
		data.receipts[table.remove(data.receiptOrder, 1)] = nil
	end
	if not DataService.Save(player, false) then
		-- Keep the receipt in memory: a retry won't double-grant, and the leave-save persists it.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService.Init(deps)
	DataService = deps.DataService
	TycoonService = deps.TycoonService

	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local key = Monetization.PassById[passId]
		if key then
			passCache[player] = passCache[player] or {}
			passCache[player][key] = true
			TycoonService.Notify(player, "Thank you! " .. Monetization.Passes[key].name .. " unlocked.", "gold")
			MonetizationService.ApplyPassPerks(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		passCache[player] = nil
	end)
end

return MonetizationService
