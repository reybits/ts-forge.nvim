-------------------------------------------------------------------------------
-- A Neovim plugin that fixes Tree-sitter issues.
--
-- Author: Andrey Ugolnik
-- License: MIT
-- GitHub: https://github.com/reybits/
--

local M = {}

--- Parser registry: lang -> { url, rev, location?, requires? }
--- Parsers bundled with Neovim (c, lua, markdown, markdown_inline, query, vim, vimdoc)
--- are not listed — they are detected automatically and preferred over compiled ones.
--- Revisions sourced from nvim-treesitter/nvim-treesitter (main branch).
M.parsers = {
    bash = {
        url = "https://github.com/tree-sitter/tree-sitter-bash",
        rev = "a06c2e4415e9bc0346c6b86d401879ffb44058f7",
    },
    cmake = {
        url = "https://github.com/uyha/tree-sitter-cmake",
        rev = "c7b2a71e7f8ecb167fad4c97227c838439280175",
    },
    cpp = {
        url = "https://github.com/tree-sitter/tree-sitter-cpp",
        rev = "8b5b49eb196bec7040441bee33b2c9a4838d6967",
        requires = { "c" },
    },
    css = {
        url = "https://github.com/tree-sitter/tree-sitter-css",
        rev = "dda5cfc5722c429eaba1c910ca32c2c0c5bb1a3f",
    },
    gitignore = {
        url = "https://github.com/shunsambongi/tree-sitter-gitignore",
        rev = "f4685bf11ac466dd278449bcfe5fd014e94aa504",
    },
    html = {
        url = "https://github.com/tree-sitter/tree-sitter-html",
        rev = "73a3947324f6efddf9e17c0ea58d454843590cc0",
    },
    java = {
        url = "https://github.com/tree-sitter/tree-sitter-java",
        rev = "e10607b45ff745f5f876bfa3e94fbcc6b44bdc11",
    },
    javascript = {
        url = "https://github.com/tree-sitter/tree-sitter-javascript",
        rev = "58404d8cf191d69f2674a8fd507bd5776f46cb11",
    },
    json = {
        url = "https://github.com/tree-sitter/tree-sitter-json",
        rev = "001c28d7a29832b06b0e831ec77845553c89b56d",
    },
    make = {
        url = "https://github.com/tree-sitter-grammars/tree-sitter-make",
        rev = "70613f3d812cbabbd7f38d104d60a409c4008b43",
    },
    python = { url = "https://github.com/tree-sitter/tree-sitter-python", rev = "v0.25.0" },
    regex = {
        url = "https://github.com/tree-sitter/tree-sitter-regex",
        rev = "b2ac15e27fce703d2f37a79ccd94a5c0cbe9720b",
    },
    tsx = {
        url = "https://github.com/tree-sitter/tree-sitter-typescript",
        rev = "75b3874edb2dc714fb1fd77a32013d0f8699989f",
        location = "tsx",
    },
    typescript = {
        url = "https://github.com/tree-sitter/tree-sitter-typescript",
        rev = "75b3874edb2dc714fb1fd77a32013d0f8699989f",
        location = "typescript",
    },
    yaml = {
        url = "https://github.com/tree-sitter-grammars/tree-sitter-yaml",
        rev = "4463985dfccc640f3d6991e3396a2047610cf5f8",
    },
}

local defaults = {
    install_dir = vim.fn.stdpath("data") .. "/site",
    ensure_installed = {},
    auto_install = false,
}

local config = {}

local installing = false

local function log(msg, level)
    vim.notify("[ts-forge] " .. msg, level or vim.log.levels.INFO)
end

local function parser_path(lang)
    return config.install_dir .. "/parser/" .. lang .. ".so"
end

local function revision_path(lang)
    return config.install_dir .. "/parser-info/" .. lang .. ".revision"
end

