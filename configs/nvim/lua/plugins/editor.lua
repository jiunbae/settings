return {
  -- Disable some default plugins if needed
  -- { "plugin-name", enabled = false },

  -- Mini.pairs - auto close brackets (LazyVim includes this by default)
  -- Customize if needed:
  -- {
  --   "echasnovski/mini.pairs",
  --   opts = {
  --     modes = { insert = true, command = false, terminal = false },
  --   },
  -- },

  -- Telescope customization
  {
    "nvim-telescope/telescope.nvim",
    opts = {
      defaults = {
        layout_strategy = "horizontal",
        layout_config = {
          horizontal = {
            prompt_position = "top",
            preview_width = 0.55,
          },
          width = 0.87,
          height = 0.80,
        },
        sorting_strategy = "ascending",
      },
    },
  },

  -- Neo-tree customization
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = {
      filesystem = {
        filtered_items = {
          hide_dotfiles = false,
          hide_gitignored = false,
          hide_by_name = {
            ".git",
            "node_modules",
            "__pycache__",
            ".venv",
          },
        },
      },
      window = {
        width = 30,
      },
    },
  },

  -- Which-key customization
  {
    "folke/which-key.nvim",
    opts = {
      delay = 300, -- Show which-key popup after 300ms
    },
  },
}
