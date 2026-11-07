--[[
	UI controller - HUD, store, hangar, rebirth, daily reward and popups.
	Everything is created in code; reads state from Player attributes that the
	server keeps up to date.
]]
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Aircraft = require(Shared.Config.Aircraft)
local Items = require(Shared.Config.Items)
local Monetization = require(Shared.Config.Monetization)
local Format = require(Shared.Util.Format)

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local UI = {}

local C = {
	bg = Color3.fromRGB(22, 26, 34),
	panel = Color3.fromRGB(32, 38, 50),
	card = Color3.fromRGB(44, 52, 68),
	text = Color3.fromRGB(240, 244, 250),
	sub = Color3.fromRGB(160, 172, 190),
	green = Color3.fromRGB(70, 210, 100),
	gold = Color3.fromRGB(255, 196, 50),
	red = Color3.fromRGB(235, 80, 80),
	blue = Color3.fromRGB(70, 150, 255),
	purple = Color3.fromRGB(170, 90, 255),
}

-- ---------------------------------------------------------------- tiny builder
local function new(class, props, children)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then
			o[k] = v
		end
	end
	for _, c in ipairs(children or {}) do
		c.Parent = o
	end
	o.Parent = props and props.Parent
	return o
end
local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r or 10) }) end
local function stroke(c, t) return new("UIStroke", { Color = c or Color3.new(0, 0, 0), Thickness = t or 2, Transparency = 0.2 }) end
local function text(props)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or C.text
	props.TextScaled = props.TextScaled ~= false
	local maxText = props.MaxText or 28
	props.MaxText = nil
	return new("TextLabel", props, { new("UITextSizeConstraint", { MaxTextSize = maxText }) })
end
local function button(props, onClick)
	local b = new("TextButton", {
		Name = props.Name, Size = props.Size, Position = props.Position, AnchorPoint = props.AnchorPoint,
		BackgroundColor3 = props.Color or C.blue, Text = props.Text or "", Font = Enum.Font.GothamBlack,
		TextColor3 = C.text, TextScaled = true, AutoButtonColor = true, LayoutOrder = props.LayoutOrder,
		Parent = props.Parent,
	}, { corner(10), stroke(Color3.new(0, 0, 0), 2), new("UITextSizeConstraint", { MaxTextSize = props.MaxText or 22 }),
		new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }) })
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

local gui, windows = nil, {}

local function closeAll()
	for _, w in pairs(windows) do
		w.Visible = false
	end
end

local function window(name, title, size)
	local f = new("Frame", {
		Name = name, Size = size or UDim2.fromScale(0.62, 0.7), Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = C.bg, Visible = false, Parent = gui,
	}, { corner(16), stroke(C.blue, 3), new("UISizeConstraint", { MaxSize = Vector2.new(900, 620), MinSize = Vector2.new(300, 260) }) })
	text({ Name = "Title", Text = title, Size = UDim2.new(1, -70, 0, 44), Position = UDim2.fromOffset(16, 8),
		TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBlack, MaxText = 32, Parent = f })
	button({ Text = "X", Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -50, 0, 10), Color = C.red, Parent = f },
		function() f.Visible = false end)
	local body = new("Frame", { Name = "Body", BackgroundTransparency = 1, Size = UDim2.new(1, -24, 1, -64),
		Position = UDim2.fromOffset(12, 56), Parent = f })
	windows[name] = f
	return f, body
end

