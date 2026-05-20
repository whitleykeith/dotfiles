-- load defaults i.e lua_lsp
require("nvchad.configs.lspconfig").defaults()

local nvlsp = require "nvchad.configs.lspconfig"

-- lsps with default config
local servers = {
  "html",
  "cssls",
  "gopls",            -- Go
  "solargraph",       -- Ruby
  "pyright",          -- Python
  "ts_ls",            -- TypeScript
  "kotlin_language_server",
}

for _, lsp in ipairs(servers) do
  vim.lsp.config(lsp, {
    on_attach = nvlsp.on_attach,
    on_init = nvlsp.on_init,
    capabilities = nvlsp.capabilities,
  })
  vim.lsp.enable(lsp)
end

-- Go: additional settings
vim.lsp.config("gopls", {
  settings = {
    gopls = {
      analyses = {
        unusedparams = true,
      },
      staticcheck = true,
      gofumpt = true,
    },
  },
})

-- Scala: metals has its own setup
vim.lsp.config("metals", {
  on_attach = nvlsp.on_attach,
  on_init = nvlsp.on_init,
  capabilities = nvlsp.capabilities,
  settings = {
    metals = {
      inlayHints = { inferredTypes = { enable = true } },
    },
  },
})
vim.lsp.enable("metals")
