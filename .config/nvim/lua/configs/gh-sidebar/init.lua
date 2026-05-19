local M = {}

local buf = nil
local win = nil
local items = {}
local username = nil
local loading = false
local last_results = nil

local config = {
  width = math.floor(vim.o.columns * 0.20),
  refresh_on_open = true,
}

local function get_username()
  if username then return username end
  local result = vim.fn.system("gh api user --jq '.login' 2>/dev/null")
  username = vim.trim(result)
  return username
end

local function run_gh(args, callback)
  vim.fn.jobstart("gh " .. args, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      local output = table.concat(data, "\n")
      if output ~= "" then
        local ok, parsed = pcall(vim.fn.json_decode, output)
        if ok then
          callback(parsed)
        else
          callback({})
        end
      else
        callback({})
      end
    end,
    on_stderr = function(_, _) end,
  })
end

local function fetch_data(callback)
  local user = get_username()
  local results = { prs = {}, issues = {}, stale_issues = {}, mentions = {}, discussions = {} }
  local pending = 4

  local function check_done()
    pending = pending - 1
    if pending == 0 then
      callback(results)
    end
  end

  -- My open PRs (search first, then enrich with last commit date)
  run_gh(
    'search prs --author=' .. user .. ' --state=open --owner=github --limit=20 --json url,title,repository,updatedAt,isDraft,commentsCount',
    function(data)
      results.prs = data or {}
      if #results.prs == 0 then
        check_done()
        return
      end
      -- Enrich each PR with last commit date via GraphQL
      local enrich_pending = #results.prs
      for _, pr in ipairs(results.prs) do
        local owner, repo, num = pr.url:match("github%.com/([^/]+)/([^/]+)/pull/(%d+)")
        if owner and repo and num then
          run_gh(
            'api graphql -f query=\'{ repository(owner: "' .. owner .. '", name: "' .. repo .. '") { pullRequest(number: ' .. num .. ') { commits(last: 1) { nodes { commit { committedDate } } } } } }\' --jq \'.data.repository.pullRequest.commits.nodes[0].commit.committedDate\' 2>/dev/null',
            function(commit_data)
              if type(commit_data) == "string" then
                pr.lastCommitDate = vim.trim(commit_data)
              elseif type(commit_data) == "table" and #commit_data > 0 then
                pr.lastCommitDate = vim.trim(commit_data[1] or "")
              end
              enrich_pending = enrich_pending - 1
              if enrich_pending == 0 then
                check_done()
              end
            end
          )
        else
          enrich_pending = enrich_pending - 1
          if enrich_pending == 0 then
            check_done()
          end
        end
      end
    end
  )

  -- Assigned issues
  run_gh(
    'search issues --assignee=' .. user .. ' --state=open --owner=github --limit=30 --json url,title,repository,updatedAt,commentsCount',
    function(data)
      -- Split into active and stale (not updated in 30 days)
      local now = os.time()
      local stale_cutoff = 30 * 24 * 60 * 60
      results.issues = {}
      results.stale_issues = {}
      for _, issue in ipairs(data or {}) do
        local updated = issue.updatedAt or ""
        -- Parse ISO date roughly
        local y, m, d = updated:match("(%d+)-(%d+)-(%d+)")
        local age = stale_cutoff + 1
        if y and m and d then
          local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) })
          age = now - t
        end
        if age > stale_cutoff then
          table.insert(results.stale_issues, issue)
        else
          table.insert(results.issues, issue)
        end
      end
      check_done()
    end
  )

  -- Recent notifications (mentions)
  run_gh(
    'api notifications --jq \'[.[] | select(.reason == "mention" or .reason == "review_requested") | {title: .subject.title, url: .subject.url, reason: .reason, repo: .repository.full_name, updated_at: .updated_at}][0:15]\' 2>/dev/null',
    function(data)
      results.mentions = data or {}
      check_done()
    end
  )

  -- Discussions (authored or mentioned)
  run_gh(
    'api graphql -f query=\'{ search(query: "org:github involves:' .. user .. ' is:open", type: DISCUSSION, first: 15) { nodes { ... on Discussion { url title createdAt repository { nameWithOwner } author { login } } } } }\' --jq \'.data.search.nodes\' 2>/dev/null',
    function(data)
      results.discussions = data or {}
      check_done()
    end
  )
