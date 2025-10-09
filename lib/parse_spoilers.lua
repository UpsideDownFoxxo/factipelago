SECTION_CACHE = nil

---@module "lib/base64"
local b64 = require("lib/base64")
local lz4 = require("lib/lz4")

local m = {}

local function split(input)
	local t = {}

	for str in string.gmatch(input, "([^\n]*)\n?") do
		table.insert(t, str)
	end

	return t
end

local data_table
local seed = require("seed")

m.get_setting_data = function()
	if not data_table then
		local compressed_spoiler = b64.decode(seed)
		local raw_spoiler = lz4.decompress(compressed_spoiler)
		local t = helpers.json_to_table(raw_spoiler)

		if not _G.data then
			-- we are not in data stage, kill the unnecessary fields to help memory consumption
			t.player_mods = nil
		end
		data_table = t
	end
	return data_table
end

local weird_headers = {
	["Factorio Recipes:"] = 1,
	["Locations:"] = 1,
	["Playthrough:"] = 1,
}

m.get_sections = function()
	if not SECTION_CACHE then
		local raw_spoiler = m.get_setting_data().spoilers
		local lines = split(raw_spoiler)

		local sections = {}

		local current_section = {}

		for _, line in ipairs(lines) do
			if line == "" then
				if (#current_section <= 2 and weird_headers[current_section[1]]) or #current_section == 0 then
					goto continue
				end
				table.insert(sections, current_section)
				current_section = {}
			else
				table.insert(current_section, line)
			end

			::continue::
		end

		SECTION_CACHE = sections
	end

	return SECTION_CACHE
end

m.get_teams = function()
	local team_sections = {}
	for _, section in ipairs(m.get_sections()) do
		if string.match(section[1], "Player %d*: .*") then
			section = table.deepcopy(section)
			local team = string.gsub(section[1], "Player %d*: ", "")

			table.remove(section, 1)

			local section_data = {}

			for _, line in ipairs(section) do
				local key, value = line:match("([^:]*):(.*)")
				value = value:gsub("^%s+", "")

				if value ~= "" then
					section_data[key] = value
				end
			end
			team_sections[team] = section_data
		end
	end

	return team_sections
end

local mappings
m.get_tech_mappings = function()
	if not mappings then
		local tech_section
		for _, section in ipairs(m.get_sections()) do
			if section[1] == "Locations:" then
				section = table.deepcopy(section)
				table.remove(section, 1)
				tech_section = section
				goto run
			end
		end

		error("Could not find location section")

		::run::
		local links = {}

		for _, line in ipairs(tech_section) do
			local location, from_team, unlock, to_team = line:match("^(%S+) %(([^%)]+)%): (.+) %(([^%)]+)%)")
			if not location then
				goto continue
			end
			local ident = from_team .. "-" .. location
			links[ident] = links[ident] or {}
			links[ident][to_team] = links[ident][to_team] or { traps = {}, techs = {} }

			if unlock:match(".*Trap") then
				table.insert(links[ident][to_team].traps, unlock)
			else
				table.insert(links[ident][to_team].techs, unlock)
			end

			::continue::
		end

		mappings = links
		return links
	end

	return mappings
end

m.ap_to_factorio = function(id)
	local first, second = id:match("AP%-(%d)%-(%d%d%d)")
	if not first then
		error("Unable to convert " .. id)
	end

	local offset = tonumber(first .. second) - 1000

	offset = offset - tonumber(first)

	return "ap-" .. (131072 + offset)
end

m.factorio_to_ap = function(id)
	local num = id:match("ap%-(%d%d%d%d%d%d)")
	if not num then
		error("Unable to convert " .. id)
	end

	local offset = tonumber(num) - 131072 + 1000

	for i = 1, 8, 1 do
		if offset >= (i * 1000) then
			offset = offset + 1
		end
	end

	assert(offset <= 7999 and offset >= 1001)

	local first = math.floor(offset / 1000)
	local second = offset % 1000

	return string.format("AP-%d-%03d", first, second)
end

return m
