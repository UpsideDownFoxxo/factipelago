require("util")
local progressive_techs = require("lib/progressive_techs")
local parse_spoilers = require("lib/parse_spoilers")
local traps = require("lib/traps")
local slot_manager = require("lib/slot_manager")
local samples = require("lib/samples")
local game_manager = require("lib/game_manager")

local crash_site_gen = require("__core__/lualib/crash-site")

local effects = parse_spoilers.get_tech_mappings()
local ap_teams = parse_spoilers.get_teams()

require("lib/commands")

local function execute_trap(trap_name, target_team, triggered_by)
	local trap = traps[trap_name]
	if not trap then
		game.print("Unknown trap " .. trap_name)
		return
	end

	trap(target_team, triggered_by)
end

local function merge_tables(source, target)
	for key, value in pairs(source) do
		if type(value) ~= "table" then
			target[key] = value
		else
			if target[key] == nil or type(target[key]) ~= "table" then
				target[key] = {}
			end

			merge_tables(source[key], target[key])
		end
	end
end

---@param copy_from SurfaceIdentification
---@param new_settings unknown
local function apply_map_gen_settings(copy_from, new_settings)
	---@type LuaSurface
	local preset_surface = game.surfaces[copy_from]
	local preset = table.deepcopy(preset_surface.map_gen_settings)

	merge_tables(new_settings, preset)
	return preset
end

---@param tech_name string
---@param force LuaForce
---@param team_name string
---@return string
local function research_team_technology(tech_name, force)
	if tech_name:match("^progressive%-") then
		return progressive_techs.research_progressive_tech(tech_name, force)
	else
		-- try and see if a personalized version exists. if yes we have to prefer it over the normal one
		local tech = force.technologies[force.name .. "-" .. tech_name] or force.technologies[tech_name]
		tech.researched = true
		return tech.name
	end
end

---@param event EventData.on_research_finished
script.on_event(defines.events.on_research_finished, function(event)
	local name = event.research.name
	-- not an AP tech, check for samples
	if not name:match("^.*%-ap%-") then
		samples.grant_tech_research_rewards(event.research)
		for slot, _ in pairs(storage.team_player_slots[event.research.force.name].players) do
			samples.try_insert_pending_samples(event.research.force.name, slot)
		end
		return
	end

	name = event.research.force.name .. "-" .. parse_spoilers.factorio_to_ap(name)
	local unlock_effects = effects[name] or {}

	for team_name, team_effects in pairs(unlock_effects) do
		local force = game.forces[team_name]

		local team_techs = team_effects.techs
		local team_traps = team_effects.traps

		for _, tech_name in pairs(team_techs) do
			tech_name = research_team_technology(tech_name, force)

			if event.research.force.index ~= force.index then
				for _, player in ipairs(event.research.force.connected_players) do
					player.print({ "player-messages.sent-tech-notification", team_name, tech_name })
				end
			end

			for _, player in ipairs(force.connected_players) do
				player.print({ "player-messages.received-tech-notification", event.research.force.name, tech_name })
			end
		end

		for _, trap_name in ipairs(team_traps) do
			if storage.victorious_forces[team_name] then
				if #storage.active_teams == 0 then
					-- we just won the game
					-- redirect on self
					team_name = force.name
				else
					-- redirect to a non-winning team
					team_name = slot_manager.get_random_team()
				end
			end
			execute_trap(trap_name, team_name, event.research.force.name)

			if event.research.force.name ~= team_name then
				for _, player in ipairs(event.research.force.connected_players) do
					player.print({ "player-messages.sent-trap-notification", team_name, trap_name })
				end
			end
		end
	end
end)

local starter_techs = {
	"steam-power",
	"electronics",
	"modules",
	"electric-mining-drill",
	"space-science-pack",
	"automation-science-pack",
	"laser",
	"flammables",
}