end

local function repo_short(repo)
  if type(repo) == "table" then
    repo = repo.nameWithOwner or repo.name or ""
  end
  return (repo:gsub("^github/", ""))
end

local function time_ago(iso_date)
  if not iso_date or iso_date == "" then return "" end
  local y, m, d, h, min = iso_date:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
  if not y then
    y, m, d = iso_date:match("(%d+)-(%d+)-(%d+)")
    h, min = 0, 0
  end
  if not y then return "" end
  local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = tonumber(h) or 0, min = tonumber(min) or 0, sec = 0 })
  local diff = os.time() - t
  if diff < 3600 then return math.floor(diff / 60) .. "m"
  elseif diff < 86400 then return math.floor(diff / 3600) .. "h"
  elseif diff < 604800 then return math.floor(diff / 86400) .. "d"
  elseif diff < 2592000 then return math.floor(diff / 604800) .. "w"
  else return math.floor(diff / 2592000) .. "mo"
  end
end

local function review_icon(decision)
  if decision == "APPROVED" then return "✓"
  elseif decision == "CHANGES_REQUESTED" then return "✗"
  elseif decision == "REVIEW_REQUIRED" then return "◎"
  else return "·"
  end
end

local function diff_stat(pr)
  local add = pr.additions or 0
  local del = pr.deletions or 0
  if add == 0 and del == 0 then return "" end
  return " +" .. add .. "/-" .. del
end

