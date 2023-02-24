# Using the Kubernetes cluster providers in GitHub actions

## Pre-requisites

Create a workflow YAML file in your `.github/workflows` directory. An
[example workflow](#example-workflow) is available below.
For more information, reference the GitHub Help Documentation for
[Creating a workflow file](https://help.github.com/en/articles/configuring-a-workflow#creating-a-workflow-file).

## Inputs

For more information on inputs, see the [API Documentation](https://developer.github.com/v3/repos/releases/#input).

- `provider`: One of the [supported cluster providers](providers.md)
  (ie, `k3d`, `kind`, `gke`...).
- `command`: The [command](entrypoints.md) to run (ie, `create`, `destroy`, `login`...)
- `name`: (optional) The name of the cluster. It should be unique.
- `size`: (optional) The total number of nodes in the cluster (including
  master and worker nodes)
- `machine`: (optional) The node size or _"model"_, depending on the cluster provider
  (ie, on Azure it can be something like `Standard_D2s_v3`)
- `region`: (optional) cluster location (ie, `us-east1-b` on GKE)
- `registry`: (optional) a custom name for the registry in the cluster (supported only in some providers)

Cluster providers usually support some advanced configuration through
environment variable. Check out the list of env vars for each [provider](providers.md).
These environmenta variables should be passed through an `env` map.

## Outputs

All the subsequent steps in the workflow will automatically have available
in their environment the [output variables](variables.md) that would be exported
with `get-env`.

### Example Workflow

Create a workflow (eg: `.github/workflows/create-cluster.yml`):

```yaml
name: Create Cluster
on: pull_request
jobs:
  create-cluster:
    runs-on: ubuntu-latest
    steps:
      - name: Create a k3d Cluster
        uses: inercia/cluster-providers@master
        with:
            provider: k3d
            command: create
        env:
            K3D_EXTRA_ARGS: "--k3s-arg \"--no-deploy=traefik@server:*\""

      - name: Test the cluster created
        run: |
          kubectl cluster-info
```

This uses [inercia/cluster-provider@master](https://www.github.com/inercia/cluster-provider)
GitHub Action to spin up a [k3d](https://github.com/rancher/k3d/) Kubernetes cluster on
every Pull Request.
