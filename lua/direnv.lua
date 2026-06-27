local M = {}

--- @class DirenvConfig
--- @field bin string Path to direnv executable
--- @field autoload_direnv boolean Automatically load direnv when opening files
--- @field auto_restart_lsp boolean Automatically restart LSP servers after direnv environment is loaded
--- @field cache_ttl integer Cache TTL in milliseconds for direnv status checks
--- @field statusline table Configuration for statusline integration
--- @field statusline.enabled boolean Enable statusline integration
--- @field statusline.icon string Icon to show in statusline
--- @field keybindings table | boolean Keybindings configuration
--- @field keybindings.allow string | boolean Keybinding to allow direnv
--- @field keybindings.deny string | boolean Keybinding to deny direnv
--- @field keybindings.reload string | boolean Keybinding to reload direnv
--- @field keybindings.edit string | boolean Keybinding to edit .envrc
--- @field notifications table Notification settings
--- @field notifications.level integer Log level for notifications
--- @field notifications.silent_autoload boolean Don't show notifications during autoload and initialization

local NO_ENVRC = {} -- sentinel: "checked and found no .envrc"

local cache = {
   status = nil,
   path = nil,
   last_check = 0,
   cwd = nil,
   pending_request = false,
}

local notification_queue = {}
local notification_queue_scheduled = false
local pending_callbacks = {}

-- Timestamp (ms) of the last successful direnv env load; nil when idle.
-- Lets the LspAttach handler catch clients that race with direnv startup.
local direnv_loaded_at = nil
-- bufnr -> direnv_loaded_at value when a restart was issued for that buffer.
-- Prevents the re-attached client from triggering a second restart loop.
local lsp_restart_issued = {}

--- Check if an executable is available in PATH
--- @param executable_name string Name of the executable
--- @return boolean is_available
local function check_executable(executable_name)
   if vim.fn.executable(executable_name) ~= 1 then
      vim.notify(
         "Executable '"
            .. executable_name
            .. "' not found. Please install "
            .. executable_name
            .. " first.",
         vim.log.levels.ERROR
      )
      return false
   end
   return true
end

--- Get current working directory safely
--- @return string|nil cwd Current working directory or nil on error
local function get_cwd()
   local cwd_result, err = vim.uv.cwd()
   if err then
      vim.schedule(function()
         vim.notify(
            "Failed to get current directory: " .. err,
            vim.log.levels.ERROR
         )
      end)
      return nil
   end
   return cwd_result
end

--- Setup keymaps for the plugin
--- @param keymaps table List of keymap definitions
--- @param mode string|table Vim mode for the keymap
local function setup_keymaps(keymaps, mode)
   for _, map in ipairs(keymaps) do
      local options = vim.tbl_extend("force", { silent = true }, map[3] or {})
      if map[1] then
         vim.keymap.set(mode, map[1], map[2], options)
      end
   end
end

--- Safe notify function that works in both sync and async contexts
--- @param msg string Message to display
--- @param level? integer Log level
--- @param opts? table Additional notification options
local function notify(msg, level, opts)
   local configured_level = M.config
         and M.config.notifications
         and M.config.notifications.level
      or vim.log.levels.INFO
   level = level or configured_level

   if level < configured_level then
      return
   end

   opts = opts or {}
   opts = vim.tbl_extend("force", { title = "direnv.nvim" }, opts)

   if vim.in_fast_event() then
      table.insert(notification_queue, {
         msg = msg,
         level = level,
         opts = opts,
      })

      if not notification_queue_scheduled then
         notification_queue_scheduled = true
         vim.schedule(function()
            notification_queue_scheduled = false
            while #notification_queue > 0 do
               local item = table.remove(notification_queue, 1)
               vim.notify(item.msg, item.level, item.opts)
            end
         end)
      end
   else
      vim.notify(msg, level, opts)
   end
end

