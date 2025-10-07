-- grab string from global, run it here to avoid fucking up our own scope
print("Loaded Dummy")
local _current_module = _G.current_module
_G.current_module = nil
local _ = load(_current_module)()
