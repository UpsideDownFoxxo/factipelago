local util = require("util")
if settings.startup.spoilers.value == "Enter Here" then
	-- no sense in doing anything if startup setting is default
	return
end

local locale = require("lib/locale")

local parse_spoilers = require("lib/parse_spoilers")

data:extend({
	---@type LuaTechnologyPrototype
	{
		type = "technology",
		name = "startup",
		icon = util.empty_icon().icon,
		hidden = true,

		research_trigger = {
			type = "capture-spawner",
			entity = "biter-spawner",
		},
		effects = {},
	},
})

local starter_tech = data.raw["technology"]["startup"]

for _, recipe in pairs(data.raw["recipe"]) do
	if recipe.enabled == nil or recipe.enabled == true then
		table.insert(starter_tech.effects, {
			type = "unlock-recipe",
			recipe = recipe.name,
		})
		recipe.enabled = false
	end
end

for _, tech in pairs(data.raw["technology"]) do
	if (tech.enabled == nil or tech.enabled == true) and tech.name ~= "startup" then
		tech.prerequisites = { "startup" }
	end
end

local old_data = data

local final_extensions = {}
local extensions = {}
local modified_recipes = {}

local recipe_proxy = {}
setmetatable(recipe_proxy, {
	__index = function(_, key)
		if modified_recipes[key] then
			return modified_recipes[key]
		end

		print("Creating copy of recipe " .. key)

		local recipe = table.deepcopy(old_data.raw["recipe"][key])
		modified_recipes[key] = recipe
		return recipe
	end,
})

local raw_proxy = {}
setmetatable(raw_proxy, {
	__index = function(_, key)
		if key == "recipe" then
			-- we only care about these, modifying other things is okay
			return recipe_proxy
		end

		return old_data.raw[key]
	end,
})

local data_proxy = {
	extend = function(_, data)
		for _, block in ipairs(data) do
			table.insert(extensions, block)
		end
	end,
	raw = raw_proxy,
}

--#region Energy bridge prototype copied from AP mod
local function energy_bridge_tint()
	return { r = 0, g = 1, b = 0.667, a = 1 }
end
local function tint_icon(obj, tint)
	obj.icons = { { icon = obj.icon, icon_size = obj.icon_size, icon_mipmaps = obj.icon_mipmaps, tint = tint } }
	obj.icon = nil
	obj.icon_size = nil
	obj.icon_mipmaps = nil
end
local energy_bridge = table.deepcopy(data.raw["accumulator"]["accumulator"])
energy_bridge.name = "ap-energy-bridge"
energy_bridge.minable.result = "ap-energy-bridge"
energy_bridge.localised_name = "Archipelago EnergyLink Bridge"
energy_bridge.energy_source.buffer_capacity = "50MJ"
energy_bridge.energy_source.input_flow_limit = "10MW"
energy_bridge.energy_source.output_flow_limit = "10MW"
tint_icon(energy_bridge, energy_bridge_tint())
energy_bridge.chargable_graphics.picture.layers[1].tint = energy_bridge_tint()
energy_bridge.chargable_graphics.charge_animation.layers[1].layers[1].tint = energy_bridge_tint()
energy_bridge.chargable_graphics.discharge_animation.layers[1].layers[1].tint = energy_bridge_tint()
data.raw["accumulator"]["ap-energy-bridge"] = energy_bridge

local energy_bridge_item = table.deepcopy(data.raw["item"]["accumulator"])
energy_bridge_item.name = "ap-energy-bridge"
energy_bridge_item.localised_name = "Archipelago EnergyLink Bridge"
energy_bridge_item.place_result = energy_bridge.name
tint_icon(energy_bridge_item, energy_bridge_tint())
data.raw["item"]["ap-energy-bridge"] = energy_bridge_item

local energy_bridge_recipe = table.deepcopy(data.raw["recipe"]["accumulator"])
energy_bridge_recipe.name = "ap-energy-bridge"
energy_bridge_recipe.results = { { type = "item", name = energy_bridge_item.name, amount = 1 } }
energy_bridge_recipe.energy_required = 1
energy_bridge_recipe.enabled = false
energy_bridge_recipe.localised_name = "Archipelago EnergyLink Bridge"
data.raw["recipe"]["ap-energy-bridge"] = energy_bridge_recipe
--#endregion

local mapping = parse_spoilers.get_tech_mappings()
local teams = parse_spoilers.get_teams()

