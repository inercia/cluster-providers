#!/bin/bash

common_sh_dir="$(cd "$(dirname ${BASH_SOURCE[0]})" >/dev/null 2>&1 && pwd)"
[ -d "$common_sh_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}

########################################################################################################################
# constants
########################################################################################################################

# default time to wait
DEF_WAIT_TIMEOUT=100

# the cluster provider. by default use the dummy provider (uses the current kubeconfig)
CLUSTER_PROVIDER="${CLUSTER_PROVIDER:-}"
DEF_CLUSTER_PROVIDER="dummy"

# the kubeconfig, and possible kubeconfig files, and the default one
DEV_KUBECONFIG="${DEV_KUBECONFIG:-}"
DEF_KUBECONFIG="${HOME}/.kube/config"

# the registry. by default, a local one.
REGISTRY="${REGISTRY:-}"
DEF_REGISTRY="registry.local:5000"

########################################################################################################################
# extra
########################################################################################################################

RED='\033[1;31m'
GRN='\033[1;32m'
YEL='\033[1;33m'
BLU='\033[1;34m'
WHT='\033[1;37m'
MGT='\033[1;95m'
CYA='\033[1;96m'
END='\033[0m'
BLOCK='\033[1;47m'

########################################################################################################################
# utils
########################################################################################################################

alias echo_on="{ set -x; }"
alias echo_off="{ set +x; } 2>/dev/null"

log() { printf >&2 ">>> $1\n"; }

hl() {
	local curr_cols=$(tput cols)
	local cols=${1:-$((curr_cols - 4))}
	printf '>>> %*s\n' "$cols" '' | tr ' ' '*'
}

info() { log "${BLU}$1${END}"; }
highlight() { log "${MGT}$1${END}"; }

failed() {
	if [ -z "$1" ]; then
		log "${RED}failed!!!${END}"
	else
		log "${RED}$1${END}"
	fi
	abort "test failed"
}

passed() {
	if [ -z "$1" ]; then
		log "${GRN}done!${END}"
	else
		log "${GRN}$1${END}"
	fi
}

bye() {
	log "${BLU}$1... exiting${END}"
	exit 0
}

warn() { log "${RED}!!! WARNING !!! $1 ${END}"; }

abort() {
	log "${RED}FATAL: $1${END}"
	exit 1
}

# get a timestamp (in seconds)
timestamp() {
	date '+%s'
}

timeout_from() {
	local start=$1
	local now=$(timestamp)
	test $now -gt $(($start + $DEF_WAIT_TIMEOUT))
}

# command_exists <cmd>
#
# return true if the command provided exsists
#
command_exists() {
	[ -x "$1" ] || command -v $1 >/dev/null 2>/dev/null
}

replace_env_file() {
	info "Replacing env in $1..."
	[ -f "$1" ] || abort "$1 does not exist"
	envsubst <"$1" >"$2"
}

# check_url <url>
#
# checks that url is responding to requests, with an optional error message
#
check_url() {
	command_exists curl || abort "curl is not installed"
	curl -L --silent -k --output /dev/null --fail "$1"
}

# get_httpcode_url <url>
#
# return tyhe HTTP code obtained when accessing some url
#
get_httpcode_url() {
	local url="$1"
	command_exists curl || abort "curl is not installed"
	curl -k -s -o /dev/null -w "%{http_code}" "$url"
}

check_http_code() {
	local url="$1"
	local exp_code="$2"
	get_httpcode_url "$url" | grep -q "$exp_code"
}

wait_until() {
	local expr="$1"
	shift
	local start_time=$(timestamp)
	info "Waiting for '$expr'"
	until timeout_from $start_time || eval "$expr"; do
		info "... still waiting"
		sleep 1
	done
	! timeout_from $start_time
}

# wait until an URL returns a specific HTTP code
wait_http_code() {
	local url="$1"
	local code="$2"
	wait_until "check_http_code $url $code"
}

# kill_background
#
# kill the background job
#
kill_background() {
	info "(Stopping background job)"
	kill $!
	wait $! 2>/dev/null
}

wait_url() {
	local url="$1"
	info "Waiting for $url (max $DEF_WAIT_TIMEOUT seconds)"
	wait_until "check_url $url"
}

# download_exe <exe> <url>
#
# download an executable from an URL
#
download_exe() {
	local exe="$1"
	local url="$2"

	if ! command_exists "$exe"; then
		mkdir -p "$(dirname $exe)"
		info "Installing $(basename $exe)..."
		curl -L -o "$exe" "$url"
		chmod +x "$exe"
	fi
}

all_shs_in() {
	local d="$1"
	echo $(for f in $d/*.sh; do echo "$(basename $f .sh)"; done) | tr "\n" " "
}

# export_env exports a variable
export_env() {
	local variable="$1"
	local value="$2"

	if [ -n "$GITHUB_ACTION" ] ; then
		echo "::set-env name=${variable}::${value}"
	else
		echo "$variable='$value'"
	fi
}
