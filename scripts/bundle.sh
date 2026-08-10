#!/bin/bash
#
# Bundle all installation files into a single self-extracting script
# Usage: ./scripts/bundle.sh > install-bundled.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Generate header
cat << 'HEADER'
#!/bin/bash
#
# Settings Installer (Bundled)
# https://github.com/jiunbae/settings
#
# This is a self-extracting installer that contains all necessary files.
#
# Usage:
#   curl -fsSL https://github.com/jiunbae/settings/releases/latest/download/install-bundled.sh | bash -s -- --all
#   curl -fsSL https://github.com/jiunbae/settings/releases/latest/download/install-bundled.sh | bash -s -- zsh nvim
#

set -euo pipefail

# Create temporary directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf '$TEMP_DIR'" EXIT

# Extract embedded files
extract_files() {
    cd "$TEMP_DIR"
HEADER

# Function to embed a file
embed_file() {
    local file="$1"
    local rel_path="${file#"$SCRIPT_DIR"/}"
    local dir_path
    dir_path=$(dirname "$rel_path")

    case "$rel_path" in
        *[!A-Za-z0-9_./-]*)
            printf 'bundle: unsafe embedded path: %s\n' "$rel_path" >&2
            return 1
            ;;
    esac
    case "$rel_path" in
        *.example|*.sample.*) ;;
        */.env|*/.env.*|*credentials*|*secret*|*auth.json|*.pem|*.key)
            printf 'bundle: refusing to embed sensitive-looking file: %s\n' "$rel_path" >&2
            return 1
            ;;
    esac
    if grep -qx 'EMBEDDED_FILE_EOF' "$file"; then
        printf 'bundle: heredoc delimiter collision in %s\n' "$rel_path" >&2
        return 1
    fi

    echo ""
    echo "    # $rel_path"
    if [[ "$dir_path" != "." ]]; then
        echo "    mkdir -p '$dir_path'"
    fi
    echo "    cat > '$rel_path' << 'EMBEDDED_FILE_EOF'"
    cat "$file"
    echo ""
    echo "EMBEDDED_FILE_EOF"
    if [[ -x "$file" ]]; then
        echo "    chmod +x '$rel_path'"
    fi
}

# Embed all necessary files
embed_file "$SCRIPT_DIR/install.sh"

for file in "$SCRIPT_DIR"/lib/*.sh; do
    embed_file "$file"
done

for file in "$SCRIPT_DIR"/modules/*.sh; do
    embed_file "$file"
done

# Embed the complete config tree. Keeping an allowlist here caused newly added
# components to ship their module code without the files that code consumes.
while IFS= read -r file; do
    embed_file "$file"
done < <(find "$SCRIPT_DIR/configs" -type f | LC_ALL=C sort)

# Runtime/capture helpers used by the AI-agent modules.
for helper_dir in "$SCRIPT_DIR/scripts/claude" "$SCRIPT_DIR/scripts/codex"; do
    [[ -d "$helper_dir" ]] || continue
    while IFS= read -r file; do
        embed_file "$file"
    done < <(find "$helper_dir" -type f | LC_ALL=C sort)
done

# Generate footer
cat << 'FOOTER'

    chmod +x install.sh
}

# Main
main() {
    extract_files
    cd "$TEMP_DIR"
    # The extraction directory is deleted on exit, so symlinking to it would
    # leave every deployed config broken. Force copy mode after user arguments
    # so even an accidental --link cannot create dangling links.
    ./install.sh "$@" --copy
}

main "$@"
FOOTER
