-- omp writes contextSnapshot.promptTokens in its own session log.

local util = require("./util")
local models = require("./models")

local adapter = {
	api = 1,
	id = "omp",
	name = "omp",
	icon = "app-omp",
}

local function windows(): { [string]: number }
	local out = {}
	local ok, text = pcall(tern.fs.read, util.home() .. "/.omp/agent/models.yml", 4_000_000)
	if not ok or type(text) ~= "string" then
		return out
	end
	for window, id in text:gmatch("contextWindow:%s*(%d+)[^\r\n]*[\r\n]+%s*id:%s*([^\r\n]+)") do
		out[id:gsub("%s+$", "")] = tonumber(window)
	end
	for id, window in text:gmatch("id:%s*([^\r\n]+)[^\r\n]*[\r\n]+%s*contextWindow:%s*(%d+)") do
		out[id:gsub("%s+$", "")] = tonumber(window)
	end
	return out
end

function adapter.fetch(done: (any) -> ())
	util.latest(util.home() .. "/.omp/agent/sessions", function(path, tail, head)
		if not path or not tail then
			done({})
			return
		end
		local used, model, at
		for line in tail:gmatch("[^\r\n]+") do
			local value = util.decode(line)
			local message = type(value) == "table" and value.message or nil
			local snapshot = type(message) == "table" and message.contextSnapshot or nil
			if type(snapshot) == "table" and type(snapshot.promptTokens) == "number" then
				used = snapshot.promptTokens
				model = message.model
				at = message.timestamp or value.timestamp
			end
		end
		if not used then
			done({})
			return
		end
		local cwd = util.cwd_of(head or tail)
		local window = model and (windows()[model] or models.window(model)) or nil
		done({
			{
				agent = adapter.name,
				icon = adapter.icon,
				project = util.project_of(cwd) or util.project_from_path(path),
				model = model,
				used = used,
				window = window,
				at = at,
			},
		})
	end)
end

return adapter
