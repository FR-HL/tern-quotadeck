-- Context windows for agents whose session log does not carry one. Users can
-- override or extend this in models.json beside plugin.toml.

local models = {}

local builtin = {
	["deepseek-v4.1-flash"] = 1_000_000,
	["deepseek-v4-pro"] = 1_000_000,
	["claude-haiku-5.5"] = 1_000_000,
	["glm-5.3"] = 1_000_000,
	["glm-5.3-flash"] = 1_000_000,
}

local function normalize(model: string): string
	local name = model:gsub("^[^/]+/", "")
	return name:lower()
end

function models.window(model: string?): number?
	if type(model) ~= "string" or model == "" then
		return nil
	end
	local overrides = {}
	local ok, text = pcall(tern.fs.read, tern.plugin.dir .. "/models.json", 65_536)
	if ok and type(text) == "string" then
		local decoded, value = pcall(tern.json.decode, text)
		if decoded and type(value) == "table" then
			overrides = value
		end
	end
	local exact = overrides[model]
	if type(exact) == "number" and exact > 0 then
		return exact
	end
	local key = normalize(model)
	local override = overrides[key]
	if type(override) == "number" and override > 0 then
		return override
	end
	return builtin[key]
end

return models
