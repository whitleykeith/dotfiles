return {
  {
    "stevearc/conform.nvim",
    -- event = 'BufWritePre', -- uncomment for format on save
    opts = require "configs.conform",
  },

  -- These are some examples, uncomment them if you want to see them work!
  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },
  {
    "pwntester/octo.nvim",
    cmd = "Octo",
    opts = {
      -- or "fzf-lua" or "snacks" or "default"
      picker = "telescope",
      -- bare Octo command opens picker of commands
      enable_builtin = true,
    },
    keys = {
      {
        "<leader>oi",
        "<CMD>Octo issue list<CR>",
        desc = "List GitHub Issues",
      },
      {
        "<leader>op",
        "<CMD>Octo pr list<CR>",
        desc = "List GitHub PullRequests",
      },
      {
        "<leader>od",
        "<CMD>Octo discussion list<CR>",
        desc = "List GitHub Discussions",
      },
      {
        "<leader>on",
        "<CMD>Octo notification list<CR>",
        desc = "List GitHub Notifications",
      },
      {
        "<leader>os",
        function()
          require("octo.utils").create_base_search_command { include_current_repo = true }
        end,
        desc = "Search GitHub",
      },
    },
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
      -- OR "ibhagwan/fzf-lua",
      -- OR "folke/snacks.nvim",
      "nvim-tree/nvim-web-devicons",
    },
  },
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown", "octo" },
    opts = {
      file_types = { "markdown", "octo" },
      render_modes = { "n", "c", "t" },
      anti_conceal = { enabled = false },
    },
    config = function(_, opts)
      require("render-markdown").setup(opts)
      -- Ensure conceallevel is set for octo buffers
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "markdown", "octo" },
        callback = function()
          vim.opt_local.conceallevel = 2
        end,
      })
    end,
    keys = {
      { "<leader>mr", "<cmd>RenderMarkdown toggle<cr>", desc = "Toggle markdown render" },
    },
  },
  {
    "folke/persistence.nvim",
    event = "VimEnter",
    opts = {},
    config = function(_, opts)
      require("persistence").setup(opts)
      vim.api.nvim_create_autocmd("SessionLoadPost", {
        callback = function()
          pcall(require("nvim-tree.api").tree.open)
          vim.defer_fn(function()
            pcall(require("configs.gh-sidebar").open)
          end, 1000)
        end,
      })
    end,
    keys = {
      { "<leader>qs", function() require("persistence").load() end, desc = "Restore session" },
      { "<leader>ql", function() require("persistence").load({ last = true }) end, desc = "Restore last session" },
      { "<leader>qd", function() require("persistence").stop() end, desc = "Stop session save" },
    },
  },
  {
    "sindrets/winshift.nvim",
    cmd = "WinShift",
    opts = {},
    keys = {
      { "<leader>wm", "<cmd>WinShift<cr>", desc = "Win shift mode" },
      { "<leader>ws", "<cmd>WinShift swap<cr>", desc = "Win shift swap" },
    },
  },
}
