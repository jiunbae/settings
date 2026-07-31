-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local lazyref = "85c7ff3711b730b4030d03144f6db6375044ae82"
  local commands = {
    { "git", "init", lazypath },
    { "git", "-C", lazypath, "remote", "add", "origin", lazyrepo },
    { "git", "-C", lazypath, "fetch", "--depth=1", "origin", lazyref },
    { "git", "-C", lazypath, "checkout", "--detach", "FETCH_HEAD" },
  }
  for _, cmd in ipairs(commands) do
    local out = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then
      vim.api.nvim_echo({
        { "Failed to bootstrap lazy.nvim:\n", "ErrorMsg" },
        { table.concat(cmd, " ") .. "\n", "WarningMsg" },
        { out, "WarningMsg" },
        { "\nPress any key to exit..." },
      }, true, {})
      vim.fn.getchar()
      os.exit(1)
    end
  end
end
vim.opt.rtp:prepend(lazypath)

-- Make sure to setup `mapleader` and `maplocalleader` before loading lazy.nvim
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Setup lazy.nvim with LazyVim
require("lazy").setup({
  spec = {
    -- Import LazyVim and its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- Language support
    { import = "lazyvim.plugins.extras.lang.typescript" },
    { import = "lazyvim.plugins.extras.lang.python" },
    -- { import = "lazyvim.plugins.extras.lang.rust" },
    -- Import/override with your plugins
    { import = "plugins" },
  },
  defaults = {
    lazy = false,
    version = false, -- always use the latest git commit
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  checker = {
    enabled = false,
    notify = false,
  },
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
