local M = {}

local function check_executable(executable_name)
   if vim.fn.executable(executable_name) ~= 1 then
      vim.notify(
         "Executable '" .. executable_name .. "' not found",
         vim.log.levels.ERROR
      )
      return false
   end
   return true
end

local function setup_keymaps(keymaps, mode)
   for _, map in ipairs(keymaps) do
      local options = vim.tbl_extend(
         "force",
         { noremap = true, silent = true },
         map[3] or {}
      )
      vim.keymap.set(mode, map[1], map[2], options)
   end
end

M.setup = function(user_config)
   local config = vim.tbl_deep_extend("force", {
      bin = "direnv",
      autoload_direnv = false,
      keybindings = {
         allow = "<Leader>da",
         deny = "<Leader>dd",
         reload = "<Leader>dr",
      },
   }, user_config or {})

   if not check_executable(config.bin) then
      return
   end

   vim.api.nvim_create_user_command("Direnv", function(opts)
      local cmds = {
         ["allow"] = M.allow_direnv,
         ["deny"] = M.deny_direnv,
         ["reload"] = M.check_direnv,
      }
      local cmd = cmds[string.lower(opts.fargs[1])]
      if cmd then
         cmd()
      end
   end, {
      nargs = 1,
      complete = function()
         return { "allow", "deny", "reload" }
      end,
   })

   setup_keymaps({
      {
         config.keybindings.allow,
         function()
            M.allow_direnv()
         end,
         { desc = "Allow direnv" },
      },
      {
         config.keybindings.deny,
         function()
            M.deny_direnv()
         end,
         { desc = "Deny direnv" },
      },
      {
         config.keybindings.reload,
         function()
            M.check_direnv()
         end,
         { desc = "Reload direnv" },
      },
   }, "n")

   -- If user has enabled autoloading, and current directory has an .envrc
   -- then load it. This has performance implications as it will check for
   -- a filepath on each BufEnter event.
   if config.autoload_direnv and vim.fn.glob("**/.envrc") ~= "" then
      local group_id = vim.api.nvim_create_augroup("DirenvNvim", {})

      vim.api.nvim_create_autocmd({ "DirChanged" }, {
         pattern = "global",
         group = group_id,
         callback = function()
            M.check_direnv()
         end,
      })
   end
end

M.allow_direnv = function()
   print("Allowing direnv...")
   os.execute("direnv allow")
end

M.deny_direnv = function()
   print("Denying direnv...")
   os.execute("direnv deny")
end

M._get_rc_status = function(callback)
   local on_exit = function(obj)
      local status = vim.json.decode(obj.stdout)

      if status.state.foundRC == nil then
         return callback(nil, nil)
      end

      callback(status.state.foundRC.allowed, status.state.foundRC.path)
   end

   return vim.system(
      { "direnv", "status", "--json" },
      { text = true, cwd = vim.fn.getcwd(-1, -1) },
      on_exit
   )
end

M._init = function(path)
   vim.schedule(function()
      vim.notify("Reloading " .. path)
   end)

   local cwd = vim.fs.dirname(path)
   local temppath = vim.fn.tempname()
   local tempfile = io.open(temppath, "w")

   if not tempfile then
      vim.notify("Couldn't create temporary file", vim.log.levels.ERROR)
      return
   end

   local write_output = function(_, data)
      if data then
         tempfile:write(data)
      end
   end

   local on_exit = function(obj)
      vim.schedule(function()
         if obj.code ~= 0 then
            vim.notify("Direnv exited with an error", vim.log.levels.ERROR)
         else
            vim.cmd.source(temppath)
         end

         tempfile:close()
         os.remove(temppath)
      end)
   end

   vim.system(
      { "direnv", "export", "vim" },
      { cwd = cwd, stdout = write_output },
      on_exit
   )
end

M.check_direnv = function()
   local on_exit = function(status, path)
      if status == nil or path == nil then
         return
      end

      vim.schedule(function()
         -- Allowed
         if status == 0 then
            return M._init(path)
         end

         -- Blocked
         if status == 2 then
            return
         end

         local choice =
            vim.fn.confirm(path .. " is blocked.", "&Allow\n&Block\n&Ignore", 3)

         if choice == 1 then
            M.allow_direnv()
            M._init(path)
         end

         if choice == 2 then
            M._init(path)
         end
      end)
   end

   M._get_rc_status(on_exit)
end

return M
