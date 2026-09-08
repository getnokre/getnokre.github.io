#!/bin/sh
# Delete the catalog entries no source under src/ names.
#
#     tools/l10n-purge.sh                          # report; writes nothing
#     tools/l10n-purge.sh --write --cut-dir <dir>  # perform it
#
# The tool is nokre's — see `../nokre/docs/localization.md`, "Purging
# unused keys", for what it cuts and what it refuses. This wrapper adds
# the one precondition nokre deliberately does not check: it invokes git
# nowhere, so "the tree is clean" is the caller's to enforce, and the
# caller here is a repository with no `dev_cli` to put it in the way
# rokovski does. `--write` rewrites `src/l10n/` in place and the undo is
# `git checkout`; over a dirty catalog there is nothing to check out.
#
# `--force` is not passed and must not be added. It overrides purge's
# "every key reads as an orphan" refusal, which is the one that stands
# between a mistyped `--src` and an erased catalog.
set -eu

# Every path below is written from the repository root, so the script is
# callable from anywhere: nokre's run step inherits this process's
# working directory, which is what those paths resolve against.
cd "$(dirname "$0")/.."

if [ -n "$(git status --porcelain -- src/l10n)" ]; then
    echo "tools/l10n-purge.sh: src/l10n has uncommitted changes." >&2
    echo "  Commit or stash them first — purge writes the catalog in place," >&2
    echo "  and the only undo is git." >&2
    exit 1
fi

# `--catalogs` and `--label` are what nokre cannot infer: the set this
# template belongs to, and the name the report leads with.
exec zig build --build-file ../nokre/build.zig l10n-purge -- \
    --template src/l10n/site_en.arb \
    --src src \
    --catalogs src/l10n \
    --label site \
    "$@"