---@param event EventData.on_force_created
local function on_force_created(event)
	local team_name = event.force.name
	local filter = "^" .. team_name .. "%-.*"
	for _, tech in pairs(event.force.technologies) do
		local name = tech.name
		local result = string.match(name, filter)
		if string.match(name, ".*%-ap%-") and not result then
			tech.enabled = false
		end
	end

	for _, tech_name in pairs(starter_techs) do
		local tech = event.force.technologies[team_name .. "-" .. tech_name] or event.force.technologies[tech_name]
		tech.researched = true
	end

	-- grant either personalized or standard starter tech
	(event.force.technologies[team_name .. "-startup"] or event.force.technologies["startup"]).researched = true

	storage.team_player_slots[team_name] = { players = {}, characters = {} }

	local team_data = ap_teams[team_name]

	local starting_items = {}

	for item, count in team_data["Starting Items"]:gmatch("([^:]*): (%d*),?%s?") do
		starting_items[item] = count
	end

	-- research starter technologies
	for item, count in team_data["Start Inventory"]:gmatch("([^:]*): (%d*),?%s?") do
		for _ = 1, count, 1 do
			research_team_technology(item, event.force)
		end
	end

	storage.team_samples[team_name] = starting_items
end

script.on_event(defines.events.on_force_created, on_force_created)

script.on_init(function()
	-- pause at the start if we expect more players
	if game.is_multiplayer() then
		game.tick_paused = true
	end
	--
	-- if settings.startup.spoilers.value == "Enter Here" then
	-- 	error("No spoiler data provided")
	-- end
	--
	local teams = parse_spoilers.get_teams()
	storage.active_teams = {}
	for team, _ in pairs(teams) do
		table.insert(storage.active_teams, team)
	end

	storage.slot_sample_data = {}
	storage.team_samples = {}
	storage.corpse_indices = {}
	---@type table<string,{players:table<number,number>,characters:table<number,LuaEntity?>}>
	storage.team_player_slots = {}
	---@type table<string,table<number,StashedData>>
	storage.stashed_character_data = {}
	storage.teleport_attempts = {}
	storage.teleport_requests = {}
	---@type table<string,true>
	storage.victorious_forces = {}
	storage.slot_preferences = {}

	for team, data in pairs(teams) do
		local map_gen_data
		if data["Map Exchange String"] then
			local settings = helpers.parse_map_exchange_string(data["Map Exchange String"])
			-- runtime settings cannot be used per-surface, so just ignore those
			map_gen_data = settings.map_gen_settings

			-- map_gen_data = apply_map_gen_settings("nauvis", map_gen_data)
		else
			local data_string =
				data["World Generation"]:gsub("'", '"'):gsub("True", "true"):gsub("False", "false"):gsub("^basic:", "")
			---@type MapGenSettings
			---@diagnostic disable-next-line: assign-type-mismatch
			local map_gen_info = helpers.json_to_table(data_string)

			map_gen_data = apply_map_gen_settings("nauvis", map_gen_info)
		end

		game.create_force(team)
		local surface = game.create_surface(team, map_gen_data)
		-- chart starter area
		surface.request_to_generate_chunks({ 0, 0 }, 8)
		surface.force_generate_chunk_requests()

		game.forces[team].chart(surface, { { -32 * 8, -32 * 8 }, { 32 * 8, 32 * 8 } })

		crash_site_gen.create_crash_site(surface, { -5, -6 }, {}, {})

		local ships = surface.find_entities_filtered({ name = "crash-site-spaceship" })
		for _, ship in pairs(ships) do
			ship.force = team
		end

		local spawn_position = surface.find_non_colliding_position("character", { 0, 0 }, 0, 1)
		assert(spawn_position, "Could not find suitable spawn location for surface " .. surface.name)

		game.forces[team].set_spawn_position(spawn_position, surface)

		on_force_created({ force = game.forces[team], tick = 0, name = defines.events.on_force_created })
	end

	remote.call("silo_script", "set_no_victory", true)
end)

