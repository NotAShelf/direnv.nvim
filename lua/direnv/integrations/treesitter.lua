local M = {}

-- Direnv keyword groups based on syntax.vim
local direnv_keywords = {
   -- Command functions (takes CLI command argument)
   command_funcs = {
      "has",
   },

   -- Path functions (takes file/dir path argument)
   path_funcs = {
      "dotenv",
      "dotenv_if_exists",
      "env_vars_required",
      "fetchurl",
      "join_args",
      "user_rel_path",
      "on_git_branch",
      "find_up",
      "has",
      "source_env",
      "source_env_if_exists",
      "source_up",
      "source_up_if_exists",
      "source_url",
      "PATH_add",
      "MANPATH_add",
      "load_prefix",
      "watch_file",
      "watch_dir",
      "semver_search",
      "strict_env",
      "unstrict_env",
   },

   -- Expand path functions
   expand_path_funcs = {
      "expand_path",
   },

   -- Path add functions (takes variable name and dir path)
   path_add_funcs = {
      "PATH_add",
      "MANPATH_add",
      "PATH_rm",
      "path_rm",
      "path_add",
   },

   -- Use functions
   use_funcs = {
      "use",
      "use_flake",
      "use_guix",
      "use_julia",
      "use_nix",
      "use_node",
      "use_nodenv",
      "use_rbenv",
      "use_vim",
      "rvm",
   },

   -- Layout functions
   layout_funcs = {
      "layout",
      "layout_anaconda",
      "layout_go",
      "layout_julia",
      "layout_node",
      "layout_perl",
      "layout_php",
      "layout_pipenv",
      "layout_pyenv",
      "layout_python",
      "layout_python2",
      "layout_python3",
      "layout_ruby",
   },

   -- Layout languages
   layout_languages = {
      "go",
      "node",
      "perl",
      "python3",
      "ruby",
   },

   -- Layout language paths
   layout_language_paths = {
      "python",
   },

   -- Other functions
   other_funcs = {
      "direnv_apply_dump",
      "direnv_layout_dir",
      "direnv_load",
      "direnv_version",
      "log_error",
      "log_status",
   },
}

-- Check if Treesitter is available
local function has_treesitter()
   return vim.fn.has("nvim-0.8.0") == 1 and pcall(require, "nvim-treesitter")
end

-- Check if bash parser is available
local function has_bash_parser()
   local ok, parsers = pcall(require, "nvim-treesitter.parsers")
   return ok and parsers.has_parser("bash")
end

-- Setup Treesitter highlighting for direnv
M.setup = function(config)
   if not config.integrations.treesitter.enabled then
      return
   end

   if not has_treesitter() then
      return
   end

   if not has_bash_parser() then
      return
   end

   -- Create highlight groups
   local highlights = {
      -- Command functions
      ["@direnv.command_func"] = { link = "Function" },
      ["@direnv.command"] = { link = "Identifier" },
      
      -- Path functions
      ["@direnv.path_func"] = { link = "Function" },
      ["@direnv.path"] = { link = "Directory" },
      ["@direnv.expand_path_func"] = { link = "Function" },
      ["@direnv.expand_path_rel"] = { link = "Directory" },
      ["@direnv.path_add_func"] = { link = "Function" },
      ["@direnv.var"] = { link = "Identifier" },
      
      -- Use functions
      ["@direnv.use_func"] = { link = "Function" },
      ["@direnv.use_command"] = { link = "Identifier" },
      
      -- Layout functions
      ["@direnv.layout_func"] = { link = "Function" },
      ["@direnv.layout_language"] = { link = "Identifier" },
      ["@direnv.layout_language_path"] = { link = "Identifier" },
      
      -- Other functions
      ["@direnv.func"] = { link = "Function" },
   }

   for group, hl in pairs(highlights) do
      vim.api.nvim_set_hl(0, group, hl)
   end

   -- Setup autocmd for .envrc files
   local group = vim.api.nvim_create_augroup("DirenvTreesitter", { clear = true })
   
   vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
      group = group,
      pattern = ".envrc",
      callback = function()
         M.setup_buffer()
      end,
   })
end

-- Setup Treesitter highlighting for current buffer
M.setup_buffer = function()
   if not has_treesitter() or not has_bash_parser() then
      return
   end

   local bufnr = vim.api.nvim_get_current_buf()
   local ft = vim.bo[bufnr].filetype

   -- Only apply to .envrc files or bash files
   if ft ~= "sh" and ft ~= "bash" and not vim.fn.expand("%:t"):match("%.envrc$") then
      return
   end

   -- Set filetype to bash if it's .envrc
   if vim.fn.expand("%:t"):match("%.envrc$") then
      vim.bo[bufnr].filetype = "bash"
   end

   -- Use the proper Treesitter API for highlighting
   local ok, ts = pcall(require, "vim.treesitter")
   if not ok then
      return
   end

   -- Create queries for direnv keywords
   local query = M.create_queries()
   
   -- Add the queries to the buffer
   ts.query.set("bash", "highlights", query)

   -- Force Treesitter to re-parse and re-highlight the buffer
   vim.schedule(function()
      local parser = ts.get_parser(bufnr, "bash")
      if parser then
         parser:parse()
      end
   end)
end

-- Create Treesitter queries for direnv keywords
M.create_queries = function()
   local patterns = {}

   -- Create query patterns for each keyword group
   local function create_pattern(keywords, capture_name)
      for _, keyword in ipairs(keywords) do
         table.insert(patterns, string.format(
            '((call_expression function: (identifier) @%s) (#eq? @%s "%s"))',
            capture_name, capture_name, keyword
         ))
      end
   end

   -- Add patterns for all keyword groups
   create_pattern(direnv_keywords.command_funcs, "direnv.command_func")
   create_pattern(direnv_keywords.path_funcs, "direnv.path_func")
   create_pattern(direnv_keywords.expand_path_funcs, "direnv.expand_path_func")
   create_pattern(direnv_keywords.path_add_funcs, "direnv.path_add_func")
   create_pattern(direnv_keywords.use_funcs, "direnv.use_func")
   create_pattern(direnv_keywords.layout_funcs, "direnv.layout_func")
   create_pattern(direnv_keywords.other_funcs, "direnv.func")
   
   -- Layout languages
   create_pattern(direnv_keywords.layout_languages, "direnv.layout_language")
   create_pattern(direnv_keywords.layout_language_paths, "direnv.layout_language_path")

   return table.concat(patterns, "\n")
end

-- Get all direnv keywords for completion
M.get_keywords = function()
   local all_keywords = {}
   
   for _, group in pairs(direnv_keywords) do
      if type(group) == "table" then
         for _, keyword in ipairs(group) do
            table.insert(all_keywords, keyword)
         end
      end
   end
   
   return all_keywords
end

return M