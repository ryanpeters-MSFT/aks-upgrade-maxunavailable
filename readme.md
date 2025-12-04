# AKS Upgrade in Capacity-Constrained Regions with maxUnavailable Strategy

The `maxUnavailable` upgrade strategy allows AKS to perform node upgrades by utilizing existing nodes instead of provisioning additional surge nodes. This approach is especially valuable in capacity-constrained regions or when using specialized VM SKUs (like GPU nodes) where additional capacity might not be readily available.

## What is maxUnavailable?

The `maxUnavailable` parameter specifies how many existing nodes can be taken offline simultaneously during an upgrade process. Unlike the traditional `maxSurge` approach that provisions new nodes before draining old ones, `maxUnavailable` upgrades nodes in-place by:

1. **Cordoning** existing nodes to prevent new pod scheduling
2. **Draining** workloads from these nodes to other available nodes
3. **Upgrading** the nodes with the new Kubernetes version or node image
4. **Uncordoning** the upgraded nodes to resume normal operations

## Benefits for Capacity-Constrained Regions

> It is important to note that during any AKS upgrade process, the re-imaged nodes are not removed from the underlying VMSS. Although they are appear as unregistered from the Kubernetes control plane during the re-imaging process (note this process also updates the OS version), they are not "released" and will not be reclaimed by Azure, even under capacity-constrained regions.

Using `maxUnavailable` provides several advantages in regions with limited capacity:

### 1. **No Additional Capacity Required**
- Eliminates the need for surge nodes during upgrades
- Prevents upgrade failures due to `SKUNotAvailable`, `AllocationFailed`, or `OverconstrainedAllocationRequest` errors
- Particularly beneficial for specialized VM SKUs (GPU, high-memory, etc.)

### 2. **Cost Optimization**
- Avoids temporary increases in compute costs during upgrades
- No risk of being charged for surge nodes that might fail to provision

### 3. **Regional Resilience**
- Ensures upgrades can proceed even when Azure regions are experiencing capacity constraints
- Reduces dependency on real-time resource availability

## Important Notes

### Cannot be Combined

Use of both a `maxSurge` > 0 and a `maxUnavailable` > 0 is not allowed - only one must have a value greater than 0 and the other must be 0. Otherwise, the following error will occur:

```powershell
The value of parameter agentPoolProfile.upgradeSettings.maxUnavailable is invalid. Error details: maxSurge and maxUnavailable cannot both bigger than 0.
```

### User Node Pools Only
The use of `maxUnavailable` and `maxSurge` can only be used on user node pools - system node pools require surge nodes to be available for upgrades due to the criticality of the workloads running on the system node pools. System node pools require that `maxSurge` must be greater than 0 and `maxUnavailable` cannot be 0.

### Pod Disruption and Available Capacity

Because no surge nodes are being added to handle the buffer or "churn" of pods during the drain and cordon process, existing nodes must have available resources (i.e., memory, CPU) to handle the influx of pods while existing nodes are drained an re-imaged. There is greater chance that any enabled PDBs may cause issues to the draining process. 

Because of this, if node capacity is limited, it may be required to reduce PDB restrictions and/or use a pod `PriorityClass` to ensure that core pods are prioritized for scheduling first when there is contention in other nodes.

## Setup Script Explanation

The `setup.ps1` script creates:

1. **Resource Group**: `rg-aks-maxunavailable` in East US 2
2. **AKS Cluster**: Basic cluster with 1 node and Kubernetes version 1.32
3. **User Node Pool**: 5-node pool configured with:
   - `--max-surge 0`: No additional nodes during upgrades
   - `--max-unavailable 2`: Up to 2 nodes can be unavailable simultaneously

This configuration means during upgrades:
- No surge nodes will be provisioned
- Up to 2 out of 5 nodes can be offline at once
- Remaining 3 nodes must handle the workload during upgrades

## Usage

Run `.\setup.ps1` to create:
- Resource group (`rg-aks-maxunavailable`) in East US 2
- AKS cluster (`aksmaxunavailable`) with 1 system node
- User node pool (`userpool`) with 5 nodes configured for `maxUnavailable=2` upgrades
## Upgrade Strategy Comparison

| Strategy | Surge Nodes | Upgrade Method | Capacity Impact | Best For |
|----------|-------------|----------------|-----------------|----------|
| **maxSurge=5, maxUnavailable=0** | 5 additional nodes | Provision → Migrate → Decommission | High | Unlimited capacity regions |
| **maxSurge=0, maxUnavailable=2** | None | Drain → Upgrade → Restore | None | Capacity-constrained regions |

## Upgrade Commands

### Control Plane and Node Pool

These commands manually update the control plane and then individual node pools. This example updates the control plane to version 1.33 and then the "userpool" to 1.33. Be sure that the max version skew is no more than 3 versions between the control plane and node kubelet.

```powershell
# upgrade the control plane AKS version
az aks upgrade -n aksmaxunavailable -g rg-aks-maxunavailable -k 1.33 --control-plane-only

# upgrade the user node pool
az aks nodepool upgrade -n userpool --cluster-name aksmaxunavailable -g rg-aks-maxunavailable -k 1.33
```

### Node OS Upgrade

These commands update only the node OS image and not the Kubernetes version. The node OS version is tied to the Kubernetes version, however, and the latest possible node OS version for older Kubernetes versions may not be available. 

```powershell
# upgrade just the node OS images
az aks nodepool upgrade --node-image-only -n userpool --cluster-name aksmaxunavailable -g rg-aks-maxunavailable
```

## Important Considerations

### Workload Requirements
- Ensure your applications can tolerate having 2 nodes unavailable (40% of capacity in this example)
- Consider implementing [Pod Disruption Budgets (PDBs)](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/) to protect critical workloads
- Test upgrade scenarios in non-production environments first

### Monitoring During Upgrades
```bash
# Check node status during upgrade
kubectl get nodes

# Monitor pod distribution
kubectl get pods -o wide --all-namespaces

# Check for nodes marked as quarantined (if drain issues occur)
kubectl get nodes --show-labels | grep quarantined
```

For enhanced Kubernetes cluster monitoring, consider using [K9s](https://k9scli.io/), a terminal-based UI that provides real-time visualization of cluster resources, making it easier to monitor node states, pod distributions, and upgrade progress.

### Troubleshooting
If upgrades fail due to Pod Disruption Budget constraints:
- Review and adjust PDB `maxUnavailable` settings
- Increase pod replicas to meet disruption budget requirements
- Consider using `--enable-force-upgrade` for critical upgrades (use with caution)

## Best Practices

1. **Test in Staging**: Always validate upgrade settings in non-production environments
2. **Monitor Resource Usage**: Ensure remaining nodes can handle the workload during upgrades
3. **Plan Maintenance Windows**: Schedule upgrades during low-traffic periods
4. **Review PDBs**: Configure Pod Disruption Budgets appropriately for your workloads
5. **Check API Compatibility**: Validate applications against target Kubernetes versions before upgrading

## Links

- [AKS Upgrade Documentation](https://learn.microsoft.com/en-us/azure/aks/upgrade-cluster)
- [Customize Node Surge Upgrade](https://learn.microsoft.com/en-us/azure/aks/upgrade-aks-cluster#customize-node-surge-upgrade)
- [Pod Disruption Budgets](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)
- [AKS Production Upgrade Strategies](https://learn.microsoft.com/en-us/azure/aks/aks-production-upgrade-strategies)