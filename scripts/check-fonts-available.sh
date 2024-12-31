#!/bin/sh

set -o errexit
set -o nounset
set -o pipefail

if ls -d .git > /dev/null; then
    typst fonts --ignore-system-fonts --font-path ./fonts
else
    echo "Failed to find .git directory. Perhaps you are in other directory instead of project root directory?" >&2
fi
