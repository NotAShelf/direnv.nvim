local M = {}

local function check_executable(executable_name)
   if vim.fn.executable(executable_name) ~= 1 then
      vim.api.nvim_err_writeln(
         string.format("Executable '%s' not found", executable_name)
      )
      return false
   end
   return true
end

local function setup_keymaps(keymaps, mode, opts)
   for _, map in ipairs(keymaps) do
      local options =
         vim.tbl_extend("force", { noremap = true, silent = true }, opts or {})
      vkms(mode, map[1], map[2], options)
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

   setup_keymaps({
      {
         config.keybindings.allow,
         function()
            M.allow_direnv()
         end,
         desc = "Allow direnv",
      },
      {
         config.keybindings.deny,
         function()
            M.deny_direnv()
         end,
         desc = "Deny direnv",
      },
      {
         config.keybindings.reload,
         function()
            M.check_direnv()
         end,
         desc = "Reload direnv",
      },
   }, "n")

   -- If user has enabled autoloading, and current directory has an .envrc
   -- then load it. This has performance implications as it will check for
   -- a filepath on each BufEnter event.
   if config.autoload_direnv and vim.fn.glob("**/.envrc") ~= "" then
      local group_id = vim.api.nvim_create_augroup("DirenvNvim", {})
      vim.api.nvim_create_autocmd({ "BufEnter" }, {
         pattern = "*",
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

M.check_direnv = function()
   print("Checking direnv status...")
   os.execute("direnv reload")
end

return M
