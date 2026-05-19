require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- GitHub sidebar
require("configs.gh-sidebar").setup()
map("n", "<leader>gs", "<cmd>GhSidebar<cr>", { desc = "Toggle GitHub sidebar" })
map("n", "<leader>gc", function() require("configs.codespaces").toggle() end, { desc = "Toggle Codespaces panel" })
map("n", "<leader>gt", function() require("configs.codespaces").terminal() end, { desc = "Codespace terminal" })
require("configs.codespaces") -- register :Codespace command

-- Window resize (Alt + arrow keys)
map("n", "<A-Up>", "<cmd>resize +3<cr>", { desc = "Increase height" })
map("n", "<A-Down>", "<cmd>resize -3<cr>", { desc = "Decrease height" })
map("n", "<A-Right>", "<cmd>vertical resize +5<cr>", { desc = "Increase width" })
map("n", "<A-Left>", "<cmd>vertical resize -5<cr>", { desc = "Decrease width" })
-- Fallback escape sequences for Ghostty
map("n", "<M-Up>", "<cmd>resize +3<cr>", { desc = "Increase height" })
map("n", "<M-Down>", "<cmd>resize -3<cr>", { desc = "Decrease height" })
map("n", "<M-Right>", "<cmd>vertical resize +5<cr>", { desc = "Increase width" })
map("n", "<M-Left>", "<cmd>vertical resize -5<cr>", { desc = "Decrease width" })

-- Quick equalize all splits
map("n", "<leader>w=", "<C-w>=", { desc = "Equalize splits" })

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")

-- Smart Telescope: use remote SSH search when on a codespace mount, normal otherwise
map("n", "<leader>ff", function()
  local cs = require("configs.codespaces")
  if cs.is_on_codespace() then
    cs.remote_find_files()
  else
    require("telescope.builtin").find_files()
  end
end, { desc = "Find files (remote-aware)" })

map("n", "<leader>fw", function()
  local cs = require("configs.codespaces")
  if cs.is_on_codespace() then
    cs.remote_live_grep()
  else
    require("telescope.builtin").live_grep()
  end
end, { desc = "Live grep (remote-aware)" })
