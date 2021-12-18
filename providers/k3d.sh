#!/usr/bin/env bash

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

EXE_DIR=${EXE_DIR:-/usr/local/bin}

K3D_EXE="k3d"

K3D_INSTALL_EXE="$EXE_DIR/k3d"

K3D_INST_URL="https://raw.githubusercontent.com/rancher/k3d/main/install.sh"

K3D_CLUSTER_NAME="${CLUSTER_NAME:-cluster-$user-$num}"

K3D_KUBECONFIG="/tmp/k3d-kubeconfig-${K3D_CLUSTER_NAME}"

K3D_NETWORK_NAME="${K3D_NETWORK_NAME:-k3d-$K3D_CLUSTER_NAME}"

K3D_API_PORT=${K3D_API_PORT:-6444}

if [ "$(uname)" = "Darwin" ]; then
    K3D_REGISTRY_NAME="${K3D_REGISTRY_NAME:-registry}"
else
    K3D_REGISTRY_NAME="${K3D_REGISTRY_NAME:-registry.localhost}"
fi

K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-5011}"

K3D_REGISTRY="$K3D_REGISTRY_NAME:$K3D_REGISTRY_PORT"

K3D_NUM_WORKERS=0

K3D_EXTRA_ARGS="${K3D_EXTRA_ARGS:-}"

K3D_ARGS="--api-port ${K3D_API_PORT} --network ${K3D_NETWORK_NAME} --registry-use ${K3D_REGISTRY_NAME} ${K3D_EXTRA_ARGS}"

# set to anything for setting up /etc/hosts for the registry
K3D_SETUP_HOSTS=${K3D_SETUP_HOSTS:-}

# set to anything for replacing the 0.0.0.0 host by the actual IP in the kubeconfig
K3D_REPLACE_HOST=${K3D_REPLACE_HOST:-}

#########################################################################################

SUDO=${SUDO:-sudo}

export PATH=$PATH:$(dirname $K3D_INSTALL_EXE)

[ -n "$CLUSTER_SIZE" ] && K3D_NUM_WORKERS=$((CLUSTER_SIZE - 1))

[ "$(uname)" = "Darwin" ] && {
    info "Forcing /etc/hosts update"
    K3D_SETUP_HOSTS=1
}

# get_local_ip
# try to get the local IP address
get_local_ip() {
    if command_exists ip; then
        ip route get 8.8.8.8 | grep -oP 'src \K[^ ]+'
    elif command_exists ifconfig; then
        ifconfig |
            grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' |
            grep -Eo '([0-9]*\.){3}[0-9]*' |
            grep -v '172.17' |
            grep -v '127.0.0.1' | head -n 1
    elif command_exists hostname; then
        hostname -I | cut -d' ' -f1
    elif command_exists ipconfig; then
        ipconfig getifaddr en0 | head -n 1
    fi
}

get_container_ips() {
    local cont="$1"
    docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$cont"
}

get_k3d_apiserver_cont_name() {
    if docker inspect "k3d-$K3D_CLUSTER_NAME-serverlb" >/dev/null 2>&1; then
        echo "k3d-$K3D_CLUSTER_NAME-serverlb"
    else
        echo "k3d-$K3D_CLUSTER_NAME-server-0"
    fi
}

get_k3d_apiserver_ip() {
    get_container_ips "$(get_k3d_apiserver_cont_name)" | cut -d" " -f1
}

# gets the container name of the (first) server
get_k3d_server_cont_name() {
    echo "k3d-$K3D_CLUSTER_NAME-server-0"
}

get_k3d_server_ip() {
    get_container_ips "$(get_k3d_server_cont_name)" | cut -d" " -f1
}

get_k3d_api_server_addrs() {
    echo "https://$(get_k3d_apiserver_cont_name):${K3D_API_PORT}" \
        "https://$(get_k3d_apiserver_ip):${K3D_API_PORT}" \
        "https://$(get_k3d_apiserver_cont_name):6443" \
        "https://$(get_k3d_apiserver_ip):6443" \
        "https://localhost:${K3D_API_PORT}" \
        "https://127.0.0.1:${K3D_API_PORT}" \
        "https://$(get_k3d_server_cont_name):${K3D_API_PORT}" \
        "https://$(get_k3d_server_ip):${K3D_API_PORT}" \
        "https://$(get_local_ip):${K3D_API_PORT}"
}

