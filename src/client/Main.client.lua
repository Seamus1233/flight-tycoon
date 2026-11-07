-- SkyForge Tycoon - client entry point
local Controllers = script.Parent:WaitForChild("Controllers")

require(Controllers.UI).Init()
require(Controllers.Flight).Init()
require(Controllers.Effects).Init()
