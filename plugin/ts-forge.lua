-------------------------------------------------------------------------------
-- A Neovim plugin that fixes Tree-sitter issues.
--
-- Author: Andrey Ugolnik
-- License: MIT
-- GitHub: https://github.com/reybits/
--

vim.api.nvim_create_user_command("TSInstall", function(args)
    require("ts-forge").install(#args.fargs > 0 and args.fargs or nil)
end, {
    nargs = "*",
    complete = function()
        return vim.tbl_keys(require("ts-forge").parsers)
    end,
    desc = "Install tree-sitter parsers",
})

vim.api.nvim_create_user_command("TSUpdate", function()
    require("ts-forge").update()
end, {
    nargs = 0,
    desc = "Update tree-sitter parsers to pinned revisions",
})
