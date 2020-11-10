#!/bin/bash

lxc_prov_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$lxc_prov_dir" ] || {
  echo "FATAL: no current dir (maybe running in zsh?)"
  exit 1
}

# shellcheck source=../common.sh
source "$lxc_prov_dir/../common.sh"

#########################################################################################

LXC_IMAGE="lxd-kube"

LXC_IMAGE_DEFINITION="$lxc_prov_dir/lxc/distrobuilder-opensuse.yaml"

LXC_IMAGE_FORCE="${LXC_IMAGE_FORCE:-}"

LXC_NUM_WORKERS=1

LXC_NETWORK="${LXC_NETWORK:-kube0}"

LXC_PROFILE="${LXC_PROFILE:-kube-profile}"

LXC_PROFILE_FILENAME="$lxc_prov_dir/lxc/kube-profile.yaml"

LXC_STORAGE=${LXC_STORAGE:-default}

#########################################################################################

[ -n "$CLUSTER_SIZE" ] && LXC_NUM_WORKERS=$((CLUSTER_SIZE - 1))

lxc_container_ip() {
  local container="$1"
  lxc info "$container" | grep -P "eth0:\tinet\t" | awk '{ print $3 }' 2>/dev/null
}

lxc_seq_workers() {
  seq 0 $((LXC_NUM_WORKERS - 1))
}

#########################################################################################

# references:
# - https://linuxcontainers.org/lxd/getting-started-cli/
# -

case $1 in

setup)
  # LXD version in Xenial is too old (2.0): we must use the snap
  info "Installing LXD snap..."
  sudo apt install -y golang-go debootstrap rsync gpg squashfs-tools git
  sudo apt remove -y --purge lxd lxd-client lxc
  sudo snap install lxd
  grep -q snap /etc/environment || sudo sh -c 'echo PATH=/snap/bin:${PATH} > /etc/environment'
  sudo lxd waitready
  sudo lxd init --auto
  sudo usermod -a -G lxd $(whoami)

  for module in overlay aufs ip_vs ip_vs_rr ip_vs_wrr ip_vs_sh nf_conntrack br_netfilter rbd ; do
    sudo modprobe $module || warn "could not local module $module"
  done
  ;;

create)
  $lxc_prov_dir/lxc/build-image.sh --img "$LXC_IMAGE" \
    --yaml "$LXC_IMAGE_DEFINITION" \
    --force "$LXC_IMAGE_FORCE" || abort "Image creation failed"

  lxc profile show $LXC_PROFILE >/dev/null 2>&1 || {
    info "Loading kube profile..."
    lxc profile create kube-profile
    cat "$LXC_PROFILE_FILENAME" | lxc profile edit $LXC_PROFILE || abort "could not load profile"
  }
  info "Kube profile:"
  lxc profile show $LXC_PROFILE || abort "could not show profile"

  lxc network info $LXC_NETWORK >/dev/null 2>&1 || {
    info "Creating the network"
    lxc network create $LXC_NETWORK ipv6.address=none ipv4.address=10.0.1.1/24 ipv4.nat=true || abort "could not create network"
  }
  info "Current LXC networks:"
  lxc network ls

  lxc info "kube-master0" >/dev/null 2>&1 || {
    info "Creating the masters:"
    lxc launch ${LXC_IMAGE} "kube-master0" -n $LXC_NETWORK -p $LXC_PROFILE -s $LXC_STORAGE ||
      abort "could not create machine"
  }
  info "Master info:"
  lxc info "kube-master0"

  for i in $(lxc_seq_workers); do
    lxc info "kube-worker${i}" >/dev/null 2>&1 || {
      info "Creating the worker $i:"
      lxc launch ${LXC_IMAGE} "kube-worker${i}" -n $LXC_NETWORK -p $LXC_PROFILE -s $LXC_STORAGE ||
        abort "could not create machine" lxc network attach $LXC_NETWORK "kube-worker${i}" || abort "could not attach to network"
    }
    info "Worker $i info:"
    lxc info "kube-worker${i}"
  done

  info "LXC machines currently running:"
  lxc list
  ;;

delete)
  lxc info "kube-master0" >/dev/null 2>&1 && {
    info "Deleting the master"
    lxc delete --force "kube-master0" 2>/dev/null || abort "could not delete machine"
  }

  for i in $(lxc_seq_workers); do
    lxc info "kube-worker${i}" >/dev/null 2>&1 && {
      info "Deleting the worker ${i}"
      lxc delete --force "kube-worker${i}" 2>/dev/null || abort "could not delete machine"
    }
  done

  lxc network info $LXC_NETWORK >/dev/null 2>&1 && {
    info "Deleting the network..."
    lxc network delete $LXC_NETWORK 2>/dev/null || abort "could not create network"
  }

  lxc profile show $LXC_PROFILE >/dev/null 2>&1 && {
    info "Deleting the Kube profile..."
    lxc profile delete $LXC_PROFILE 2>/dev/null || abort "could not show profile"
  }

  ;;

#
# get the environment vars
#
get-env)
  if [ -n "$KUBECONFIG" ]; then
    export_env "DEV_KUBECONFIG" "$KUBECONFIG"
    export_env "KUBECONFIG" "$KUBECONFIG"
  elif [ -n "$DEV_KUBECONFIG" ]; then
    export_env "DEV_KUBECONFIG" "$DEV_KUBECONFIG"
    export_env "KUBECONFIG" "$DEV_KUBECONFIG"
  fi

  export_env "CLUSTER_NAME="
  export_env "CLUSTER_SIZE" $((LXC_NUM_WORKERS + 1))
  export_env "CLUSTER_MACHINE" ""
  export_env "CLUSTER_REGION" ""

  if [ -n "$DEV_REGISTRY" ]; then
    export_env "DEV_REGISTRY" "$DEV_REGISTRY"
  fi

  all_ips=""
  lxc info "kube-master0" >/dev/null 2>&1 && {
    master_ip=$(lxc_container_ip kube-master0)
    all_ips="$master_ip"
    export_env "SSH_IP_MASTER0" "$master_ip"
  }

  for i in $(lxc_seq_workers); do
    lxc info "kube-worker${i}" >/dev/null 2>&1 && {
      worker_ip=$(lxc_container_ip kube-worker${i})
      all_ips="$all_ips $worker_ip"
      export_env "SSH_IP_WORKER$i" "$worker_ip"
    }
  done

  export_env "SSH_IPS" "$all_ips"

  # these machines will never be accessible from the outside world, so it
  # is ok to have a weak username/password
  export_env "SSH_USERNAME" "root"
  export_env "SSH_PASSWORD" "linux"
  ;;

#
# return True if the cluster exists
#
exists)
  /bin/true
  ;;

*)
  info "'$1' ignored for $CLUSTER_PROVIDER"
  ;;

esac
