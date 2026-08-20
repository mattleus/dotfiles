return {
  {
    'neovim/nvim-lspconfig',
    lazy = false,  -- servers start at startup, attaching to matching filetypes
    dependencies = { 'b0o/schemastore.nvim' },  -- json/yaml schemas (package.json, github actions, ...)
    config = function()
      -- Binaries come from home.nix (nix), not mason, so the machine stays reproducible.
      -- lspconfig ships sane defaults; vim.lsp.config overrides, vim.lsp.enable turns on.
      vim.lsp.config('lua_ls', {
        settings = {
          Lua = {
            -- the globals this config uses, so they stop showing as "undefined"
            diagnostics = { globals = { 'vim', 'Snacks' } },
          },
        },
      })
      vim.lsp.config('jsonls', {
        settings = {
          json = {
            schemas = require('schemastore').json.schemas(),
            validate = { enable = true },
          },
        },
      })
      vim.lsp.config('yamlls', {
        settings = {
          yaml = {
            schemaStore = { enable = false, url = '' },  -- schemastore serves them instead
            schemas = require('schemastore').yaml.schemas(),
          },
        },
      })

      vim.lsp.enable('pyright')   -- python
      vim.lsp.enable('ts_ls')     -- typescript / javascript / react
      vim.lsp.enable('jsonls')    -- json
      vim.lsp.enable('yamlls')    -- yaml
      vim.lsp.enable('lua_ls')    -- lua

      -- gd already lives in snacks (navigation.lua). Neovim 0.11+ also maps
      -- grn (rename), gra (code action), grr (references) once a server attaches;
      -- the leader ones below just make them show up in which-key.
      vim.api.nvim_create_autocmd('LspAttach', {
        callback = function(event)
          local map = function(keys, fn, desc)
            vim.keymap.set('n', keys, fn, { buffer = event.buf, desc = desc })
          end
          map('<leader>rn', vim.lsp.buf.rename, 'Rename Symbol')
          map('<leader>ca', vim.lsp.buf.code_action, 'Code Action')
          map('<leader>r', function() Snacks.picker.lsp_references() end, 'References')
          map('[d', function() vim.diagnostic.jump({ count = -1 }) end, 'Prev Diagnostic')
          map(']d', function() vim.diagnostic.jump({ count = 1 }) end, 'Next Diagnostic')
        end,
      })
    end,
  },
}
