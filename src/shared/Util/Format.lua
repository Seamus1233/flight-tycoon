local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function Format.Money(n: number): string
	n = math.floor(n or 0)
	local neg = n < 0
	n = math.abs(n)
	local s
	if n < 1000 then
		s = tostring(n)
	else
		local i = 1
		local v = n
		while v >= 1000 and i < #SUFFIXES do
			v /= 1000
			i += 1
		end
		if v >= 100 then
			s = string.format("%d%s", math.floor(v), SUFFIXES[i])
		elseif v >= 10 then
			s = string.format("%.1f%s", math.floor(v * 10) / 10, SUFFIXES[i])
		else
			s = string.format("%.2f%s", math.floor(v * 100) / 100, SUFFIXES[i])
		end
	end
	return (neg and "-$" or "$") .. s
end

function Format.Time(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	end
	return string.format("%d:%02d", m, s)
end

return Format