--- Get current direnv status via JSON API
--- @param callback function Callback function to handle result
M._get_rc_status = function(callback)
   local cwd = get_cwd()
   if not cwd then
      return callback(nil, nil)
   end

   local now = math.floor(vim.uv.hrtime() / 1000000) -- ns -> ms
   local ttl = (M.config and M.config.cache_ttl) or 5000

   if cache.cwd ~= nil and cache.cwd ~= cwd then
      cache.status = nil
      cache.cwd = nil
   end

   if cache.status ~= nil and (now - cache.last_check) < ttl then
      if cache.status == NO_ENVRC then
         return callback(nil, nil)
      end
      return callback(cache.status, cache.path)
   end

   table.insert(pending_callbacks, callback)

   if cache.pending_request then
      return
   end

   cache.pending_request = true

   local on_exit = function(obj)
      cache.pending_request = false

      if obj.code ~= 0 then
         vim.schedule(function()
            notify(
               "Failed to get direnv status: "
                  .. (obj.stderr or "unknown error"),
               vim.log.levels.ERROR
            )
         end)
         for _, cb in ipairs(pending_callbacks) do
            cb(nil, nil)
         end
         pending_callbacks = {}
         return
      end

      local ok, status = pcall(vim.json.decode, obj.stdout)
      if not ok or not status or not status.state then
         vim.schedule(function()
            notify(
               "Failed to parse direnv status. Your version of direnv may not support JSON output. "
                  .. "Please ensure you have direnv v2.33.0 or later installed. "
                  .. "You can verify by running: direnv status --json",
               vim.log.levels.ERROR
            )
         end)
         for _, cb in ipairs(pending_callbacks) do
            cb(nil, nil)
         end
         pending_callbacks = {}
         return
      end

      if status.state.foundRC == vim.NIL then
         cache.status = NO_ENVRC
         cache.path = nil
         cache.cwd = cwd
         cache.last_check = now
         for _, cb in ipairs(pending_callbacks) do
            cb(nil, nil)
         end
         pending_callbacks = {}
         return
      end

      cache.status = status.state.foundRC.allowed
      cache.path = status.state.foundRC.path
      cache.cwd = cwd
      cache.last_check = now

      for _, cb in ipairs(pending_callbacks) do
         cb(status.state.foundRC.allowed, status.state.foundRC.path)
      end
      pending_callbacks = {}
   end

   vim.system(
      { (M.config or {}).bin or "direnv", "status", "--json" },
      { text = true, cwd = cwd },
      on_exit
   )
end

M.refresh_status = function()
   cache.status = nil
   cache.cwd = nil
   M._get_rc_status(function() end)
end

--- Unload direnv environment by running direnv export in the current directory.
--- direnv handles proper env restoration (including $PATH), unlike manual tracking.
M._unload = function()
   local cwd = get_cwd()
   if not cwd then
      return
   end

   vim.system(
      { M.config.bin, "export", "json" },
      { text = true, cwd = cwd },
      function(obj)
         if obj.code ~= 0 then
            vim.schedule(function()
               notify(
                  "Failed to unload direnv: " .. (obj.stderr or "unknown error"),
                  vim.log.levels.WARN
               )
            end)
            return
         end

         vim.schedule(function()
            local stdout = obj.stdout or ""
            if stdout == "" then
               return
            end

            local ok, env = pcall(vim.json.decode, stdout)
            if not ok or type(env) ~= "table" then
               return
            end

            for key, value in pairs(env) do
               if value == vim.NIL or value == nil then
                  vim.env[key] = nil
               else
                  if type(value) ~= "string" then
                     value = tostring(value)
                  end
                  vim.env[key] = value
               end
            end

            notify("direnv environment unloaded", vim.log.levels.DEBUG)
         end)
      end
   )
end

