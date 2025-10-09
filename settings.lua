data:extend({
	{
		type = "string-setting",
		name = "spoilers",
		setting_type = "startup",
		default_value = "Enter Here",
	},
	{
		type = "int-setting",
		name = "death-percent",
		default_value = 70,
		setting_type = "runtime-global",
		minimum_value = 0,
		maximum_value = 100,
	},
})
