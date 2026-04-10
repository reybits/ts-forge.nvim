# ts-forge.nvim

Minimal tree-sitter parser manager for Neovim 0.12+. No plugin dependencies.

Compiles parsers from upstream grammar repos using the `tree-sitter` CLI, copies query files, and tracks revisions. Parsers bundled with Neovim are detected automatically and never overwritten.

## Features

- Async install — does not block Neovim
- Auto-install on startup (optional)
- Bundled parser detection — prefers Neovim's built-in parsers and queries
- Monorepo support (e.g. typescript/tsx share a repo)
- Dependency resolution (e.g. cpp installs c first)
- Revision pinning with integrity checks
- Cross-platform — macOS (clang) and Linux (gcc)
- `:checkhealth` support

## Requirements

- Neovim >= 0.12
- [tree-sitter CLI](https://github.com/tree-sitter/tree-sitter/blob/master/cli/README.md) >= 0.22
- `git`
- C compiler (`cc`)

## Installation

### lazy.nvim

```lua
{
    "reybits/ts-forge.nvim",
    config = function()
        require("ts-forge").setup({
            auto_install = true,
            ensure_installed = {
                "bash",
                "c",
                "cpp",
                "json",
                "lua",
                "markdown",
                "markdown_inline",
                "python",
                "yaml",
            },
        })
    end,
}
```

## Configuration

```lua
require("ts-forge").setup({
    -- Parsers to ensure are installed.
    -- Bundled parsers (c, lua, markdown, etc.) are included automatically.
    ensure_installed = {},

    -- Automatically install missing parsers on startup (async).
    auto_install = false,

    -- Where to store compiled parsers, queries, and revision info.
    -- Default location is already on Neovim's runtimepath.
    install_dir = vim.fn.stdpath("data") .. "/site",
})
```

## Commands

| Command                 | Description                                          |
| ----------------------- | ---------------------------------------------------- |
| `:TSInstall`            | Install all missing `ensure_installed` parsers       |
| `:TSInstall lua cpp`    | Install specific parsers (tab completion supported)  |
| `:TSUpdate`             | Reinstall parsers that are outdated or incomplete    |
| `:checkhealth ts-forge` | Check requirements, installed parsers, and integrity |

## How it works

1. **Fetch** — shallow-clones a single commit from the grammar repo
2. **Build** — compiles with `tree-sitter build` (handles C/C++ scanners and platform flags)
3. **Queries** — copies `.scm` query files from the grammar repo to the install directory. For parsers bundled with Neovim, both the parser and queries are skipped entirely.
4. **Track** — records the installed revision and query status to skip unnecessary reinstalls

Install state is tracked per-parser in `<install_dir>/parser-info/<lang>.revision`. This file records the pinned revision and whether queries were copied, enabling integrity checks: if the `.so` or query files are deleted, the next install restores them.

## Bundled parsers

Neovim 0.12 ships with parsers and queries for: **c**, **lua**, **markdown**, **markdown\_inline**, **query**, **vim**, **vimdoc**. These are detected at runtime and preferred over compiled versions. You can safely include them in `ensure_installed` — they will be skipped.

## Adding a parser

Add an entry to `M.parsers` in `lua/ts-forge/init.lua`:

```lua
rust = {
    url = "https://github.com/tree-sitter/tree-sitter-rust",
    rev = "<commit-hash-or-tag>",
},
```

For monorepo grammars, add `location`:

```lua
tsx = {
    url = "https://github.com/tree-sitter/tree-sitter-typescript",
    rev = "...",
    location = "tsx",
},
```

For parsers whose queries use `; inherits:` from another language, add `requires` so the dependency is installed first:

```lua
cpp = {
    url = "https://github.com/tree-sitter/tree-sitter-cpp",
    rev = "...",
    requires = { "c" },
},
```

## License

[MIT License](LICENSE)
