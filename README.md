# ts-forge.nvim

Minimal tree-sitter parser manager for Neovim 0.12+. No dependencies — just `git` and `tree-sitter` CLI.

Compiles parsers from upstream grammar repos, copies their query files, and tracks revisions. Runs async so Neovim stays responsive.

## Requirements

- Neovim >= 0.12
- [tree-sitter CLI](https://github.com/tree-sitter/tree-sitter/blob/master/cli/README.md) >= 0.22
- `git`
- C compiler (`cc` — clang on macOS, gcc on Linux)

## Installation

### lazy.nvim

```lua
{
    "reybits/ts-forge.nvim",
    config = function()
        require("ts-forge").setup({
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
    -- Parsers to install if missing.
    ensure_installed = {},

    -- Automatically install missing ensure_installed parsers on startup.
    -- Runs async, does not block Neovim.
    auto_install = false,

    -- Where to store compiled parsers, queries, and revision info.
    -- Default is on the runtimepath so Neovim finds them automatically.
    install_dir = vim.fn.stdpath("data") .. "/site",
})
```

## Commands

| Command              | Description                                        |
| -------------------- | -------------------------------------------------- |
| `:TSInstall`         | Install all missing `ensure_installed` parsers     |
| `:TSInstall lua cpp` | Install specific parsers (tab completion supported) |
| `:TSUpdate`          | Update all installed parsers to pinned revisions   |

## How it works

1. **Fetch** — shallow-clones a single commit from the grammar repo (`git fetch --depth 1`)
2. **Build** — compiles with `tree-sitter build` (handles C/C++ scanners, platform flags automatically)
3. **Queries** — copies `.scm` query files from the grammar repo
4. **Track** — records the installed revision to skip reinstalls

Parsers and queries are installed to `<install_dir>/parser/` and `<install_dir>/queries/` respectively. Dependencies are resolved automatically (e.g. `cpp` installs `c` first).

## Available parsers

bash, c, cmake, cpp, css, gitignore, html, java, javascript, json, lua, make, markdown, markdown_inline, python, query, regex, tsx, typescript, vim, vimdoc, yaml

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

For parsers that depend on another parser's queries (via `; inherits:`), add `requires`:

```lua
cpp = {
    url = "https://github.com/tree-sitter/tree-sitter-cpp",
    rev = "...",
    requires = { "c" },
},
```

## License

[MIT License](LICENSE)

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.
