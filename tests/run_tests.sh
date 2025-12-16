#!/bin/bash
#
# Test runner for UDM VPN Monitor tests
# Runs all tests using bats (Bash Automated Testing System)
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Show bats installation instructions
show_bats_instructions() {
    echo "Install bats using one of the following methods:" >&2
    echo "" >&2
    echo "  macOS (Homebrew):" >&2
    echo "    brew install bats-core" >&2
    echo "" >&2
    echo "  Linux (from source):" >&2
    echo "    git clone https://github.com/bats-core/bats-core.git" >&2
    echo "    cd bats-core" >&2
    echo "    sudo ./install.sh /usr/local" >&2
    echo "" >&2
    echo "  Ubuntu/Debian:" >&2
    echo "    sudo apt-get update && sudo apt-get install -y bats" >&2
    echo "" >&2
    echo "  Fedora/RHEL:" >&2
    echo "    sudo dnf install -y bats" >&2
    echo "" >&2
}

# Check if bats is installed
check_bats() {
    if ! command -v bats >/dev/null 2>&1; then
        echo -e "${RED}Error: bats is not installed${NC}" >&2
        echo "" >&2
        echo "bats (Bash Automated Testing System) is required to run tests." >&2
        echo "" >&2
        
        # Prompt user to see instructions (interactive mode only)
        if [[ -t 0 ]] && [[ -t 1 ]]; then
            echo -e "${YELLOW}Would you like to see installation instructions? (yes/no) [yes]:${NC} "
            read -r response
            response="${response:-yes}"
            
            if [[ "$response" =~ ^[Yy][Ee][Ss]$ ]]; then
                echo "" >&2
                show_bats_instructions
            fi
        else
            # Non-interactive mode - always show instructions
            show_bats_instructions
        fi
        
        exit 1
    fi
    
    # Check bats version (should be 1.x or higher)
    local bats_version
    bats_version=$(bats --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "0.0")
    local major_version
    major_version=$(echo "$bats_version" | cut -d. -f1)
    
    if [[ $major_version -lt 1 ]]; then
        echo -e "${YELLOW}Warning: bats version $bats_version may be outdated${NC}" >&2
        echo "Consider upgrading to bats-core 1.x or higher" >&2
    fi
}

# Check for bats-support and bats-assert (optional but recommended)
check_bats_helpers() {
    local helpers_missing=0
    local missing_helpers=()
    
    if [[ ! -d "${SCRIPT_DIR}/../bats-support" ]]; then
        echo -e "${YELLOW}Warning: bats-support not found${NC}" >&2
        helpers_missing=1
        missing_helpers+=("bats-support")
    fi
    
    if [[ ! -d "${SCRIPT_DIR}/../bats-assert" ]]; then
        echo -e "${YELLOW}Warning: bats-assert not found${NC}" >&2
        helpers_missing=1
        missing_helpers+=("bats-assert")
    fi
    
    if [[ ! -d "${SCRIPT_DIR}/../bats-file" ]]; then
        echo -e "${YELLOW}Warning: bats-file not found${NC}" >&2
        helpers_missing=1
        missing_helpers+=("bats-file")
    fi
    
    if [[ $helpers_missing -eq 1 ]]; then
        echo "" >&2
        echo "Optional bats helper libraries not found: ${missing_helpers[*]}" >&2
        echo "Tests will work but some assertions may not be available." >&2
        echo "" >&2
        
        # Prompt user to install
        if [[ -t 0 ]] && [[ -t 1 ]]; then
            # Interactive mode
            echo -e "${YELLOW}Would you like to install the helper libraries? (yes/no) [yes]:${NC} "
            read -r response
            response="${response:-yes}"
            
            if [[ "$response" =~ ^[Yy][Ee][Ss]$ ]]; then
                echo "" >&2
                echo -e "${GREEN}Installing bats helper libraries...${NC}" >&2
                echo "" >&2
                
                if [[ -f "${SCRIPT_DIR}/install_bats_helpers.sh" ]]; then
                    if bash "${SCRIPT_DIR}/install_bats_helpers.sh"; then
                        echo "" >&2
                        echo -e "${GREEN}Helper libraries installed successfully!${NC}" >&2
                        echo "" >&2
                    else
                        echo -e "${RED}Failed to install helper libraries${NC}" >&2
                        echo "You can install them manually later using:" >&2
                        echo "  ${SCRIPT_DIR}/install_bats_helpers.sh" >&2
                        echo "" >&2
                    fi
                else
                    echo -e "${RED}Install script not found: ${SCRIPT_DIR}/install_bats_helpers.sh${NC}" >&2
                    echo "Please install manually or create the install script." >&2
                    echo "" >&2
                fi
            else
                echo "" >&2
                echo "Skipping helper library installation." >&2
                echo "To install later, run: ${SCRIPT_DIR}/install_bats_helpers.sh" >&2
                echo "" >&2
            fi
        else
            # Non-interactive mode - just show instructions
            echo "To install helpers:" >&2
            echo "  ${SCRIPT_DIR}/install_bats_helpers.sh" >&2
            echo "" >&2
        fi
    fi
}

# Run tests
run_tests() {
    local test_files=("${SCRIPT_DIR}"/test_*.sh)
    local test_count=${#test_files[@]}
    
    if [[ $test_count -eq 0 ]]; then
        echo -e "${RED}Error: No test files found${NC}" >&2
        exit 1
    fi
    
    echo -e "${GREEN}Running $test_count test file(s)...${NC}"
    echo ""
    
    # Run bats with all test files
    cd "$PROJECT_ROOT"
    bats "${test_files[@]}"
}

# Main execution
main() {
    echo -e "${GREEN}UDM VPN Monitor Test Suite${NC}"
    echo "=========================="
    echo ""
    
    check_bats
    check_bats_helpers
    
    echo -e "${GREEN}Starting tests...${NC}"
    echo ""
    
    run_tests
}

# Run main
main "$@"