local function render(results)
  items = {}
  local lines = {}
  local highlights = {}

  -- Use actual window width for content sizing
  local w = config.width
  if win and vim.api.nvim_win_is_valid(win) then
    w = vim.api.nvim_win_get_width(win)
  end

  -- Header
  table.insert(lines, "  GitHub — " .. get_username())
  table.insert(lines, "  " .. string.rep("─", math.max(w - 4, 10)))
  table.insert(items, { type = "header" })
  table.insert(items, { type = "header" })

  -- My Open PRs
  local pr_count = #results.prs
  table.insert(lines, "")
  table.insert(items, { type = "spacer" })
  local pr_header = "  📝 My Open PRs (" .. pr_count .. ")"
  table.insert(lines, pr_header)
  table.insert(highlights, { line = #lines, col = 0, len = #pr_header, hl = "Title" })
  table.insert(items, { type = "section" })

  if pr_count == 0 then
    table.insert(lines, "     (none)")
    table.insert(items, { type = "empty" })
  else
    for _, pr in ipairs(results.prs) do
      local repo = repo_short(pr.repository)
      local icon = pr.isDraft and "◌ " or "● "
      local rv = pr.isDraft and "◌" or "●"
      local title_line = "   " .. rv .. " " .. repo .. " — " .. (pr.title or ""):sub(1, w - #repo - 10)
      table.insert(lines, title_line)
      table.insert(items, { type = "pr", url = pr.url })
      -- Metadata line: last commit time + comments
      local commit_time = pr.lastCommitDate and pr.lastCommitDate ~= "" and pr.lastCommitDate or pr.updatedAt
      local ago = time_ago(commit_time)
      local ago_label = pr.lastCommitDate and pr.lastCommitDate ~= "" and ("⏱ " .. ago) or (ago)
      local comments = (pr.commentsCount or 0) > 0 and (" 💬" .. pr.commentsCount) or ""
      local meta = "      " .. ago_label .. comments
      table.insert(lines, meta)
      table.insert(highlights, { line = #lines, col = 0, len = #meta, hl = "Comment" })
      table.insert(items, { type = "pr_meta", url = pr.url })
    end
  end

  -- Assigned Issues
  local issue_count = #results.issues
  table.insert(lines, "")
  table.insert(items, { type = "spacer" })
  local issue_header = "  📌 Assigned Issues (" .. issue_count .. ")"
  table.insert(lines, issue_header)
  table.insert(highlights, { line = #lines, col = 0, len = #issue_header, hl = "Title" })
  table.insert(items, { type = "section" })

  if issue_count == 0 then
    table.insert(lines, "     (none)")
    table.insert(items, { type = "empty" })
  else
    for _, issue in ipairs(results.issues) do
      local repo = repo_short(issue.repository)
      local line = "     " .. repo .. " — " .. (issue.title or ""):sub(1, w - #repo - 10)
      table.insert(lines, line)
      table.insert(items, { type = "issue", url = issue.url })
      local ago = time_ago(issue.updatedAt)
      local comments = (issue.commentsCount or 0) > 0 and (" 💬" .. issue.commentsCount) or ""
      local meta = "      " .. ago .. comments
      table.insert(lines, meta)
      table.insert(highlights, { line = #lines, col = 0, len = #meta, hl = "Comment" })
      table.insert(items, { type = "issue_meta", url = issue.url })
    end
  end

  -- Stale Assigned Issues
  local stale_count = #results.stale_issues
  if stale_count > 0 then
    table.insert(lines, "")
    table.insert(items, { type = "spacer" })
    local stale_header = "  🕸 Stale Issues (" .. stale_count .. ")"
    table.insert(lines, stale_header)
    table.insert(highlights, { line = #lines, col = 0, len = #stale_header, hl = "Comment" })
    table.insert(items, { type = "section" })

    for _, issue in ipairs(results.stale_issues) do
      local repo = repo_short(issue.repository)
      local line = "     " .. repo .. " — " .. (issue.title or ""):sub(1, w - #repo - 10)
      table.insert(lines, line)
      table.insert(items, { type = "issue", url = issue.url })
      local ago = time_ago(issue.updatedAt)
      local meta = "      " .. ago .. " ago"
      table.insert(lines, meta)
      table.insert(highlights, { line = #lines, col = 0, len = #meta, hl = "Comment" })
      table.insert(items, { type = "issue_meta", url = issue.url })
    end
  end

  -- Mentions / Notifications
  local mention_count = #results.mentions
  table.insert(lines, "")
  table.insert(items, { type = "spacer" })
  local mention_header = "  🔔 Mentions (" .. mention_count .. ")"
  table.insert(lines, mention_header)
  table.insert(highlights, { line = #lines, col = 0, len = #mention_header, hl = "Title" })
  table.insert(items, { type = "section" })

  if mention_count == 0 then
    table.insert(lines, "     (none)")
    table.insert(items, { type = "empty" })
  else
    for _, notif in ipairs(results.mentions) do
      local repo = repo_short(notif.repo or "")
      local reason_icon = notif.reason == "review_requested" and "👀" or "💬"
      local line = "   " .. reason_icon .. " " .. repo .. " — " .. (notif.title or ""):sub(1, w - #repo - 12)
      table.insert(lines, line)
      -- Convert API URL to web URL for Octo
      local web_url = (notif.url or "")
        :gsub("api%.github%.com/repos/", "github.com/")
        :gsub("/pulls/", "/pull/")
      table.insert(items, { type = "notification", url = web_url, api_url = notif.url })
      local ago = time_ago(notif.updated_at)
      if ago ~= "" then
        local meta = "      " .. ago
        table.insert(lines, meta)
        table.insert(highlights, { line = #lines, col = 0, len = #meta, hl = "Comment" })
        table.insert(items, { type = "notif_meta", url = web_url })
      end
    end
  end

  -- Discussions
  local disc_count = #results.discussions
  table.insert(lines, "")
  table.insert(items, { type = "spacer" })
  local disc_header = "  💬 Discussions (" .. disc_count .. ")"
  table.insert(lines, disc_header)
  table.insert(highlights, { line = #lines, col = 0, len = #disc_header, hl = "Title" })
  table.insert(items, { type = "section" })

  if disc_count == 0 then
    table.insert(lines, "     (none)")
    table.insert(items, { type = "empty" })
  else
    for _, disc in ipairs(results.discussions) do
      local repo = repo_short(disc.repository or "")
      local author = (disc.author or {}).login or ""
      local is_mine = author == get_username()
      local icon = is_mine and "✎ " or "↩ "
      local line = "   " .. icon .. repo .. " — " .. (disc.title or ""):sub(1, w - #repo - 10)
      table.insert(lines, line)
      table.insert(items, { type = "discussion", url = disc.url })
    end
  end

  -- Footer
  table.insert(lines, "")
  table.insert(lines, "  " .. string.rep("─", w - 4))
  table.insert(lines, "  r: refresh  q: close  <CR>: open")
  table.insert(items, { type = "spacer" })
  table.insert(items, { type = "footer" })
  table.insert(items, { type = "footer" })

  -- Write to buffer
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_set_option(buf, "modifiable", true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf, "modifiable", false)

    for _, hl in ipairs(highlights) do
      vim.api.nvim_buf_add_highlight(buf, -1, hl.hl, hl.line - 1, hl.col, hl.col + hl.len)
    end
  end
end

local function open_item()
  local cursor = vim.api.nvim_win_get_cursor(win)
  local row = cursor[1]
  local item = items[row]
  if not item then return end

  if item.type == "pr" or item.type == "issue" or item.type == "notification" or item.type == "discussion" then
    local url = item.url
    if url and url ~= "" then
      -- Open in the previous window (the one user came from)
      local sidebar_win = win
      vim.cmd("wincmd p")
      -- If we landed back in sidebar or nvim-tree, try creating a new split
      local cur_ft = vim.bo.filetype
      if cur_ft == "gh-sidebar" or cur_ft == "NvimTree" then
        vim.cmd("wincmd h")
        cur_ft = vim.bo.filetype
        if cur_ft == "NvimTree" or cur_ft == "gh-sidebar" then
          vim.cmd("vnew")
        end
      end
      vim.cmd("Octo " .. url)
    end
  end
end

function M.refresh()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  if loading then return end
  loading = true

  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "  Loading..." })
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  fetch_data(function(results)
    vim.schedule(function()
      last_results = results
      render(results)
      loading = false
    end)
  end)
end

function M.toggle()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
    win = nil
    return
  end

  -- Create buffer
  buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  vim.api.nvim_buf_set_option(buf, "filetype", "gh-sidebar")

  -- Create window on the far right edge using botright vsplit
  local ea = vim.o.equalalways
  vim.o.equalalways = false
  vim.cmd("botright vsplit")
  win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_width(win, config.width)

  vim.api.nvim_win_set_option(win, "number", false)
  vim.api.nvim_win_set_option(win, "relativenumber", false)
  vim.api.nvim_win_set_option(win, "signcolumn", "no")
  vim.api.nvim_win_set_option(win, "wrap", false)
  vim.api.nvim_win_set_option(win, "cursorline", true)
  vim.api.nvim_win_set_option(win, "winfixwidth", false)

  -- Restore equalalways but keep sidebar fixed
  vim.o.equalalways = ea

  -- Keymaps
  local opts = { buffer = buf, noremap = true, silent = true }
  vim.keymap.set("n", "q", M.toggle, opts)
  vim.keymap.set("n", "<CR>", open_item, opts)
  vim.keymap.set("n", "r", M.refresh, opts)

  -- Re-render on resize so content fits new width
  vim.api.nvim_create_autocmd("WinResized", {
    buffer = buf,
    callback = function()
      if last_results then
        render(last_results)
      end
    end,
  })

  if config.refresh_on_open then
    M.refresh()
  end
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
  vim.api.nvim_create_user_command("GhSidebar", M.toggle, { desc = "Toggle GitHub sidebar" })
end

return M
