local parse_spoilers = require("lib/parse_spoilers")
local ap_teams = parse_spoilers.get_teams()
local team_players = require("lib/per_force_players")

local function random_offset_position(pos, offset)
	return { x = pos.x + math.random(-offset, offset), y = pos.y + math.random(-offset, offset) }
end

---comment
---@param force LuaForce
---@param _function function
local function for_connected_players(force, _function)
	for _, player in pairs(force.connected_players) do
		_function(player)
	end
end

---@param force LuaForce
---@param message LocalisedString
local function force_broadcast_trap(force, message, triggered_by)
	if force.name == triggered_by then
		message[1] = message[1] .. "-self"
	end

	for_connected_players(force, function(player)
		player.print(message)
	end)
end

---@param force LuaForce
---@param projectile string
---@param speed number
local function launch_at_players(force, projectile, speed)
	---@param player LuaPlayer
	for_connected_players(force, function(player)
		---@type LuaEntity | MapPosition
		local target = player.character
		if not target then
			target = player.position
		end

		player.surface.create_entity({
			name = projectile,
			position = random_offset_position(player.position, 128),
			speed = speed,
			target = target,
		})
	end)
end

---@param entities LuaEntity[]
---@param projectile string
---@param speed number
local function launch_at_entities(entities, projectile, speed)
	for _, entity in ipairs(entities) do
		---@type LuaEntity | MapPosition
		local target = entity
		if not entity.health then
			target = entity.position
		end

		entity.surface.create_entity({
			name = projectile,
			target = target,
			position = random_offset_position(entity.position, 128),
			speed = speed,
		})
	end
end

local max_teleport_attempts = 100

---@param team string
---@param slot number
local function try_teleport_player(team, slot, triggered_by)
	local player = team_players.get_slot_player(slot, team) or { print = function(...) end }
	local character = storage.team_player_slots[team].characters[slot]

	if not character or not character.valid then
		return
	end

	local ident = team .. ":" .. slot

	if (storage.teleport_attempts[ident] or 0) >= max_teleport_attempts then
		player.print({ "traps.teleport-timeout" })
		storage.teleport_attempts[ident] = 0
		return
	end

	local surface = character.surface
	local start_pos = character.position
	local end_pos_candidate = random_offset_position(start_pos, 1024)

	local end_pos = surface.find_non_colliding_position(character.prototype, end_pos_candidate, 0, 1)

	if not end_pos then
		storage.teleport_attempts[ident] = (storage.teleport_attempts[ident] or 0) + 1
		return try_teleport_player(team, slot, triggered_by)
	end

	local path_request = surface.request_path({
		start = start_pos,
		goal = end_pos,
		force = character.force,
		bounding_box = character.bounding_box,
		collision_mask = { layers = { ["player"] = true } },
		pathfind_flags = {
			allow_paths_through_own_entities = true,
			allow_destroy_friendly_entities = true,
		},
	})

	storage.teleport_requests[path_request] = { team = team, slot = slot, triggered_by = triggered_by }
end

