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

      nvchad_opts.filesystem_watchers = {
        enable = true,
        debounce_delay = 50,
        ignore_dirs = { "node_modules", ".git", "__pycache__", ".venv", "target", "dist", "build" },
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
        vim.keymap.set("n", "+", api.tree.change_root_to_node, { buffer = bufnr, desc = "CD into dir" })
      end

      require("nvim-tree").setup(nvchad_opts)

      -- Fallback refresh for cases fs_event misses (codespaces/SSHFS, agent edits)
      vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter" }, {
        callback = function()
          local ok_view, view = pcall(require, "nvim-tree.view")
          if ok_view and view.is_visible() then
            require("nvim-tree.api").tree.reload()
          end
        end,
      })
    end,
  },
  {
    "stevearc/conform.nvim",
    -- event = 'BufWritePre', -- uncomment for format on save
    opts = require "configs.conform",
  },

  -- JSON/YAML schema catalog
  { "b0o/schemastore.nvim", lazy = true },

  -- Scala: nvim-metals manages the Metals LSP (install via :MetalsInstall)
  {
    "scalameta/nvim-metals",
    dependencies = { "nvim-lua/plenary.nvim" },
    ft = { "scala", "sbt", "java" },
    opts = function()
      local metals = require("metals")
      local nvlsp = require("nvchad.configs.lspconfig")

      local config = metals.bare_config()

      config.settings = {
        showImplicitArguments = true,
        excludedPackages = {
          "akka.actor.typed.javadsl",
          "com.github.swagger.akka.javadsl",
        },
        inlayHints = {
          inferredTypes = { enable = true },
          typeParameters = { enable = true },
          hintsInPatternMatch = { enable = true },
        },
        serverVersion = "latest.stable",
      }

      config.init_options.statusBarProvider = "on"
      config.capabilities = nvlsp.capabilities

      config.on_attach = function(client, bufnr)
        nvlsp.on_attach(client, bufnr)
        local map = function(lhs, rhs, desc)
          vim.keymap.set("n", lhs, rhs, { buffer = bufnr, desc = desc })
        end
        map("<leader>mc", function() require("metals").commands() end, "Metals commands")
        map("<leader>mh", function() require("metals").hover_worksheet() end, "Metals hover worksheet")
        map("<leader>mi", function() require("metals").info() end, "Metals info")
        map("<leader>mt", function() require("metals.tvp").toggle_tree_view() end, "Metals tree view")
        map("<leader>mR", function() require("metals").restart_build_server() end, "Metals restart build server")
      end

      return config
    end,
    config = function(_, metals_config)
      local group = vim.api.nvim_create_augroup("nvim-metals", { clear = true })
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "scala", "sbt", "java" },
        callback = function()
          require("metals").initialize_or_attach(metals_config)
        end,
        group = group,
      })
    end,
  },

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
        "jdtls",
        -- "metals" is installed by nvim-metals (Coursier), not Mason
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
    "Ramilito/kubectl.nvim",
    version = "2.*",
    dependencies = { "saghen/blink.download" },
    cmd = { "Kubectl", "Kubens", "Kubectx" },
    keys = {
      { "<leader>k", function() require("kubectl").toggle() end, desc = "Kubectl toggle" },
    },
    config = function()
      require("kubectl").setup()
    end,
  },
}
