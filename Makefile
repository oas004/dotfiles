.PHONY: test lint format update restore

# Honours NVIM_APPNAME, TEST_SKIP etc. from the environment; see tests/run.sh.
test:
	tests/run.sh

# Needs selene (https://github.com/Kampfkarren/selene), config in selene.toml,
# and lua-language-server (https://github.com/LuaLS/lua-language-server),
# config in .luarc.json. lua-language-server type-checks vim.* against the
# runtime of the nvim on PATH (or $VIMRUNTIME if set) and fails on warnings.
# Also needs shellcheck (https://github.com/koalaman/shellcheck), config in
# .shellcheckrc, which checks every tracked *.sh at its default severity, and
# stylua (https://github.com/JohnnyMorganz/StyLua), config in stylua.toml,
# which fails if a Lua file isn't formatted. CI pins the version of each.
SHELL_SCRIPTS := $(shell git ls-files '*.sh')
LUA_PATHS := init.lua lua tests .github/scripts

# The runtime lua-language-server checks against. It is passed to that
# command only: exported from the Makefile, it would also be forced on the
# nvim that test, update and restore start, and break them when NVIM is a
# different Neovim version. "=" so nvim only runs when lint does.
LINT_VIMRUNTIME = $(or $(VIMRUNTIME),$(shell nvim --clean --headless -c 'lua io.stdout:write(vim.env.VIMRUNTIME)' -c 'qa!' 2>/dev/null))

lint:
	stylua --check $(LUA_PATHS)
	selene $(LUA_PATHS)
	shellcheck $(SHELL_SCRIPTS)
	@test -n "$(LINT_VIMRUNTIME)" || { echo "error: set VIMRUNTIME or put nvim on PATH" >&2; exit 1; }
	VIMRUNTIME="$(LINT_VIMRUNTIME)" lua-language-server --check=. --checklevel=Warning --logpath="$${TMPDIR:-/tmp}/luals-check"

# Rewrites the Lua files in place with stylua.
format:
	stylua $(LUA_PATHS)

# Updates plugins (:Lazy! update), runs the tests against them and prints the
# lazy-lock.json diff to review and commit. See scripts/plugins.sh.
update:
	scripts/plugins.sh update

# Puts plugins back at the commits in lazy-lock.json (:Lazy! restore).
restore:
	scripts/plugins.sh restore
