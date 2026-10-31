-- Shared helpers for context adapters. Each adapter reads its agent's own
-- session log; nothing here depends on a proxy or a vendor quota endpoint.

local util = {}

function util.home(): string
	return tern.getenv("USERPROFILE") or tern.getenv("HOME") or ""
end

-- Returns up to limit newest *.jsonl files under root, with first and last
-- lines of each. Every record is { path, head, tail }.
function util.recent(root: string, limit: number, done: (any) -> ())
	limit = math.max(1, limit or 1)
	local command
	if tern.runtime.os == "windows" then
		local quoted = root:gsub("'", "''")
		command = {
			"powershell",
			"-NoProfile",
			"-Command",
			"$files = Get-ChildItem -LiteralPath '" .. quoted .. "' -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First " .. limit
				.. "; foreach ($f in $files) { Write-Output ('__FILE__' + $f.FullName); Write-Output ('__HEAD__' + (Get-Content -LiteralPath $f.FullName -TotalCount 1)); Get-Content -LiteralPath $f.FullName -Tail 40 }",
		}
	else
		command = {
			"sh",
			"-c",
			'find "$1" -type f -name "*.jsonl" -exec ls -t {} + 2>/dev/null | head -n "$2" | while IFS= read -r f; do echo "__FILE__$f"; echo "__HEAD__$(head -n 1 "$f")"; tail -n 40 "$f"; done',
			"sh",
			root,
			tostring(limit),
		}
	end
	tern.process.run(command, { timeout_ms = 15_000 }, function(result)
		if not result or result.status ~= 0 or type(result.stdout) ~= "string" then
			done({})
			return
		end
		local files = {}
		local current = nil
		for line in result.stdout:gmatch("[^\r\n]+") do
			if line:sub(1, 8) == "__FILE__" then
				if current then
					files[#files + 1] = current
				end
				current = { path = line:sub(9), head = nil, lines = {} }
			elseif current and not current.head and line:sub(1, 8) == "__HEAD__" then
				current.head = line:sub(9)
			elseif current then
				current.lines[#current.lines + 1] = line
			end
		end
		if current then
			files[#files + 1] = current
		end
		for _, file in ipairs(files) do
			file.tail = table.concat(file.lines, "\n")
			file.lines = nil
		end
		done(files)
	end)
end

function util.latest(root: string, done: (string?, string?, string?) -> ())
	util.recent(root, 1, function(files)
		local file = files[1]
		if file then
			done(file.path, file.tail, file.head)
		else
			done(nil, nil, nil)
		end
	end)
end

function util.first(path: string): string?
	local ok, text = pcall(tern.fs.read, path, 65_536)
	if ok and type(text) == "string" then
		return text
	end
	return nil
end

function util.cwd_of(text: string?): string?
	if type(text) ~= "string" then
		return nil
	end
	for line in text:gmatch("[^\r\n]+") do
		local ok, value = pcall(tern.json.decode, line)
		if ok and type(value) == "table" and type(value.cwd) == "string" then
			return value.cwd
		end
	end
	local cwd = text:match('"cwd"%s*:%s*"([^"]+)"')
	if cwd then
		return (cwd:gsub("\\\\", "\\"):gsub("\\/", "/"))
	end
	return nil
end

function util.project_of(cwd: string?): string?
	if type(cwd) ~= "string" or cwd == "" then
		return nil
	end
	local name = cwd:match("([^/\\]+)[/\\]*$")
	return name or cwd
end

function util.project_from_path(path: string?): string?
	if type(path) ~= "string" then
		return nil
	end
	local dir = path:match("([^/\\]+)[/\\][^/\\]+$")
	if not dir then
		return nil
	end
	dir = dir:gsub("^%-%-", ""):gsub("%-%-$", "")
	dir = dir:gsub("^(%a)%-%-", "%1:\\"):gsub("%-", "\\")
	return dir:match("([^/\\]+)$") or dir
end

function util.decode(line: string): any?
	local ok, value = pcall(tern.json.decode, line)
	if ok and type(value) == "table" then
		return value
	end
	return nil
end

function util.compact(value: number): string
	if value >= 1_000_000 then
		return string.format("%.1fM", value / 1_000_000)
	elseif value >= 1_000 then
		return string.format("%.0fK", value / 1_000)
	end
	return string.format("%.0f", value)
end

return util
