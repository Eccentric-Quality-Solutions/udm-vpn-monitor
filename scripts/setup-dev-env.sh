#!/bin/bash
#
# Development Environment Setup Script
# Ensures development tools (shfmt, shellcheck) are available in PATH
#
# Usage:
#   ./scripts/setup-dev-env.sh
#
# This script checks for development tools in standard system paths (apt-installed)
# and Homebrew paths. If tools are found in system paths, no changes are needed.
# If tools are only available via Homebrew, it adds Homebrew's bin directory to
# PATH in your shell configuration file (.bashrc, .zshrc, or .profile).
#
# The script detects which shell configuration file to use and only adds PATH
# entries if necessary. It also checks for missing tools and provides installation
# instructions for both apt and Homebrew.

set -euo pipefail

# Detect shell configuration file
SHELL_CONFIG=""
if [[ -n "${ZSH_VERSION:-}" ]]; then
	SHELL_CONFIG="$HOME/.zshrc"
elif [[ -n "${BASH_VERSION:-}" ]]; then
	SHELL_CONFIG="$HOME/.bashrc"
else
	# Fallback to .profile
	SHELL_CONFIG="$HOME/.profile"
fi

# Check if shell config file exists, create if not
if [[ ! -f "$SHELL_CONFIG" ]]; then
	echo "Creating $SHELL_CONFIG..."
	touch "$SHELL_CONFIG"
fi

# Homebrew paths to check and add
BREW_PATHS=(
	"/home/linuxbrew/.linuxbrew/bin" # Linux Homebrew (default)
	"$HOME/.linuxbrew/bin"           # Linux Homebrew (user install)
	"/opt/homebrew/bin"              # macOS Homebrew (Apple Silicon)
)

# Find which Homebrew path exists (optional - only needed if tools aren't in system PATH)
BREW_BIN=""
for brew_path in "${BREW_PATHS[@]}"; do
	if [[ -d "$brew_path" ]]; then
		BREW_BIN="$brew_path"
		break
	fi
done

if [[ -n "$BREW_BIN" ]]; then
	echo "Found Homebrew at: $BREW_BIN"
fi

# Check if tools are available in system paths (apt-installed)
TOOLS_IN_SYSTEM_PATH=0
for sys_path in "/usr/bin" "/usr/local/bin" "/bin"; do
	if [[ -x "${sys_path}/shfmt" ]] || [[ -x "${sys_path}/shellcheck" ]]; then
		TOOLS_IN_SYSTEM_PATH=1
		break
	fi
done

# Only add Homebrew to PATH if:
# 1. Homebrew exists
# 2. Tools aren't already in system PATH
# 3. PATH entry doesn't already exist
if [[ -n "$BREW_BIN" ]] && [[ $TOOLS_IN_SYSTEM_PATH -eq 0 ]]; then
	if grep -q "export PATH.*$BREW_BIN" "$SHELL_CONFIG" 2>/dev/null; then
		echo "✓ Homebrew PATH already configured in $SHELL_CONFIG"
	else
		# Add PATH entry
		echo "" >>"$SHELL_CONFIG"
		echo "# Homebrew PATH (added by udm-vpn-monitor setup-dev-env.sh)" >>"$SHELL_CONFIG"
		echo "export PATH=\"$BREW_BIN:\$PATH\"" >>"$SHELL_CONFIG"
		echo "✓ Added Homebrew to PATH in $SHELL_CONFIG"
	fi
elif [[ $TOOLS_IN_SYSTEM_PATH -eq 1 ]]; then
	echo "✓ Tools found in system PATH (/usr/bin, /usr/local/bin, /bin)"
	if [[ -n "$BREW_BIN" ]]; then
		echo "  Homebrew PATH not needed (tools available via apt/system package manager)"
	fi
elif [[ -z "$BREW_BIN" ]]; then
	echo "⚠ Homebrew not found and tools not in system PATH"
	echo "  Install tools using apt or install Homebrew:"
	echo "    sudo apt-get install -y shfmt shellcheck"
	echo "    # OR"
	echo "    /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