--- Initialize direnv for current directory
--- @param path string Path to .envrc file
M._init = function(path)
   local cwd = vim.fs.dirname(path)
   local silent = M.config.notifications.silent_autoload
      and vim.b.direnv_autoload_triggered

   if not silent then
      vim.schedule(function()
         notify("Loading environment from " .. path, vim.log.levels.INFO)
      end)
   end

   local on_exit = function(obj)
      if obj.code ~= 0 then
         vim.schedule(function()
            notify(
               "Failed to load direnv: " .. (obj.stderr or "unknown error"),
               vim.log.levels.ERROR
            )
         end)
         return
      end

      vim.schedule(function()
         local stdout = obj.stdout or ""

         if stdout == "" then
            -- direnv exported no changes; nothing to do
            notify(
               "direnv export produced no output (no changes)",
               vim.log.levels.DEBUG
            )
            return
         end

         local ok, env = pcall(vim.json.decode, stdout)

         if not ok or type(env) ~= "table" then
            notify("Failed to parse direnv JSON output", vim.log.levels.ERROR)
            return
         end

         for key, value in pairs(env) do
            if value == vim.NIL or value == nil then
               vim.env[key] = nil
            else
               if type(value) ~= "string" then
                  value = tostring(value)
               end
               vim.env[key] = value
            end
         end

         if not silent then
            notify(
               "direnv environment loaded successfully",
               vim.log.levels.INFO
            )
         end
         vim.api.nvim_exec_autocmds(
            "User",
            { pattern = "DirenvLoaded", modeline = false }
         )

         if M.config.auto_restart_lsp then
            -- Reset per-load state so the LspAttach handler covers fresh buffers.
            direnv_loaded_at = vim.uv.hrtime() / 1e6
            lsp_restart_issued = {}

            local bufnr = vim.api.nvim_get_current_buf()
            local bufname = vim.api.nvim_buf_get_name(bufnr)
            if bufname ~= "" then
               -- Mark this buffer so the LspAttach handler doesn't double-restart
               -- the clients that re-attach after our vim.cmd("edit") below.
               lsp_restart_issued[bufnr] = direnv_loaded_at
               for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
                  client:stop()
               end
               vim.defer_fn(function()
                  if
                     vim.api.nvim_buf_is_valid(bufnr)
                     and vim.api.nvim_buf_get_name(bufnr) ~= ""
                  then
                     vim.cmd("edit")
                  end
               end, 500)
            end
         end
      end)
   end

   vim.system(
      { M.config.bin, "export", "json" },
      { text = true, cwd = cwd },
      on_exit
   )
end

---Allow direnv for current directory
M.allow_direnv = function()
   M._get_rc_status(function(_, path)
      if not path then
         vim.schedule(function()
            notify(
               "No .envrc file found in current directory",
               vim.log.levels.WARN
            )
         end)
         return
      end

      vim.schedule(function()
         notify("Allowing direnv for " .. path, vim.log.levels.INFO)
      end)

      -- Capture dir before the async call
      local cwd = get_cwd()
      if not cwd then
         return
      end

      vim.system(
         { M.config.bin, "allow" },
         { text = true, cwd = cwd },
         function(obj)
            if obj.code ~= 0 then
               vim.schedule(function()
                  notify(
                     "Failed to allow direnv: " .. (obj.stderr or ""),
                     vim.log.levels.ERROR
                  )
               end)
               return
            end

            -- Clear cache to ensure we get fresh data
            -- and then load the environment
            cache.status = nil
            M.check_direnv()

            vim.schedule(function()
               notify("direnv allowed for " .. path, vim.log.levels.INFO)
            end)
         end
      )
   end)
end

--- Deny direnv for current directory
M.deny_direnv = function()
   M._get_rc_status(function(_, path)
      if not path then
         vim.schedule(function()
            notify(
               "No .envrc file found in current directory",
               vim.log.levels.WARN
            )
         end)
         return
      end

      vim.schedule(function()
         notify("Denying direnv for " .. path, vim.log.levels.INFO)
      end)

      local cwd = get_cwd()
      if not cwd then
         return
      end

      vim.system(
         { M.config.bin, "deny" },
         { text = true, cwd = cwd },
         function(obj)
            if obj.code ~= 0 then
               vim.schedule(function()
                  notify(
                     "Failed to deny direnv: " .. (obj.stderr or ""),
                     vim.log.levels.ERROR
                  )
               end)
               return
            end

            cache.status = nil

            vim.schedule(function()
               notify("direnv denied for " .. path, vim.log.levels.INFO)
            end)
         end
      )
   end)
