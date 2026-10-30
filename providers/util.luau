-- Shared helpers for provider adapters (host half).

local util = {}

function util.home(): string
	return tern.getenv("USERPROFILE") or tern.getenv("HOME") or ""
end

function util.data_dir(): string
	local xdg = tern.getenv("XDG_DATA_HOME")
	if xdg and xdg ~= "" then
		return xdg
	end
	return util.home() .. "/.local/share"
end

function util.read_json(path: string): any?
	local ok, text = pcall(tern.fs.read, path, 65_536)
	if not ok or type(text) ~= "string" then
		return nil
	end
	local decoded, value = pcall(tern.json.decode, text)
	if not decoded then
		return nil
	end
	return value
end

function util.fetch_json(url: string, opts: any, done: (any?, string?, number?) -> ())
	tern.fetch(url, opts, function(res)
		if res.error then
			done(nil, res.error, 0)
			return
		end
		if res.status ~= 200 then
			done(nil, "HTTP " .. tostring(res.status), res.status)
			return
		end
		local ok, value = pcall(tern.json.decode, res.body)
		if not ok then
			done(nil, "invalid JSON", res.status)
			return
		end
		done(value, nil, res.status)
	end)
end

function util.remaining(used: number): number
	local value = 100 - used
	if value < 0 then
		return 0
	elseif value > 100 then
		return 100
	end
	return value
end

function util.from_epoch_ms(ms: any): string?
	if type(ms) ~= "number" or ms <= 0 then
		return nil
	end
	return os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(ms / 1000))
end

return util
