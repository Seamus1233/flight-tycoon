--[[
	Monetization catalogue.

	SETUP: create each Game Pass / Developer Product on the Creator Dashboard
	(Creations -> your experience -> Monetization) and paste its numeric ID
	below. Anything left at 0 is hidden from the store and never prompted.

	Suggested Robux prices are only shown here for reference; the store UI
	reads the real price from Roblox.
]]
local Monetization = {}

-- Game passes: permanent perks
Monetization.Passes = {
	DoubleCash = {
		id = 0, suggested = 399, order = 1,
		name = "2x Cash",
		desc = "Double ALL income, forever. Stacks with everything.",
		incomeMult = 2,
	},
	VIP = {
		id = 0, suggested = 699, order = 2,
		name = "VIP Commander",
		desc = "+50% income, gold name tag, VIP lounge and +25% offline earnings.",
		incomeMult = 1.5,
	},
	AutoCollect = {
		id = 0, suggested = 249, order = 3,
		name = "Auto Collect",
		desc = "Income goes straight to your wallet. No vault cap, no walking.",
	},
	Overdrive = {
		id = 0, suggested = 299, order = 4,
		name = "Overdrive Assembly",
		desc = "Production lines run 25% faster (+25% income).",
		incomeMult = 1.25,
	},
	Afterburner = {
		id = 0, suggested = 149, order = 5,
		name = "Afterburner",
		desc = "+50% flight speed and double walk speed.",
	},
	StarterPack = {
		id = 0, suggested = 99, order = 6,
		name = "Starter Pack",
		desc = "+$2,500 instantly and +20% income forever. Best value!",
		incomeMult = 1.2,
		oneTimeCash = 2500,
	},
	BlackProjectB21 = {
		id = 0, suggested = 499, order = 7,
		name = "Black Project: B-21 Raider",
		desc = "Classified bomber line. Earns 3x your best aircraft. Flyable.",
		aircraft = "b21",
	},
	BlackProjectF47 = {
		id = 0, suggested = 799, order = 8,
		name = "Black Project: F-47 NGAD",
		desc = "6th-gen fighter line. Earns 5x your best aircraft. Flyable.",
		aircraft = "f47",
	},
	BlackProjectSR72 = {
		id = 0, suggested = 1199, order = 9,
		name = "Black Project: SR-72",
		desc = "Mach 6 hypersonic line. Earns 8x your best aircraft. Fastest plane in the game.",
		aircraft = "sr72",
	},
}

-- Income of a premium aircraft = multiplier x the best free aircraft the player owns.
Monetization.PremiumAircraftMult = { b21 = 3, f47 = 5, sr72 = 8 }
Monetization.PremiumAircraftMinIncome = 25

-- Developer products: consumables, can be bought repeatedly
Monetization.Products = {
	CashSmall = { id = 0, suggested = 49, order = 1, name = "Cash Crate",
		desc = "15 minutes of income instantly.", incomeMinutes = 15, minCash = 500 },
	CashMedium = { id = 0, suggested = 149, order = 2, name = "Cash Pallet",
		desc = "1 hour of income instantly.", incomeMinutes = 60, minCash = 2500 },
	CashLarge = { id = 0, suggested = 399, order = 3, name = "Cash Cargo Plane",
		desc = "4 hours of income instantly.", incomeMinutes = 240, minCash = 12000 },
	CashHuge = { id = 0, suggested = 999, order = 4, name = "Federal Reserve",
		desc = "12 hours of income instantly.", incomeMinutes = 720, minCash = 50000 },
	Boost2x30 = { id = 0, suggested = 99, order = 5, name = "2x Boost (30 min)",
		desc = "Double income for 30 minutes. Stacks duration.", boostSeconds = 1800 },
	SkipNext = { id = 0, suggested = 75, order = 6, name = "Skip Next Purchase",
		desc = "Instantly unlock the next item in your tycoon for free." },
	RebirthToken = { id = 0, suggested = 499, order = 7, name = "Rebirth Token",
		desc = "+1 rebirth multiplier WITHOUT resetting your tycoon." },
}

Monetization.PassById = {}
for key, p in pairs(Monetization.Passes) do
	p.key = key
end
Monetization.ProductKeyById = {}
for key, p in pairs(Monetization.Products) do
	p.key = key
end

function Monetization.Rebuild()
	table.clear(Monetization.PassById)
	table.clear(Monetization.ProductKeyById)
	for key, p in pairs(Monetization.Passes) do
		if p.id ~= 0 then
			Monetization.PassById[p.id] = key
		end
	end
	for key, p in pairs(Monetization.Products) do
		if p.id ~= 0 then
			Monetization.ProductKeyById[p.id] = key
		end
	end
end
Monetization.Rebuild()

return Monetization
