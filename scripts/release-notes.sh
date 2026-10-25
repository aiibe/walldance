#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
    echo "Usage: $0 VERSION [CHANGELOG]" >&2
    exit 1
fi
version="$1"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must have the form 1.2.3" >&2
    exit 1
fi

awk -v version="$version" '
    { sub(/\r$/, "") }
    /^##[ \t]+/ {
        if (collecting) exit
        heading = $0
        sub(/[ \t]+$/, "", heading)
        collecting = (heading == "## " version)
        next
    }
    collecting { notes = notes $0 "\n" }
    END {
        if (notes !~ /[^[:space:]]/) {
            print "No changelog entries for " version > "/dev/stderr"
            exit 1
        }
        sub(/^\n+/, "", notes)
        sub(/\n+$/, "", notes)
        print notes
    }
' "${2:-CHANGELOG.md}"
