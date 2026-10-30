--!strict
-- Format: number display for the HUD (999, 1.2K, 3.4M, ...).

local SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local Format = {}

function Format.number(n: number): string
	if n ~= n then
		return "0" -- NaN guard
	end
	local sign = if n < 0 then "-" else ""
	n = math.abs(n)
	if n < 1000 then
		return sign .. tostring(math.floor(n))
	end
	local tier = 0
	while n >= 1000 and tier < #SUFFIXES do
		n /= 1000
		tier += 1
	end
	-- One decimal under 100 (1.2K, 45.6M), none above (123K).
	local text = if n < 100 then string.format("%.1f", math.floor(n * 10) / 10) else tostring(math.floor(n))
	text = string.gsub(text, "%.0$", "")
	return sign .. text .. SUFFIXES[tier]
end

return Format
