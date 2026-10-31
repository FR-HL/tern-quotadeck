-- Claude Code records each assistant message's usage in its project JSONL.

local util = require("./util")
local models = require("./models")

local adapter = {
	api = 1,
	id = "claude",
	name = "Claude Code",
	icon = "app-claude",
}

function adapter.fetch(done: (any) -> ())
	util.latest(util.home() .. "/.claude/projects", function(path, tail, head)
		if not path or not tail then
			done({})
			return
		end
		local used, model, at
		for line in tail:gmatch("[^\r\n]+") do
			local value = util.decode(line)
			local message = type(value) == "table" and value.message or nil
			local usage = type(message) == "table" and message.usage or nil
			if type(usage) == "table" and type(usage.input_tokens) == "number" then
				used = usage.input_tokens
					+ (tonumber(usage.cache_read_input_tokens) or 0)
					+ (tonumber(usage.cache_creation_input_tokens) or 0)
				model = message.model
				at = message.timestamp or value.timestamp
			end
		end
		if not used then
			done({})
			return
		end
		local cwd = util.cwd_of(head) or util.cwd_of(tail)
		done({
			{
				agent = adapter.name,
				icon = adapter.icon,
				provider = "claude",
				project = util.project_of(cwd) or util.project_from_path(path),
				model = model,
				used = used,
				window = models.window(model),
				at = at,
			},
		})
	end)
end

return adapter
