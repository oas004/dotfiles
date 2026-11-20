-- https://github.com/saghen/blink.cmp
-- Completion: LSP, file paths, snippets (friendly-snippets and those the
-- language servers send, expanded with vim.snippet) and words from open
-- buffers, plus completion on the : and / command lines.

-- Move through the menu without inserting the item (like Tab and the arrow
-- keys did with nvim-cmp's Select behaviour). Returns nil when the menu is
-- closed, so the next command for the key runs. In select mode (a snippet
-- placeholder is selected) blink's menu can still be open from typing in the
-- previous placeholder; Tab/S-Tab jump there instead of selecting, as they
-- did with nvim-cmp, which closed its menu on leaving insert mode.
local function in_select_mode()
  return vim.api.nvim_get_mode().mode == "s"
end

local function select_next(cmp)
  if in_select_mode() then
    return
  end
  return cmp.select_next({ auto_insert = false })
end

local function select_prev(cmp)
  if in_select_mode() then
    return
  end
  return cmp.select_prev({ auto_insert = false })
end

-- C-n/C-p insert the item as they move through the menu; with the menu
-- closed they fall through to "show".
local function insert_next(cmp)
  return cmp.select_next({ auto_insert = true })
end

local function insert_prev(cmp)
  return cmp.select_prev({ auto_insert = true })
end

local function scroll_docs(delta)
  return function(cmp)
    if delta < 0 then
      return cmp.scroll_documentation_up(-delta)
    end
    return cmp.scroll_documentation_down(delta)
  end
end

return {
  {
    "saghen/blink.cmp",
    -- On a release tag, blink downloads the prebuilt fuzzy matcher for that
    -- release. lazy-lock.json holds the commit actually installed.
    version = "1.*",
    dependencies = { "rafamadriz/friendly-snippets" },
    -- Fetch the prebuilt fuzzy matcher at install and update time (also run
    -- by :Lazy! restore in bootstrap.sh and CI), so it isn't downloaded on
    -- first use. If that fails later (offline, unsupported system),
    -- fuzzy.implementation below falls back to the Lua matcher quietly.
    build = function()
      local done, failed = false, nil
      require("blink.cmp.fuzzy.download").ensure_downloaded(function(err, implementation)
        failed = err or (implementation ~= "rust" and "fell back to the Lua matcher") or nil
        done = true
      end)
      vim.wait(120000, function()
        return done
      end, 100)
      if failed or not done then
        error("blink.cmp fuzzy matcher download failed: " .. tostring(failed or "timed out"))
      end
    end,
    -- Loaded at startup rather than on InsertEnter: language servers attach
    -- when a file is opened, before the first InsertEnter, and need blink's
    -- completion capabilities (plugins/language-server.lua).
    lazy = false,
    opts = {
      keymap = {
        preset = "none",
        ["<C-Space>"] = { "show" },
        -- Menu open: select. Otherwise jump between snippet placeholders,
        -- otherwise the key's own meaning (indent). Also mapped in select
        -- mode, where vim.snippet leaves the placeholder text selected.
        ["<Tab>"] = { select_next, "snippet_forward", "fallback" },
        ["<S-Tab>"] = { select_prev, "snippet_backward", "fallback" },
        -- Accepts the selected item, or the first one if none is selected
        ["<CR>"] = { "select_and_accept", "fallback" },
        -- Only accepts an item that is selected
        ["<C-y>"] = { "accept", "fallback" },
        ["<C-e>"] = { "cancel", "fallback" },
        ["<Up>"] = { select_prev, "fallback" },
        ["<Down>"] = { select_next, "fallback" },
        ["<C-p>"] = { insert_prev, "show" },
        ["<C-n>"] = { insert_next, "show" },
        ["<C-u>"] = { scroll_docs(-4), "fallback" },
        ["<C-d>"] = { scroll_docs(4), "fallback" },
      },
      completion = {
        -- Nothing is selected or inserted until you move into the menu
        list = { selection = { preselect = false, auto_insert = false } },
        documentation = { auto_show = true, auto_show_delay_ms = 200 },
        menu = {
          draw = {
            -- Label, then the source ([LSP], [Buffer], ...) and the kind
            columns = { { "label", "label_description", gap = 1 }, { "source_name" }, { "kind" } },
            components = {
              source_name = {
                text = function(ctx)
                  return "[" .. ctx.source_name .. "]"
                end,
              },
            },
          },
        },
      },
      -- blink's own signature help stays off (the default). Insert-mode
      -- <C-k> shows LSP signature help in LSP buffers (language-server.lua).
      signature = { enabled = false },
      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
      },
      -- The prebuilt Rust matcher when it is there, otherwise the Lua one,
      -- without the startup warning of prefer_rust_with_warning.
      fuzzy = { implementation = "prefer_rust" },
    },
    -- Lets other specs add to sources.default (e.g. lazydev) instead of
    -- replacing the list
    opts_extend = { "sources.default" },
  },
}
