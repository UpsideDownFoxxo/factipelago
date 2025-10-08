local game_manager = require("lib/game_manager")
local slot_manager = require("lib/slot_manager")

local parse_spoilers = require("lib/parse_spoilers")
local ap_teams = parse_spoilers.get_teams()

local traps = require("lib/traps")

---@type CustomCommandData
commands.add_command("swap", "", function()
	game_manager.swap_random_teams()
end)

---@type CustomCommandData
commands.add_command("balance", "", function()
	game_manager.balance_teams()
end)

---@type CustomCommandData
commands.add_command("transfer", "", function(data)
	local team = data.parameter

	if not team or not game.forces[team] then
		game.print("Cannot transfer to this force")
		return
	end

	---@type LuaPlayer
	local player = game.players[data.player_index]

	slot_manager.transfer_player(player, team)
end)

---@param data CustomCommandData
commands.add_command("trigger_trap", "", function(data)
	local player = game.players[data.player_index]
	---@type LuaForce
	local force = player.force

	local player_team

	for team, _ in pairs(ap_teams) do
		if game.forces[team].index == force.index then
			player_team = team
			break
		end
	end

	local trap = traps[data.parameter]
	if not trap then
		player.print("Don't know that trap, sorry")
		return
	end
	trap(player_team, game.players[data.player_index].name)
end)

commands.add_command("tag", { "command-help.tag" }, function(event)
	local player = game.get_player(event.player_index)
	assert(player)

	player.tag = event.parameter or ""
end)
