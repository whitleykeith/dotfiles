local M = {}

-- State
local buf = nil
local win = nil
local data = {}
local loading = false
local width = 45
local mount_base = vim.fn.expand("~/codespaces")
local active_mounts = {} -- cs.name -> mount_path

-- Icons
local icons = {
  active = "●",
  shutdown = "○",
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

-- Generate SSH config and return the host alias for a codespace
local function get_ssh_host(cs_name, callback)
  vim.fn.jobstart({ "gh", "cs", "ssh", "--config" }, {
    stdout_buffered = true,
    on_stdout = function(_, out)
      local config_str = table.concat(out, "\n")
      -- Find the Host line matching this codespace name
      local host = nil
      for line in config_str:gmatch("[^\n]+") do
        local h = line:match("^Host%s+(cs%." .. vim.pesc(cs_name) .. "%.%S+)")
        if h then
          host = h
          break
        end
      end
      -- Write SSH config for sshfs to use
      local config_path = vim.fn.expand("~/.ssh/codespaces_config")
      local f = io.open(config_path, "w")
      if f then
        f:write(config_str)
        f:close()
      end
      vim.schedule(function()
        if callback then callback(host) end
      end)
    end,
  })
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
  local shutdown = {}
  for _, cs in ipairs(data) do
    if cs.state == "Available" then
      table.insert(active, cs)
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
  add("  ⏎ connect  s start  x stop", "CsHelp")
  add("  n new  d delete  r refresh", "CsHelp")
  add("  p ports  b browser", "CsHelp")

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
    vim.notify("Already mounted, switching to " .. mount_path, vim.log.levels.INFO)
    vim.cmd("cd " .. mount_path)
    pcall(function() require("nvim-tree.api").tree.change_root(mount_path) end)
    return
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
      host .. ":/workspaces",
      mount_path,
      "-F", vim.fn.expand("~/.ssh/codespaces_config"),
      "-o", "reconnect",
      "-o", "ServerAliveInterval=15",
      "-o", "ServerAliveCountMax=3",
      "-o", "volname=" .. repo_short,
    }

    vim.fn.jobstart(sshfs_cmd, {
      on_exit = function(_, code)
        vim.schedule(function()
          if code == 0 then
            active_mounts[cs.name] = mount_path
            vim.notify("Mounted " .. repo_short .. " at " .. mount_path, vim.log.levels.INFO)
            vim.cmd("cd " .. mount_path)
            pcall(function() require("nvim-tree.api").tree.change_root(mount_path) end)
            fetch_data(function() vim.schedule(render) end)
          else
            vim.notify("SSHFS mount failed (is macFUSE installed?)", vim.log.levels.ERROR)
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
  vim.keymap.set("n", "x", function() stop_cs(get_cs_at_cursor()) end, opts)
  vim.keymap.set("n", "d", function() delete_cs(get_cs_at_cursor()) end, opts)
  vim.keymap.set("n", "n", create_cs, opts)
  vim.keymap.set("n", "r", function() fetch_data(function() vim.schedule(render) end) end, opts)
  vim.keymap.set("n", "b", function() open_browser(get_cs_at_cursor()) end, opts)
  vim.keymap.set("n", "p", function() show_ports(get_cs_at_cursor()) end, opts)
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

setup_highlights()

return M
