-- This file needs to have same structure as nvconfig.lua 
-- https://github.com/NvChad/ui/blob/v2.5/lua/nvconfig.lua

---@type ChadrcConfig
local M = {}

M.base46 = {
	theme = "onedark",
	hl_override = {
		-- YAML: make values pop instead of falling through to Normal
		["@property.yaml"] = { link = "Keyword" },
		["@string.yaml"] = { link = "String" },
		["@number.yaml"] = { link = "Number" },
		["@boolean.yaml"] = { link = "Boolean" },
		["@constant.builtin.yaml"] = { link = "Constant" },
		["@punctuation.special.yaml"] = { link = "Special" },
		["@punctuation.delimiter.yaml"] = { link = "Delimiter" },
		["@tag.yaml"] = { link = "Type" },
		["@string.escape.yaml"] = { link = "SpecialChar" },
	},
}

M.ui = {
	statusline = {
		separator_style = { left = "", right = "" },
		order = { "mode", "file", "git", "%=", "lsp_msg", "metals", "%=", "diagnostics", "lsp", "cwd", "cursor" },
		modules = {
			metals = function()
				local status = vim.g["metals_status"]
				if status == nil or status == "" then
					return ""
				end
				return "%#St_LspMsg# " .. status .. " "
			end,
		},
	},
}

return M

-- Global vim options
vim.opt.backspace = "indent,eol,start"
vim.opt.equalalways = false
