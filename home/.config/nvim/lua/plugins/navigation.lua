return {
  {
    'stevearc/oil.nvim',
    opts = { view_options = { show_hidden = true } },
    keys = { { '<leader>e', '<cmd>Oil<cr>', desc = 'File Browser' } },
  },
  {
    'nvim-neo-tree/neo-tree.nvim',
    branch = 'v3.x',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'MunifTanjim/nui.nvim',
      'nvim-tree/nvim-web-devicons',
    },
    -- opts as a function so it evaluates at plugin load time; a plain table
    -- would require neo-tree.* before the plugin is even on the runtimepath
    opts = function()
      return {
        filesystem = {
          follow_current_file = { enabled = true },  -- tree tracks whatever buffer you're in
          window = {
            mappings = {
              ['gr'] = 'git_revert_file',  -- discard local changes for the highlighted file (asks first)
            },
          },
        },
        -- after git ops from the tree (gr revert etc.), rescan open buffers
        -- so a restored file reloads instead of showing the stale copy
        event_handlers = {
          {
            event = require('neo-tree.events').GIT_EVENT,
            handler = function() vim.cmd('checktime') end,
          },
        },
      }
    end,
    keys = {
      { '<leader>t', '<cmd>Neotree toggle<cr>', desc = 'File Tree' },
      { '<leader>R', '<cmd>Neotree reveal<cr>', desc = 'Reveal File in Tree' },
    },
  },
  {
    'folke/snacks.nvim',
    priority = 1000,
    lazy = false,
    opts = {
      picker = { enabled = true },
      notifier = { enabled = true },
      input = { enabled = true },
      words = { enabled = true },  -- highlight every occurrence of the symbol under the cursor (LSP)
    },
    keys = {
      { '<leader>f', function() Snacks.picker.files() end, desc = 'Find Files' },
      { '<leader>s', function() Snacks.picker.grep() end,  desc = 'Search Text' },
      { '<leader>b', function() Snacks.picker.buffers() end, desc = 'Buffers' },
      { 'gd', function() Snacks.picker.lsp_definitions() end, desc = 'Goto Definition' },
    },
  },
}