--- Read revision info. Returns (rev, had_queries).
local function read_revision(lang)
    local path = revision_path(lang)
    if vim.fn.filereadable(path) == 0 then
        return nil, false
    end
    local lines = vim.fn.readfile(path)
    return lines[1], (lines[2] or "") ~= "queries=false"
end

--- Single source of truth: is this parser fully installed?
--- Handles bundled parsers, revision checks, and query integrity.
local function is_complete(lang)
    local info = M.parsers[lang]

    -- Not in our registry (bundled parsers like c, lua, markdown, etc.):
    -- complete if any parser exists on runtimepath. Never compiled by us.
    if not info then
        return #vim.api.nvim_get_runtime_file("parser/" .. lang .. ".so", false) > 0
    end

    -- Parser .so must exist
    if vim.fn.filereadable(parser_path(lang)) == 0 then
        return false
    end

    -- Revision must match
    local saved_rev, had_queries = read_revision(lang)
    if saved_rev ~= info.rev then
        return false
    end

    -- If install recorded queries=true, queries must still exist
    if had_queries then
        return #vim.api.nvim_get_runtime_file("queries/" .. lang .. "/highlights.scm", false) > 0
    end

    return true
end

--- Run a command asynchronously. Must be called from a coroutine.
--- Yields to the event loop so Neovim stays responsive.
local function run(cmd, opts)
    local co = assert(coroutine.running(), "run() must be called from a coroutine")
    vim.system(cmd, opts or {}, function(r)
        vim.schedule(function()
            coroutine.resume(co, r)
        end)
    end)
    local r = coroutine.yield()
    if r.code ~= 0 then
        return nil, vim.trim((r.stderr or "") .. (r.stdout or ""))
    end
    return true
end

--- Wrap a function to run in a coroutine.
local function async(fn)
    return function(...)
        local args = { ... }
        coroutine.resume(coroutine.create(function()
            fn(unpack(args))
        end))
    end
end

--- Resolve dependency order (dependencies before dependents).
--- Skips unknown languages (e.g. virtual query-only langs like ecma).
local function resolve_deps(langs)
    local resolved = {}
    local seen = {}

    local function add(lang)
        if seen[lang] then
            return
        end
        seen[lang] = true
        local info = M.parsers[lang]
        if not info then
            return
        end
        if info.requires then
            for _, dep in ipairs(info.requires) do
                add(dep)
            end
        end
        table.insert(resolved, lang)
    end

    for _, lang in ipairs(langs) do
        add(lang)
    end

    return resolved
end

local function install_one(lang)
    if is_complete(lang) then
        return true
    end

    local info = M.parsers[lang]
    if not info then
        log("Unknown parser: " .. lang, vim.log.levels.ERROR)
        return false
    end

    local tmpdir = vim.fn.tempname()

    vim.fn.mkdir(config.install_dir .. "/parser", "p")
    vim.fn.mkdir(config.install_dir .. "/parser-info", "p")

    log("Installing " .. lang .. "...")

    -- Shallow-fetch a single revision (works with tags and commit hashes)
    local ok, err = run({ "git", "init", tmpdir })
    if not ok then
        log("git init failed: " .. err, vim.log.levels.ERROR)
        return false
    end

    ok, err = run({ "git", "-C", tmpdir, "fetch", "--depth", "1", info.url, info.rev })
    if not ok then
        log("Fetch failed for " .. lang .. ": " .. err, vim.log.levels.ERROR)
        vim.fn.delete(tmpdir, "rf")
        return false
    end

    ok, err = run({ "git", "-C", tmpdir, "checkout", "FETCH_HEAD" })
    if not ok then
        log("Checkout failed for " .. lang .. ": " .. err, vim.log.levels.ERROR)
        vim.fn.delete(tmpdir, "rf")
        return false
    end

    -- Monorepo support: grammar may be in a subdirectory
    local grammar_dir = info.location and (tmpdir .. "/" .. info.location) or tmpdir

    -- Compile with tree-sitter CLI (handles C/C++ scanners, platform flags)
    local output = parser_path(lang)
    ok, err = run({ "tree-sitter", "build", "-o", output }, { cwd = grammar_dir })
    if not ok then
        log("Build failed for " .. lang .. ": " .. err, vim.log.levels.ERROR)
        vim.fn.delete(tmpdir, "rf")
        return false
    end

    -- Copy query files from the grammar repo.
    -- Monorepos may keep queries at <grammar_dir>/queries/ or <repo_root>/queries/
    local queries_copied = false
    local src_queries = grammar_dir .. "/queries"
    if vim.fn.isdirectory(src_queries) == 0 and info.location then
        src_queries = tmpdir .. "/queries"
    end
    if vim.fn.isdirectory(src_queries) == 1 then
        local dst_queries = config.install_dir .. "/queries/" .. lang
        vim.fn.mkdir(dst_queries, "p")
        local files = vim.fn.glob(src_queries .. "/*.scm", false, true)
        for _, file in ipairs(files) do
            local name = vim.fn.fnamemodify(file, ":t")
            vim.fn.writefile(vim.fn.readfile(file), dst_queries .. "/" .. name)
        end
        queries_copied = #files > 0
    end

    -- Track installed revision and query status
    vim.fn.writefile({ info.rev, "queries=" .. tostring(queries_copied) }, revision_path(lang))

    vim.fn.delete(tmpdir, "rf")
    log("Installed " .. lang)
    return true
