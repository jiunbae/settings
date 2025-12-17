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
    local rel_path="${file#$SCRIPT_DIR/}"
    local dir_path=$(dirname "$rel_path")

    echo ""
    echo "    # $rel_path"
    if [[ "$dir_path" != "." ]]; then
        echo "    mkdir -p '$dir_path'"
    fi
    echo "    cat > '$rel_path' << 'EMBEDDED_FILE_EOF'"
    cat "$file"
    echo ""
    echo "EMBEDDED_FILE_EOF"
}

# Embed all necessary files
embed_file "$SCRIPT_DIR/install.sh"

for file in "$SCRIPT_DIR"/lib/*.sh; do
    embed_file "$file"
done

for file in "$SCRIPT_DIR"/modules/*.sh; do
    embed_file "$file"
done

# Embed config files
for file in "$SCRIPT_DIR"/configs/.zshrc "$SCRIPT_DIR"/configs/.p10k.zsh "$SCRIPT_DIR"/configs/.tmux.conf; do
    if [[ -f "$file" ]]; then
        embed_file "$file"
    fi
done

# Embed SpaceVim config if exists
if [[ -d "$SCRIPT_DIR/configs/.SpaceVim.d" ]]; then
    for file in "$SCRIPT_DIR"/configs/.SpaceVim.d/*; do
        if [[ -f "$file" ]]; then
            embed_file "$file"
        fi
    done
fi

# Generate footer
cat << 'FOOTER'

    chmod +x install.sh
}

# Main
main() {
    extract_files
    cd "$TEMP_DIR"
    ./install.sh "$@"
}

main "$@"
FOOTER
