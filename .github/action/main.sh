#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

CURR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
TOP_DIR=$(realpath $CURR_DIR/../..)

maybe_setup() {
    if [ ! -e /tmp/.cluster-provider-setup-$provider ] ; then
        "$TOP_DIR/providers.sh" "setup"
        touch /tmp/.cluster-provider-setup-$provider
    fi
}

main() {
    local provider="${INPUT_PROVIDER}"
    local command="${INPUT_COMMAND}"

    [ "$INPUT_NAME" ] && export CLUSTER_NAME="$INPUT_NAME"
    [ "$INPUT_SIZE" ] && export CLUSTER_SIZE="$INPUT_SIZE"
    [ "$INPUT_MACHINE" ] && export CLUSTER_MACHINE="$INPUT_MACHINE"
    [ "$INPUT_REGION" ] && export CLUSTER_REGION="$INPUT_REGION"
    [ "$INPUT_REGISTRY" ] && export CLUSTER_REGISTRY="$INPUT_REGISTRY"

    export CLUSTER_PROVIDER="$provider"

    case $command in
    *)
        echo ">>> Running command $command"
        maybe_setup
        "$TOP_DIR/providers.sh" "$command"
        ;;
    esac

    echo ">>> Getting ennvironment"
    "$TOP_DIR/providers.sh" "get-env"
}

main
