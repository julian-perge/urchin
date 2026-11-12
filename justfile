# Local shortcuts for urchin. `just` lists them, and `just <recipe>` runs one.

set shell := ["bash", "-euo", "pipefail", "-c"]

[private]
default:
    @just --list --unsorted

[doc('Remove caches, build artifacts and editor temp files')]
clean:
    find . -name __pycache__ -prune -exec rm -rf {} +
    find . -name '*.egg-info' -prune -exec rm -rf {} +
    find . -type f \( -name '*.py[co]' -o -name '*~' -o -name '@*' -o -name '#*#' -o -name '*.orig' -o -name '*.rej' \) -delete
    rm -rf build dist
