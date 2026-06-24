if vim.b.did_ftplugin then
   return
end
vim.b.did_ftplugin = true

-- Set buffer-local commentstring
vim.bo.commentstring = "# %s"

-- Saving an .envrc (or related) should automatically trigger the plugin's
-- reload/refresh behavior without causing errors when the plugin/command
-- is not installed.
local group = vim.api.nvim_create_augroup("DirenvBuffer", { clear = false })
vim.api.nvim_create_autocmd("BufWritePost", {
   group = group,
   buffer = 0,
   callback = function()
      -- Trigger the Direnv reload command if available
      if vim.fn.exists(":Direnv") == 2 then
         pcall(vim.cmd, "Direnv reload")
      end
   end,
})

-- Decide whether to use tree-sitter or legacy syntax script. Tree-sitter
-- is more modern and is almost always preferrable to Regex-based highlighting
-- that the legacy method requires, but it's difficult to bundle a Tree-sitter
-- grammar, so we cannot unconditionally load my own Direnv grammar. Though, if
-- it IS available then we should skip legacy syntax highlighting.
local has_ts = false
local ok, parsers = pcall(require, "nvim-treesitter.parsers")
if ok and type(parsers.has_parser) == "function" then
   has_ts = parsers.has_parser("direnv")
end

if has_ts then
   -- If a parser exists, prefer tree-sitter highlighting. Nothing to do
   -- here because nvim-treesitter will attach based on filetype by itself.
   return
end

-- Set syntax to direnv so Vim will load the bundled syntax file. Only set
-- if no syntax is already active for this buffer, i.e., if tree-sitter is
-- not loaded/available.
if not vim.bo.syntax or vim.bo.syntax == "" then
   -- setlocal syntax=direnv should cause Vim to load syntax/direnv.vim from runtime
   pcall(vim.cmd, "setlocal syntax=direnv")
end
