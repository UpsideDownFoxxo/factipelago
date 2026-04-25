local game_manager = require("lib/game_manager")
local slot_manager = require("lib/slot_manager")

local parse_spoilers = require("lib/parse_spoilers")
local ap_teams = parse_spoilers.get_teams()

local traps = require("lib/traps")

-- admin only
local function admin_check(event)
	local player = game.players[event.player_index]
	assert(player)

	return player.admin
end

---@type CustomCommandData
commands.add_command("swap", "", function(event)
	if not admin_check(event) then
		return
	end

	game_manager.swap_random_teams()
end)

---@type CustomCommandData
commands.add_command("balance", "", function(event)
	if not admin_check(event) then
		return
	end
	game_manager.balance_teams()
end)

---@type CustomCommandData
commands.add_command("transfer", "", function(event)
	if not admin_check(event) then
		return
	end
	local team = event.parameter

	if not team or not game.forces[team] then
		game.print("Cannot transfer to this force")
		return
	end

	---@type LuaPlayer
	local player = game.players[event.player_index]

	slot_manager.transfer_player(player, team)
end)

---@param event CustomCommandData
commands.add_command("trigger_trap", "", function(event)
	if not admin_check(event) then
		return
	end
	local player = game.players[event.player_index]
	---@type LuaForce
	local force = player.force

	local player_team

	for team, _ in pairs(ap_teams) do
		if game.forces[team].index == force.index then
			player_team = team
			break
		end
	end

	local trap = traps[event.parameter]
	if not trap then
		player.print("Don't know that trap, sorry")
		return
	end
	trap(player_team, game.players[event.player_index].name)
end)

commands.add_command("swap_interval", { "command-help.swap_interval" }, function(event)
	if not admin_check(event) then
		return
	end
	event.parameter = event.parameter or ""
	local new_interval = helpers.evaluate_expression(event.parameter)
	if not new_interval then
		game.players[event.player_index].print("Failed to parse expression'" .. event.parameter .. "'")
		return
	end

	game_manager.set_swap_interval(math.ceil(new_interval))

	local player = game.get_player(event.player_index)
	if player then
		player.print({ "player-messages.updated-swap-interval", math.ceil(new_interval) })
	end
end)

-- all players
commands.add_command("tag", { "command-help.tag" }, function(event)
	local player = game.get_player(event.player_index)
	assert(player)

	player.tag = event.parameter or ""
	player.print({ "player-messages.updated-tag", player.tag })
end)
