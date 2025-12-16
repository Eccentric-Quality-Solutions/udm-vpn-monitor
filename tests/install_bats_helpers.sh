#!/bin/bash
#
# Install bats helper libraries (bats-support, bats-assert, bats-file)
# These are optional but recommended for better test assertions
#

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Helper library versions (use latest stable)
BATS_SUPPORT_VERSION="0.3.0"
BATS_ASSERT_VERSION="2.1.0"
BATS_FILE_VERSION="0.3.0"

# Install helper library
install_helper() {
    local name="$1"
    local repo="$2"
    local version="$3"
    local target_dir="${PROJECT_ROOT}/${name}"
    
    echo -e "${GREEN}Installing ${name}...${NC}"
    
    if [[ -d "$target_dir" ]]; then
        echo -e "${YELLOW}${name} already exists, skipping${NC}"
        return 0
    fi
    
    # Download and extract
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    wget -q "https://github.com/${repo}/archive/v${version}.tar.gz" -O "${name}.tar.gz" || {
        echo "Failed to download ${name}" >&2
        rm -rf "$temp_dir"
        return 1
    }
    
    tar -xzf "${name}.tar.gz"
    mv "${name}-${version}" "$target_dir"
    
    rm -rf "$temp_dir"
    
    echo -e "${GREEN}${name} installed successfully${NC}"
}

# Main installation
main() {
    echo -e "${GREEN}Installing bats helper libraries...${NC}"
    echo ""
    
    cd "$PROJECT_ROOT"
    
    install_helper "bats-support" "bats-core/bats-support" "$BATS_SUPPORT_VERSION"
    install_helper "bats-assert" "bats-core/bats-assert" "$BATS_ASSERT_VERSION"
    install_helper "bats-file" "bats-core/bats-file" "$BATS_FILE_VERSION"
    
    echo ""
    echo -e "${GREEN}All helper libraries installed successfully!${NC}"
    echo ""
    echo "You can now run tests with:"
    echo "  ./tests/run_tests.sh"
}

# Run main
main "$@"

