return {
  -- syntax-tree aware editing: real highlighting + smart selection
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'master',  -- legacy master branch: still carries the module system (highlight, incremental_selection)
    build = ':TSUpdate',
    main = 'nvim-treesitter.configs',
    opts = {
      ensure_installed = {
        'lua', 'python', 'typescript', 'tsx', 'javascript',
        'go', 'scala', 'java',
        'json', 'yaml', 'nix', 'vim', 'vimdoc', 'markdown', 'markdown_inline',
      },
      highlight = { enable = true },
      -- IntelliJ-style expand selection: vv grabs the word under the cursor,
      -- v grows it outward (word -> string -> expression -> statement -> block),
      -- <BS> shrinks back down.
      incremental_selection = {
        enable = true,
        keymaps = {
          init_selection = 'vv',
          node_incremental = 'v',
          node_decremental = '<BS>',
        },
      },
    },
  },
}
