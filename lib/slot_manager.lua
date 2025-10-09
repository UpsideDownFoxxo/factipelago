local samples = require("lib/samples")
local m = require("lib/per_force_players")

---@alias StashedData {quickbar_pages:number[],quickbar_slots:unknown[],death_location:MapPosition?,ticks_to_respawn:number?,color:Color,chat_color:Color,opened:unknown,force:LuaForce,tag:string,controller_type:defines.controllers,position:MapPosition,zoom:number}

local function get_corpse_index(team, slot)
	storage.current_corpse_index = storage.current_corpse_index or 10000

	if not storage.corpse_indices[team] or not storage.corpse_indices[team][slot] then
		local index = storage.current_corpse_index
		storage.corpse_indices[team] = storage.corpse_indices[team] or {}
		storage.corpse_indices[team][slot] = index
		storage.current_corpse_index = index + 1
		return index
	end

	return storage.corpse_indices[team][slot]
end

---@param player LuaPlayer
local function unlink_corpses(player)
	local team, slot = m.get_player_slot(player)

	local stash_index = get_corpse_index(team, slot)

	local corpses = game.surfaces[team].find_entities_filtered({ type = "character-corpse" })
	for _, corpse in pairs(corpses) do
		if corpse.character_corpse_player_index == player.index then
			local old_inv = corpse.get_inventory(defines.inventory.character_corpse)

			local new_corpse = game.surfaces[team].create_entity({
				name = "character-corpse",
				position = corpse.position,
				force = corpse.force,
				color = corpse.color,
				inventory_size = #old_inv,
			})

			assert(new_corpse)

			-- copy properties
			new_corpse.character_corpse_death_cause = corpse.character_corpse_death_cause
			new_corpse.character_corpse_tick_of_death = corpse.character_corpse_tick_of_death
			new_corpse.character_corpse_player_index = stash_index

			local new_inv = new_corpse.get_inventory(defines.inventory.character_corpse)

			assert(old_inv and new_inv)

			-- copy inventory
			for _, stack in ipairs(old_inv.get_contents()) do
				---@diagnostic disable-next-line: param-type-mismatch
				new_inv.insert(stack)
			end

			-- kill the old corpse
			corpse.destroy()
		end
	end
end

---@param player LuaPlayer
local function relink_corpses(player)
	local team, slot = m.get_player_slot(player)

	local stash_index = get_corpse_index(team, slot)

	local corpses = game.surfaces[team].find_entities_filtered({ type = "character-corpse" })
	for _, corpse in pairs(corpses) do
		if corpse.character_corpse_player_index == stash_index then
			corpse.character_corpse_player_index = player.index
			player.add_pin({ entity = corpse })
		end
	end
end

---@param player LuaPlayer
m.disassociate_player = function(player)
	print("disassociating " .. player.name)
	-- record player data
	---@type StashedData
	local old_player_data = {
		ticks_to_respawn = player.ticks_to_respawn,
		quickbar_pages = {},
		quickbar_slots = {},
		color = player.color,
		chat_color = player.chat_color,
		---@diagnostic disable-next-line: assign-type-mismatch
		force = player.force,
		death_location = player.ticks_to_respawn and player.position or nil,
		opened = player.opened or (player.opened_self and "self") or nil,
		tag = player.tag,
		controller_type = player.controller_type,
		position = player.position,
		zoom = player.zoom,
	}

	player.opened = nil

	unlink_corpses(player)

	for i = 1, 10, 1 do
		old_player_data.quickbar_pages[i] = player.get_active_quick_bar_page(i)
	end

	for i = 1, 100, 1 do
		old_player_data.quickbar_slots[i] = player.get_quick_bar_slot(i)
	end

	local old_team, old_slot = m.get_player_slot(player)

	-- mark as vacant
	storage.team_player_slots[old_team].players[old_slot] = -1

	storage.stashed_character_data[old_team] = storage.stashed_character_data[old_team] or {}
	storage.stashed_character_data[old_team][old_slot] = old_player_data

	local old_character = player.character
	player.set_controller({ type = defines.controllers.ghost })

	if old_character then
		old_character.color = player.color
	end

	print(serpent.block(storage.team_player_slots))
	print(serpent.block(storage.stashed_character_data))
end