end

--- Edit the .envrc file
M.edit_envrc = function()
   M._get_rc_status(function(_, path)
      if not path then
         -- TODO: envrc can be in a different directory, e.g., the parent.
         -- We should search for it backwards eventually.
         local cwd = get_cwd()
         if not cwd then
            return
         end

         local envrc_path = cwd .. "/.envrc"
         vim.schedule(function()
            local create_new = vim.fn.confirm(
               "No .envrc file found. Create one?",
               "&Yes\n&No",
               1
            )

            if create_new == 1 then
               vim.cmd.edit(envrc_path)
            end
         end)
         return
      end

      vim.schedule(function()
         vim.cmd.edit(path)
      end)
   end)
end

--- Check and load direnv if applicable
M.check_direnv = function()
   local on_exit = function(status, path)
      if status == nil or path == nil then
         M._unload()
         return
      end

      -- Status 0 means the .envrc file is allowed
      if status == 0 then
         return M._init(path)
      end

      -- Status 2 means the .envrc file is explicitly blocked
      if status == 2 then
         vim.schedule(function()
            notify(
               path .. " is explicitly blocked by direnv",
               vim.log.levels.WARN
            )
         end)
         return
      end

      -- Status 1 means the .envrc file needs approval
      vim.schedule(function()
         local choice = vim.fn.confirm(
            path .. " is not allowed by direnv. What would you like to do?",
            "&Allow\n&Block\n&Ignore",
            1
         )

         if choice == 1 then
            M.allow_direnv()
         elseif choice == 2 then
            M.deny_direnv()
         end
         -- Ignore means do nothing
      end)
   end

   M._get_rc_status(on_exit)
end

--- Get direnv status for statusline integration
--- @return string status_string
M.statusline = function()
   if not M.config.statusline.enabled then
      return ""
   end

   if cache.status == 0 then
      return M.config.statusline.icon .. " active"
   elseif cache.status == 1 then
      return M.config.statusline.icon .. " pending"
   elseif cache.status == 2 then
      return M.config.statusline.icon .. " blocked"
   else
      return ""
   end
end

