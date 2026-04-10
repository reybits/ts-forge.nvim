local M = {}

function M.check()
    local forge = require("ts-forge")
    local health = vim.health

    -- Requirements
    health.start("Requirements")

    local ts_abi = vim.treesitter.language_version
    if ts_abi and ts_abi >= 13 then
        health.ok(string.format("Neovim tree-sitter ABI version %d (>= 13)", ts_abi))
    else
        health.error(string.format("Neovim tree-sitter ABI version %s (need >= 13)", tostring(ts_abi)))
    end

    for _, tool in ipairs({ "tree-sitter", "git", "cc" }) do
        local path = vim.fn.exepath(tool)
        if path ~= "" then
            local version = ""
            if tool == "tree-sitter" then
                local r = vim.system({ tool, "--version" }):wait()
                version = " " .. vim.trim(r.stdout or "")
            elseif tool == "git" then
                local r = vim.system({ tool, "--version" }):wait()
                version = " " .. vim.trim(r.stdout or ""):gsub("git version ", "")
            end
            health.ok(string.format("%s%s (%s)", tool, version, path))
        else
            health.error(tool .. " not found in PATH")
        end
    end

    -- Install directory
    health.start("Install directory")

    local install_dir = forge._config and forge._config.install_dir
        or (vim.fn.stdpath("data") .. "/site")
    local parser_dir = install_dir .. "/parser"

    if vim.fn.isdirectory(install_dir) == 1 then
        health.ok(install_dir .. " exists")
    else
        health.warn(install_dir .. " does not exist (will be created on first install)")
    end

    -- Installed parsers
    health.start("Installed parsers")

    local langs = {}
    for lang in pairs(forge.parsers) do
        table.insert(langs, lang)
    end
    table.sort(langs)

    local installed_count = 0
    local outdated_count = 0
    local missing_count = 0

    for _, lang in ipairs(langs) do
        local info = forge.parsers[lang]
        local so = parser_dir .. "/" .. lang .. ".so"

        if vim.fn.filereadable(so) == 1 then
            installed_count = installed_count + 1

            -- Check revision
            local rev_path = install_dir .. "/parser-info/" .. lang .. ".revision"
            local current_rev = vim.fn.filereadable(rev_path) == 1
                and vim.fn.readfile(rev_path)[1] or nil

            -- Check queries
            local has_queries = #vim.api.nvim_get_runtime_file("queries/" .. lang .. "/highlights.scm", false) > 0

            local status = {}
            if current_rev ~= info.rev then
                table.insert(status, "outdated")
                outdated_count = outdated_count + 1
            end
            if not has_queries then
                table.insert(status, "no queries")
            end

            if #status > 0 then
                health.warn(string.format("%s (%s)", lang, table.concat(status, ", ")))
            else
                health.ok(lang)
            end
        else
            missing_count = missing_count + 1
            health.warn(lang .. " (not installed)")
        end
    end

    -- Summary
    health.start("Summary")
    health.info(string.format(
        "%d installed, %d outdated, %d not installed",
        installed_count, outdated_count, missing_count
    ))
end

return M
