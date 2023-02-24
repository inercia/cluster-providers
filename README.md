# Kubernetes Cluster Providers

Easily create/delete/_something-else_ Kubernetes clusters.

Features:

- common interface for creating Kubernetes clusters in both local
  and cloud environments.
- clusters have their own _Docker registry_ for pushing/pulling images.
- configuration via environment variables. cluster information is also obtained
  from environment variables.

It can be used both as a standalone script as well as a GitHub action.

## Example GitHub action

```yaml
name: Create Cluster
on: pull_request
jobs:
  create-cluster:
    runs-on: ubuntu-latest
    steps:
      - name: Create a local k3d cluster
        uses: inercia/cluster-providers@master
        # changing the provider to something different would keep things the same
        with:
            provider: k3d
            command: create
        # we can pass some advanced, provider-specific configuration in env variables
        env:
            K3D_EXTRA_ARGS: "--k3s-arg \"--no-deploy=traefik@server:*\""

      - name: Test the cluster we created
        # KUBECONFIG has been set by the previous step: kubectl should work fine
        run: |
          kubectl cluster-info

      - name: Delete the k3d cluster
        uses: inercia/cluster-providers@master
        # not really important to destroy a local cluster, but we should always
        # remember to do it in cloud providers like GKE or Azure.
        with:
            provider: k3d
            command: delete
```

# Table of contents

- Using the Kubernetes cluster providers in:
  - [shell scripts](docs/usage-shell.md)
  - [GitHub actions](docs/usage-github.md)
- Usage:
  - [List of commands](docs/entrypoints.md): `create`, `delete`...
  - [Input and output](docs/variables.md) variables: configuring the cluster and getting info from it.
- List of [current providers](docs/providers.md):
  - [k3d](docs/providers.md#k3d)
  - [KIND](docs/providers.md#kind)
  - [GKE](docs/providers.md#GKE)
  - [Azure](docs/providers.md#Azure)
