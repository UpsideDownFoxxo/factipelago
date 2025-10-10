local team_players = require("lib/per_force_players")
local FREE_SAMPLE_BLACKLIST = {["space-science-pack"] = 1,
["chemical-science-pack"] = 1,
["rocket-part"] = 1,
["logistic-science-pack"] = 1,
["automation-science-pack"] = 1,
["utility-science-pack"] = 1,
["military-science-pack"] = 1,
["production-science-pack"] = 1,
["rocket-silo"] = 1,
["satellite"] = 1
}

local m = {}

local ap_teams = require("lib/parse_spoilers").get_teams()

m.try_insert_pending_samples = function(team, slot)
	local character = storage.team_player_slots[team].characters[slot]
	if not character or not character.valid then
		return
	end

  ---@type {print:function}
  local player = team_players.get_slot_player(slot, team) or {print=function(...) end}

	local sample_data = storage.slot_sample_data[team .. ":" .. slot] or {samples={},inv_warning=false}
  local not_enough_space

  local quality = string.lower(ap_teams[team]["Free Samples Quality"])

	---@param sample data.ItemID
	for sample, count in pairs(sample_data.samples) do
    ---@type ItemStackDefinition
		local stack = {
			name = sample,
			count = count,
      quality = script.active_mods["quality"] and quality or nil
		}


		if not prototypes.item[sample] then
      sample_data.samples[sample] = nil
			player.print({ "player-messages.unknown-sample", sample })
			goto continue
		end

		local inserted = character.insert(stack)

		if inserted > 0 then
      sample_data.inv_warning = true
			player.print({ "player-messages.received-sample", inserted, sample })
		end

    if inserted ~= count then
      not_enough_space = true
    end

    local remaining = count - inserted
    sample_data.samples[sample] = (remaining > 0) and remaining or nil

		::continue::
	end

  if not_enough_space and sample_data.inv_warning then
		player.print({ "player-messages.full-inventory" })
    sample_data.inv_warning = false
  end
end

m.grant_sample = function (team,slot,sample,count)
  local ident = team .. ":" .. slot

  storage.slot_sample_data[ident] = storage.slot_sample_data[ident] or {samples={},inv_warning=true}
  local sample_data = storage.slot_sample_data[ident]

  sample_data.samples[sample] = (sample_data.samples[sample] or 0) + count
end

local function get_stack_size(item)
  local prototype = prototypes.item[item] or prototypes.equipment[item] or {stack_size = 1}
  return prototype.stack_size
end

local sample_calculation = {
  ["Single Craft"] = function (_,amount)
    return amount
  end,
  ["Half Stack"] = function (item,_)
    return math.ceil(get_stack_size(item) / 2)
  end,
  ["Stack"] = function (item,_)
    return math.ceil(get_stack_size(item))
  end
}

---@param technology LuaTechnology
m.grant_tech_research_rewards = function (technology)
  local team = ap_teams[technology.force.name]
  local sample_reward = team["Free Samples"]
  local team_samples = storage.team_samples[technology.force.name]

  if sample_reward == "None" then
    return
  end

  local samples = {}

  for _, effect in ipairs(technology.prototype.effects or {}) do
    if effect.type == "unlock-recipe" then

      for _, product in pairs(prototypes.recipe[effect.recipe].products) do
        if product.type == "item" and product.amount then
          if FREE_SAMPLE_BLACKLIST[product.name] then
            goto continue
          end
        end

        samples[product.name] = (samples[product.name] or 0) + sample_calculation[sample_reward](product.name,product.amount)

          ::continue::
      end
    end
  end

  -- register for new players
  for sample, count in pairs(samples) do
    team_samples[sample] = (team_samples[sample] or 0) + count
  end


  for slot, _ in pairs(storage.team_player_slots[technology.force.name].players) do
    for sample,count in pairs(samples) do
      m.grant_sample(technology.force.name,slot,sample,count)
    end
  end
end

---@param team string
---@param slot number
m.catch_up_slot = function (team,slot)
  for sample,count in pairs(storage.team_samples[team]) do
      m.grant_sample(team,slot,sample,count)
  end
end

m.swample_update_handler = function ()
  for team, slots in pairs(storage.team_player_slots) do
		for slot, _ in ipairs(slots.players) do
			m.try_insert_pending_samples(team, slot)
		end
	end

end

return m
