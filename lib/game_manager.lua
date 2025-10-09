local slot_manager = require("lib/slot_manager")
local samples = require("lib/samples")
local parse_spoilers = require("lib/parse_spoilers")
local m = {}

m.swap_random_players = function(team_a, team_b)
	while true do
		local player_a = slot_manager.get_random_player(team_a)
		local player_b = slot_manager.get_random_player(team_b)

		print(player_a)
		print(player_b)

		if not player_a or not player_b then
			-- one of the two teams does not actually have a player
			return false
		end

		if player_a.index ~= player_b.index then
			slot_manager.swap_players(player_a, player_b)
			return true
		end
	end
end

m.swap_random_teams = function()
	-- make sure swapping between teams even makes sense
	if #storage.active_teams <= 1 then
		local team = storage.active_teams[1]
		print("swapping within team " .. team)
		-- try to just swap two players
		if slot_manager.count_team_players(team) > 1 then
			m.swap_random_players(team, team)
		end
		return
	end

	local team_a = storage.active_teams[math.random(#storage.active_teams)]

	print(serpent.block(storage.active_teams))

	local team_b
	while true do
		team_b = storage.active_teams[math.random(#storage.active_teams)]
		print(team_b)
		if team_b ~= team_a then
			break
		end
	end

	print("swapping " .. team_a .. " and " .. team_b)
	m.swap_random_players(team_a, team_b)
end

m.balance_teams = function()
	local min_team_count = 10000
	local max_team_count = 0
	local min_teams = {}
	local max_teams = {}

	for _, team in pairs(storage.active_teams) do
		local count = slot_manager.count_team_players(team)

		if count == min_team_count then
			table.insert(min_teams, team)
		end

		if count == max_team_count then
			table.insert(max_teams, team)
		end

		if count < min_team_count then
			min_team_count = count
			min_teams = { team }
		end

		if count > max_team_count then
			max_team_count = count
			max_teams = { team }
		end
	end

	print("teams: " .. min_team_count .. " to " .. max_team_count)

	-- teams are balanced, nothing more to do
	if min_team_count == max_team_count then
		return
	end

	local max_team = max_teams[math.random(#max_teams)]
	local min_team = min_teams[math.random(#min_teams)]

	local max_player = slot_manager.get_random_player(max_team)
	assert(max_player)

	slot_manager.transfer_player(max_player, min_team)
end

---@param player LuaPlayer
m.add_player = function(player)
	local slot_preference = storage.slot_preferences[player.index]

	local character = player.character
	player.set_controller({ type = defines.controllers.ghost })
	if character then
		character.destroy()
	end

	local team
	local slot, new

	if slot_preference and storage.team_player_slots[slot_preference[1]].players[slot_preference[2]] == -1 then
		team = slot_preference[1]
		slot = slot_preference[2]
	else
		team = slot_manager.get_least_populated_team()
		slot, new = slot_manager.get_or_make_empty_slot(team, player)

		if new then
			samples.catch_up_slot(team, slot)
		end
	end

	slot_manager.associate_player(player, team, slot)
end

local tech_mappings = parse_spoilers.get_tech_mappings()

---@param team string
local function research_affecting(team)
	-- research all remaining tech (traps will be redirected)
	local technologies = game.forces[team].technologies
	for key, tech in pairs(technologies) do
		if key:match("^" .. team .. "%-ap%-") then
			tech.researched = true
		end
	end

	-- if a tech would unlock something useful for this team, instantly mark it as researched
	for ident, effects in pairs(tech_mappings) do
		if effects[team] and #effects[team].techs > 0 then
			local source_team = ident:match("^([^%-]*)")

			local tech_id = parse_spoilers.ap_to_factorio(ident)

			game.forces[source_team].technologies[source_team .. "-" .. tech_id .. "-"].researched = true
		end
	end
end

m.set_team_won = function(team)
	-- add/remove from relevant lists
	storage.victorious_forces[team] = true
	for i = #storage.active_teams, 1, -1 do
		local team_t = storage.active_teams[i]
		if team_t == team then
			table.remove(storage.active_teams, i)
			break
		end
	end

	if #storage.active_teams == 0 then
		-- we won, show victory screen
		game.set_game_state({ game_finished = true, player_won = true, can_continue = true })
	else
		-- other teams exist that have not won the game

		-- distribute players onto random teams
		for _, player_index in pairs(storage.team_player_slots[team].players) do
			if player_index == -1 then
				goto continue
			end
			local player = game.get_player(player_index)
			if not player or not player.connected then
				-- player is fucked or just not connected. skip until they rejoin
				goto continue
			end

			local new_team = slot_manager.get_least_populated_team()
			slot_manager.transfer_player(player, new_team)

			player.print({ "player-messages.won-team-transfer", new_team })
			::continue::
		end
	end

	research_affecting(team)
end

local ap_teams = parse_spoilers.get_teams()

---@param initial_dead_player_name LocalisedString
---@param from_team string
---@param initial_dead_player LuaPlayer
m.trigger_death_link = function(initial_dead_player_name, from_team, initial_dead_player)
	-- create empty player-like object we can call print on
	initial_dead_player = initial_dead_player or { print = function(...) end }

	storage.death_link_active = true
	local deaths = 0
	for team, team_settings in pairs(ap_teams) do
		if team_settings["Death Link"] == "No" then
			goto continue
		end

		-- team wants to die
		local players = storage.team_player_slots[team].players
		local characters = storage.team_player_slots[team].characters
		for slot, character in pairs(characters) do
			if character.valid then
				local should_die = math.random() < (settings.global["death-percent"].value / 100)
				local player_index = players[slot]
				if player_index ~= -1 then
					local player = game.get_player(player_index)
					assert(player)

					if should_die then
						print("killing " .. player.name)
						player.print({ "player-messages.death-link", initial_dead_player_name, from_team })
					else
						print("sparing " .. player.name)
						player.print({ "player-messages.death-link-failed", initial_dead_player_name, from_team })
					end
				end

				if should_die then
					print("killing character " .. team .. ":" .. slot)
					character.die()
					deaths = deaths + 1
					characters[slot] = nil
				end
			end
		end

		::continue::
	end
	storage.death_link_active = nil

	local all_players = #game.connected_players - 1

	if deaths == all_players then
		initial_dead_player.print({ "player-messages.death-link-report-wipeout", deaths })
	else
		initial_dead_player.print({ "player-messages.death-link-report", deaths })
	end
end

m.swap_handler = function()
	m.swap_random_teams()
	m.balance_teams()
end

---@param ticks int
m.set_swap_interval = function(ticks)
	-- remove old handler
	script.on_nth_tick(nil)

	if ticks == 0 then
		storage.swap_interval = nil
	else
		script.on_nth_tick(ticks, m.swap_handler)
		storage.swap_interval = ticks
	end
end
return m
