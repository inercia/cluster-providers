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

K3D_URL="https://github.com/rancher/k3d/releases/download/v1.7.0/k3d-linux-amd64"

K3D_CLUSTER_NAME="${CLUSTER_NAME:-cluster-$user-$num}"

K3D_NETWORK_NAME="k3d-$K3D_CLUSTER_NAME"

K3D_API_PORT=${K3D_API_PORT:-6444}

K3D_REGISTRY_NAME="${K3D_REGISTRY_NAME:-registry.localhost}"

K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-5000}"

K3D_REGISTRY="$K3D_REGISTRY_NAME:$K3D_REGISTRY_PORT"

K3D_NUM_WORKERS=0

K3D_EXTRA_ARGS="${K3D_EXTRA_ARGS:-}"

K3D_ARGS="--wait=60 --name=${K3D_CLUSTER_NAME} --api-port ${K3D_API_PORT} --enable-registry --registry-name ${K3D_REGISTRY_NAME} --registry-port ${K3D_REGISTRY_PORT} ${K3D_EXTRA_ARGS}"

#########################################################################################

export PATH=$PATH:$(dirname $K3D_INSTALL_EXE)

[ -n "$CLUSTER_SIZE" ] && K3D_NUM_WORKERS=$((CLUSTER_SIZE - 1))

get_kubeconfig() {
    $K3D_EXE get-kubeconfig --name="$K3D_CLUSTER_NAME" 2>/dev/null
}

get_k3d_server_ip() {
    local cont="k3d-$K3D_CLUSTER_NAME-server"
    docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $cont
}

check_k3d_cluster_exists() {
    $K3D_EXE list 2>/dev/null | grep -q "$K3D_CLUSTER_NAME"
}

# replace the IP in the kubeconfig (127.0.0.1 or localhost) by the real IP of the container,
# so we can connect from the Ambassador builder container
replace_ip_kubeconfig() {
    local kc="$1"
    local current_ip=$(get_k3d_server_ip)

    info "Replacing 127.0.0.1 by $current_ip"
    for addr in "127.0.0.1" "localhost"; do
        sed -i -e 's/'$addr'\b/'$current_ip'/g' "$kc"
    done
}

create_cluster() {
    info "Creating k3d cluster $K3D_CLUSTER_NAME..."
    $K3D_EXE create --workers $K3D_NUM_WORKERS --server-arg '--no-deploy=traefik' $K3D_ARGS
    sleep 3
    kc=$(get_kubeconfig)
    [ -n "$kc" ] || abort "could not obtain a valid KUBECONFIG from k3d"

    replace_ip_kubeconfig "$kc"

    info "Showing some k3d cluster info:"
    kubectl --kubeconfig="$kc" cluster-info
}

#########################################################################################

case $1 in
#
# setup and cleanup
#
setup)
    if ! command_exists $K3D_EXE; then
        info "Installing k3d"

        curl -Lo ./k3d "$K3D_URL" || abort "could not download K3D from $K3D_URL"
        chmod +x ./k3d
        mkdir -p "$(dirname $K3D_INSTALL_EXE)"
        mv ./k3d $K3D_INSTALL_EXE
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
        info "curl -Lo /tmp/k3d $K3D_URL ; chmod 755 /tmp/k3d ; sudo cp -f /tmp/k3d /usr/local/bin/"
        abort "no k3d executable found"
    fi

    if check_k3d_cluster_exists; then
        info "A cluster $K3D_CLUSTER_NAME exists: removing..."
        $0 delete
    fi

    create_cluster
    ;;

delete)
    for ancestor in builder "$K3D_REGISTRY:aes"; do
        cid="$(docker ps --filter ancestor=$ancestor -q)"
        if [ -n "$cid" ]; then
            info "Stopping container CID:$cid"
            docker stop "$cid" 2>/dev/null
        fi
    done

    info "Destroying k3d cluster $K3D_CLUSTER_NAME..."
    $K3D_EXE delete --name="$K3D_CLUSTER_NAME" 2>/dev/null || /bin/true
    ;;

#
# create and destroy the registry
# in the k3d case, the registry is associated to the cluster
#
create-registry)
    if check_k3d_cluster_exists; then
        info "A cluster $K3D_CLUSTER_NAME exists: nothing to do..."
    else
        create_cluster
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
    export_env "DEV_REGISTRY" "${K3D_REGISTRY}"
    export_env "DOCKER_NETWORK" "${K3D_NETWORK_NAME}"

    kc=$(get_kubeconfig)
    if [ -n "$kc" ]; then
        export_env "DEV_KUBECONFIG" "${kc}"
        export_env "KUBECONFIG" "${kc}"
    fi

    export_env "CLUSTER_NAME" "$K3D_CLUSTER_NAME"
    export_env "CLUSTER_SIZE" "$((K3D_NUM_WORKERS + 1))"
    export_env "CLUSTER_MACHINE="
    export_env "CLUSTER_REGION="

    # k3d-specific vars
    export_env "K3D_CLUSTER_NAME" "$K3D_CLUSTER_NAME"
    export_env "K3D_NETWORK_NAME" "$K3D_NETWORK_NAME"
    export_env "K3D_API_PORT" "$K3D_API_PORT"
    ;;

*)
    info "'$1' ignored for $CLUSTER_PROVIDER"
    ;;

esac