check_registry_exists() {
    $K3D_EXE registry list | grep -v "exited" | grep -q "$K3D_REGISTRY_NAME" >/dev/null 2>&1
}

check_k3d_cluster_exists() {
    $K3D_EXE cluster list 2>/dev/null | grep -q "$K3D_CLUSTER_NAME" >/dev/null 2>&1
}

# replace the IP in the kubeconfig (127.0.0.1 or localhost) by the real IP of the container
replace_ip_kubeconfig() {
    local kc="$1"
    local current_ip=$(get_k3d_server_ip)

    info "Replacing 0.0.0.0 by $current_ip"
    for addr in "0.0.0.0" "localhost"; do
        sed -i -e 's/'$addr'\b/'$current_ip'/g' "$kc"
    done
}

create_registry() {
    if check_registry_exists; then
        info "k3d registry alreay exists"
    else
        info "Creating k3d registry..."
        $K3D_EXE registry create "$K3D_REGISTRY_NAME" \
            --port $K3D_REGISTRY_PORT || abort "could not create registry"
    fi

    local registry_ip="127.0.0.1"

    if [ -n "$K3D_SETUP_HOSTS" ]; then
        info "Checking that $K3D_REGISTRY_NAME is resolvable"
        if ! grep -q "$K3D_REGISTRY_NAME" /etc/hosts; then
            if [ -z "$IS_CI" ] && [ -z "$CI" ]; then
                warn "$K3D_REGISTRY_NAME is not in /etc/hosts: please add an entry manually."
            fi

            info "Adding '$registry_ip k3d-$K3D_REGISTRY_NAME' to /etc/hosts"
            echo "$registry_ip k3d-$K3D_REGISTRY_NAME" | $SUDO tee -a /etc/hosts || warn "could not add $K3D_REGISTRY_NAME to /etc/hosts"
        else
            passed "... good: $K3D_REGISTRY_NAME is in /etc/hosts"
        fi
    fi
}

delete_registry() {
    if check_registry_exists; then
        info "K3D registry running: destroying..."
        $K3D_EXE registry delete "$K3D_REGISTRY_NAME" || abort "could not destroy registry"

        local registry_ip="127.0.0.1"
        if [ -n "$K3D_SETUP_HOSTS" ]; then
            if grep -q "$K3D_REGISTRY_NAME" /etc/hosts; then
                info "Removing k3d-$K3D_REGISTRY_NAME from /etc/hosts"
                $SUDO sed -i "/k3d-$K3D_REGISTRY_NAME/d" /etc/hosts || warn "could not delete $K3D_REGISTRY_NAME from /etc/hosts"
            fi
        fi
    fi
}

create_cluster() {
    create_registry || abort "could not create registry"

    info "Creating k3d cluster $K3D_CLUSTER_NAME..."
    KUBECONFIG="$K3D_KUBECONFIG" \
        $K3D_EXE cluster create \
        --agents $K3D_NUM_WORKERS \
        $K3D_ARGS "$K3D_CLUSTER_NAME" || abort
    sleep 3

    [ -n "$K3D_REPLACE_HOST" ] && replace_ip_kubeconfig "$K3D_KUBECONFIG"

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
    delete_registry
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
    export_env "REGISTRY" "k3d-${K3D_REGISTRY}"
    export_env "DOCKER_NETWORK" "${K3D_NETWORK_NAME}"

    export_env "DEV_KUBECONFIG" "$K3D_KUBECONFIG"
    export_env "KUBECONFIG" "$K3D_KUBECONFIG"

    export_env "CLUSTER_NAME" "$K3D_CLUSTER_NAME"
    export_env "CLUSTER_SIZE" "$((K3D_NUM_WORKERS + 1))"
    export_env "CLUSTER_MACHINE"
    export_env "CLUSTER_REGION"
    export_env "CLUSTER_API_ADDRS" "$(get_k3d_api_server_addrs)"

    # k3d-specific vars
    export_env "K3D_CLUSTER_NAME" "$K3D_CLUSTER_NAME"
    export_env "K3D_NETWORK_NAME" "$K3D_NETWORK_NAME"
    export_env "K3D_API_PORT" "$K3D_API_PORT"
    ;;

*)
    info "command '$1' ignored for $CLUSTER_PROVIDER"
    ;;

esac
