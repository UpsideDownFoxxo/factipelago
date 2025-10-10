local progressive_technologies = {
	["progressive-advanced-material-processing"] = { "advanced-material-processing", "advanced-material-processing-2" },
	["progressive-armor"] = { "heavy-armor", "modular-armor", "power-armor", "power-armor-mk2" },
	["progressive-automation"] = { "automation", "automation-2", "automation-3" },
	["progressive-braking-force"] = {
		"braking-force-1",
		"braking-force-2",
		"braking-force-3",
		"braking-force-4",
		"braking-force-5",
		"braking-force-6",
		"braking-force-7",
	},
	["progressive-efficiency-module"] = { "efficiency-module", "efficiency-module-2", "efficiency-module-3" },
	["progressive-electric-energy-distribution"] = {
		"electric-energy-distribution-1",
		"electric-energy-distribution-2",
	},
	["progressive-energy-shield"] = { "energy-shield-equipment", "energy-shield-mk2-equipment" },
	["progressive-engine"] = { "engine", "electric-engine" },
	["progressive-flamethrower"] = {
		"flamethrower",
		"refined-flammables-1",
		"refined-flammables-2",
		"refined-flammables-3",
		"refined-flammables-4",
		"refined-flammables-5",
		"refined-flammables-6",
	},
	["progressive-fluid-handling"] = { "fluid-handling", "fluid-wagon" },
	["progressive-follower"] = { "defender", "distractor", "destroyer" },
	["progressive-follower-robot-count"] = {
		"follower-robot-count-1",
		"follower-robot-count-2",
		"follower-robot-count-3",
		"follower-robot-count-4",
	},
	["progressive-inserter"] = {
		"fast-inserter",
		"bulk-inserter",
		"inserter-capacity-bonus-1",
		"inserter-capacity-bonus-2",
		"inserter-capacity-bonus-3",
		"inserter-capacity-bonus-4",
		"inserter-capacity-bonus-5",
		"inserter-capacity-bonus-6",
		"inserter-capacity-bonus-7",
	},
	["progressive-inserter-capacity-bonus"] = {
		"inserter-capacity-bonus-1",
		"inserter-capacity-bonus-2",
		"inserter-capacity-bonus-3",
		"inserter-capacity-bonus-4",
		"inserter-capacity-bonus-5",
		"inserter-capacity-bonus-6",
		"inserter-capacity-bonus-7",
	},
	["progressive-laser-shooting-speed"] = {
		"laser-shooting-speed-1",
		"laser-shooting-speed-2",
		"laser-shooting-speed-3",
		"laser-shooting-speed-4",
		"laser-shooting-speed-5",
		"laser-shooting-speed-6",
		"laser-shooting-speed-7",
	},
	["progressive-laser-weapons-damage"] = {
		"laser-weapons-damage-1",
		"laser-weapons-damage-2",
		"laser-weapons-damage-3",
		"laser-weapons-damage-4",
		"laser-weapons-damage-5",
		"laser-weapons-damage-6",
	},
	["progressive-logistics"] = { "logistics", "logistics-2", "logistics-3" },
	["progressive-military"] = { "military", "military-2", "military-3", "military-4" },
	["progressive-mining-productivity"] = { "mining-productivity-1", "mining-productivity-2", "mining-productivity-3" },
	["progressive-personal-battery"] = { "battery-equipment", "battery-mk2-equipment" },
	["progressive-personal-roboport-equipment"] = { "personal-roboport-equipment", "personal-roboport-mk2-equipment" },
	["progressive-physical-projectile-damage"] = {
		"physical-projectile-damage-1",
		"physical-projectile-damage-2",
		"physical-projectile-damage-3",
		"physical-projectile-damage-4",
		"physical-projectile-damage-5",
		"physical-projectile-damage-6",
	},
	["progressive-processing"] = {
		"steel-processing",
		"oil-processing",
		"sulfur-processing",
		"advanced-oil-processing",
		"coal-liquefaction",
		"uranium-processing",
		"kovarex-enrichment-process",
		"nuclear-fuel-reprocessing",
	},
	["progressive-productivity-module"] = { "productivity-module", "productivity-module-2", "productivity-module-3" },
	["progressive-refined-flammables"] = {
		"refined-flammables-1",
		"refined-flammables-2",
		"refined-flammables-3",
		"refined-flammables-4",
		"refined-flammables-5",
		"refined-flammables-6",
	},
	["progressive-research-speed"] = {
		"research-speed-1",
		"research-speed-2",
		"research-speed-3",
		"research-speed-4",
		"research-speed-5",
		"research-speed-6",
	},
	["progressive-rocketry"] = { "rocketry", "explosive-rocketry", "atomic-bomb" },
	["progressive-science-pack"] = {
		"logistic-science-pack",
		"military-science-pack",
		"chemical-science-pack",
		"production-science-pack",
		"utility-science-pack",
		"space-science-pack",
	},
	["progressive-speed-module"] = { "speed-module", "speed-module-2", "speed-module-3" },
	["progressive-stronger-explosives"] = {
		"stronger-explosives-1",
		"stronger-explosives-2",
		"stronger-explosives-3",
		"stronger-explosives-4",
		"stronger-explosives-5",
		"stronger-explosives-6",
	},
	["progressive-train-network"] = {
		"railway",
		"automated-rail-transportation",
		"braking-force-1",
		"braking-force-2",
		"braking-force-3",
		"braking-force-4",
		"braking-force-5",
		"braking-force-6",
		"braking-force-7",
	},
	["progressive-turret"] = { "gun-turret", "laser-turret" },
	["progressive-vehicle"] = { "automobilism", "tank", "spidertron" },
	["progressive-wall"] = { "stone-wall", "gate" },
	["progressive-weapon-shooting-speed"] = {
		"weapon-shooting-speed-1",
		"weapon-shooting-speed-2",
		"weapon-shooting-speed-3",
		"weapon-shooting-speed-4",
		"weapon-shooting-speed-5",
		"weapon-shooting-speed-6",
	},
	["progressive-worker-robots-speed"] = {
		"worker-robots-speed-1",
		"worker-robots-speed-2",
		"worker-robots-speed-3",
		"worker-robots-speed-4",
		"worker-robots-speed-5",
	},
	["progressive-worker-robots-storage"] = {
		"worker-robots-storage-1",
		"worker-robots-storage-2",
		"worker-robots-storage-3",
	},
}

local m = {}
---@param force LuaForce
m.research_progressive_tech = function(key, force)
	local tech_stack = progressive_technologies[key]
	for _, tech in ipairs(tech_stack) do
		local personal = force.name .. "-" .. tech
		tech = force.technologies[personal] and personal or tech

		if not force.technologies[tech].researched then
			force.technologies[tech].researched = true
			return tech
		end
	end

	print("Requested unavailable technology level for " .. key)
end

return m
