return {
  {
    'NeogitOrg/neogit',
    dependencies = { 'nvim-lua/plenary.nvim', 'sindrets/diffview.nvim' },
    keys = {
      { '<leader>gg', function() require('neogit').open() end, desc = 'Neogit' },
      { '<leader>gd', '<cmd>Gitsigns diffthis main<cr>', desc = 'Diff File vs main' },
      { '<leader>gD', '<cmd>DiffviewOpen main...<cr>', desc = 'Diff Project vs main' },
    },
  },
  {
    'lewis6991/gitsigns.nvim',
    event = 'BufWinEnter',
    opts = { current_line_blame = true },  -- who last touched this line
  },
}