local function localize_tech(extension_data, team_name, tree_visibility)
	local ap_name = team_name .. "-" .. parse_spoilers.factorio_to_ap(extension_data.name)
	local trimmed_ap_name = ap_name:match(".*%-(AP%-%d%-%d%d%d)")
	if tree_visibility == "Full" then
		local tech_effects = mapping[ap_name]
		for to_team, effects in pairs(tech_effects) do
			if effects.techs[1] then
				local localised_name = {}
				local tech_name = {
					"technology-name."
						.. (effects.techs[1]:match("^.*%-rocket%-silo") and "rocket-silo" or effects.techs[1]),
				}

				if effects.techs[1]:match("^progressive") then
					localised_name = { "technology-name.progressive", to_team, tech_name }
				else
					local tech_prototype = data.raw["technology"][effects.techs[1]]

					localised_name = { "technology-name.general", to_team, tech_prototype.localised_name or tech_name }
				end

				extension_data.localised_name = localised_name

				break
			else
				extension_data.localised_name = {
					"technology-name.trapped",
					to_team,
					effects.traps[1],
				}
			end
		end
	elseif tree_visibility == "Advancement" then
		local important = not extension_data.icon:find("important")
		if important then
			extension_data.localised_name = { "technology-name.important", trimmed_ap_name }
		else
			extension_data.localised_name = { "technology-name.unimportant", trimmed_ap_name }
		end
	else
		extension_data.localised_name = { "technology-name.hidden", trimmed_ap_name }
	end
end

local player_mods = parse_spoilers.get_setting_data().player_mods

local function make_team(team_name)
	extensions = {}
	modified_recipes = {}
	data = data_proxy

	_G.current_module = player_mods[team_name]

	print("Loading Dummy")
	require("lib.dummy")
	-- immediately unload dummy again
	package.loaded["__factipelago__/lib/dummy.lua"] = nil

	data = old_data

	local needs_separate_tech = {}

	---@param recipe data.RecipePrototype
	for _, recipe in pairs(modified_recipes) do
		local new_name = team_name .. "-" .. recipe.name
		-- chase down techs that unlock this and clone them later
		needs_separate_tech[recipe.name] = true
		recipe.localised_name = locale.of_recipe(recipe)
		recipe.name = new_name

		table.insert(final_extensions, recipe)
	end

	-- duplicate technologies that unlock modified recipes
	---@param tech data.TechnologyPrototype
	for _, tech in pairs(data.raw["technology"]) do
		local new_tech = nil
		for i, effect in ipairs(tech.effects or {}) do
			if effect.type == "unlock-recipe" and needs_separate_tech[effect.recipe] then
				if not new_tech then
					new_tech = table.deepcopy(tech)
				end
				new_tech.effects[i].recipe = team_name .. "-" .. effect.recipe
			end
		end

		if new_tech then
			new_tech.localised_name = new_tech.localised_name or { "technology-name." .. new_tech.name }
			new_tech.localised_description = new_tech.localised_description
				or { "technology-description." .. new_tech.name }
			new_tech.name = team_name .. "-" .. new_tech.name
			table.insert(final_extensions, new_tech)
		end
	end

	for _, extension_data in ipairs(extensions) do
		-- add namespace
		extension_data.name = team_name .. "-" .. extension_data.name

		-- patch icon paths
		if extension_data.icon then
			extension_data.icon = extension_data.icon:gsub("__AP.*__", "__factipelago__")
		end

		if extension_data.type == "technology" then
			extension_data.hidden = false

			-- add name
			localize_tech(extension_data, team_name, teams[team_name]["Technology Tree Information"])
		end

		-- patch tech dependencies
		for index, value in pairs(extension_data.prerequisites) do
			if value:match("^ap%-%d%d%d%d%d%d%-") then
				extension_data.prerequisites[index] = team_name .. "-" .. value
			end
		end

		-- add dependencies on the techs providing the required science
		for _, pack in pairs(extension_data.unit.ingredients) do
			table.insert(extension_data.prerequisites, pack[1])
		end
	end

	for _, value in ipairs(extensions) do
		table.insert(final_extensions, value)
	end
end

for team_name, _ in pairs(teams) do
	make_team(team_name)
end
-- set actual technology research costs to nothing
for _, tech in pairs(data.raw["technology"]) do
	if tech.unit then
		tech.unit = nil

		-- locale on this is overridden, it just says "Git gud!"
		tech.research_trigger = {
			type = "capture-spawner",
			entity = "biter-spawner",
		}
	end
end

data.raw["rocket-silo"]["rocket-silo"].fixed_recipe = nil

local disable_overrides = {
	"artillery-shell-range-1",
	"artillery-shell-speed-1",
	"follower-robot-count-5",
	"laser-weapons-damage-7",
	"mining-productivity-4",
	"physical-projectile-damage-7",
	"refined-flammables-7",
	"stronger-explosives-7",
	"worker-robots-speed-6",
}

for _, value in ipairs(disable_overrides) do
	data.raw["technology"][value].hidden = true
	data.raw["technology"][value].hidden_in_factoriopedia = true
end

data:extend(final_extensions)
-- fix dependencies if personalized tech is available
for tech_name, tech in pairs(data.raw["technology"]) do
	local team_name = tech_name:match("([^-]*)")
	if teams[team_name] then
		for i, prerequisite in pairs(tech.prerequisites or {}) do
			if data.raw["technology"][team_name .. "-" .. prerequisite] then
				print(
					"Corrected dependency "
						.. prerequisite
						.. " of technology "
						.. tech_name
						.. " to "
						.. team_name
						.. "-"
						.. prerequisite
				)
				tech.prerequisites[i] = team_name .. "-" .. prerequisite
			end
		end
	end
end
