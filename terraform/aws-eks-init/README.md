# Platform node root storage

The EKS module uses a custom launch template. Root volume capacity must be
configured through `block_device_mappings`, using `/dev/xvda` for the current
Amazon Linux 2023 AMI. The module's `disk_size` input is ignored with custom
launch templates.

The selected cluster's `group-platform-disk-size-gb` setting specifies GiB.
`atlas-apps` is configured for a 60 GiB gp3 root volume. Application PVCs are
separate volumes; container images, writable layers, logs, and disk-backed
`emptyDir` volumes consume root storage.

## Applying a size change

- Review the Terraform plan for unrelated drift, especially the API endpoint
  access list when its configuration is `AUTO`, and automatic AMI upgrades.
- A launch-template change affects new instances, not an existing root disk.
- An existing EBS root volume can be enlarged online. Verify the volume ID
  against the node's disk serial, then expand the partition and filesystem.
  The current AMI uses XFS; confirm this before using `growpart` and
  `xfs_growfs`. EBS volumes cannot be shrunk in place.
- Adopting a new launch-template version through an EKS node-group update
  recycles nodes. Single-replica applications can be interrupted. Preserve
  the current AMI release explicitly for a disk-only update.
- Rancher also reconciles the imported EKS cluster. Before adopting a new
  version, align `clusters.management.cattle.io/c-v7khk` at
  `spec.eksConfig.nodeGroups[0].launchTemplate.version` with the intended
  version, verifying the node-group name first. Otherwise Rancher rolls the
  node group back to its saved version after the AWS update completes.
  Use a narrow patch: the general edit form can populate unrelated defaults.
- Verify EKS update completion, replacement-node root capacity, node pressure,
  deployment readiness, PVC attachment, and load-balancer target health.
  Refresh Terraform state after an EKS update performed through the AWS API.
- The current application EBS volumes are zonal in `us-east-1a`, while the
  node group spans two zones. During this single-worker rollout, temporary
  scale-in protection kept the replacement in `us-east-1a` through scale-down;
  remove that protection after the update. Future node-replacement design
  should explicitly account for this placement constraint.

## September 15, 2026 repair

The original node had a 20 GiB root volume despite a 40 GiB configuration.
Repeated image garbage-collection failures culminated in disk pressure,
Ask Atlas UAT evictions, and deployment scheduling failures. Its live root
volume was expanded online to 60 GiB and XFS grew successfully, leaving
approximately 43 GiB free. Launch-template version 2 was applied through
Terraform with the corrected disk mapping. The approved EKS rollout uses
the existing AMI release `1.34.4-20260318`.

The first rollout succeeded, but Rancher immediately requested version 1
again. CloudTrail identified the separate Go SDK request from
`100.24.129.154` at `2026-09-16T02:29:00Z`. Rancher's saved version was
confirmed as 1, then patched and verified as 2. This reconciliation must
remain aligned with Terraform for the capacity change to persist.
The already-running rollback could not be stopped by changing Rancher's
desired version. Its temporary 20 GiB worker also hit disk pressure and was
expanded online to 60 GiB while the corrective rollout started. This caused
additional application restarts beyond the initially approved rollout.

Final verification on September 15 at approximately 21:56 CDT: EKS update
`44984e43-ffc9-36fc-ae54-354bb1245e59` succeeded; the node group is `ACTIVE`
on launch-template version 2 with min/desired/max of 1/1/2. The retained
worker `ip-10-90-18-72.ec2.internal` has a 60 GiB root filesystem, roughly
41 GiB free after import rehydration, and no disk pressure. All 28
deployments are available and all 12 application target groups have healthy
targets. HTTPS checks returned 200 for eight application homepages and 307
for the four Ask Atlas homepages. This verifies reachability, not signed-in
application workflows. Temporary scale-in protection was removed and
Terraform state was refreshed. Configuration validation and formatting
checks passed. The existing AMI release and API access list were preserved.

Follow-up capacity work: budget Ask Atlas import-inbox `emptyDir` storage,
review Rancher agent writable-layer growth, and alert on node filesystem
headroom before the kubelet's 10% free-space eviction threshold.
