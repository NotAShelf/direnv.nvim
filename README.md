# direnv.nvim

[Direnv]: https://direnv.net/

Dead simple Neovim plugin to add automatic [Direnv] environment loading,
inspired by `direnv.vim` and written in Lua for better performance and
maintainability.

## ✨ Features

- Seamless integration with Direnv for managing project environment variables
  - Automatic detection of `.envrc` files in your workspace
  - Proper handling of allowed, pending, and denied states
  - Keybinds for various Direnv commands
- Built-in `.envrc` editor with file creation wizard
- Statusline component showing real-time direnv status
- Event hooks for integration with other plugins
- Comprehensive API for extending functionality

### 📓 TODO

`direnv.nvim` is generally feature complete. There are no major planned
features, and it should be considered stable for the most part. What
`direnv.nvim` _cannot_ do yet is **syntax highlighting** similar to `direnv.vim`
but this is planned to be remedied through either using Treesitter, or by
porting `direnv.vim`'s syntax.vim.'

Feature requests are welcome. Please create an issue to describe the feature
that you would like to see.

## 📦 Installation

Install `direnv.nvim` with your favorite plugin manager, or clone it manually.
You will need to call the setup function to load the plugin.

### Prerequisites

- Neovim 0.8.0 or higher
- [Direnv] v2.33.0 or later installed and available in your `PATH`

### Using lazy.nvim

```lua
{
  "NotAShelf/direnv.nvim",
  config = function()
    require("direnv").setup({})
  end,
}
```

## 🚀 Usage

direnv.nvim will manage your `.envrc` files in Neovim by providing commands to
allow, deny, reload and edit them. When auto-loading is enabled, the plugin will
automatically detect and prompt for allowing `.envrc` files in your current
directory.

### Commands

- `:Direnv allow` - Allow the current directory's .envrc file
- `:Direnv deny` - Deny the current directory's .envrc file
- `:Direnv reload` - Reload direnv for the current directory
- `:Direnv edit` - Edit the `.envrc` file (creates one if it doesn't exist)
- `:Direnv status` - Show the current direnv status

### Configuration

You can pass your config table into the `setup()` function or `opts` if you use
`lazy.nvim`.

### Options

```lua
require("direnv").setup({
  -- Path to the direnv executable
  bin = "direnv",

  -- Whether to automatically load direnv when entering a directory with .envrc
  autoload_direnv = false,

  -- Statusline integration
  statusline = {
    -- Enable statusline component
    enabled = false,
    -- Icon to display in statusline
    icon = "󱚟",
  },

  -- Keyboard mappings
  keybindings = {
    allow = "<Leader>da",
    deny = "<Leader>dd",
    reload = "<Leader>dr",
    edit = "<Leader>de",
  },

  -- Notification settings
  notifications = {
    -- Log level (vim.log.levels.INFO, ERROR, etc.)
    level = vim.log.levels.INFO,
    -- Don't show notifications during autoload
    silent_autoload = true,
  },
})
```

### Statusline Integration

You can add direnv status to your statusline by using the provided function:

```lua
-- For lualine
require('lualine').setup({
  sections = {
    lualine_x = {
      function()
        return require('direnv').statusline()
      end,
      'encoding',
      'fileformat',
      'filetype',
    }
  }
})

-- For a Neovim-native statusline without plugins
vim.o.statusline = '%{%v:lua.require("direnv").statusline()%} ...'
```

The statusline function will show:

- Nothing when disabled or no .envrc is found
- "active" when the .envrc is allowed
- "pending" when the .envrc needs approval
- "blocked" when the .envrc is explicitly denied

## 🔍 API Reference

### Public Functions

- `direnv.setup(config)` - Initialize the plugin with optional configuration
- `direnv.allow_direnv()` - Allow the current directory's `.envrc` file
- `direnv.deny_direnv()` - Deny the current directory's `.envrc` file
- `direnv.check_direnv()` - Check and reload direnv for the current directory
- `direnv.edit_envrc()` - Edit the `.envrc` file
- `direnv.statusline()` - Get a string for statusline integration

#### Example

```lua
local direnv = require("direnv")

direnv.setup({
  autoload_direnv = true,
  statusline = {
    enabled = true,
  },
  keybindings = {
    allow = "<Leader>ea", -- Custom keybinding example
  },
})

-- You can also call functions directly
vim.keymap.set('n', '<Leader>er', function()
  direnv.check_direnv()
end, { desc = "Reload direnv" })
```

#### Events

The plugin triggers a User autocmd event that you can hook into:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "DirenvLoaded",
  callback = function()
    -- Code to run after direnv environment is loaded
    print("Direnv environment loaded!")
  end,
})
```

## 🫂 Special Thanks

I extend my thanks to the awesome [Lychee](https://github.com/itslychee),
[mrshmllow](https://github.com/mrshmllow) and
[diniamo](https://github.com/diniamo) for their invaluable assistance in the
creation of this plugin. I would also like to thank
[direnv.vim](https://github.com/direnv/direnv.vim) maintainers for their initial
work.

## 📜 License

<!-- markdownlint-disable MD059 -->

direnv.nvim is made available under Mozilla Public License (MPL) version 2.0.
See [LICENSE](LICENSE) for more details on the exact conditions. An online copy
is provided [here](https://www.mozilla.org/en-US/MPL/2.0/).

<!-- markdownlint-enable MD059 -->