local function open(name)
	local w = windows[name]
	if not w then return end
	local wasOpen = w.Visible
	closeAll()
	w.Visible = not wasOpen
	if w.Visible then
		w.Size = w.Size -- keep
		local s = new("UIScale", { Scale = 0.85, Parent = w })
		TweenService:Create(s, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		task.delay(0.2, function() s:Destroy() end)
	end
end
UI.Open = open

-- ---------------------------------------------------------------- notifications
local toastHolder
function UI.Toast(msg: string, style: string?)
	local color = ({ error = C.red, gold = C.gold, success = C.green })[style or ""] or C.blue
	local t = new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = C.bg, BackgroundTransparency = 0.1, Parent = toastHolder },
		{ corner(10), stroke(color, 2) })
	text({ Text = msg, Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), TextColor3 = color, MaxText = 20, Parent = t })
	task.delay(3.5, function()
		TweenService:Create(t, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		task.wait(0.3)
		t:Destroy()
	end)
end

-- ---------------------------------------------------------------- HUD
local hud = {}
local function buildHud()
	local top = new("Frame", { Name = "TopBar", Size = UDim2.fromOffset(340, 92), Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = C.bg, BackgroundTransparency = 0.15, Parent = gui },
		{ corner(14), stroke(C.green, 2) })
	hud.cash = text({ Text = "$0", Size = UDim2.new(1, -20, 0, 44), Position = UDim2.fromOffset(10, 4),
		Font = Enum.Font.GothamBlack, TextColor3 = C.green, MaxText = 40, Parent = top })
	hud.income = text({ Text = "+$0/s", Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 46),
		TextColor3 = C.text, MaxText = 20, Parent = top })
	hud.vault = text({ Text = "", Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 68),
		TextColor3 = C.sub, MaxText = 16, Parent = top })
	hud.boost = text({ Text = "", Size = UDim2.fromOffset(340, 24), Position = UDim2.new(0.5, 0, 0, 104),
		AnchorPoint = Vector2.new(0.5, 0), TextColor3 = C.gold, Font = Enum.Font.GothamBlack, Visible = false, Parent = gui })

	local side = new("Frame", { Name = "Side", Size = UDim2.fromOffset(120, 300), Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1, Parent = gui },
		{ new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
	button({ Text = "STORE", Size = UDim2.fromOffset(120, 54), Color = C.gold, LayoutOrder = 1, Parent = side }, function() open("Store") end)
	button({ Text = "HANGAR", Size = UDim2.fromOffset(120, 54), Color = C.blue, LayoutOrder = 2, Parent = side }, function() open("Hangar") end)
	hud.daily = button({ Text = "DAILY", Size = UDim2.fromOffset(120, 54), Color = C.green, LayoutOrder = 3, Parent = side },
		function() Remotes.Action:FireServer("ClaimDaily") end)
	button({ Text = "REBIRTH", Size = UDim2.fromOffset(120, 54), Color = C.purple, LayoutOrder = 4, Parent = side }, function() open("Rebirth") end)

	toastHolder = new("Frame", { Name = "Toasts", Size = UDim2.fromOffset(420, 220), Position = UDim2.new(0.5, 0, 1, -120),
		AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1, Parent = gui },
		{ new("UIListLayout", { Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Bottom }) })
end

local function updateHud()
	local cash = player:GetAttribute("Cash") or 0
	local income = player:GetAttribute("Income") or 0
	local mult = player:GetAttribute("Multiplier") or 1
	hud.cash.Text = Format.Money(cash)
	hud.income.Text = string.format("+%s/s   x%.2f", Format.Money(income), mult)
	local passes = player:GetAttribute("Passes") or ""
	if string.find(passes, "AutoCollect") then
		hud.vault.Text = "Auto Collect ON"
	else
		local v, cap = player:GetAttribute("Vault") or 0, player:GetAttribute("VaultCap") or 0
		hud.vault.Text = string.format("Vault %s / %s%s", Format.Money(v), Format.Money(cap), v >= cap and cap > 0 and "  FULL!" or "")
		hud.vault.TextColor3 = (v >= cap and cap > 0) and C.red or C.sub
	end
	local boost = (player:GetAttribute("BoostUntil") or 0) - os.time()
	hud.boost.Visible = boost > 0
	hud.boost.Text = "2x BOOST " .. Format.Time(boost)
	local ready = (player:GetAttribute("DailyReadyAt") or 0) - os.time()
	hud.daily.Text = ready <= 0 and "DAILY!" or Format.Time(ready)
	hud.daily.BackgroundColor3 = ready <= 0 and C.green or C.card
end

-- ---------------------------------------------------------------- store
local priceCache = {}
local function fetchPrice(id, infoType, label)
	if id == 0 then
		label.Text = "SOON"
		return
	end
	if priceCache[id] then
		label.Text = "R$ " .. priceCache[id]
		return
	end
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, infoType)
		if ok and info and info.PriceInRobux then
			priceCache[id] = info.PriceInRobux
			label.Text = "R$ " .. info.PriceInRobux
		end
	end)
end