---@param player LuaPlayer
---@param team string
---@param slot number
m.associate_player = function(player, team, slot)
	print("associating " .. player.name .. " with " .. team .. ":" .. slot)
	print(serpent.block(storage.team_player_slots))
	print(serpent.block(storage.stashed_character_data))
	local character = storage.team_player_slots[team].characters[slot]
	local player_data = storage.stashed_character_data[team][slot]

	storage.team_player_slots[team].players[slot] = player.index

	if not character or not character.valid then
		-- player was dead, create character and delete again since player cannot actually respawn otherwise
		assert(
			player_data.ticks_to_respawn,
			"Player " .. team .. ":" .. slot .. " was not respawning and did not have a character"
		)
		local temp_character = game.surfaces[team].create_entity({ name = "character", position = { 0, 0 } })
		assert(temp_character)

		player.teleport(temp_character.position, temp_character.surface)
		player.set_controller({ type = defines.controllers.character, character = temp_character })
		player.ticks_to_respawn = player_data.ticks_to_respawn

		temp_character.destroy()

		player.teleport(player_data.death_location)
	else
		player.teleport(character.position, character.surface)
		player.set_controller({ type = defines.controllers.character, character = character })
	end

	player.force = player_data.force

	for i = 1, 100, 1 do
		player.set_quick_bar_slot(i, player_data.quickbar_slots[i])
	end

	for index, page in pairs(player_data.quickbar_pages) do
		player.set_active_quick_bar_page(index, page)
	end

	player.color = player_data.color
	player.chat_color = player_data.chat_color
	player.tag = player_data.tag

	if player_data.opened == "self" then
		player_data.opened = player
	elseif player_data.opened and not player_data.opened.valid then
		player_data.opened = nil
	end

	player.opened = player_data.opened

	relink_corpses(player)

	player.zoom = player_data.zoom

	if player_data.controller_type == defines.controllers.remote then
		player.set_controller({ type = defines.controllers.remote })
		player.teleport(player_data.position)
	end
end

-- HSV to RGB
--https://stackoverflow.com/a/71365991
local function HSV2RGB(h, s, v)
	local min = math.min
	local max = math.max
	local abs = math.abs

	local k1 = v * (1 - s)
	local k2 = v - k1
	local r = min(max(3 * abs((h / 180) % 2 - 1) - 1, 0), 1)
	local g = min(max(3 * abs(((h - 120) / 180) % 2 - 1) - 1, 0), 1)
	local b = min(max(3 * abs(((h + 120) / 180) % 2 - 1) - 1, 0), 1)
	return k1 + k2 * r, k1 + k2 * g, k1 + k2 * b
end

---@param team string
---@param player LuaPlayer
m.get_or_make_empty_slot = function(team, player)
	local slots = storage.team_player_slots[team].players
	for slot, player_index in pairs(slots) do
		if player_index == -1 then
			slots[slot] = player.index
			return slot, false
		end
	end

	local slot = #slots + 1
	slots[slot] = player.index

	-- create character
	local surface = game.surfaces[team]
	local spawn_position =
		surface.find_non_colliding_position("character", game.forces[team].get_spawn_position(surface), 0, 1)

	assert(spawn_position, "Could not find a spot to put the player")

	local character = surface.create_entity({
		name = "character",
		position = spawn_position,
		force = team,
	})
	assert(character, "Could not create character")

	-- insert factorio starter items
	if remote.interfaces["freeplay"] then
		---@type table<data.ItemID,number>
		---@diagnostic disable-next-line
		local items = remote.call("freeplay", "get_created_items")

		for item, count in pairs(items) do
			---@type 	ItemStackDefinition
			local stack = { name = item, count = count }
			character.insert(stack)
		end
	end

	storage.team_player_slots[team].characters[slot] = character

	-- create character data
	-- get random color
	local r, g, b = HSV2RGB(math.random(0, 360), 1, 0.5)

	local color = {
		r = r * 255,
		g = g * 255,
		b = b * 255,
		a = 0.5,
	}

	local chat_color = table.deepcopy(color)
	chat_color.a = 1
	storage.stashed_character_data[team] = storage.stashed_character_data[team] or {}
	storage.stashed_character_data[team][slot] = {
		ticks_to_respawn = nil,
		quickbar_pages = {},
		quickbar_slots = {},
		color = color,
		chat_color = chat_color,
		force = game.forces[team],
		tag = "",
		zoom = 1,
	}

	samples.catch_up_slot(team, slot)

	return slot, true
end

---@param player LuaPlayer
---@param team string
m.transfer_player = function(player, team)
	m.disassociate_player(player)
	local slot = m.get_or_make_empty_slot(team, player)

	local slot_preference = storage.slot_preferences[player.index]
	if slot_preference then
		slot_preference[1] = team
		slot_preference[2] = slot
	end

	m.associate_player(player, team, slot)
end

---@param player_a LuaPlayer
---@param player_b LuaPlayer
m.swap_players = function(player_a, player_b)
	if not player_a.connected and player_b.connected then
		game.print("cannot swap with an offline player")
		return
	end

	local team_a, slot_a = m.get_player_slot(player_a)
	local team_b, slot_b = m.get_player_slot(player_b)

	local slot_preference_a = storage.slot_preferences[player_a.index]
	if slot_preference_a then
		slot_preference_a[1] = team_b
		slot_preference_a[2] = slot_b
	end

	local slot_preference_b = storage.slot_preferences[player_a.index]
	if slot_preference_b then
		slot_preference_b[1] = team_a
		slot_preference_b[2] = slot_a
	end

	m.disassociate_player(player_a)
	m.disassociate_player(player_b)

	m.associate_player(player_b, team_a, slot_a)
	m.associate_player(player_a, team_b, slot_b)
end
return m