---@param event EventData.on_script_path_request_finished
script.on_event(defines.events.on_script_path_request_finished, function(event)
	local request = storage.teleport_requests[event.id]

	storage.teleport_requests[event.id] = nil
	local ident = request.team .. ":" .. request.slot

	local player = team_players.get_slot_player(request.slot, request.team) or { print = function(...) end }
	local character = storage.team_player_slots[request.team].characters[request.slot]

	local path = event.path
	if not path or not character or not character.valid then
		storage.teleport_attempts[ident] = (storage.teleport_attempts[ident] or 0) + 1
		return try_teleport_player(request.team, request.slot, request.triggered_by)
	end

	character.teleport(path[#path].position)
	if character.force.name == request.triggered_by then
		player.print({
			"traps.teleport-trap-self",
			request.triggered_by,
		})
	else
		player.print({
			"traps.teleport-trap",
			request.triggered_by,
		})
	end
	storage.teleport_attempts[ident] = 0
end)

local function spill_character_inventory(character)
	if not (character and character.valid) then
		return false
	end

	-- grab attrs once pre-loop
	local position = character.position
	local surface = character.surface

	local inventories_to_spill = {
		defines.inventory.character_main, -- Main inventory
		defines.inventory.character_trash, -- Logistic trash slots
	}

	for _, inventory_type in pairs(inventories_to_spill) do
		local inventory = character.get_inventory(inventory_type)
		if inventory and inventory.valid then
			-- Spill each item stack onto the ground
			for i = 1, #inventory do
				local stack = inventory[i]
				if stack and stack.valid_for_read then
					local spilled_items = surface.spill_item_stack({
						position = position,
						stack = stack,
						enable_looted = false, -- do not mark for auto-pickup
						force = nil, -- do not mark for auto-deconstruction
						allow_belts = true, -- do mark for putting it onto belts
					})
					if #spilled_items > 0 then
						stack.clear() -- only delete if spilled successfully
					end
				end
			end
		end
	end
end

local traps = {
	["Evolution Trap"] = function(team, triggered_by)
		---@type LuaSurface
		local team_surface = game.surfaces[team]
		---@type LuaForce
		local team_force = game.forces[team]

		local trap_evo_factor = tonumber(ap_teams[team]["Evolution Trap % Effect"]) / 100

		-- calculation from AP mod
		local new_factor = game.forces["enemy"].get_evolution_factor(team_surface)
			+ (trap_evo_factor * (1 - game.forces["enemy"].get_evolution_factor(team_surface)))

		game.forces["enemy"].set_evolution_factor(new_factor, team_surface)

		force_broadcast_trap(
			team_force,
			{ "traps.evolution-trap-1", triggered_by, math.floor(new_factor * 100 + 0.5) },
			triggered_by
		)

		force_broadcast_trap(
			team_force,
			{ "traps.evolution-trap-2", triggered_by, math.floor(new_factor * 100 + 0.5) },
			triggered_by
		)
	end,
	["Attack Trap"] = function(team, _)
		---@type LuaSurface
		local team_surface = game.surfaces[team]
		---@type LuaForce
		local team_force = game.forces[team]

		team_surface.build_enemy_base(team_force.get_spawn_position(team_surface), 25)
	end,
	["Inventory Spill Trap"] = function(team, triggered_by)
		---@type LuaForce
		local team_force = game.forces[team]

		for _, player in ipairs(team_force.connected_players) do
			spill_character_inventory(player.character)
		end

		force_broadcast_trap(team_force, { "traps.spill-trap", triggered_by }, triggered_by)
	end,
	["Atomic Rocket Trap"] = function(team, triggered_by)
		---@type LuaForce
		local team_force = game.forces[team]

		launch_at_players(team_force, "atomic-rocket", 0.1)
		force_broadcast_trap(team_force, { "traps.atomic-rocket-trap", triggered_by }, triggered_by)
	end,
	["Grenade Trap"] = function(team, triggered_by)
		---@type LuaForce
		local team_force = game.forces[team]

		launch_at_players(team_force, "grenade", 0.1)
		force_broadcast_trap(team_force, { "traps.grenade-trap", triggered_by }, triggered_by)
	end,
	["Cluster Grenade Trap"] = function(team, triggered_by)
		---@type LuaForce
		local team_force = game.forces[team]

		launch_at_players(team_force, "cluster-grenade", 0.1)
		force_broadcast_trap(team_force, { "traps.cluster-grenade-trap", triggered_by }, triggered_by)
	end,
	["Artillery Trap"] = function(team, triggered_by)
		---@type LuaForce
		local team_force = game.forces[team]

		launch_at_players(team_force, "artillery-projectile", 1)
		force_broadcast_trap(team_force, { "traps.artillery-trap", triggered_by }, triggered_by)
	end,
	["Teleport Trap"] = function(team, triggered_by)
		---@type LuaForce
		local team_force = game.forces[team]

		---@param player LuaPlayer
		for_connected_players(team_force, function(player)
			local team_name, slot = team_players.get_player_slot(player)
			try_teleport_player(team_name, slot, triggered_by)
		end)
	end,
	["Atomic Cliff Remover Trap"] = function(team, triggered_by)
		---@type LuaSurface
		local team_surface = game.surfaces[team]
		---@type LuaForce
		local team_force = game.forces[team]

		local cliffs = team_surface.find_entities_filtered({ type = "cliff" })
		if #cliffs > 0 then
			local index = math.random(1, #cliffs)
			launch_at_entities({ cliffs[index] }, "atomic-rocket", 0.1)
		end

		force_broadcast_trap(team_force, { "traps.atomic-cliff-remover-trap", triggered_by }, triggered_by)
	end,
}

return traps
