.PHONY: test lint

# Honours NVIM_APPNAME, TEST_SKIP etc. from the environment; see tests/run.sh.
test:
	tests/run.sh

# Needs selene (https://github.com/Kampfkarren/selene), config in selene.toml,
# and lua-language-server (https://github.com/LuaLS/lua-language-server),
# config in .luarc.json. lua-language-server type-checks vim.* against the
# runtime of the nvim on PATH (or $VIMRUNTIME if set) and fails on warnings.
ifndef VIMRUNTIME
VIMRUNTIME := $(shell nvim --clean --headless -c 'lua io.stdout:write(vim.env.VIMRUNTIME)' -c 'qa!' 2>/dev/null)
endif
export VIMRUNTIME

lint:
	selene init.lua lua tests .github/scripts
	@test -n "$(VIMRUNTIME)" || { echo "error: set VIMRUNTIME or put nvim on PATH" >&2; exit 1; }
	lua-language-server --check=. --checklevel=Warning --logpath="$${TMPDIR:-/tmp}/luals-check"