fi

# Check for required tools
echo ""
echo "Checking for development tools..."

# Check if a development tool exists in PATH or standard installation locations
#
# Searches for a tool in multiple locations: current PATH, standard system
# paths (/usr/bin, /usr/local/bin, /bin), and Homebrew paths. This ensures
# tools are found even if they're not in the current PATH (e.g., when running
# in git hooks with minimal environment).
#
# Arguments:
#   $1: Name of the tool/command to check (e.g., "shfmt", "shellcheck")
#
# Returns:
#   0: Tool found in PATH or standard locations
#   1: Tool not found in any checked location
#
# Side effects:
#   None
#
# Examples:
#   if tool_exists "shfmt"; then
#       echo "shfmt is available"
#   fi
#
#   if ! tool_exists "shellcheck"; then
#       echo "shellcheck not found"
#   fi
#
# Note:
#   Uses command -v for PATH checking (most reliable method)
#   Checks system paths for apt-installed tools
#   Checks Homebrew paths if BREW_BIN variable is set
#   Only checks executable files (not just presence of file)
tool_exists() {
	local tool="$1"

	# Check if already in PATH
	if command -v "$tool" >/dev/null 2>&1; then
		return 0
	fi

	# Check standard system paths (for apt-installed tools)
	local system_paths=(
		"/usr/bin"
		"/usr/local/bin"
		"/bin"
	)

	for sys_path in "${system_paths[@]}"; do
		if [[ -x "${sys_path}/${tool}" ]]; then
			return 0
		fi
	done

	# Check Homebrew path
	if [[ -n "$BREW_BIN" ]] && [[ -x "$BREW_BIN/$tool" ]]; then
		return 0
	fi

	return 1
}

MISSING_TOOLS=()

if ! tool_exists "shfmt"; then
	MISSING_TOOLS+=("shfmt")
fi

if ! tool_exists "shellcheck"; then
	MISSING_TOOLS+=("shellcheck")
fi

if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then
	echo "⚠ Missing tools: ${MISSING_TOOLS[*]}"
	echo ""
	echo "Install missing tools using one of the following methods:"
	echo ""
	echo "  Homebrew:"
	echo "    brew install ${MISSING_TOOLS[*]}"
	echo ""
	echo "  Ubuntu/Debian (apt):"
	echo "    sudo apt-get update"
	echo "    sudo apt-get install -y ${MISSING_TOOLS[*]}"
	echo ""
	echo "  Fedora/RHEL (dnf):"
	echo "    sudo dnf install -y ${MISSING_TOOLS[*]}"
	echo ""
	echo "After installation, reload your shell configuration:"
	echo "  source $SHELL_CONFIG"
else
	echo "✓ All development tools found"
	echo ""
	echo "Tools available:"
	if tool_exists "shfmt"; then
		if command -v shfmt >/dev/null 2>&1; then
			shfmt --version
		else
			# Find it in system paths
			for sys_path in "/usr/bin" "/usr/local/bin" "/bin" "$BREW_BIN"; do
				if [[ -n "$sys_path" ]] && [[ -x "${sys_path}/shfmt" ]]; then
					"${sys_path}/shfmt" --version
					break
				fi
			done
		fi
	fi
	if tool_exists "shellcheck"; then
		if command -v shellcheck >/dev/null 2>&1; then
			shellcheck --version
		else
			# Find it in system paths
			for sys_path in "/usr/bin" "/usr/local/bin" "/bin" "$BREW_BIN"; do
				if [[ -n "$sys_path" ]] && [[ -x "${sys_path}/shellcheck" ]]; then
					"${sys_path}/shellcheck" --version
					break
				fi
			done
		fi
	fi
fi

echo ""
echo "Setup complete!"
echo ""
echo "To apply changes to your current shell session, run:"
echo "  source $SHELL_CONFIG"
echo ""
echo "Or open a new terminal window."
