# Environment variables

## Input variables: configuring the cluster we want

* `CLUSTER_PROVIDER`: the name of one of the cluster providers currently supported.
* `CLUSTER_NAME`: specifies the name of the cluster. It should be unique, but it should
  be "constant" so that a new execution of the provider could detect if the cluster
  already exists.
* `CLUSTER_SIZE`: total number of nodes in the cluster (including master and worker nodes).
  Some cluster will always create the same number of masters (ie, K3D or LXC always create 1).
* `CLUSTER_MACHINE`: node size or _model_, depending on the cluster provider
  (ie, on Azure it can be something like `Standard_D2s_v3`).
* `CLUSTER_REGION`: cluster location (ie, `us-east1-b` on GKE).
* `CLUSTER_REGISTRY`: (supported by some providers) custom name for the registry in the cluster.
* `CLUSTER_VERSION`: (supported by some providers) the version of Kubernetes.


## Output variables: getting info for using the cluster

* `DEV_REGISTRY`: the registry created (ie, `registry.localhost:5000`).
* `KUBECONFIG`: the kubeconfig generated for connecting to the API server in this cluster.
* `DEV_KUBECONFIG`: same as `KUBECONFIG`.
* `CLUSTER_NAME`: a unique cluster name. Will be the `CLUSTER_NAME` provided when it was not empty.
* `CLUSTER_SIZE`: (see the input environment variables)
* `CLUSTER_MACHINE`: (see the input environment variables)
* `CLUSTER_REGION`: (see the input environment variables)

In some environments you can get:

* `DOCKER_NETWORK`:the docker network used for connecting all the machines in the cluster.
* `SSH_IP_MASTER<NUM>`: the IP address for ssh'ing to the master number `<NUM>`
* `SSH_IP_WORKER<NUM>`: the IP address for ssh'ing to the worker number `<NUM>`
* `SSH_IPS`: all the IP addresses for ssh'ing to the nodes.
* `SSH_USERNAME`: the ssh username required for connecting to the nodes of the cluster
  (will never be provided for machines created in the cloud, only for local environments).
* `SSH_PASSWORD`: the ssh password required for connecting to the nodes of the cluster
  (will never be provided for machines created in the cloud, only for local environments).

Example for LXC:

```console
$ CLUSTER_PROVIDER=lxc ./providers.sh get-env
>>> (cluster provider: lxc: get-env)
CLUSTER_NAME=
CLUSTER_SIZE=2
CLUSTER_MACHINE=
CLUSTER_REGION=
SSH_IP_MASTER0=10.0.1.169
SSH_IP_WORKER0=10.0.1.57
SSH_IPS='10.0.1.169 10.0.1.57'
```
