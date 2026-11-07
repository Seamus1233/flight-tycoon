-- Global tuning knobs. Economy numbers live in Items.lua (generated).
local Game = {}

Game.MaxPlots = 8
Game.PlotSize = Vector3.new(440, 1, 560)
Game.PlotSpacing = 480

Game.IncomeTickSeconds = 1
Game.VaultCapMinutes = 10            -- uncollected cash caps at this many minutes of income
Game.AutosaveSeconds = 90
Game.OfflineEarningsRate = 0.25      -- fraction of income earned while offline
Game.OfflineEarningsMaxHours = 8

Game.FriendBonusEach = 0.05          -- +5% per friend in the server
Game.FriendBonusMax = 0.20
Game.PremiumBonus = 0.10             -- Roblox Premium members

Game.DailyRewardMinutes = { 5, 10, 15, 20, 30, 45, 60 } -- minutes of income, by streak day

Game.DisplayLength = 20              -- studs, aircraft on display in a bay
Game.FlightStudsPerMetre = 1.25      -- flyable aircraft scale
Game.FlightMaxStuds = 70             -- cap huge bombers
Game.FlightSpeedScale = 0.11         -- km/h -> studs/s
Game.FlightMinSpeed = 60
Game.FlightMaxSpeed = 420

Game.StartingCash = 0
Game.DataStoreName = "SkyForgeTycoon_v1"
Game.LeaderboardStoreName = "SkyForgeTycoon_Earned_v1"

return Game
