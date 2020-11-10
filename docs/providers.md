# Current cluster providers

## k3d

The `k3d` provider create a local Kubernetes cluster with the
latest, stable version of [k3d](github.com/rancher/k3d).

### Additional input variables for advanced configuration

The `k3d` cluster provider supports some environment variables for tweaking
the configuration:

- `K3D_EXTRA_ARGS`: custom arguments for `k3d create`.

## KIND

The `kind` provider creates a Kubenetes cluster with the latest
version of [KIND](kind.sigs.k8s.io/).

## Azure

The `azure` provider creates a Kubenetes cluster in Azure AKS using the `az` cli.

### Credentials

In order to create a cluster in Azure you must obtain some valib credentials
and make them available through environment variables.

- Login into azure with `az login`
- Get the list of subscriptions with `az account list`
  ```json
   {
     "cloudName": "AzureCloud",
     "id": "<SUBSCRIPTION_ID>",
     "isDefault": true,
     "name": "<...>",
     "state": "Enabled",
     "tenantId": "<TENANT_ID>",
     "user": {
       "name": "test@something.io",
       "type": "user"
     }
   }
  ```
- Set the account with `az account set --subscription="<SUBSCRIPTION_ID>"`
- Run `az ad sp create-for-rbac --role="Contributor" --scopes="/subscriptions/<SUBSCRIPTION_ID>"`. You
  will get an output like:
  ```json
  {
   "appId": "<AZ_USERNAME>",
   "name": "<...>",
   "password": "<AZ_PASSWORD>",
   "tenant": "<AZ_TENANT>"
  }
  ```
  and save it to `az-credentials.json`.
- Now you must save the file encoded in a variable.
  - encode the file with `AZ_AUTH=$(cat az-credentials.json | base64 | tr -d ' ' | tr -d '\n')`
  - make this variable available to the cluster provider. In CI:
    - For _Travis_, you could use the command line tool like:
      ```console
      $ travis env set AZ_AUTH "$AZ_AUTH"
      ```
    - for _GitHub actions_, you can save it in a Secret and then create a
      `env` block in your _Step_ with that secret, as:
      ```yaml
      env:
        AZ_AUTH: ${{ secrets.AZ_AUTH }}
      ```
- Set some other environment variables:
  - `AZ_USERNAME`: value of `appId`
  - `AZ_PASSWORD`: value of `password`
  - `AZ_TENANT`: value of `tenant`

  In CI, make sure these variables are kept safe (ie, not printed to console)
  by storing them in secrets.


## GKE

The `gke` provider creates a Kubenetes cluster in GKE using the `gcloud` cli.

### Credentials

In order to create a cluster in GKE you must obtain some valib credentials
and make them available through environment variables.

- Login into the [GCloud console](https://console.cloud.google.com)
- Create a [new service account](https://console.cloud.google.com/iam-admin/serviceaccounts).
- Verity the roles assigned [here](https://console.cloud.google.com/iam-admin/iam).
- Assign _"Kubernetes Admin"_ role
- Create a new _Key_. Select `JSON` as the format. The JSON file will be downloaded
  and saved to your computer automatically.
- Then you could use some env variables:
  - encode the file with `GKE_AUTH=$(cat gke-credentials.json | base64 | tr -d ' ' | tr -d '\n')`
  - make this variable available to the cluster provider. In CI:
    - for _Travis_, you can do it with the command line client with:
      ```console
      $ travis env set GKE_AUTH "$GKE_AUTH
      ```
    - for _GitHub actions_, you can save it in a Secret and then create a
      `env` block in your _Step_ with that secret, as:
      ```yaml
      env:
        GKE_AUTH: ${{ secrets.GKE_AUTH }}
      ```
