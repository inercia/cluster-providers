# Using the cluster providers from shell scripts

## How to use the cluster providers

* _running the script_ from command line: just invoke the main script with the right
  entrypoint, like `providers.sh setup`. Get the environment for the current
  cluster with `eval "$(providers.sh get-env)"`.

* _including the script_: with `source providers.sh` and then
  running the `cluster_provider` function with the desired _entrypoint_,
  like `cluster_provider 'create'`. After creating the cluster you can get the
  environment with `eval "$(cluster_provider 'get-env')"`

Note that some cluster providers will require some [authentication](#Authentication)
as well as some [customization with environment variables](#Configuring-the-cluster-with-env-variables).

## Example

For example, we can create local k3d cluster with:

```console
$ CLUSTER_PROVIDER=k3d ./providers.sh create
>>> (cluster provider: k3d: create)
>>> Creating k3d cluster operator-tests-alvaro-0...
INFO[0000] Created cluster network with ID 8f45e65287b15083cbfb5c208862d791f0b25a82416de9df8417a2ff5b32d187
INFO[0000] Created docker volume  k3d-operator-tests-alvaro-0-images
INFO[0000] Creating cluster [operator-tests-alvaro-0]
INFO[0000] Registry already present: ensuring that it's running and connecting it to the 'k3d-operator-tests-alvaro-0' network...
INFO[0000] Creating server using docker.io/rancher/k3s:v1.17.4-k3s1...
INFO[0006] SUCCESS: created cluster [operator-tests-alvaro-0]
INFO[0006] A local registry has been started as registry.localhost:5000
INFO[0006] You can now use the cluster with:

export KUBECONFIG="$(k3d get-kubeconfig --name='operator-tests-alvaro-0')"
kubectl cluster-info
>>> Replacing 127.0.0.1 by 172.29.0.3
>>> Showing some k3d cluster info:
Kubernetes master is running at https://172.29.0.3:6444
CoreDNS is running at https://172.29.0.3:6444/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
Metrics-server is running at https://172.29.0.3:6444/api/v1/namespaces/kube-system/services/https:metrics-server:/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

and then we can get the configuration for this cluster with:

```console
$ CLUSTER_PROVIDER=k3d ./providers.sh get-env
>>> (cluster provider: k3d: get-env)
DEV_REGISTRY=registry.localhost:5000
DOCKER_NETWORK=k3d-operator-tests-alvaro-0
DEV_KUBECONFIG=/home/alvaro/.config/k3d/operator-tests-alvaro-0/kubeconfig.yaml
KUBECONFIG=/home/alvaro/.config/k3d/operator-tests-alvaro-0/kubeconfig.yaml
CLUSTER_NAME=operator-tests-alvaro-0
CLUSTER_SIZE=1
CLUSTER_MACHINE=
CLUSTER_REGION=
K3D_CLUSTER_NAME=operator-tests-alvaro-0
K3D_NETWORK_NAME=k3d-operator-tests-alvaro-0
K3D_API_PORT=6444
```

Once we are done, we can destroy the cluster with:

```console
$ CLUSTER_PROVIDER=k3d ./providers.sh delete
>>> (cluster provider: k3d: delete)
>>> Stopping container CID:b521db1b8bc4
b521db1b8bc4
>>> Destroying k3d cluster operator-tests-alvaro-0...
INFO[0000] Removing cluster [operator-tests-alvaro-0]
INFO[0000] ...Removing server
INFO[0000] ...Disconnecting Registry from the k3d-operator-tests-alvaro-0 network
INFO[0000] ...Removing docker image volume
INFO[0000] Removed cluster [operator-tests-alvaro-0]
```