local M = {}

-- State
local buf = nil
local win = nil
local data = {}
local loading = false
local width = 45
local mount_base = vim.fn.expand("~/codespaces")
local active_mounts = {} -- cs.name -> mount_path
local active_ssh = nil   -- { host = "cs.xxx", remote_dir = "/workspaces/repo", mount_path = "..." }
local file_cache = nil   -- cached file list for Telescope find_files
local file_cache_updating = false

-- Disable heavy filesystem features for SSHFS-mounted buffers
vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
  pattern = mount_base .. "/*",
  callback = function()
    vim.bo.swapfile = false
    vim.bo.undofile = false
    -- Treesitter folding (syntax-aware, no filesystem calls)
    vim.wo.foldmethod = "expr"
    vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
    vim.wo.foldlevel = 99  -- start with all folds open
    -- Prevent gitsigns from attaching and satisfy NvChad statusline guard
    vim.b.gitsigns_head = nil
    vim.b.gitsigns_status_dict = nil
    vim.b.gitsigns_git_status = nil
    vim.b.disable_gitsigns = true
  end,
})
vim.api.nvim_create_autocmd("BufReadPost", {
  pattern = mount_base .. "/*",
  callback = function()
    pcall(function() require("gitsigns").detach() end)
  end,
})

-- Icons
local icons = {
  active = "●",
  shutdown = "○",
  rebuilding = "⟳",
  starting = "◐",
  dirty = "✱",
  branch = "",
  repo = "",
  create = "",
}

-- Forward declarations
local render

-- Highlight groups
local function setup_highlights()
  vim.api.nvim_set_hl(0, "CsHeader", { fg = "#c678dd", bold = true })
  vim.api.nvim_set_hl(0, "CsActive", { fg = "#98c379" })
  vim.api.nvim_set_hl(0, "CsShutdown", { fg = "#5c6370" })
  vim.api.nvim_set_hl(0, "CsRebuilding", { fg = "#e5c07b", bold = true })
  vim.api.nvim_set_hl(0, "CsStarting", { fg = "#56b6c2" })
  vim.api.nvim_set_hl(0, "CsRepo", { fg = "#61afef" })
  vim.api.nvim_set_hl(0, "CsBranch", { fg = "#d19a66" })
  vim.api.nvim_set_hl(0, "CsDirty", { fg = "#e5c07b" })
  vim.api.nvim_set_hl(0, "CsHelp", { fg = "#5c6370", italic = true })
  vim.api.nvim_set_hl(0, "CsCreate", { fg = "#98c379", bold = true })
  vim.api.nvim_set_hl(0, "CsMounted", { fg = "#98c379", italic = true })
end

-- Check if a path is currently mounted
local function is_mounted(path)
  local handle = io.popen("mount | grep " .. vim.fn.shellescape(path) .. " 2>/dev/null")
  if handle then
    local result = handle:read("*a")
    handle:close()
    return result ~= ""
  end
  return false
end

