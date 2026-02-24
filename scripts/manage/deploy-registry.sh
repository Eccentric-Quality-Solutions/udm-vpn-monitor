#!/bin/bash
#
# Deployment Registry
# Tracks which UDMs have been deployed, what version, and when.
# Used by deploy-to-udm.sh and deploy-to-udms.sh for skip/resume logic.
#
# Registry format (tab-separated, one line per host):
#   host	version	timestamp
#
# Arguments:
#   Uses DEPLOY_REGISTRY_FILE if set; otherwise defaults to REPO_ROOT/logs/deploy-registry
#
# Returns:
#   Functions return 0 on success, 1 on failure (or empty when no record found)

# Default registry path (caller should set REPO_ROOT)
DEPLOY_REGISTRY_FILE="${DEPLOY_REGISTRY_FILE:-}"

# Get registry file path.
# Requires REPO_ROOT to be set by caller.
#
# Arguments:
#   None (uses REPO_ROOT and DEPLOY_REGISTRY_FILE from environment)
#
# Returns:
#   0: Path printed to stdout
#   1: REPO_ROOT not set
get_registry_path() {
	if [[ -z "${REPO_ROOT:-}" ]]; then
		return 1
	fi
	if [[ -n "${DEPLOY_REGISTRY_FILE}" ]]; then
		echo "$DEPLOY_REGISTRY_FILE"
		return 0
	fi
	echo "${REPO_ROOT}/logs/deploy-registry"
	return 0
}

# Extract SCRIPT_VERSION from a package file (zip or tar.gz).
#
# Arguments:
#   $1: package_path - Path to udm-vpn-monitor.zip or udm-vpn-monitor.tar.gz
#
# Returns:
#   0: Version printed to stdout
#   1: Package not found, unreadable, or version not found
get_package_version() {
	local pkg="${1:-}"
	local v=""

	[[ -f "$pkg" ]] || return 1

	if [[ "$pkg" == *.zip ]]; then
		v=$(unzip -p "$pkg" vpn-monitor.sh 2>/dev/null | grep -E '^SCRIPT_VERSION=' | head -1 | sed -E 's/^SCRIPT_VERSION=["'\'']?([^"'\'' ]+).*/\1/' | tr -d ' ')
	elif [[ "$pkg" == *.tar.gz ]] || [[ "$pkg" == *.tgz ]]; then
		v=$(tar -xzf "$pkg" -O vpn-monitor.sh 2>/dev/null | grep -E '^SCRIPT_VERSION=' | head -1 | sed -E 's/^SCRIPT_VERSION=["'\'']?([^"'\'' ]+).*/\1/' | tr -d ' ')
	else
		return 1
	fi

	[[ -n "$v" ]] && echo "$v" && return 0
	return 1
}

# Get deployed version and timestamp for a host from the registry.
#
# Arguments:
#   $1: host - Target host or IP (as used in deploy config)
#
# Returns:
#   0: version and timestamp printed (tab-separated: version\ttimestamp)
#   1: No record found or registry error
get_deployed_info() {
	local host="$1"
	local reg_path
	local line

	reg_path=$(get_registry_path) || return 1
	[[ -f "$reg_path" ]] || return 1

	# Match exact host (first field) to avoid 192.168.1.10 matching 192.168.1.100
	line=$(awk -F'\t' -v h="$host" '$1==h {print $0; exit}' "$reg_path" 2>/dev/null)
	[[ -z "$line" ]] && return 1

	# Format: host	version	timestamp
	local _host _version _ts
	IFS=$'\t' read -r _host _version _ts <<<"$line"
	[[ -n "$_version" ]] || return 1

	echo "${_version}	${_ts}"
	return 0
}

# Check if host has the given version deployed (and optionally newer).
#
# Arguments:
#   $1: host - Target host or IP
#   $2: version - Version to compare against (e.g. current package version)
#
# Returns:
#   0: Host has this version or newer deployed (skip deploy)
#   1: Host needs deployment (no record, or older version)
host_has_version() {
	local host="$1"
	local want_version="$2"
	local info
	local deployed_version

	[[ -n "$host" ]] || return 1
	[[ -n "$want_version" ]] || return 1

	info=$(get_deployed_info "$host") || return 1
	deployed_version=$(echo "$info" | cut -f1)
	[[ -n "$deployed_version" ]] || return 1

	# Exact match: skip
	[[ "$deployed_version" == "$want_version" ]] && return 0

	# Simple version comparison: if deployed matches or is "newer" we skip
	# For now, exact match only; semantic version comparison could be added
	return 1
}

# Record a successful deployment in the registry.
# Uses atomic write (write to .tmp, then mv).
#
# Arguments:
#   $1: host - Target host or IP
#   $2: version - Deployed version
#   $3: timestamp - When deployed (ISO format or epoch; default: now)
#
# Returns:
#   0: Record written successfully
#   1: Write failed
record_deployment() {
	local host="$1"
	local version="$2"
	local timestamp="${3:-$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)}"
	local reg_path
	local tmp_path
	local new_line

	[[ -n "$host" ]] || return 1
	[[ -n "$version" ]] || return 1

	reg_path=$(get_registry_path) || return 1
	tmp_path="${reg_path}.tmp"
	mkdir -p "$(dirname "$reg_path")" 2>/dev/null || true

	new_line="${host}	${version}	${timestamp}"

	# Remove existing line for this host (exact match on first field), append new one
	if [[ -f "$reg_path" ]]; then
		awk -F'\t' -v h="$host" '$1!=h {print}' "$reg_path" 2>/dev/null >"$tmp_path" || true
	else
		: >"$tmp_path"
	fi
	echo "$new_line" >>"$tmp_path"

	if mv "$tmp_path" "$reg_path" 2>/dev/null; then
		return 0
	fi
	rm -f "$tmp_path" 2>/dev/null
	return 1
}
