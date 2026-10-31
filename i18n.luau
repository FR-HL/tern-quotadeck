-- English and Simplified Chinese labels for the Quota surfaces.

local i18n = {}

local strings = {
	en = {
		providers = "Providers",
		overview = "Overview",
		all = "All",
		context = "Context",
		context_hint = "Read from each agent's own recent session logs.",
		context_unknown_model = "model unknown",
		context_tokens = "tokens",
		custom = "Custom",
		custom_hint = "Auto-detected from Magpie and installed CLIs. Add an endpoint only for a relay that is not listed.",
		add_custom = "Add endpoint",
		add_new_api = "New API relay",
		add_openai_billing = "OpenAI billing",
		auto = "Auto",
		relay_added = "Endpoint added",






		no_relays = "No custom endpoints.",
		remove = "Remove",
		settings = "Settings",
		normal = "Normal",
		auth = "Sign-in expired",
		signed_out = "Not signed in",
		unavailable = "Unavailable",
		no_providers = "No signed-in providers.",
		open_as = "Open as",
		status_bar = "Status line",
		status_quota = "Value",
		status_names = "Names",
		short_names = "Short codes",
		full_names = "Full names",
		hidden_names = "Hidden",
		icon = "Icon",
		remaining = "Left",
		used = "Used",
		window = "Window",
		reset = "Countdown",
		percent = "Percent",
		speed = "Speed",
		status_show = "Show",
		down_color = "Download",
		up_color = "Upload",
		green = "Green",
		red = "Red",
		yellow = "Yellow",
		blue = "Blue",
		orange = "Orange",
		gray = "Gray",
		white = "White",
		open_tab = "Tab",
		open_dock = "Docked",
		open_float = "Floating",
		language = "Language",
		auto = "Auto",
		english = "English",
		chinese = "中文",
		refresh = "Refresh",
		minute1 = "1 minute",
		minute2 = "2 minutes",
		minute5 = "5 minutes",
		no_usage = "No usage data",
		show = "Show",
		set_key = "Key",
		sign_in = "Sign in",
		hide_hint = "The grid icon hides a provider from the overview; the gauge icon hides it from the status bar. Neither signs you out.",
		hide_overview = "Hide from overview",
		show_overview = "Show in overview",
		hide_status = "Hide from status bar",
		show_status = "Show in status bar",
		window_5h = "5 hours",
		window_7d = "7 days",
		window_month = "Monthly",
		window_premium = "Premium requests",
		window_chat = "Chat",
		window_completions = "Completions",
		window_included = "Included",
		window_api = "API",
		window_quota = "Quota",
	},
	zh = {
		providers = "服务商",
		overview = "概览",
		all = "全部",
		context = "上下文",
		context_hint = "读取每个 Agent 自己最近的会话记录。",
		context_unknown_model = "模型未知",
		context_tokens = "tokens",
		custom = "自定义",
		custom_hint = "自动读取 Magpie 和已安装 CLI；只有列表里没有的中转站才需要自定义。",
		add_custom = "添加接口",
		add_new_api = "New API 中转",
		add_openai_billing = "OpenAI 账单",
		auto = "自动识别",
		relay_added = "接口已添加",






		no_relays = "还没有自定义接口。",
		remove = "移除",
		settings = "设置",
		normal = "正常",
		auth = "登录失效",
		signed_out = "未登录",
		unavailable = "不可用",
		no_providers = "没有已登录的服务商。",
		open_as = "打开方式",
		status_bar = "状态栏",
		status_quota = "数值",
		status_names = "名称",
		short_names = "短代码",
		full_names = "完整名称",
		hidden_names = "隐藏",
		icon = "图标",
		remaining = "剩余",
		used = "已用",
		window = "窗口",
		reset = "倒计时",
		percent = "百分比",
		speed = "网速",
		status_show = "显示",
		down_color = "下载颜色",
		up_color = "上传颜色",
		green = "绿",
		red = "红",
		yellow = "黄",
		blue = "蓝",
		orange = "橙",
		gray = "灰",
		white = "白",
		open_tab = "标签页",
		open_dock = "停靠",
		open_float = "浮动",
		language = "语言",
		auto = "自动",
		english = "English",
		chinese = "中文",
		refresh = "刷新",
		minute1 = "1 分钟",
		minute2 = "2 分钟",
		minute5 = "5 分钟",
		no_usage = "暂无用量数据",
		show = "显示",
		set_key = "密钥",
		sign_in = "登录",
		hide_hint = "网格图标只控制概览，仪表图标只控制状态栏；两者都不会注销账号。",
		hide_overview = "从概览隐藏",
		show_overview = "在概览显示",
		hide_status = "从状态栏隐藏",
		show_status = "在状态栏显示",
		window_5h = "5 小时",
		window_7d = "7 天",
		window_month = "月",
		window_premium = "高级请求",
		window_chat = "聊天",
		window_completions = "代码补全",
		window_included = "包含额度",
		window_api = "API",
		window_quota = "额度",
	},
}

local label_keys = {
	["5 hours"] = "window_5h",
	["7 days"] = "window_7d",
	["Monthly"] = "window_month",
	["Premium requests"] = "window_premium",
	["Chat"] = "window_chat",
	["Completions"] = "window_completions",
	["Included"] = "window_included",
	["API"] = "window_api",
	["Quota"] = "window_quota",
}

function i18n.resolve(setting: any): string
	if setting == "zh" or setting == "en" then
		return setting
	end
	local env = (tern.getenv("LANG") or tern.getenv("LC_ALL") or ""):lower()
	if env:find("zh", 1, true) then
		return "zh"
	end
	return "en"
end

function i18n.t(lang: string, key: string): string
	local table_ = strings[lang] or strings.en
	return table_[key] or strings.en[key] or key
end

function i18n.window_label(lang: string, label: string?): string
	if type(label) ~= "string" then
		return ""
	end
	local key = label_keys[label]
	return key and i18n.t(lang, key) or label
end

return i18n
