-- Parsers installed by nvim-treesitter. Languages without an entry here
-- can still be installed manually with :TSInstall <lang>.
local parsers = {
    "c", "lua", "vim", "vimdoc", "query",
    "javascript", "json", "kotlin", "typescript", "yaml",
    -- Rust / WebAssembly
    "rust", "toml", "wit",
    -- Languages with configured LSPs
    "java", "python", "haskell", "cpp", "bash", "markdown", "markdown_inline",
}
-- Exposed so bootstrap.sh can install the same list synchronously.
vim.g.treesitter_parsers = parsers

-- Treesitter highlighting is skipped for files larger than this.
local max_filesize = 100 * 1024

-- nvim-treesitter's main branch dropped Neovim 0.11 support in c82bf96f.
-- On 0.11, pin the last main commit that still supports it. Once Neovim is
-- 0.12 or newer the pin goes away and the plugin follows main.
local nvim_011_commit = "90cd6580e720caedacb91fdd587b747a6e77d61f"

return {
    -- https://github.com/nvim-treesitter/nvim-treesitter/tree/main
    {
        "nvim-treesitter/nvim-treesitter",
        branch = "main",
        commit = vim.fn.has("nvim-0.12") == 0 and nvim_011_commit or nil,
        lazy = false, -- main does not support lazy-loading
        priority = 100,
        build = ":TSUpdate",
        config = function()
            local ts = require("nvim-treesitter")
            if not ts.install then
                -- Still on the old master checkout until lazy switches branches
                vim.notify("nvim-treesitter is not on the main branch yet, run :Lazy sync", vim.log.levels.WARN)
                return
            end

            -- Install missing parsers in the background. Compiling a parser
            -- needs the tree-sitter CLI and a C compiler.
            local installed = ts.get_installed("parsers")
            local missing = vim.tbl_filter(function(lang)
                return not vim.list_contains(installed, lang)
            end, parsers)
            if #missing > 0 then
                if vim.fn.executable("tree-sitter") == 1 then
                    ts.install(missing)
                else
                    vim.notify(
                        "nvim-treesitter: tree-sitter CLI not found, cannot install parsers: "
                            .. table.concat(missing, ", "),
                        vim.log.levels.WARN
                    )
                end
            end

            -- Highlighting is no longer a plugin module on main; start it per
            -- buffer instead. pcall because not every filetype has a parser.
            vim.api.nvim_create_autocmd("FileType", {
                group = vim.api.nvim_create_augroup("treesitter_highlight", { clear = true }),
                callback = function(args)
                    local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(args.buf))
                    if ok and stats and stats.size > max_filesize then
                        return
                    end
                    pcall(vim.treesitter.start, args.buf)
                end,
            })
        end,
    },

    -- Treesitter text objects (af, if, etc)
    {
        "nvim-treesitter/nvim-treesitter-textobjects",
        branch = "main",
        dependencies = { "nvim-treesitter/nvim-treesitter" },
        config = function()
            require("nvim-treesitter-textobjects").setup({
                select = {
                    lookahead = true,
                },
            })

            -- Text object keymaps: af = around function, if = inside function
            vim.keymap.set({ "x", "o" }, "af", function()
                require("nvim-treesitter-textobjects.select").select_textobject("@function.outer", "textobjects")
            end, { desc = "Select around function" })

            vim.keymap.set({ "x", "o" }, "if", function()
                require("nvim-treesitter-textobjects.select").select_textobject("@function.inner", "textobjects")
            end, { desc = "Select inside function" })

            vim.keymap.set({ "x", "o" }, "ac", function()
                require("nvim-treesitter-textobjects.select").select_textobject("@class.outer", "textobjects")
            end, { desc = "Select around class" })

            vim.keymap.set({ "x", "o" }, "ic", function()
                require("nvim-treesitter-textobjects.select").select_textobject("@class.inner", "textobjects")
            end, { desc = "Select inside class" })

            -- Move keymaps: ]m = next function, [m = previous function
            vim.keymap.set({ "n", "x", "o" }, "]m", function()
                require("nvim-treesitter-textobjects.move").goto_next_start("@function.outer", "textobjects")
            end, { desc = "Next function start" })

            vim.keymap.set({ "n", "x", "o" }, "[m", function()
                require("nvim-treesitter-textobjects.move").goto_previous_start("@function.outer", "textobjects")
            end, { desc = "Previous function start" })

            vim.keymap.set({ "n", "x", "o" }, "]M", function()
                require("nvim-treesitter-textobjects.move").goto_next_end("@function.outer", "textobjects")
            end, { desc = "Next function end" })

            vim.keymap.set({ "n", "x", "o" }, "[M", function()
                require("nvim-treesitter-textobjects.move").goto_previous_end("@function.outer", "textobjects")
            end, { desc = "Previous function end" })
        end,
    },
}