local storeCards = {}
local function buildStore()
	local _, body = window("Store", "AIRBASE STORE")
	local tabs = new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, Parent = body },
		{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }) })
	local pages = {}
	local function page(name)
		local p = new("ScrollingFrame", { Name = name, Size = UDim2.new(1, 0, 1, -48), Position = UDim2.fromOffset(0, 48),
			BackgroundTransparency = 1, ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(), Visible = false, Parent = body },
			{ new("UIGridLayout", { CellSize = UDim2.new(0.32, 0, 0, 170), CellPadding = UDim2.new(0.015, 0, 0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder }) })
		pages[name] = p
		return p
	end
	local passPage, cashPage = page("Passes"), page("Cash")
	passPage.Visible = true
	for _, name in ipairs({ "Passes", "Cash" }) do
		button({ Text = name == "Passes" and "GAME PASSES" or "CASH & BOOSTS", Size = UDim2.fromOffset(190, 38),
			Color = C.card, Parent = tabs }, function()
			for n, p in pairs(pages) do p.Visible = n == name end
		end)
	end

	local function card(parent, def, isPass)
		local c = new("Frame", { BackgroundColor3 = C.card, LayoutOrder = def.order, Parent = parent },
			{ corner(12), stroke(def.aircraft and C.gold or C.blue, 2) })
		text({ Text = def.name, Size = UDim2.new(1, -12, 0, 28), Position = UDim2.fromOffset(6, 6),
			Font = Enum.Font.GothamBlack, TextColor3 = def.aircraft and C.gold or C.text, MaxText = 20, Parent = c })
		text({ Text = def.desc, Size = UDim2.new(1, -12, 0, 72), Position = UDim2.fromOffset(6, 36), TextWrapped = true,
			Font = Enum.Font.Gotham, TextColor3 = C.sub, MaxText = 15, TextYAlignment = Enum.TextYAlignment.Top, Parent = c })
		local b = button({ Text = "...", Size = UDim2.new(1, -16, 0, 42), Position = UDim2.new(0, 8, 1, -50), Color = C.green, Parent = c },
			function()
				Remotes.Action:FireServer(isPass and "BuyPass" or "BuyProduct", def.key)
			end)
		fetchPrice(def.id, isPass and Enum.InfoType.GamePass or Enum.InfoType.Product, b)
		if isPass then storeCards[def.key] = b end
	end
	for _, def in pairs(Monetization.Passes) do card(passPage, def, true) end
	for _, def in pairs(Monetization.Products) do card(cashPage, def, false) end
end

local function updateStoreOwned()
	local passes = player:GetAttribute("Passes") or ""
	for key, b in pairs(storeCards) do
		if string.find("," .. passes .. ",", "," .. key .. ",", 1, true) then
			b.Text = "OWNED"
			b.BackgroundColor3 = C.card
			b.Active = false
		end
	end
end

-- ---------------------------------------------------------------- hangar
local hangarRows = {}
local function buildHangar()
	local _, body = window("Hangar", "HANGAR - FLY YOUR AIRCRAFT")
	local list = new("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = body },
		{ new("UIGridLayout", { CellSize = UDim2.new(0.24, 0, 0, 96), CellPadding = UDim2.new(0.01, 0, 0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder }) })
	for i, a in ipairs(Aircraft.List) do
		local era = Aircraft.Eras[a.era]
		local c = new("Frame", { BackgroundColor3 = C.card, LayoutOrder = a.premium and i - 100 or i, Parent = list },
			{ corner(10), stroke(a.premium and C.gold or Color3.new(era.color[1], era.color[2], era.color[3]), 2) })
		text({ Text = a.name, Size = UDim2.new(1, -10, 0, 22), Position = UDim2.fromOffset(5, 4), MaxText = 16,
			TextColor3 = a.premium and C.gold or C.text, Parent = c })
		local item = Items.ById[a.id]
		text({ Text = a.premium and "BLACK PROJECT" or string.format("%s  |  %d km/h", era.name, a.speed),
			Size = UDim2.new(1, -10, 0, 16), Position = UDim2.fromOffset(5, 26), MaxText = 12, Font = Enum.Font.Gotham,
			TextColor3 = C.sub, Parent = c })
		local b = button({ Text = "", Size = UDim2.new(1, -12, 0, 38), Position = UDim2.new(0, 6, 1, -44), Color = C.card, Parent = c },
			function()
				local owned = string.find("," .. (player:GetAttribute("OwnedAircraft") or "") .. ",", "," .. a.id .. ",", 1, true)
				if owned then
					closeAll()
					Remotes.Action:FireServer("Fly", a.id)
				elseif a.premium then
					for key, p in pairs(Monetization.Passes) do
						if p.aircraft == a.id then Remotes.Action:FireServer("BuyPass", key) end
					end
				end
			end)
		hangarRows[a.id] = { button = b, item = item, spec = a }
	end
end

local function updateHangar()
	local owned = "," .. (player:GetAttribute("OwnedAircraft") or "") .. ","
	for id, row in pairs(hangarRows) do
		if string.find(owned, "," .. id .. ",", 1, true) then
			row.button.Text = "FLY"
			row.button.BackgroundColor3 = C.green
		elseif row.spec.premium then
			row.button.Text = "UNLOCK (R$)"
			row.button.BackgroundColor3 = C.gold
		else
			row.button.Text = "LOCKED " .. Format.Money(row.item.cost)
			row.button.BackgroundColor3 = C.panel
		end
	end
end

-- ---------------------------------------------------------------- rebirth / popups
local rebirthInfo, rebirthBtn
local function buildRebirth()
	local _, body = window("Rebirth", "REBIRTH", UDim2.fromScale(0.4, 0.45))
	rebirthInfo = text({ Text = "", Size = UDim2.new(1, 0, 0.55, 0), TextWrapped = true, Font = Enum.Font.Gotham,
		MaxText = 22, Parent = body })
	rebirthBtn = button({ Text = "REBIRTH", Size = UDim2.new(0.6, 0, 0, 50), Position = UDim2.new(0.2, 0, 0.6, 0),
		Color = C.purple, Parent = body }, function()
		if player:GetAttribute("CanRebirth") then
			Remotes.Action:FireServer("Rebirth")
			closeAll()
		end
	end)
	button({ Text = "Rebirth Token: +1 without reset (R$)", Size = UDim2.new(0.9, 0, 0, 40), Position = UDim2.new(0.05, 0, 0.83, 0),
		Color = C.gold, MaxText = 16, Parent = body }, function()
		Remotes.Action:FireServer("BuyProduct", "RebirthToken")
	end)
end

local function updateRebirth()
	local r = player:GetAttribute("Rebirths") or 0
	local can = player:GetAttribute("CanRebirth")
	local finalName = Items.ById[Items.FinalItemId].name
	rebirthInfo.Text = string.format(
		"Rebirths: %d\nPermanent income x%.1f  ->  x%.1f\n\n%s",
		r, 1 + Items.RebirthBonus * r, 1 + Items.RebirthBonus * (r + 1),
		can and "Resets your cash and airbase. Black Projects and passes are kept." or ("Unlock the " .. finalName .. " to rebirth."))
	rebirthBtn.BackgroundColor3 = can and C.purple or C.card
end

local function popup(title, body, actionText, action)
	local f = new("Frame", { Size = UDim2.fromOffset(380, 210), Position = UDim2.fromScale(0.5, 0.45), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.bg, Parent = gui }, { corner(16), stroke(C.gold, 3) })
	text({ Text = title, Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 10), Font = Enum.Font.GothamBlack,
		TextColor3 = C.gold, MaxText = 30, Parent = f })
	text({ Text = body, Size = UDim2.new(1, -20, 0, 70), Position = UDim2.fromOffset(10, 54), TextWrapped = true,
		Font = Enum.Font.Gotham, MaxText = 20, Parent = f })
	button({ Text = "OK", Size = UDim2.fromOffset(110, 44), Position = UDim2.new(0, 20, 1, -58), Color = C.card, Parent = f },
		function() f:Destroy() end)
	if actionText then
		button({ Text = actionText, Size = UDim2.fromOffset(210, 44), Position = UDim2.new(1, -230, 1, -58), Color = C.green,
			MaxText = 18, Parent = f }, function()
			f:Destroy()
			action()
		end)
	end
	task.delay(12, function() if f.Parent then f:Destroy() end end)
end

local lastNeedCash = 0
local function onOpenUI(kind, a, b)
	if kind == "Rebirth" then
		if not windows.Rebirth.Visible then open("Rebirth") end
	elseif kind == "Offline" then
		popup("WELCOME BACK!", string.format("Your airbase earned %s while you were away (%s).", Format.Money(a), Format.Time(b)),
			"2x income forever", function() Remotes.Action:FireServer("BuyPass", "DoubleCash") end)
	elseif kind == "NeedCash" then
		if os.clock() - lastNeedCash > 90 then
			lastNeedCash = os.clock()
			popup("NOT ENOUGH CASH", "You need " .. Format.Money(a) .. " more. Grab a cash pack and keep building!",
				"Open Cash Store", function()
					open("Store")
					windows.Store.Body.Passes.Visible = false
					windows.Store.Body.Cash.Visible = true
				end)
		end
	end
end

-- ---------------------------------------------------------------- init
function UI.Init()
	gui = new("ScreenGui", { Name = "SkyForgeUI", ResetOnSpawn = false, IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })
	buildHud()
	buildStore()
	buildHangar()
	buildRebirth()

	Remotes.Notify.OnClientEvent:Connect(UI.Toast)
	Remotes.OpenUI.OnClientEvent:Connect(onOpenUI)
	for _, attr in ipairs({ "Passes" }) do
		player:GetAttributeChangedSignal(attr):Connect(updateStoreOwned)
	end
	player:GetAttributeChangedSignal("OwnedAircraft"):Connect(updateHangar)
	updateStoreOwned()
	updateHangar()
	task.spawn(function()
		while true do
			updateHud()
			updateRebirth()
			task.wait(0.25)
		end
	end)
end

return UI
