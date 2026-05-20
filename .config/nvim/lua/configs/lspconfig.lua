-- load defaults i.e lua_lsp
require("nvchad.configs.lspconfig").defaults()

local nvlsp = require "nvchad.configs.lspconfig"

-- lsps with default config
local servers = {
  -- Languages
  "html",
  "cssls",
  "gopls",            -- Go
  "solargraph",       -- Ruby
  "pyright",          -- Python
  "ts_ls",            -- TypeScript
  "kotlin_language_server",
  "bashls",           -- Bash/Shell
  -- Infrastructure / Config
  "dockerls",         -- Dockerfile
  "docker_compose_language_service",
  "terraformls",      -- Terraform HCL
  "helm_ls",          -- Helm charts
  "taplo",            -- TOML
  "sqls",             -- SQL
  "buf_ls",           -- Protobuf
  "jsonls",           -- JSON (with SchemaStore)
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

-- YAML: with Kubernetes schema detection
vim.lsp.config("yamlls", {
  on_attach = nvlsp.on_attach,
  on_init = nvlsp.on_init,
  capabilities = nvlsp.capabilities,
  settings = {
    yaml = {
      schemas = {
        kubernetes = "/*.k8s.yaml",
        ["http://json.schemastore.org/github-workflow"] = ".github/workflows/*",
        ["http://json.schemastore.org/github-action"] = ".github/action.{yml,yaml}",
        ["http://json.schemastore.org/kustomization"] = "kustomization.{yml,yaml}",
        ["http://json.schemastore.org/chart"] = "Chart.{yml,yaml}",
      },
      schemaStore = {
        enable = true,
        url = "https://www.schemastore.org/api/json/catalog.json",
      },
      validate = true,
      completion = true,
      hover = true,
    },
  },
})
vim.lsp.enable("yamlls")

-- JSON: with SchemaStore support
vim.lsp.config("jsonls", {
  settings = {
    json = {
      schemas = require("schemastore").json.schemas(),
      validate = { enable = true },
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
