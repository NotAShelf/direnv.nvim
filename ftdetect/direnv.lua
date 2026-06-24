-- Detect .envrc, .direnvrc, direnvrc files and set filetype to 'direnv'
local group = vim.api.nvim_create_augroup("direnv_ftdetect", { clear = true })
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
   group = group,
   pattern = { ".envrc*", ".direnvrc*", "direnvrc*" },
   callback = function()
      vim.bo.filetype = "direnv"
   end,
})
