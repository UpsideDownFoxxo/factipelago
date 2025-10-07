local m = {}
local ap_teams = require("lib/parse_spoilers").get_teams()

---@param player LuaPlayer
m.get_player_slot = function(player)
	for slot, player_index in pairs(storage.team_player_slots[player.force.name].players) do
		if player_index == player.index then
			return player.force.name, slot
		end
	end
end

---@param slot number
---@param force string
---@return LuaPlayer?
m.get_slot_player = function(slot, force)
	local players = (storage.team_player_slots[force] or {}).players
	return players and players[slot] and (players[slot] > 0) and game.get_player(players[slot]) or nil
end

m.count_team_players = function(team_name)
	local taken = 0
	for _, value in pairs(storage.team_player_slots[team_name].players) do
		if value ~= -1 then
			taken = taken + 1
		end
	end

	return taken
end

---@return string
m.get_least_populated_team = function()
	local min_players = 1000000 -- a big number. if this causes problems, congrats. you have impressed me
	local lpf = nil

	for team_name, _ in pairs(ap_teams) do
		if storage.victorious_forces[team_name] then
			goto continue
		end
		local taken = m.count_team_players(team_name)
		if taken < min_players then
			min_players = taken
			lpf = team_name
		end
		::continue::
	end

	assert(lpf, "No viable force found")

	return lpf
end

m.get_random_team = function()
	local i = 1
	local teams = {}
	for team_name, _ in pairs(ap_teams) do
		teams[i] = team_name
		i = i + 1
	end

	while true do
		local team_name = teams[math.random(i - 1)]
		if not storage.victorious_forces[team_name] then
			return team_name
		end
	end
end

m.get_random_player = function(team_name)
	local team_players = storage.team_player_slots[team_name].players

	local candidates = {}

	for slot, index in ipairs(team_players) do
		if index ~= -1 then
			table.insert(candidates, slot)
		end
	end

	if #candidates == 0 then
		return
	end

	local slot = candidates[math.random(#candidates)]
	return m.get_slot_player(slot, team_name)
end

return m
