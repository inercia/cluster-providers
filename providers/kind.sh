#!/bin/bash

kind_prov_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$kind_prov_dir" ] || {
  echo "FATAL: no current dir (maybe running in zsh?)"
  exit 1
}

# shellcheck source=../common.sh
source "$kind_prov_dir/../common.sh"

user=$(whoami)
num="${TRAVIS_BUILD_ID:-0}"

#########################################################################################

KIND_EXE="kind"

KIND_INSTALL_EXE="$HOME/bin/kind"

KIND_HTTP_PORT=${KIND_HTTP_PORT:-80}

KIND_HTTPS_PORT=${KIND_HTTPS_PORT:-443}

KIND_CLUSTER_NAME="${CLUSTER_NAME:-kind-$user-$num}"

KIND_KUBECONFIG="$HOME/.kube/${KIND_CLUSTER_NAME}"

KIND_NETWORK_NAME="kind"

KIND_REGISTRY_ENABLED=1

KIND_REGISTRY_NAME="${KIND_REGISTRY_NAME:-registry.localhost}"

KIND_REGISTRY_PORT="${KIND_REGISTRY_PORT:-5000}"

KIND_REGISTRY="$KIND_REGISTRY_NAME:$KIND_REGISTRY_PORT"

KIND_NUM_WORKERS=0

KIND_URL="https://github.com/kubernetes-sigs/kind/releases/latest/download/kind-linux-amd64"

KIND_ARGS="--wait=60s --kubeconfig=$KIND_KUBECONFIG --name=${KIND_CLUSTER_NAME} ${KIND_EXTRA_ARGS}"

#########################################################################################

[ -n "$CLUSTER_SIZE" ] && KIND_NUM_WORKERS=$((CLUSTER_SIZE - 1))

get_kubeconfig() {
  $KIND_EXE get-kubeconfig --name="$KIND_CLUSTER_NAME" 2>/dev/null
}

check_kind_cluster_exists() {
  $KIND_EXE get clusters 2>/dev/null | grep -q "$KIND_CLUSTER_NAME"
}

create_cluster() {
  mkdir -p "$(dirname $KIND_KUBECONFIG)"

  if [ -n "$KIND_REGISTRY_ENABLED" ] ; then
    info "Creating a registry container (unless it already exists)..."
    running="$(docker inspect -f '{{.State.Running}}' "${KIND_REGISTRY_NAME}" 2>/dev/null || true)"
    if [ "${running}" != 'true' ]; then
      docker run \
        -d --restart=always -p "${KIND_REGISTRY_PORT}:5000" --name "${KIND_REGISTRY_NAME}" \
        registry:2
    fi
  fi

  info "Creating KIND cluster $KIND_CLUSTER_NAME (with ${KIND_HTTP_PORT}->80, ${KIND_HTTPS_PORT}->443)"
  cat <<EOF | $KIND_EXE create cluster $KIND_ARGS --config=- || abort "when creating cluster"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: ${KIND_HTTP_PORT}
    protocol: TCP
    listenAddress: "127.0.0.1"
  - containerPort: 443
    hostPort: ${KIND_HTTPS_PORT}
    protocol: TCP
    listenAddress: "127.0.0.1"
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${KIND_REGISTRY_PORT}"]
    endpoint = ["http://${KIND_REGISTRY_NAME}:${KIND_REGISTRY_PORT}"]
EOF

  if [ -n "$KIND_REGISTRY_ENABLED" ] ; then
    info "Connecting the registry to the cluster network"
    docker network connect "$KIND_NETWORK_NAME" "${KIND_REGISTRY_NAME}"
  fi

  # tell https://tilt.dev to use the registry
  # https://docs.tilt.dev/choosing_clusters.html#discovering-the-registry
  info "Telling https://tilt.dev to use the registry..."
  for node in $(kind get nodes --name=$KIND_CLUSTER_NAME); do
    kubectl annotate node "${node}" "kind.x-k8s.io/registry=localhost:${KIND_REGISTRY_PORT}"
  done

  info "Showing some KIND cluster info:"
  kubectl --kubeconfig="$KIND_KUBECONFIG" cluster-info
}

#########################################################################################

case $1 in
#
# setup and cleanup
#
setup)
  if ! command_exists kind; then
    info "Installing KIND"
    curl -Lo ./kind "$KIND_URL" || abort "could not download kind from $KIND_URL"
    chmod +x ./kind
    mkdir -p "$(dirname $KIND_INSTALL_EXE)"
    mv ./kind $KIND_INSTALL_EXE
    command_exists kind || abort "could not install kind"
  else
    info "kind seems to be installed"
  fi
  ;;

cleanup)
  info "Cleaning up kind..."
  # TODO
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
  if ! command_exists kind; then
    warn "No kind command found. Install kind or use a different CLUSTER_PROVIDER."
    info "You can manually install kind with:"
    info "curl -Lo ./kind "$KIND_URL""
    abort "no KIND executable found"
  fi

  if check_kind_cluster_exists; then
    info "A cluster $KIND_CLUSTER_NAME exists: removing..."
    $0 delete
  fi

  create_cluster
  ;;

delete)
  info "Destroying KIND cluster $KIND_CLUSTER_NAME..."
  $KIND_EXE delete cluster --name="$KIND_CLUSTER_NAME" || /bin/true
  rm -f "$KIND_KUBECONFIG"
  ;;

#
# create and destroy the registry
# in the kind case, the registry is associated to the cluster
#
create-registry)
  if check_kind_cluster_exists; then
    info "A cluster $KIND_CLUSTER_NAME exists: nothing to do..."
  else
    create_cluster
  fi
  ;;

delete-registry)
  info "Stopping registry at $KIND_CLUSTER_NAME"
  docker stop "${KIND_REGISTRY_NAME}"
  docker rm "${KIND_REGISTRY_NAME}"
  ;;

#
# return True if the cluster exists
#
exists)
  check_kind_cluster_exists
  ;;

#
# get the environment vars
#
get-env)
  export_env "DEV_REGISTRY" "${KIND_REGISTRY}"
  export_env "DOCKER_NETWORK" "${KIND_NETWORK_NAME}"

  export_env "DEV_KUBECONFIG" "${KIND_KUBECONFIG}"
  export_env "KUBECONFIG" "${KIND_KUBECONFIG}"

  export_env "CLUSTER_NAME" "$KIND_CLUSTER_NAME"
  export_env "CLUSTER_SIZE" "$((KIND_NUM_WORKERS + 1))"
  export_env "CLUSTER_MACHINE" ""
  export_env "CLUSTER_REGION" ""

  # kind-specific vars
  export_env "KIND_CLUSTER_NAME" "$KIND_CLUSTER_NAME"
  export_env "KIND_NETWORK_NAME" "$KIND_NETWORK_NAME"
  ;;

*)
  info "'$1' ignored for $CLUSTER_PROVIDER"
  ;;

esac
