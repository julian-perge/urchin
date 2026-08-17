# Set the default shell to bash
SHELL := bash
.SHELLFLAGS := -o errexit -o nounset -o pipefail -c
# ensures each Make recipe is ran as one single shell session, rather than one new shell per line.
.ONESHELL:
# if a Make rule fails, it’s target file is deleted. This ensures the next time you run Make, it’ll properly re-run the failed rule, and guards against broken files.
.DELETE_ON_ERROR:
# if you are referring to Make variables that don’t exist, that’s probably wrong and it’s good to get a warning.
MAKEFLAGS += --warn-undefined-variables
# This disables the bewildering array of built in rules to automatically build Yacc grammars out of your data if you accidentally add the wrong file suffix.
MAKEFLAGS += --no-builtin-rules

ifeq ($(origin .RECIPEPREFIX), undefined)
  $(error This Make does not support .RECIPEPREFIX. Please use GNU Make 4.0 or later)
endif
.RECIPEPREFIX = >

.PHONY: clean
clean: ## Remove caches, build artifacts, editor temp files
> rm -rf `find . -name __pycache__`
> rm -rf `find . -name *.egg-info`
> rm -f `find . -type f -name '*.py[co]' `
> rm -f `find . -type f -name '*~' `
> rm -f `find . -type f -name '.*~' `
> rm -f `find . -type f -name '@*' `
> rm -f `find . -type f -name '#*#' `
> rm -f `find . -type f -name '*.orig' `
> rm -f `find . -type f -name '*.rej' `
> rm -rf build
> rm -rf dist

##@ Help

# AWK_HELP: awk script powering the `help` target.
#
# Parses this Makefile and prints a colorized target list. Recognizes two
# patterns:
#   1. `target: [deps] ## description` -> prints `target` + `description`.
#      FS = ":.*##" splits on the colon-through-## span so prerequisites
#      are swallowed and only the target name and doc text remain.
#   2. `##@ Section Name` -> prints a bold section header. `substr($0, 5)`
#      strips the leading `##@ ` marker.
#
# `$$1`/`$$0` escape `$` for Make. ANSI codes: \033[36m cyan, \033[1m bold,
# \033[0m reset. Exported so the recipe can read it via `$$AWK_HELP`.
define AWK_HELP
BEGIN {
  FS = ":.*##"
  printf "\nUsage:\n  make \033[36m<target>\033[0m\n"
}
/^[a-zA-Z_0-9-]+:.*?##/ {
  printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2
}
/^##@/ {
  printf "\n\033[1m%s\033[0m\n", substr($$0, 5)
}
endef
export AWK_HELP

.PHONY: help
help: ## Display this help.
> @awk "$$AWK_HELP" $(MAKEFILE_LIST)
