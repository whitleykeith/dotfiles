require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- GitHub sidebar
require("configs.gh-sidebar").setup()
map("n", "<leader>gs", "<cmd>GhSidebar<cr>", { desc = "Toggle GitHub sidebar" })
map("n", "<leader>gc", function() require("configs.codespaces").toggle() end, { desc = "Toggle Codespaces panel" })

-- Window resize (Alt + arrow keys)
map("n", "<A-Up>", "<cmd>resize +3<cr>", { desc = "Increase height" })
map("n", "<A-Down>", "<cmd>resize -3<cr>", { desc = "Decrease height" })
map("n", "<A-Right>", "<cmd>vertical resize +5<cr>", { desc = "Increase width" })
map("n", "<A-Left>", "<cmd>vertical resize -5<cr>", { desc = "Decrease width" })

-- Quick equalize all splits
map("n", "<leader>w=", "<C-w>=", { desc = "Equalize splits" })

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")
