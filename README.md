# direnv.nvim

Dead simple Neovim plugin to add automatic Direnv loading, inspired by
`direnv.vim` and written in Lua.

## 📦 Installation

Install `direnv.nvim` with your favorite plugin manager, or clone it manually.
You will need to call the setup function to load the plugin.

## 🚀 Usage

direnv.nvim will automatically call `direnv allow` in your current directory if
`direnv` is available in your PATH, and you have auto-loading enabled.

## 🔧 Configuration

You can pass your config table into the `setup()` function or `opts` if you use
`lazy.nvim`.

### Options

- `bin` (optional, type: string): the path to the Direnv binary. May be an
  absolute path, or just `direnv` if it's available in your PATH. - Default:
  `direnv`
- `autoload_direnv` (optional, type: boolean): whether to call `direnv allow`
  when you enter a directory that contains an `.envrc`. - Default: `false`
- `keybindings` (optional, type: table of strings): the table of keybindings to
  use.
  - Default:
    `{allow = "<Leader>da", deny = "<Leader>dd", reload = "<Leader>dr"}`

#### Example:

```lua
require("direnv").setup({
   autoload_direnv = true,
})
```