---@param event EventData.on_player_created
script.on_event(defines.events.on_player_created, function(event)
	local player = game.get_player(event.player_index)
	assert(player)

	if player.controller_type == defines.controllers.cutscene then
		player.exit_cutscene()
	end

	-- hide surfaces panel
	player.game_view_settings.show_surface_list = false
end)

script.on_event(defines.events.on_entity_died, function(event)
	if event.entity.name ~= "character" then
		return
	end

	local slot
	local team
	-- character died, check through slots to see who it was
	for team_t, data in pairs(storage.team_player_slots) do
		for slot_t, character in pairs(data.characters) do
			if character.valid and character.unit_number == event.entity.unit_number then
				slot = slot_t
				team = team_t
				-- remove
				data.characters[slot_t] = nil
				goto found
			end
		end
	end
	-- we did not find a matching character. should probably go investigate
	error("Could not find matching character in registry")

	::found::
	-- add respawn time to stashed player data
	if storage.stashed_character_data[team] and storage.stashed_character_data[team][slot] then
		local data = storage.stashed_character_data[team][slot]
		data.ticks_to_respawn = 60 * 10
		data.death_location = event.entity.position
	end

	if not storage.death_link_active then
		local player_index = storage.team_player_slots[team].players[slot]
		local player

		---@type LocalisedString
		local responsible = { "player-messages.no-player-character-name" }

		if player_index ~= -1 then
			player = game.get_player(player_index)
			assert(player)
			responsible = player.name
		end

		print(type(responsible))

		game_manager.trigger_death_link(responsible, team, player)
	end
end)

script.on_event(defines.events.on_player_respawned, function(event)
	local player = game.get_player(event.player_index)
	assert(player)

	print(player.name .. " respawned")

	local team, slot = slot_manager.get_player_slot(player)

	local character = storage.team_player_slots[team].characters[slot]

	if character and character.valid then
		local old_character = player.character
		player.teleport(character.position, character.surface)
		player.set_controller({ type = defines.controllers.character, character = character })

		if old_character then
			old_character.destroy()
		end

		return
	end

	assert(
		player.character and player.character.valid,
		"Player " .. player.name .. " respawned without valid character"
	)

	print("registered new character for " .. player.name)
	storage.team_player_slots[team].characters[slot] = player.character
end)

script.on_event(defines.events.on_player_toggled_map_editor, function(event)
	-- check if player left map editor
	local player = game.get_player(event.player_index)
	assert(player)

	if player.controller_type == defines.controllers.character then
		local team, slot = slot_manager.get_player_slot(player)
		storage.team_player_slots[team].characters[slot] = player.character
	end
end)

script.on_event(defines.events.on_player_joined_game, function(event)
	local player = game.get_player(event.player_index)
	assert(player)

	game_manager.add_player(player)

	local team, _ = slot_manager.get_player_slot(player)

	if storage.victorious_forces[team] then
		local new_team = slot_manager.get_least_populated_team()
		slot_manager.transfer_player(player, new_team)

		player.print({ "player-messages.won-team-transfer", new_team })
	end
end)

script.on_event(defines.events.on_pre_player_left_game, function(event)
	-- disassociate player from their character so it stays
	local player = game.get_player(event.player_index)
	assert(player)

	local team, slot = slot_manager.get_player_slot(player)

	storage.slot_preferences[player.index] = { team, slot }

	slot_manager.disassociate_player(player)
end)

script.on_event(defines.events.on_rocket_launched, function(event)
	-- return if we don't think this team has won
	local team_data = ap_teams[event.rocket.force.name]
	if team_data["Goal"] == "Satellite" then
		local rocket_inventory = event.rocket.cargo_pod.get_inventory(defines.inventory.cargo_unit)
		assert(rocket_inventory)
		-- look through, see if we find the satellite
		if not rocket_inventory.find_item_stack("satellite") then
			return
		end
	end

	game_manager.set_team_won(event.rocket.force.name)
end)
