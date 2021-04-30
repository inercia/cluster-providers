#!/bin/bash

k3d_prov_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$k3d_prov_dir" ] || {
    echo "FATAL: no current dir (maybe running in zsh?)"
    exit 1
}

# shellcheck source=../common.sh
source "$k3d_prov_dir/../common.sh"

user=$(whoami)
num="${TRAVIS_BUILD_ID:-0}"

#########################################################################################

K3D_EXE="k3d"

K3D_INSTALL_EXE="$HOME/bin/k3d"

K3D_INST_URL="https://raw.githubusercontent.com/rancher/k3d/main/install.sh"

K3D_CLUSTER_NAME="${CLUSTER_NAME:-cluster-$user-$num}"

K3D_KUBECONFIG="/tmp/k3d-kubeconfig-${K3D_CLUSTER_NAME}"

K3D_NETWORK_NAME="k3d-$K3D_CLUSTER_NAME"

K3D_API_PORT=${K3D_API_PORT:-6444}

K3D_REGISTRY_NAME="${K3D_REGISTRY_NAME:-registry.localhost}"

K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-5000}"

K3D_REGISTRY="$K3D_REGISTRY_NAME:$K3D_REGISTRY_PORT"

K3D_NUM_WORKERS=0

K3D_EXTRA_ARGS="${K3D_EXTRA_ARGS:-}"

K3D_ARGS="--wait --api-port ${K3D_API_PORT} --registry-use ${K3D_REGISTRY_NAME} ${K3D_EXTRA_ARGS}"

#########################################################################################

export PATH=$PATH:$(dirname $K3D_INSTALL_EXE)

[ -n "$CLUSTER_SIZE" ] && K3D_NUM_WORKERS=$((CLUSTER_SIZE - 1))

get_k3d_server_ip() {
    local cont="k3d-$K3D_CLUSTER_NAME-server-0"
    docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $cont
}

check_registry_exists() {
    $K3D_EXE registry list | grep -q "$K3D_REGISTRY_NAME" >/dev/null 2>&1
}

check_k3d_cluster_exists() {
    $K3D_EXE cluster list 2>/dev/null | grep -q "$K3D_CLUSTER_NAME" >/dev/null 2>&1
}

# replace the IP in the kubeconfig (127.0.0.1 or localhost) by the real IP of the container
replace_ip_kubeconfig() {
    local kc="$1"
    local current_ip=$(get_k3d_server_ip)

    info "Replacing 127.0.0.1 by $current_ip"
    for addr in "127.0.0.1" "localhost"; do
        sed -i -e 's/'$addr'\b/'$current_ip'/g' "$kc"
    done
}

create_registry() {
    if check_registry_exists ; then
        info "k3d registry alreay exists"
    else
        info "Creating k3d registry..."
        $K3D_EXE registry create "$K3D_REGISTRY_NAME" --port $K3D_REGISTRY_PORT || abort
    fi
}

create_cluster() {
    create_registry || abort "could not create registry"

    info "Creating k3d cluster $K3D_CLUSTER_NAME..."
    KUBECONFIG="$K3D_KUBECONFIG" $K3D_EXE cluster create --agents $K3D_NUM_WORKERS $K3D_ARGS "$K3D_CLUSTER_NAME" || abort
    sleep 3

    # replace_ip_kubeconfig "$K3D_KUBECONFIG"

    info "Showing some k3d cluster info:"
    kubectl --kubeconfig="$K3D_KUBECONFIG" cluster-info || abort
}

#########################################################################################

[ -n "$1" ] || abort "no command provided"

case $1 in
#
# setup and cleanup
#
setup)
    if ! command_exists $K3D_EXE; then
        info "Installing k3d"

        curl -s "$K3D_INST_URL" | bash
        [ $? -eq 0 ] || abort "could not download K3D from $K3D_INST_URL"

        # chmod +x ./k3d
        # mkdir -p "$(dirname $K3D_INSTALL_EXE)"
        # mv ./k3d $K3D_INSTALL_EXE

        command_exists $K3D_EXE || abort "could not install k3d"
    else
        info "k3d seems to be installed"
    fi

    info "Checking that $K3D_REGISTRY_NAME is resolvable"
    grep -q $K3D_REGISTRY_NAME /etc/hosts
    if [ $? -ne 0 ]; then
        if [ -z "$IS_CI" ] && [ -z "$CI" ] ; then
            abort "$K3D_REGISTRY_NAME is not in /etc/hosts: please add an entry manually."
        fi

        info "Adding '127.0.0.1 $K3D_REGISTRY_NAME' to /etc/hosts"
        echo "127.0.0.1 $K3D_REGISTRY_NAME" | sudo tee -a /etc/hosts
    else
        passed "... good: $K3D_REGISTRY_NAME is in /etc/hosts"
    fi
    ;;

cleanup)
    info "Cleaning up k3d..."
    $0 delete
    # TODO: uninstall stuff
    ;;

#
# login
#
login)
    info "No login to do"
    ;;

#
# logout
#
logout)
    info "No logout to do"
    ;;

#
# create and destroy tyhe cluster
#
create)
    if ! command_exists k3d; then
        warn "No k3d command found. Install k3d or use a different CLUSTER_PROVIDER."
        info "You can manually install k3d with:"
        info "curl -s $K3D_INST_URL | bash"
        abort "no k3d executable found"
    fi

    if check_k3d_cluster_exists; then
        info "A cluster $K3D_CLUSTER_NAME exists: removing..."
        $0 delete
    fi

    create_cluster
    ;;

delete)
    info "Destroying k3d cluster $K3D_CLUSTER_NAME..."
    KUBECONFIG=$K3D_KUBECONFIG $K3D_EXE cluster delete "$K3D_CLUSTER_NAME" 2>/dev/null || /bin/true
    rm -f "$K3D_KUBECONFIG"
    ;;

#
# create and destroy the registry
#
create-registry)
    create_registry
    ;;

delete-registry)
    if check_registry_exists ; then
        $K3D_EXE registry delete "$K3D_REGISTRY_NAME"
    fi
    ;;

#
# return True if the cluster exists
#
exists)
    check_k3d_cluster_exists
    ;;

#
# get the environment vars
#
get-env)
    export_env "DEV_REGISTRY" "k3d-${K3D_REGISTRY}"
    export_env "DOCKER_NETWORK" "${K3D_NETWORK_NAME}"

    export_env "DEV_KUBECONFIG" "$K3D_KUBECONFIG"
    export_env "KUBECONFIG" "$K3D_KUBECONFIG"

    export_env "CLUSTER_NAME" "$K3D_CLUSTER_NAME"
    export_env "CLUSTER_SIZE" "$((K3D_NUM_WORKERS + 1))"
    export_env "CLUSTER_MACHINE"
    export_env "CLUSTER_REGION"

    # k3d-specific vars
    export_env "K3D_CLUSTER_NAME" "$K3D_CLUSTER_NAME"
    export_env "K3D_NETWORK_NAME" "$K3D_NETWORK_NAME"
    export_env "K3D_API_PORT" "$K3D_API_PORT"
    ;;

*)
    info "command '$1' ignored for $CLUSTER_PROVIDER"
    ;;

esac
