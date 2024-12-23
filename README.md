# kubernetes-nodes-rolling-upgrade

Script to upgrade worker nodes in a Kubernetes cluster on AWS.

## Assumptions

- You want to upgrade from version _x_ to version _y_
- Your nodes are in an autoscaling group (or use karpenter), and newly created nodes will be created as version _y_

## Operation

This script will list all nodes running on version _x_ and, one by one:
- Drain it with `kubectl drain`
- Terminate it with `aws ec2 terminate-instance`
- Wait until the cluster is stable, i.e. no pod in Terminating / Pending / ContainerCreating state
- Carry on with the next node

`kubectl drain` is the recommended way to [Safely Drain a Node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/). Under the hood, it uses Kubernetes' [Eviction API](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/#eviction-api) to manage voluntary disruptions. This will result in a fully transparent, no-downtime upgrade, _as long as you have the proper HA measures in place_. ✅

By "proper HA measures", I mean:
- Well-configured replicated [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) or [StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/); including resource requests & limits, readiness / liveness probes, clean shutdown behaviour, etc
- [Pod Disruption Budgets](https://kubernetes.io/docs/tasks/run-application/configure-pdb/), or at least [PodAntiAffinity rules](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) or [Pod Topology Spread constraints](https://kubernetes.io/docs/concepts/workloads/pods/pod-topology-spread-constraints/) to ensure that workloads are spread across the cluster rather than on a single node

Nodes are drained with:
- `--ignore-daemonsets`, to allow draining a node even if it has DaemonSets
- `--delete-local-data`, to allow draining a node even if Pods are storing data locally

Drain **will not** delete a node if there are pods not managed by a ReplicationController, ReplicaSet, Job, DaemonSet or StatefulSet, as these pods would not be recreated automatically on a new node. If you need this, you'll need to add the `--force` flag to `kubectl drain`.

**Warning**: this script _does not_ recreate nodes! It only terminates them cleanly and relies on the ASG or the cluster autoscaler to recreate updated nodes.

## Prerequisites

- [kubectl](https://kubernetes.io/docs/reference/kubectl/kubectl/)
- [aws-cli](https://aws.amazon.com/cli/)

## Usage

```bash
TARGET_VERSION=v1.30 ./rolling-upgrade.sh
```

## Configuration

Configuration is done through env vars.

| Environment variable   | Action                                            | Default value |
|------------------------|---------------------------------------------------|---------------|
| `TARGET_VERSION`       | The target version to upgrade to. Must be a substring match in the "VERSION" field of `kubectl get node` | _Unset_ |
| `DRY_RUN`              | Whether to actually delete the nodes, or just print out what the script would do. Any non-empty value forces a dry run. | `""` |
| `DRAIN_TIMEOUT`        | Maximum time for a node to finish draining before it gets forcefully terminated, in seconds. | `300` |