--- Setup the plugin with user configuration
--- @param user_config? table User configuration table
M.setup = function(user_config)
   if user_config and user_config.keybindings == true then
      user_config.keybindings = nil
   end

   local function check_bind(command)
      ---@diagnostic disable-next-line: need-check-nil
      if user_config.keybindings[command] == true then
         ---@diagnostic disable-next-line: need-check-nil
         user_config.keybindings[command] = nil
      end
   end

   if user_config and user_config.keybindings then
      for k, _ in pairs(user_config.keybindings) do
         check_bind(k)
      end
   end

   M.config = vim.tbl_deep_extend("force", {
      bin = "direnv",
      autoload_direnv = false,
      auto_restart_lsp = false,
      cache_ttl = 5000,
      statusline = {
         enabled = false,
         icon = "󱚟",
      },
      keybindings = {
         allow = "<Leader>da",
         deny = "<Leader>dd",
         reload = "<Leader>dr",
         edit = "<Leader>de",
      },
      notifications = {
         level = vim.log.levels.INFO,
         silent_autoload = true,
      },
   }, user_config or {})

   if not check_executable(M.config.bin) then
      return
   end

   -- Create user commands
   vim.api.nvim_create_user_command("Direnv", function(opts)
      local cmds = {
         ["allow"] = M.allow_direnv,
         ["deny"] = M.deny_direnv,
         ["reload"] = M.check_direnv,
         ["edit"] = M.edit_envrc,
         ["status"] = function()
            M._get_rc_status(function(status, path)
               if not path then
                  vim.schedule(function()
                     notify(
                        "No .envrc file found in current directory",
                        vim.log.levels.INFO
                     )
                  end)
                  return
               end

               local status_text = (status == 0 and "allowed")
                  or (status == 1 and "pending")
                  or (status == 2 and "blocked")
                  or "unknown"

               vim.schedule(function()
                  notify(
                     "direnv status: " .. status_text .. " for " .. path,
                     vim.log.levels.INFO
                  )
               end)
            end)
         end,
      }

      local cmd = cmds[string.lower(opts.fargs[1])]
      if cmd then
         cmd()
      else
         notify(
            "Unknown direnv command: " .. opts.fargs[1],
            vim.log.levels.ERROR
         )
      end
   end, {
      nargs = 1,
      complete = function()
         return { "allow", "deny", "reload", "edit", "status" }
      end,
   })

   -- Setup keybindings
   if M.config.keybindings then
      setup_keymaps({
         {
            M.config.keybindings.allow,
            M.allow_direnv,
            { desc = "Allow direnv" },
         },
         { M.config.keybindings.deny, M.deny_direnv, { desc = "Deny direnv" } },
         {
            M.config.keybindings.reload,
            M.check_direnv,
            { desc = "Reload direnv" },
         },
         {
            M.config.keybindings.edit,
            M.edit_envrc,
            { desc = "Edit .envrc file" },
         },
      }, "n")
   end

   -- Check for .envrc files and set up autoload
   local group_id = vim.api.nvim_create_augroup("DirenvNvim", { clear = true })

   if M.config.autoload_direnv then
      -- Check on directory change
      vim.api.nvim_create_autocmd({ "DirChanged" }, {
         group = group_id,
         callback = function()
            vim.b.direnv_autoload_triggered = true
            M.check_direnv()
            vim.defer_fn(function()
               vim.b.direnv_autoload_triggered = false
            end, 1000)
         end,
      })

      -- Check on startup if we're in a directory with .envrc
      vim.api.nvim_create_autocmd({ "VimEnter" }, {
         group = group_id,
         callback = function()
            vim.b.direnv_autoload_triggered = true
            M.check_direnv()
            -- Reset the flag after a short delay
            vim.defer_fn(function()
               vim.b.direnv_autoload_triggered = false
            end, 1000)
         end,
         once = true,
      })
   end

   -- Check for .envrc changes
   vim.api.nvim_create_autocmd({ "BufWritePost" }, {
      pattern = ".envrc",
      group = group_id,
      callback = function()
         M.refresh_status()
         notify(
            ".envrc file changed. Run :Direnv allow to activate changes.",
            vim.log.levels.INFO
         )
      end,
   })

   -- Restart LSP clients that attach within 10 s of a direnv load.
   -- Handles the session-manager race where buffers restore and LSP starts
   -- before (or simultaneously with) direnv loading the environment.
   vim.api.nvim_create_autocmd("LspAttach", {
      group = group_id,
      callback = function(ev)
         if not M.config.auto_restart_lsp or not direnv_loaded_at then
            return
         end

         local now = vim.uv.hrtime() / 1e6
         if now - direnv_loaded_at > 10000 then
            direnv_loaded_at = nil
            lsp_restart_issued = {}
            return
         end

         -- Skip buffers we already handled in _init or a prior LspAttach.
         if lsp_restart_issued[ev.buf] == direnv_loaded_at then
            return
         end
         lsp_restart_issued[ev.buf] = direnv_loaded_at

         for _, client in ipairs(vim.lsp.get_clients({ bufnr = ev.buf })) do
            client:stop()
         end
         vim.defer_fn(function()
            if vim.api.nvim_buf_is_valid(ev.buf) then
               vim.api.nvim_buf_call(ev.buf, function()
                  vim.cmd("edit")
               end)
            end
         end, 500)
      end,
   })

   -- Expose a command to refresh the statusline value without triggering reload
   vim.api.nvim_create_user_command("DirenvStatuslineRefresh", function()
      M.refresh_status()
   end, {})

   M._get_rc_status(function() end)

   if not M.config.notifications.silent_autoload then
      notify("direnv.nvim initialized", vim.log.levels.DEBUG)
   end
end

return M
