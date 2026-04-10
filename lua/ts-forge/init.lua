local M = {}

--- Parser registry: lang -> { url, rev, location?, requires? }
--- Revisions sourced from nvim-treesitter/nvim-treesitter (main branch).
M.parsers = {
    bash            = { url = "https://github.com/tree-sitter/tree-sitter-bash",       rev = "a06c2e4415e9bc0346c6b86d401879ffb44058f7" },
    c               = { url = "https://github.com/tree-sitter/tree-sitter-c",          rev = "ae19b676b13bdcc13b7665397e6d9b14975473dd" },
    cmake           = { url = "https://github.com/uyha/tree-sitter-cmake",             rev = "c7b2a71e7f8ecb167fad4c97227c838439280175" },
    cpp             = { url = "https://github.com/tree-sitter/tree-sitter-cpp",         rev = "8b5b49eb196bec7040441bee33b2c9a4838d6967", requires = { "c" } },
    css             = { url = "https://github.com/tree-sitter/tree-sitter-css",         rev = "dda5cfc5722c429eaba1c910ca32c2c0c5bb1a3f" },
    gitignore       = { url = "https://github.com/shunsambongi/tree-sitter-gitignore",  rev = "f4685bf11ac466dd278449bcfe5fd014e94aa504" },
    html            = { url = "https://github.com/tree-sitter/tree-sitter-html",        rev = "73a3947324f6efddf9e17c0ea58d454843590cc0" },
    java            = { url = "https://github.com/tree-sitter/tree-sitter-java",        rev = "e10607b45ff745f5f876bfa3e94fbcc6b44bdc11" },
    javascript      = { url = "https://github.com/tree-sitter/tree-sitter-javascript",  rev = "58404d8cf191d69f2674a8fd507bd5776f46cb11" },
    json            = { url = "https://github.com/tree-sitter/tree-sitter-json",        rev = "001c28d7a29832b06b0e831ec77845553c89b56d" },
    lua             = { url = "https://github.com/tree-sitter-grammars/tree-sitter-lua", rev = "10fe0054734eec83049514ea2e718b2a56acd0c9" },
    make            = { url = "https://github.com/tree-sitter-grammars/tree-sitter-make", rev = "70613f3d812cbabbd7f38d104d60a409c4008b43" },
    markdown        = { url = "https://github.com/tree-sitter-grammars/tree-sitter-markdown", rev = "f969cd3ae3f9fbd4e43205431d0ae286014c05b5", location = "tree-sitter-markdown" },
    markdown_inline = { url = "https://github.com/tree-sitter-grammars/tree-sitter-markdown", rev = "f969cd3ae3f9fbd4e43205431d0ae286014c05b5", location = "tree-sitter-markdown-inline" },
    python          = { url = "https://github.com/tree-sitter/tree-sitter-python",      rev = "v0.25.0" },
    query           = { url = "https://github.com/tree-sitter-grammars/tree-sitter-query", rev = "fc5409c6820dd5e02b0b0a309d3da2bfcde2db17" },
    regex           = { url = "https://github.com/tree-sitter/tree-sitter-regex",       rev = "b2ac15e27fce703d2f37a79ccd94a5c0cbe9720b" },
    tsx             = { url = "https://github.com/tree-sitter/tree-sitter-typescript",   rev = "75b3874edb2dc714fb1fd77a32013d0f8699989f", location = "tsx" },
    typescript      = { url = "https://github.com/tree-sitter/tree-sitter-typescript",   rev = "75b3874edb2dc714fb1fd77a32013d0f8699989f", location = "typescript" },
    vim             = { url = "https://github.com/tree-sitter-grammars/tree-sitter-vim", rev = "3092fcd99eb87bbd0fc434aa03650ba58bd5b43b" },
    vimdoc          = { url = "https://github.com/neovim/tree-sitter-vimdoc",           rev = "f061895a0eff1d5b90e4fb60d21d87be3267031a" },
    yaml            = { url = "https://github.com/tree-sitter-grammars/tree-sitter-yaml", rev = "4463985dfccc640f3d6991e3396a2047610cf5f8" },
}

local defaults = {
    install_dir = vim.fn.stdpath("data") .. "/site",
    ensure_installed = {},
    auto_install = false,
}

local config = {}

local function log(msg, level)
    vim.notify("[ts-parsers] " .. msg, level or vim.log.levels.INFO)
end

local function parser_path(lang)
    return config.install_dir .. "/parser/" .. lang .. ".so"
end

local function revision_path(lang)
    return config.install_dir .. "/parser-info/" .. lang .. ".revision"
end

local function is_installed(lang)
    return vim.fn.filereadable(parser_path(lang)) == 1
end

local function current_revision(lang)
    local path = revision_path(lang)
    if vim.fn.filereadable(path) == 1 then
        return vim.fn.readfile(path)[1]
    end
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
    local info = M.parsers[lang]
    if not info then
        log("Unknown parser: " .. lang, vim.log.levels.ERROR)
        return false
    end

    if current_revision(lang) == info.rev then
        return true
    end

    local tmpdir = vim.fn.tempname()

    vim.fn.mkdir(config.install_dir .. "/parser", "p")
    vim.fn.mkdir(config.install_dir .. "/queries/" .. lang, "p")
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

    -- Skip query installation for languages bundled with Neovim —
    -- their runtime queries are higher quality and actively maintained.
    local is_bundled = false
    for _, path in ipairs(vim.api.nvim_get_runtime_file("queries/" .. lang .. "/highlights.scm", false)) do
        if path:find(vim.env.VIMRUNTIME, 1, true) then
            is_bundled = true
            break
        end
    end

    if not is_bundled then
        local src_queries = grammar_dir .. "/queries"
        if vim.fn.isdirectory(src_queries) == 1 then
            local dst_queries = config.install_dir .. "/queries/" .. lang
            vim.fn.mkdir(dst_queries, "p")
            local files = vim.fn.glob(src_queries .. "/*.scm", false, true)
            for _, file in ipairs(files) do
                local name = vim.fn.fnamemodify(file, ":t")
                vim.fn.writefile(vim.fn.readfile(file), dst_queries .. "/" .. name)
            end
        end
    end

    -- Track installed revision
    vim.fn.writefile({ info.rev }, revision_path(lang))

    vim.fn.delete(tmpdir, "rf")
    log("Installed " .. lang)
    return true
end

--- Install parsers. If no langs given, installs all missing ensure_installed.
--- Runs asynchronously — does not block Neovim.
--- @param langs? string[]
M.install = async(function(langs)
    if not langs or #langs == 0 then
        langs = M.get_missing()
        if #langs == 0 then
            log("All parsers are installed")
            return
        end
    end

    for _, lang in ipairs(langs) do
        if not M.parsers[lang] then
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
end)

--- Update all installed parsers to their pinned revisions.
--- Runs asynchronously — does not block Neovim.
M.update = async(function()
    local outdated = {}
    for lang, info in pairs(M.parsers) do
        if is_installed(lang) and current_revision(lang) ~= info.rev then
            table.insert(outdated, lang)
        end
    end

    if #outdated == 0 then
        log("All parsers are up to date")
        return
    end

    -- Inline the install logic (already in a coroutine)
    local langs = resolve_deps(outdated)

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
end)

--- Return list of ensure_installed parsers that are not yet compiled.
--- @return string[]
function M.get_missing()
    local missing = {}
    for _, lang in ipairs(config.ensure_installed) do
        if not is_installed(lang) then
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
                string.format("Missing parsers: %s\nRun :TSInstall to install.", table.concat(missing, ", ")),
                vim.log.levels.WARN
            )
        end
    end
end

return M
