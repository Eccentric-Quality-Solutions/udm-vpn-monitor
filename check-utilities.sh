#!/bin/bash
#
# UDM Utility Availability Checker
# Checks whether required Linux utilities are available on the system
#
# Version: 0.8.1
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# List of utilities to check
UTILITIES=(
	ip
	ss
	netstat
	ps
	top
	htop
	free
	uptime
	df
	dig
	nslookup
	getent
	logread
	dmesg
	awk
	sed
	grep
	watch
	timeout
	crontab
	date
	expr
)

# Check if a utility is available
#
# Checks if a command exists in the system PATH using 'command -v'.
# This is POSIX-compliant and more reliable than 'which'.
#
# Arguments:
#   $1: Utility name to check
#
# Returns:
#   0: Utility is available
#   1: Utility is not available
#
# Examples:
#   check_utility "ip"
#   if check_utility "ss"; then echo "ss is available"; fi
check_utility() {
	local utility="$1"
	if command -v "$utility" >/dev/null 2>&1; then
		return 0
	else
		return 1
	fi
}

# Main function to check all utilities
#
# Iterates through the list of utilities and checks their availability.
# Prints results with color coding: green for available, red for missing.
# Provides a summary at the end.
#
# Arguments:
#   None
#
# Returns:
#   0: All utilities are available
#   1: One or more utilities are missing
main() {
	local missing_count=0
	local available_count=0
	local missing_utilities=()

	echo "Checking utility availability on UDM..."
	echo ""

	# Check each utility
	for utility in "${UTILITIES[@]}"; do
		if check_utility "$utility"; then
			echo -e "${GREEN}[✓]${NC} $utility"
			((available_count++)) || true
		else
			echo -e "${RED}[✗]${NC} $utility"
			missing_utilities+=("$utility")
			((missing_count++)) || true
		fi
	done

	# Print summary
	echo ""
	echo "=========================================="
	echo "Summary:"
	echo "  Available: ${available_count}/${#UTILITIES[@]}"
	if [ $missing_count -gt 0 ]; then
		echo -e "  Missing: ${RED}${missing_count}${NC}"
		echo ""
		echo "Missing utilities:"
		for util in "${missing_utilities[@]}"; do
			echo "  - $util"
		done
		return 1
	else
		echo -e "  Missing: ${GREEN}0${NC}"
		echo ""
		echo "All utilities are available!"
		return 0
	fi
}

# Run main function
main "$@"