end

--- Resolve, validate, and install a list of parsers. Must be called from a coroutine.
local function install_langs(langs)
    for _, lang in ipairs(langs) do
        if not M.parsers[lang] and not is_complete(lang) then
            log("Unknown parser: " .. lang, vim.log.levels.ERROR)
            return
        end
    end

    langs = resolve_deps(langs)

    local installed, failed = 0, 0
    for _, lang in ipairs(langs) do
        if install_one(lang) then
            installed = installed + 1
        else
            failed = failed + 1
        end
    end

    if failed > 0 then
        log(string.format("Done: %d installed, %d failed", installed, failed), vim.log.levels.WARN)
    else
        log(string.format("Done: %d installed", installed))
    end
end

--- Install parsers. If no langs given, installs all ensure_installed.
--- Runs asynchronously — does not block Neovim.
--- @param langs? string[]
M.install = async(function(langs)
    if installing then
        log("Already running", vim.log.levels.WARN)
        return
    end
    installing = true

    if not langs or #langs == 0 then
        langs = vim.deepcopy(config.ensure_installed)
        if #langs == 0 then
            log("No parsers in ensure_installed")
            installing = false
            return
        end
    end

    install_langs(langs)
    installing = false
end)

--- Update all installed parsers to their pinned revisions.
--- Runs asynchronously — does not block Neovim.
M.update = async(function()
    if installing then
        log("Already running", vim.log.levels.WARN)
        return
    end
    installing = true

    local outdated = {}
    for lang, info in pairs(M.parsers) do
        local saved_rev = read_revision(lang)
        if not is_complete(lang) and vim.fn.filereadable(parser_path(lang)) == 1 then
            table.insert(outdated, lang)
        end
    end

    if #outdated == 0 then
        log("All parsers are up to date")
        installing = false
        return
    end

    install_langs(outdated)
    installing = false
end)

--- Return list of ensure_installed parsers that are not fully installed.
--- @return string[]
function M.get_missing()
    local missing = {}
    for _, lang in ipairs(config.ensure_installed) do
        if not is_complete(lang) then
            table.insert(missing, lang)
        end
    end
    return missing
end

function M.setup(opts)
    config = vim.tbl_deep_extend("force", defaults, opts or {})
    M._config = config

    local missing = M.get_missing()
    if #missing > 0 then
        if config.auto_install then
            M.install(missing)
        else
            log(
                string.format(
                    "Missing parsers: %s\nRun :TSInstall to install.",
                    table.concat(missing, ", ")
                ),
                vim.log.levels.WARN
            )
        end
    end
end

return M
