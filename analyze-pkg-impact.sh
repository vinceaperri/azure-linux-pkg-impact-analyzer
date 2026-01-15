#!/bin/bash
#
# Builds a complete package dependency graph using rpm, then computes transitive removal impact.
#
# Phase 1: Build graph (one-time)
# Phase 2: Query transitive deps for each package
#
set -euo pipefail

GRAPH_FILE=""
OUTPUT_FILE=""
REFRESH=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -g|--graph)
            GRAPH_FILE="$2"
            shift 2
            ;;
        -r|--refresh)
            REFRESH=1
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [-g|--graph GRAPH_FILE] [-r|--refresh] OUTPUT_FILE" >&2
            exit 1
            ;;
        *)
            OUTPUT_FILE="$1"
            shift
            ;;
    esac
done

if [ -z "$OUTPUT_FILE" ]; then
    echo "Usage: $0 [-g|--graph GRAPH_FILE] [-r|--refresh] OUTPUT_FILE" >&2
    exit 1
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

[ -z "$GRAPH_FILE" ] && GRAPH_FILE="$TMP_DIR/pkg-graph.txt"
PKG_LIST="$TMP_DIR/pkg-list.txt"
PKG_INFO="$TMP_DIR/pkg-info.txt"

# Query package info once: NEVRA, NAME, SIZE
echo "Querying installed packages..."
rpm -qa --qf '%{NEVRA}\t%{NAME}\t%{SIZE}\n' | sort > "$PKG_INFO"
cut -f1 "$PKG_INFO" > "$PKG_LIST"

# Build the dependency graph
build_graph() {
    echo "Building dependency graph..."
    : > "$GRAPH_FILE"

    local total current=0
    total=$(wc -l < "$PKG_LIST")

    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        current=$((current + 1))
        printf "\r\033[K%d/%d: %s" "$current" "$total" "$pkg"

        # Extract base name from NEVRA for whatrequires query
        local pkg_name matches count
        matches=$(grep "^${pkg}	" "$PKG_INFO") || { echo "Error: No match for NEVRA '$pkg'" >&2; exit 1; }
        count=$(echo "$matches" | wc -l)
        if [ "$count" -gt 1 ]; then
            echo "Error: Multiple matches for NEVRA '$pkg'" >&2
            exit 1
        fi
        pkg_name=$(echo "$matches" | cut -f2)

        # Get direct reverse dependencies (packages that require this one)
        local deps
        deps=$(rpm -q --whatrequires "$pkg_name" 2>/dev/null | \
               grep -v "no package requires" | \
               sort -u | tr '\n' ' ') || true

        # Format: package: dep1 dep2 dep3
        echo "$pkg:$deps" >> "$GRAPH_FILE"
    done < "$PKG_LIST"

    echo -e "\nGraph built: $GRAPH_FILE"
}

# Find all packages that would be removed transitively
find_transitive_deps() {
    local target="$1"
    local -A visited
    local queue=("$target")

    while [ ${#queue[@]} -gt 0 ]; do
        local current="${queue[0]}"
        queue=("${queue[@]:1}")

        [ -z "$current" ] && continue
        [ "${visited[$current]:-}" = "1" ] && continue
        visited["$current"]=1

        # Find packages that depend on current
        local line
        line=$(grep "^${current}:" "$GRAPH_FILE" 2>/dev/null || true)
        if [ -n "$line" ]; then
            local dependents
            dependents="${line#*:}"
            for dep in $dependents; do
                [ -z "$dep" ] && continue
                [ "${visited[$dep]:-}" = "1" ] && continue
                queue+=("$dep")
            done
        fi
    done

    printf '%s\n' "${!visited[@]}" | sort
}

# Get package size from cached file (using NEVRA)
get_pkg_size() {
    local pkg="$1"
    local matches
    matches=$(grep "^${pkg}	" "$PKG_INFO" 2>/dev/null) || { echo "0"; return; }
    local count
    count=$(echo "$matches" | wc -l)
    if [ "$count" -gt 1 ]; then
        echo "Error: Multiple matches for NEVRA '$pkg'" >&2
        exit 1
    fi
    echo "$matches" | cut -f3
}

# Human readable size
human_size() {
    local bytes="$1"
    if [ "$bytes" -ge 1073741824 ]; then
        awk "BEGIN {printf \"%.2fGiB\", $bytes/1073741824}"
    elif [ "$bytes" -ge 1048576 ]; then
        awk "BEGIN {printf \"%.2fMiB\", $bytes/1048576}"
    elif [ "$bytes" -ge 1024 ]; then
        awk "BEGIN {printf \"%.2fKiB\", $bytes/1024}"
    else
        echo "${bytes}B"
    fi
}

# Main analysis
analyze_all() {
    echo "Analyzing transitive removal impact..."
    echo "Name,Package Size,Package Size (Bytes),Total Removal Size,Total Removal Size (Bytes),Would Also Remove" > "$OUTPUT_FILE"

    local total current=0
    total=$(wc -l < "$PKG_LIST")

    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        current=$((current + 1))
        printf "\r\033[K%d/%d: %s" "$current" "$total" "$pkg"

        # Get transitive deps
        local trans_deps dep_list
        trans_deps=$(find_transitive_deps "$pkg")
        # Exclude the package itself from the "Would Remove" list
        dep_list=$(echo "$trans_deps" | grep -v "^${pkg}$" | tr '\n' ' ' | sed 's/ $//' || true)

        # Calculate sizes
        local pkg_size total_size=0
        pkg_size=$(get_pkg_size "$pkg")
        
        while IFS= read -r dep; do
            [ -z "$dep" ] && continue
            local size
            size=$(get_pkg_size "$dep")
            [ -n "$size" ] && total_size=$((total_size + size))
        done <<< "$trans_deps"

        echo "$pkg,$(human_size "$pkg_size"),$pkg_size,$(human_size "$total_size"),$total_size,\"$dep_list\"" >> "$OUTPUT_FILE"
    done < "$PKG_LIST"

    echo -e "\nDone! Results saved to $OUTPUT_FILE"
}

# Run
if [ -s "$GRAPH_FILE" ] && [ "$REFRESH" -eq 0 ]; then
    echo "Reusing existing graph: $GRAPH_FILE"
else
    build_graph
fi

analyze_all
