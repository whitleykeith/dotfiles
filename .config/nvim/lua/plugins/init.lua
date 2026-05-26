return {
  {
    "nvim-tree/nvim-tree.lua",
    config = function()
      local api = require("nvim-tree.api")
      local nvchad_opts = require("nvchad.configs.nvimtree")

      nvchad_opts.view.width = 35
      nvchad_opts.actions = {
        open_file = {
          quit_on_open = false,
          resize_window = false,
          window_picker = { enable = true },
        },
      }

      local preview_buf, preview_win
      local function close_preview()
        if preview_win and vim.api.nvim_win_is_valid(preview_win) then
          vim.api.nvim_win_close(preview_win, true)
        end
        if preview_buf and vim.api.nvim_buf_is_valid(preview_buf) then
          vim.api.nvim_buf_delete(preview_buf, { force = true })
        end
        preview_buf, preview_win = nil, nil
      end

      local function preview_file()
        local node = api.tree.get_node_under_cursor()
        if not node or node.nodes then return end
        close_preview()
        local filepath = node.absolute_path
        local lines = vim.fn.readfile(filepath, "", 200)
        preview_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines)
        local ft = vim.filetype.match({ filename = filepath }) or ""
        if ft ~= "" then vim.bo[preview_buf].filetype = ft end
        vim.bo[preview_buf].modifiable = false
        local tree_width = vim.api.nvim_win_get_width(0)
        local width = math.floor(vim.o.columns * 0.5)
        local height = math.floor(vim.o.lines * 0.7)
        preview_win = vim.api.nvim_open_win(preview_buf, false, {
          relative = "editor",
          width = width,
          height = height,
          col = tree_width + 1,
          row = 2,
          style = "minimal",
          border = "rounded",
        })
      end

      nvchad_opts.on_attach = function(bufnr)
        api.config.mappings.default_on_attach(bufnr)
        vim.keymap.set("n", "<Tab>", preview_file, { buffer = bufnr, desc = "Preview file (float)" })
        vim.keymap.set("n", "q", close_preview, { buffer = bufnr, desc = "Close preview" })
      end

      require("nvim-tree").setup(nvchad_opts)
    end,
  },
  {
    "stevearc/conform.nvim",
    -- event = 'BufWritePre', -- uncomment for format on save
    opts = require "configs.conform",
  },

  -- JSON/YAML schema catalog
  { "b0o/schemastore.nvim", lazy = true },

  {
    "williamboman/mason.nvim",
    opts = {},
  },
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "mason.nvim", "neovim/nvim-lspconfig" },
    opts = {
      ensure_installed = {
        -- Languages
        "gopls",
        "solargraph",
        "pyright",
        "ts_ls",
        "kotlin_language_server",
        "lua_ls",
        "html",
        "cssls",
        "bashls",
        -- Infrastructure / Config
        "yamlls",
        "jsonls",
        "dockerls",
        "docker_compose_language_service",
        "terraformls",
        "helm_ls",
        "taplo",
        "sqls",
        "buf_ls",
      },
      automatic_installation = true,
    },
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
  {
    "hrsh7th/nvim-cmp",
    opts = function(_, opts)
      local cmp = require("cmp")
      -- Remove Tab/S-Tab from cmp — let Copilot own Tab
      opts.mapping["<Tab>"] = nil
      opts.mapping["<S-Tab>"] = nil
      -- Use C-n/C-p for cmp cycling instead
      opts.mapping["<C-n>"] = cmp.mapping.select_next_item()
      opts.mapping["<C-p>"] = cmp.mapping.select_prev_item()
    end,
  },
  {
    "github/copilot.vim",
    event = "InsertEnter",
    config = function()
      vim.g.copilot_no_tab_map = true
      vim.keymap.set("i", "<Tab>", function()
        if vim.fn["copilot#GetDisplayedSuggestion"]().text ~= "" then
          return vim.fn["copilot#Accept"]("")
        else
          return vim.api.nvim_replace_termcodes("<Tab>", true, false, true)
        end
      end, { expr = true, silent = true, replace_keycodes = false })
      vim.keymap.set("i", "<C-]>", "<Plug>(copilot-next)", { silent = true })
      vim.keymap.set("i", "<C-\\>", "<Plug>(copilot-dismiss)", { silent = true })
    end,
  },
  {
    "Pocco81/auto-save.nvim",
    event = { "InsertLeave", "TextChanged" },
    opts = {
      debounce_delay = 2000,
      condition = function(buf)
        -- Skip special buffers, nvim-tree, help, etc.
        local buftype = vim.fn.getbufvar(buf, "&buftype")
        local filetype = vim.fn.getbufvar(buf, "&filetype")
        if buftype ~= "" then return false end
        if vim.tbl_contains({ "NvimTree", "oil", "harpoon", "octo" }, filetype) then return false end
        return true
      end,
    },
    keys = {
      { "<leader>ta", "<cmd>ASToggle<cr>", desc = "Toggle auto-save" },
    },
  },
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    dependencies = { "github/copilot.vim", "nvim-lua/plenary.nvim" },
    cmd = { "CopilotChat", "CopilotChatOpen", "CopilotChatToggle" },
    opts = {
      model = "claude-opus-4.6-1m",
      agent = "copilot",
      window = {
        layout = "vertical",
        width = 0.3,
      },
    },
    keys = {
      { "<leader>cc", "<cmd>CopilotChatToggle<cr>", desc = "Copilot Chat toggle" },
      { "<leader>ce", "<cmd>CopilotChatExplain<cr>", mode = "v", desc = "Copilot explain selection" },
      { "<leader>cf", "<cmd>CopilotChatFix<cr>", mode = "v", desc = "Copilot fix selection" },
      { "<leader>cr", "<cmd>CopilotChatReview<cr>", mode = "v", desc = "Copilot review selection" },
      { "<leader>ct", "<cmd>CopilotChatTests<cr>", mode = "v", desc = "Copilot generate tests" },
    },
  },
  {
    "chrishrb/gx.nvim",
    keys = { { "gx", "<cmd>Browse<cr>", mode = { "n", "x" }, desc = "Open URL under cursor" } },
    cmd = { "Browse" },
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = function()
      -- In codespaces/SSH there's no xdg-open; print URL to yank instead
      local open_cmd = nil
      if vim.fn.has("mac") == 1 then
        open_cmd = "open"
      elseif vim.fn.executable("xdg-open") == 1 then
        open_cmd = "xdg-open"
      end

      return {
        open_browser_app = open_cmd,
        handler_options = {
          search_engine = "https://search.brave.com/search?q=",
        },
        handlers = {
          -- Fallback: copy URL to clipboard when no browser available
          brewfile = false,
          search = open_cmd and true or {
            name = "copy url",
            handle = function(_, url)
              vim.fn.setreg("+", url)
              vim.notify("Copied: " .. url, vim.log.levels.INFO)
            end,
          },
        },
      }
    end,
  },
  {
    "r-pletnev/pdfreader.nvim",
    ft = "pdf",
    dependencies = {
      "nvim-telescope/telescope.nvim",
      { "folke/snacks.nvim", opts = { image = { enabled = true } } },
    },
    opts = {
      reading_mode = "dark",
    },
  },
}
