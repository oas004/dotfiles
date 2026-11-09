.PHONY: test lint

# Honours NVIM_APPNAME, TEST_SKIP etc. from the environment; see tests/run.sh.
test:
	tests/run.sh

# Needs selene (https://github.com/Kampfkarren/selene); config in selene.toml.
lint:
	selene init.lua lua tests .github/scripts