-- Generate a stable SSH config for a codespace (host = codespace name, doesn't change with branch)
local function get_ssh_host(cs_name, callback)
  local host = "cs-" .. cs_name
  local config_path = vim.fn.expand("~/.ssh/codespaces")
  local gh_path = vim.fn.exepath("gh")
  if gh_path == "" then gh_path = "/opt/homebrew/bin/gh" end
  local key_path = vim.fn.expand("~/.ssh/codespaces.auto")

  local entry = string.format([[
Host %s
  User codespace
  ProxyCommand %s cs ssh -c %s --stdio -- -i %s
  UserKnownHostsFile=/dev/null
  StrictHostKeyChecking no
  LogLevel quiet
  ControlMaster auto
  ControlPath /tmp/cs_%%r@%%h
  ControlPersist 10m
  IdentityFile %s
]], host, gh_path, cs_name, key_path, key_path)

  -- Read existing config and check if this host is already present
  local existing = ""
  local rf = io.open(config_path, "r")
  if rf then
    existing = rf:read("*a")
    rf:close()
  end

  if not existing:find("Host " .. host .. "\n", 1, true) then
    -- Append new entry
    local f = io.open(config_path, "a")
    if f then
      f:write("\n" .. entry)
      f:close()
    end
  end

  vim.schedule(function()
    if callback then callback(host) end
  end)
end

-- Build file index for Telescope (one SSH call, cached locally)
local function refresh_file_cache(cb)
  if not active_ssh then return end
  if file_cache_updating then return end
  file_cache_updating = true
  vim.notify("Building file index...", vim.log.levels.INFO)
  vim.fn.jobstart(
    { "ssh", "-F", active_ssh.config, active_ssh.host,
      "/usr/bin/find " .. active_ssh.remote_dir .. " -type f"
        .. " -not -path '*/.git/*'"
        .. " -not -path '*/node_modules/*'"
        .. " -not -path '*/target/*'"
        .. " -not -path '*/build/*'"
        .. " -not -name '*.class'"
        .. " | /usr/bin/head -10000"
        .. " | /usr/bin/sed 's|" .. active_ssh.remote_dir .. "/||'" },
    {
      stdout_buffered = true,
      on_stdout = function(_, out)
        file_cache = {}
        for _, line in ipairs(out) do
          if line ~= "" then table.insert(file_cache, line) end
        end
        file_cache_updating = false
        vim.schedule(function()
          vim.notify(#file_cache .. " files indexed", vim.log.levels.INFO)
          if cb then cb() end
        end)
      end,
      on_exit = function(_, code)
        if code ~= 0 then
          file_cache_updating = false
          vim.schedule(function()
            vim.notify("File index failed", vim.log.levels.ERROR)
          end)
        end
      end,
    }
  )
end

-- Pre-warm SSHFS cache by reading source files in background (speeds up LSP indexing)
local function prewarm_sshfs_cache(cb)
  if not active_ssh then if cb then cb() end return end
  vim.notify("Pre-warming file cache for LSP...", vim.log.levels.INFO)
  vim.fn.jobstart(
    { "ssh", "-F", active_ssh.config, active_ssh.host,
      "/usr/bin/find " .. active_ssh.remote_dir .. " -type f"
        .. " \\( -name '*.kt' -o -name '*.java' -o -name '*.py' -o -name '*.ts' -o -name '*.js' -o -name '*.go' \\)"
        .. " -not -path '*/.git/*' -not -path '*/target/*' -not -path '*/node_modules/*' -not -path '*/build/*'"
        .. " | /usr/bin/head -2000"
        .. " | /usr/bin/xargs /bin/cat > /dev/null 2>&1" },
    {
      on_exit = function(_, code)
        vim.schedule(function()
          if code == 0 then
            vim.notify("File cache warmed", vim.log.levels.INFO)
          end
          if cb then cb() end
        end)
      end,
    }
  )
end

-- Parse codespace data from gh CLI
local function fetch_data(callback)
  loading = true
  render()
  vim.fn.jobstart(
    { "gh", "cs", "list", "--json", "name,repository,state,gitStatus,createdAt,lastUsedAt,machineName" },
    {
      stdout_buffered = true,
      on_stdout = function(_, out)
        local json_str = table.concat(out, "")
        if json_str == "" then
          data = {}
          loading = false
          if callback then callback() end
          return
        end
        local ok, parsed = pcall(vim.json.decode, json_str)
        if ok and parsed then
          -- Sort: active first, then by lastUsedAt descending
          table.sort(parsed, function(a, b)
            if a.state ~= b.state then
              return a.state == "Available"
            end
            return (a.lastUsedAt or "") > (b.lastUsedAt or "")
          end)
          data = parsed
        end
        loading = false
        if callback then callback() end
      end,
      on_stderr = function(_, err)
        local msg = table.concat(err, "")
        if msg ~= "" then
          vim.schedule(function()
            vim.notify("Codespaces: " .. msg, vim.log.levels.WARN)
          end)
        end
      end,
    }
  )
end

-- Get the line info for mapping lines to codespaces
local line_map = {}

render = function()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_set_option(buf, "modifiable", true)

  local lines = {}
  local highlights = {}
  line_map = {}

  local function add(text, hl, line_data)
    table.insert(lines, text)
    local ln = #lines - 1
    if hl then
      table.insert(highlights, { hl, ln, 0, -1 })
    end
    if line_data then
      line_map[#lines] = line_data
    end
  end

  add("  Codespaces", "CsHeader")
  add("")

  if loading then
    add("  Loading...", "CsHelp")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    for _, hl in ipairs(highlights) do
      vim.api.nvim_buf_add_highlight(buf, -1, hl[1], hl[2], hl[3], hl[4])
    end
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
    return
  end

  if #data == 0 then
    add("  No codespaces found", "CsHelp")
    add("")
    add("  Press 'n' to create one", "CsHelp")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    for _, hl in ipairs(highlights) do
      vim.api.nvim_buf_add_highlight(buf, -1, hl[1], hl[2], hl[3], hl[4])
    end
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
    return
  end

  -- Group by state
  local active = {}
  local rebuilding = {}
  local starting = {}
  local shutdown = {}
  for _, cs in ipairs(data) do
    if cs.state == "Available" then
      table.insert(active, cs)
    elseif cs.state == "Rebuilding" or cs.state == "Moved" then
      table.insert(rebuilding, cs)
    elseif cs.state == "Starting" or cs.state == "Queued" or cs.state == "Provisioning" or cs.state == "Awaiting" then
      table.insert(starting, cs)
    else
      table.insert(shutdown, cs)
    end
  end

  -- Active section
  if #active > 0 then
    add("  " .. icons.active .. " Active (" .. #active .. ")", "CsActive")
    add("")
    for _, cs in ipairs(active) do
      local repo_short = cs.repository:match("[^/]+$") or cs.repository
      local branch = (cs.gitStatus and cs.gitStatus.ref) or "main"
      local dirty = (cs.gitStatus and cs.gitStatus.hasUncommittedChanges) and (" " .. icons.dirty) or ""

      add("  " .. icons.repo .. " " .. repo_short, "CsRepo", { type = "codespace", cs = cs })
      add("    " .. icons.branch .. " " .. branch .. dirty, dirty ~= "" and "CsDirty" or "CsBranch")
      add("    " .. cs.name:sub(1, 30), "CsShutdown")
      add("")
    end
  end

  -- Rebuilding section
  if #rebuilding > 0 then
    add("  " .. icons.rebuilding .. " Rebuilding (" .. #rebuilding .. ")", "CsRebuilding")
    add("")
    for _, cs in ipairs(rebuilding) do
      local repo_short = cs.repository:match("[^/]+$") or cs.repository
      add("  " .. icons.repo .. " " .. repo_short, "CsRepo", { type = "codespace", cs = cs })
      add("    " .. icons.rebuilding .. " " .. cs.state, "CsRebuilding")
      add("    " .. cs.name:sub(1, 30), "CsShutdown")
      add("")
    end
  end

  -- Starting section
  if #starting > 0 then
    add("  " .. icons.starting .. " Starting (" .. #starting .. ")", "CsStarting")
    add("")
    for _, cs in ipairs(starting) do
      local repo_short = cs.repository:match("[^/]+$") or cs.repository
      add("  " .. icons.repo .. " " .. repo_short, "CsRepo", { type = "codespace", cs = cs })
      add("    " .. icons.starting .. " " .. cs.state, "CsStarting")
      add("    " .. cs.name:sub(1, 30), "CsShutdown")
      add("")
    end
  end

  -- Shutdown section
  if #shutdown > 0 then
    add("  " .. icons.shutdown .. " Shutdown (" .. #shutdown .. ")", "CsShutdown")
    add("")
    for _, cs in ipairs(shutdown) do
      local repo_short = cs.repository:match("[^/]+$") or cs.repository
      local branch = (cs.gitStatus and cs.gitStatus.ref) or "main"
      local dirty = (cs.gitStatus and cs.gitStatus.hasUncommittedChanges) and (" " .. icons.dirty) or ""

      add("  " .. icons.repo .. " " .. repo_short, "CsRepo", { type = "codespace", cs = cs })
      add("    " .. icons.branch .. " " .. branch .. dirty, dirty ~= "" and "CsDirty" or "CsBranch")
      add("    " .. cs.name:sub(1, 30), "CsShutdown")
      add("")
    end
  end

  -- Help footer
  add("─────────────────────────", "CsShutdown")
  add("  ⏎ mount  u unmount  t ssh", "CsHelp")
  add("  s start  x stop  n new", "CsHelp")
  add("  d delete  r refresh  q close", "CsHelp")
  add("  p ports  b browser", "CsHelp")
  add("  l logs  R rebuild", "CsHelp")

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(buf, -1, hl[1], hl[2], hl[3], hl[4])
  end
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

-- Find the codespace for the current cursor line (look up from cursor)
local function get_cs_at_cursor()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  -- Walk up from current line to find the nearest codespace entry
  for i = line, 1, -1 do
    if line_map[i] and line_map[i].type == "codespace" then
      return line_map[i].cs
    end
  end
  return nil
end

-- Connect to codespace via SSHFS mount
local function connect(cs)
  if not cs then return end

  local repo_short = cs.repository:match("[^/]+$") or cs.repository
  local mount_path = mount_base .. "/" .. repo_short

  -- Already mounted?
  if is_mounted(mount_path) then
    if vim.fn.isdirectory(mount_path) == 1 then
      vim.notify("Already mounted, switching to " .. mount_path, vim.log.levels.INFO)
      vim.cmd("cd " .. mount_path)
      pcall(function()
        local tree_api = require("nvim-tree.api")
        tree_api.tree.close()
        tree_api.tree.open({ path = mount_path })
      end)
      return
    else
      -- Stale mount — unmount and re-mount
      vim.notify("Stale mount detected, remounting...", vim.log.levels.WARN)
      vim.fn.system("umount " .. vim.fn.shellescape(mount_path) .. " 2>/dev/null; diskutil unmount force " .. vim.fn.shellescape(mount_path) .. " 2>/dev/null")
    end
  end

  -- Create mount directory
  vim.fn.mkdir(mount_path, "p")

  vim.notify("Connecting to " .. repo_short .. "...", vim.log.levels.INFO)

  -- Generate SSH config first, then mount
  get_ssh_host(cs.name, function(host)
    if not host then
      vim.notify("Could not find SSH config for codespace", vim.log.levels.ERROR)
      return
    end

    local sshfs_cmd = {
      "sshfs",
      host .. ":/workspaces/" .. repo_short,
      mount_path,
      "-F", vim.fn.expand("~/.ssh/codespaces"),
      "-o", "reconnect",
      "-o", "ServerAliveInterval=15",
      "-o", "ServerAliveCountMax=3",
      "-o", "volname=" .. repo_short,
      "-o", "Compression=yes",
      "-o", "ControlMaster=auto",
      "-o", "ControlPath=/tmp/sshfs_cs_%r@%h:%p",
      "-o", "ControlPersist=10m",
      "-o", "cache=yes",
      "-o", "cache_timeout=600",
      "-o", "attr_timeout=600",
      "-o", "entry_timeout=600",
      "-o", "dcache_max_size=50000",
      "-o", "defer_permissions",
      "-o", "noappledouble",
    }

    local stderr_chunks = {}
    vim.fn.jobstart(sshfs_cmd, {
      stderr_buffered = true,
      on_stderr = function(_, err)
        if err then
          for _, line in ipairs(err) do
            if line ~= "" then table.insert(stderr_chunks, line) end
          end
        end
      end,
      on_exit = function(_, code)
        vim.schedule(function()
          if code == 0 then
            active_mounts[cs.name] = mount_path
            active_ssh = {
              host = host,
              remote_dir = "/workspaces/" .. repo_short,
              mount_path = mount_path,
              config = vim.fn.expand("~/.ssh/codespaces"),
            }
            -- Prevent git from traversing SSHFS mount (blocks nvim main loop)
            vim.env.GIT_CEILING_DIRECTORIES = mount_base
            vim.env.GIT_DISCOVERY_ACROSS_FILESYSTEM = "0"
            vim.notify("Mounted " .. repo_short .. " — warming up...", vim.log.levels.INFO)
            vim.cmd("cd " .. mount_path)
            -- Detach gitsigns from any buffers on the mount
            pcall(function() require("gitsigns").detach() end)

            -- Pre-build file index for Telescope
            file_cache = nil
            local warmup_done = { files = false, cache = false }
            local function check_ready()
              if warmup_done.files and warmup_done.cache then
                vim.notify("Ready! Opening file tree...", vim.log.levels.INFO)
                pcall(function()
                  local tree_api = require("nvim-tree.api")
                  tree_api.tree.close()
                  tree_api.tree.open({ path = mount_path })
                end)
                fetch_data(function() vim.schedule(render) end)
              end
            end

            refresh_file_cache(function()
              warmup_done.files = true
              check_ready()
            end)

            -- Pre-warm SSHFS cache for LSP
            prewarm_sshfs_cache(function()
              warmup_done.cache = true
              check_ready()
            end)
          else
            local err_msg = table.concat(stderr_chunks, "\n")
            vim.notify("SSHFS mount failed (code " .. code .. "): " .. err_msg, vim.log.levels.ERROR)
          end
        end)
      end,
    })
  end)
end

-- Disconnect / unmount a codespace
local function disconnect(cs)
  if not cs then return end
  local repo_short = cs.repository:match("[^/]+$") or cs.repository
  local mount_path = mount_base .. "/" .. repo_short

  if not is_mounted(mount_path) then
    vim.notify("Not mounted", vim.log.levels.INFO)
    return
  end

  vim.fn.jobstart({ "umount", mount_path }, {
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          active_mounts[cs.name] = nil
          vim.notify("Unmounted " .. repo_short, vim.log.levels.INFO)
          -- Switch back to home
          vim.cmd("cd ~")
          pcall(function() require("nvim-tree.api").tree.change_root(vim.fn.expand("~")) end)
          fetch_data(function() vim.schedule(render) end)
        else
          vim.notify("Unmount failed — try 'umount -f " .. mount_path .. "'", vim.log.levels.WARN)
        end
      end)
    end,
  })
end

-- Start a codespace (just SSH in — it auto-starts)
local function start_cs(cs)
  if not cs then return end
  if cs.state == "Available" then
    vim.notify("Already running", vim.log.levels.INFO)
    return
  end
  connect(cs)
end

-- Stop a codespace
local function stop_cs(cs)
  if not cs then return end
  if cs.state ~= "Available" then
    vim.notify("Already stopped", vim.log.levels.INFO)
    return
  end
  vim.notify("Stopping " .. cs.name:sub(1, 25) .. "...", vim.log.levels.INFO)
  vim.fn.jobstart({ "gh", "cs", "stop", "-c", cs.name }, {
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          vim.notify("Codespace stopped", vim.log.levels.INFO)
          fetch_data(function() vim.schedule(render) end)
        else
          vim.notify("Failed to stop codespace", vim.log.levels.ERROR)
        end
      end)
    end,
  })
end

-- Delete a codespace
local function delete_cs(cs)
  if not cs then return end
  local repo_short = cs.repository:match("[^/]+$") or cs.repository
  vim.ui.input({ prompt = "Delete " .. repo_short .. " codespace? (y/N): " }, function(input)
    if input ~= "y" and input ~= "Y" then return end
    vim.notify("Deleting...", vim.log.levels.INFO)
    vim.fn.jobstart({ "gh", "cs", "delete", "-c", cs.name, "--force" }, {
      on_exit = function(_, code)
        vim.schedule(function()
          if code == 0 then
            vim.notify("Codespace deleted", vim.log.levels.INFO)
            fetch_data(function() vim.schedule(render) end)
          else
            vim.notify("Failed to delete codespace", vim.log.levels.ERROR)
          end
        end)
      end,
    })
  end)
end

-- Create a new codespace
local function create_cs()
  vim.ui.input({ prompt = "Repo (owner/repo): ", default = "github/" }, function(repo)
    if not repo or repo == "" or repo == "github/" then return end
    vim.notify("Creating codespace for " .. repo .. "...", vim.log.levels.INFO)
    vim.fn.jobstart({ "gh", "cs", "create", "-R", repo, "--default-permissions" }, {
      stdout_buffered = true,
      on_stdout = function(_, out)
        local name = vim.trim(table.concat(out, ""))
        if name ~= "" then
          vim.schedule(function()
            vim.notify("Created: " .. name, vim.log.levels.INFO)
            fetch_data(function() vim.schedule(render) end)
          end)
        end
      end,
      on_exit = function(_, code)
        if code ~= 0 then
          vim.schedule(function()
            vim.notify("Failed to create codespace", vim.log.levels.ERROR)
          end)
        end
      end,
    })
  end)
end

-- Open in browser
local function open_browser(cs)
  if not cs then return end
  vim.fn.jobstart({ "gh", "cs", "code", "-c", cs.name, "--web" })
end

-- Show ports
local function show_ports(cs)
  if not cs then return end
  vim.fn.jobstart({ "gh", "cs", "ports", "-c", cs.name, "--json", "label,sourcePort,visibility" }, {
    stdout_buffered = true,
    on_stdout = function(_, out)
      local json_str = table.concat(out, "")
      vim.schedule(function()
        if json_str == "" or json_str == "[]" then
          vim.notify("No forwarded ports", vim.log.levels.INFO)
          return
        end
        local ok, ports = pcall(vim.json.decode, json_str)
        if ok and ports then
          local msg = "Ports:\n"
          for _, p in ipairs(ports) do
            msg = msg .. "  " .. p.sourcePort .. " (" .. (p.label or "unlabeled") .. ") — " .. p.visibility .. "\n"
          end
          vim.notify(msg, vim.log.levels.INFO)
        end
      end)
    end,
  })
end

-- Create the sidebar buffer and window
local function create_buf()
  buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  vim.api.nvim_buf_set_option(buf, "filetype", "codespaces")
  vim.api.nvim_buf_set_name(buf, "Codespaces")

  -- Keymaps
  local opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set("n", "<CR>", function() connect(get_cs_at_cursor()) end, opts)
  vim.keymap.set("n", "s", function() start_cs(get_cs_at_cursor()) end, opts)
  vim.keymap.set("n", "u", function() disconnect(get_cs_at_cursor()) end, opts)
  vim.keymap.set("n", "x", function() stop_cs(get_cs_at_cursor()) end, opts)
  vim.keymap.set("n", "d", function() delete_cs(get_cs_at_cursor()) end, opts)
  vim.keymap.set("n", "t", function()
    local cs = get_cs_at_cursor()
    if cs then
      vim.cmd("wincmd h")
      vim.cmd("belowright split")
      vim.cmd("resize 15")
      vim.cmd("terminal gh cs ssh -c " .. cs.name)
      vim.bo.buflisted = false
      vim.cmd("startinsert")
    end
  end, opts)
  vim.keymap.set("n", "n", create_cs, opts)
  vim.keymap.set("n", "r", function() fetch_data(function() vim.schedule(render) end) end, opts)
  vim.keymap.set("n", "b", function() open_browser(get_cs_at_cursor()) end, opts)
  vim.keymap.set("n", "p", function() show_ports(get_cs_at_cursor()) end, opts)
  vim.keymap.set("n", "l", function()
    local cs = get_cs_at_cursor()
    if cs then
      vim.cmd("wincmd h")
      M.codespace_logs(cs.name)
    end
  end, opts)
  vim.keymap.set("n", "R", function()
    local cs = get_cs_at_cursor()
    if cs then
      vim.ui.select({ "Rebuild", "Rebuild (full, no cache)" }, { prompt = "Rebuild " .. (cs.repository:match("[^/]+$") or cs.name) .. "?" }, function(choice)
        if choice then
          M.rebuild_codespace(choice:find("full") ~= nil, cs.name)
        end
      end)
    end
  end, opts)
  vim.keymap.set("n", "q", function() M.close() end, opts)
end

function M.open()
  if win and vim.api.nvim_win_is_valid(win) then return end

  local ea = vim.o.equalalways
  vim.o.equalalways = false

  create_buf()
  vim.cmd("botright vsplit")
  win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_width(win, width)

  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].winfixwidth = true
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true

  vim.o.equalalways = ea

  fetch_data(function() vim.schedule(render) end)
end

function M.close()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  win = nil
  buf = nil
end

function M.toggle()
  if win and vim.api.nvim_win_is_valid(win) then
    M.close()
  else
    M.open()
  end
end

-- Open SSH terminal for the currently mounted codespace (works without sidebar)
function M.terminal()
  -- Find which codespace is mounted based on cwd
  local cwd = vim.fn.getcwd()
  local cs_name = nil
  local repo_short = nil

  -- Check if cwd is under ~/codespaces/
  local mount_match = cwd:match(mount_base .. "/([^/]+)")
  if mount_match then
    repo_short = mount_match
    -- Find the codespace name from active_mounts
    for name, path in pairs(active_mounts) do
      if path:find(mount_match) then
        cs_name = name
        break
      end
    end
  end

  -- If not found in active_mounts, search by repo name
  if not cs_name and repo_short then
    vim.fn.jobstart(
      { "gh", "cs", "list", "--json", "name,repository,state" },
      {
        stdout_buffered = true,
        on_stdout = function(_, out)
          local json_str = table.concat(out, "")
          if json_str == "" then return end
          local ok, parsed = pcall(vim.json.decode, json_str)
          if ok and parsed then
            for _, cs in ipairs(parsed) do
              local r = cs.repository:match("[^/]+$") or cs.repository
              if r == repo_short then
                cs_name = cs.name
                break
              end
            end
          end
          vim.schedule(function()
            if cs_name then
              vim.cmd("belowright split")
              vim.cmd("resize 15")
              vim.cmd("terminal gh cs ssh -c " .. cs_name)
              vim.bo.buflisted = false
              vim.cmd("startinsert")
            else
              vim.notify("No codespace found for " .. (repo_short or "current dir"), vim.log.levels.WARN)
            end
          end)
        end,
      }
    )
    return
  end

  if cs_name then
    vim.cmd("belowright split")
    vim.cmd("resize 15")
    vim.cmd("terminal gh cs ssh -c " .. cs_name)
    vim.bo.buflisted = false
    vim.cmd("startinsert")
  else
    vim.notify("Not in a codespace directory", vim.log.levels.WARN)
  end
end

-- Create a codespace and mount it
-- Usage: :Codespace github/trino
-- Usage: :Codespace github/trino branch-name
function M.create_and_mount(repo, branch)
  if not repo or repo == "" then
    vim.notify("Usage: :Codespace owner/repo [branch]", vim.log.levels.WARN)
    return
  end

  vim.notify("Checking for existing codespace for " .. repo .. "...", vim.log.levels.INFO)

  -- First check if there's already a codespace for this repo
  vim.fn.jobstart({ "gh", "cs", "list", "--json", "name,repository,state" }, {
    stdout_buffered = true,
    on_stdout = function(_, list_out)
      local list_str = table.concat(list_out, "")
      local ok, codespaces = pcall(vim.json.decode, list_str)
      if ok and codespaces then
        for _, cs in ipairs(codespaces) do
          if cs.repository == repo then
            vim.schedule(function()
              vim.notify("Found existing codespace, connecting...", vim.log.levels.INFO)
              -- Refresh data and connect
              fetch_data(function()
                vim.schedule(function()
                  for _, d in ipairs(data) do
                    if d.name == cs.name then
                      connect(d)
                      return
                    end
                  end
                end)
              end)
            end)
            return
          end
        end
      end

      -- No existing codespace — create one
      vim.schedule(function()
        vim.notify("No existing codespace, creating...", vim.log.levels.INFO)
      end)

      local machine_cmd = { "gh", "api", "repos/" .. repo .. "/codespaces/machines", "--jq", ".machines[].name" }
      vim.fn.jobstart(machine_cmd, {
        stdout_buffered = true,
        on_stdout = function(_, mach_out)
          local machines_str = vim.trim(table.concat(mach_out, "\n"))
          local machine = nil
          for m in machines_str:gmatch("([^\n]+)") do
            machine = m -- last = largest
          end
          if not machine or machine == "" then
            vim.schedule(function()
              vim.notify("No machine types available for " .. repo, vim.log.levels.ERROR)
            end)
            return
          end

          local args = { "gh", "cs", "create", "-R", repo, "-m", machine, "--default-permissions" }
          if branch and branch ~= "" then
            table.insert(args, "-b")
            table.insert(args, branch)
          end

          vim.schedule(function()
            vim.notify("Creating codespace (" .. machine .. ")...", vim.log.levels.INFO)
          end)

          vim.fn.jobstart(args, {
            stdout_buffered = true,
            stderr_buffered = true,
            on_stdout = function(_, cs_out)
              local name = vim.trim(table.concat(cs_out, ""))
              if name ~= "" then
                vim.schedule(function()
                  vim.notify("Created: " .. name .. " — mounting...", vim.log.levels.INFO)
                  fetch_data(function()
                    vim.schedule(function()
                      for _, cs in ipairs(data) do
                        if cs.name == name then
                          connect(cs)
                          return
                        end
                      end
                      vim.notify("Created but couldn't auto-mount. Use sidebar.", vim.log.levels.WARN)
                    end)
                  end)
                end)
              end
            end,
            on_stderr = function(_, err)
              local msg = vim.trim(table.concat(err, ""))
              if msg ~= "" then
                vim.schedule(function() vim.notify("Codespace: " .. msg, vim.log.levels.WARN) end)
              end
            end,
            on_exit = function(_, code)
              if code ~= 0 then
                vim.schedule(function()
                  vim.notify("Failed to create codespace", vim.log.levels.ERROR)
                end)
              end
            end,
          })
        end,
      })
    end,
  })
end

vim.api.nvim_create_user_command("Codespace", function(opts)
  local args = vim.split(opts.args, "%s+")
  M.create_and_mount(args[1], args[2])
end, {
  nargs = "+",
  desc = "Create a codespace and mount it",
  complete = function()
    return { "github/" }
  end,
})

setup_highlights()

-- Remote Telescope: cached file list + SSH grep

function M.remote_find_files()
  if not active_ssh then
    vim.notify("No codespace mounted", vim.log.levels.WARN)
    return
  end

  local function show_picker()
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    pickers.new({}, {
      prompt_title = "Remote Files (" .. active_ssh.remote_dir:match("[^/]+$") .. ")",
      finder = finders.new_table({
        results = file_cache,
        entry_maker = function(line)
          return {
            value = line,
            display = line,
            ordinal = line,
            path = active_ssh.mount_path .. "/" .. line,
          }
        end,
      }),
      sorter = conf.file_sorter({}),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry then
            vim.cmd("edit " .. vim.fn.fnameescape(entry.path))
          end
        end)
        return true
      end,
    }):find()
  end

  if file_cache then
    show_picker()
  else
    refresh_file_cache(show_picker)
  end
end

function M.remote_live_grep()
  if not active_ssh then
    vim.notify("No codespace mounted", vim.log.levels.WARN)
    return
  end
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local sorters = require("telescope.sorters")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers.new({}, {
    prompt_title = "Remote Grep (" .. active_ssh.remote_dir:match("[^/]+$") .. ")",
    finder = finders.new_async_job({
      command_generator = function(prompt)
        if not prompt or prompt == "" then return nil end
        return { "ssh", "-F", active_ssh.config, active_ssh.host,
          "grep -rn --include='*' -I -i '" .. prompt:gsub("'", "") .. "' " .. active_ssh.remote_dir .. " | head -1000 | sed 's|" .. active_ssh.remote_dir .. "/||'" }
      end,
      entry_maker = function(line)
        if not line or line == "" then return nil end
        local file, lnum, text = line:match("^(.+):(%d+):(.*)$")
        if not file then return nil end
        return {
          value = line,
          display = file .. ":" .. lnum .. ": " .. text,
          ordinal = line,
          filename = active_ssh.mount_path .. "/" .. file,
          lnum = tonumber(lnum),
          col = 1,
        }
      end,
    }),
    sorter = sorters.get_generic_fuzzy_sorter(),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if entry then
          vim.cmd("edit +" .. (entry.lnum or 1) .. " " .. vim.fn.fnameescape(entry.filename))
        end
      end)
      return true
    end,
  }):find()
end

-- Refresh the file cache (call after creating/deleting files)
function M.refresh_files()
  file_cache = nil
  refresh_file_cache()
end

function M.is_on_codespace()
  return active_ssh ~= nil
end

function M.get_active_ssh()
  return active_ssh
end

function M.rebuild_codespace(full, cs_name)
  local name = cs_name or (active_ssh and active_ssh.host) or nil

  if not name then
    -- Prompt for codespace name
    vim.ui.input({ prompt = "Codespace name: " }, function(input)
      if input and input ~= "" then
        local cmd = "gh cs rebuild --codespace " .. input
        if full then cmd = cmd .. " --full" end
        vim.notify("Rebuilding " .. input .. (full and " (full)" or "") .. "...", vim.log.levels.INFO)
        vim.fn.jobstart(cmd, {
          on_exit = function(_, code)
            if code == 0 then
              vim.notify(input .. " is rebuilding", vim.log.levels.INFO)
            else
              vim.notify("Failed to rebuild " .. input, vim.log.levels.ERROR)
            end
          end,
        })
      end
    end)
    return
  end

  local cmd = "gh cs rebuild --codespace " .. name
  if full then cmd = cmd .. " --full" end
  vim.notify("Rebuilding " .. name .. (full and " (full)" or "") .. "...", vim.log.levels.INFO)
  vim.fn.jobstart(cmd, {
    on_exit = function(_, code)
      if code == 0 then
        vim.schedule(function()
          vim.notify(name .. " is rebuilding", vim.log.levels.INFO)
        end)
      else
        vim.schedule(function()
          vim.notify("Failed to rebuild " .. name, vim.log.levels.ERROR)
        end)
      end
    end,
  })
end

vim.api.nvim_create_user_command("CsRebuild", function(opts)
  local full = opts.args == "full"
  M.rebuild_codespace(full)
end, {
  nargs = "?",
  desc = "Rebuild the active (or specified) codespace",
  complete = function()
    return { "full" }
  end,
})

function M.codespace_logs(cs_name)
  local name = cs_name or (active_ssh and active_ssh.host) or nil

  local function open_logs(n)
    -- Creation logs are only available in the browser UI
    local url = "https://" .. n .. ".github.dev"
    vim.notify("Opening creation log for " .. n .. " in browser...", vim.log.levels.INFO)
    vim.fn.jobstart({ "open", url })
  end

  if name then
    open_logs(name)
  else
    vim.ui.input({ prompt = "Codespace name: " }, function(input)
      if input and input ~= "" then
        open_logs(input)
      end
    end)
  end
end

vim.api.nvim_create_user_command("CsLogs", function()
  M.codespace_logs()
end, { desc = "Show codespace creation logs" })

return M
