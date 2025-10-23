# variables
$group = "rg-aks-maxunavailable"
$cluster = "aksmaxunavailable"
$location = "eastus2"
$nodePool = "userpool"

# create resource group
az group create --name $group --location $location

# create aks cluster
az aks create `
  --resource-group $group `
  --name $cluster `
  --node-count 1 `
  --kubernetes-version 1.32 `
  --generate-ssh-keys

# add user node pool with maxunavailable upgrade strategy
az aks nodepool add `
  --resource-group $group `
  --cluster-name $cluster `
  --name $nodePool `
  --node-count 5 `
  --max-surge 0 `
  --max-unavailable 2

# get credentials
az aks get-credentials --resource-group $group --name $cluster