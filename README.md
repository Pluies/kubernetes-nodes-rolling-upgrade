# kubernetes-nodes-rolling-upgrade

Script to upgrade worker nodes in a Kubernetes cluster on AWS.

## Assumptions

- You want to upgrade from version _x_ to version _y_
- Your nodes are in an autoscaling group, and new nodes will be created as version _y_

## Operation

This script will list all nodes running on version _x_ and, one by one:
- Drain it with `kubectl`
- Terminate it with `aws ec2 terminate-instance`
- Wait until the cluster is stable, i.e. no pod in Terminating / Pending / ContainerCreating state
- Carry on with the next node

**Warning**: this script _does not_ recreate nodes! It only terminates them cleanly and relies on the ASG or the cluster-autoscaler to recreate updated nodes.

## Prerequisites

- [kubectl](https://kubernetes.io/docs/reference/kubectl/kubectl/)
- [aws-cli](https://aws.amazon.com/cli/)

## Usage

```bash
VERSION=v1.19.6 ./rolling-upgrade.sh
```

## Configuration

Configuration is done through env vars.

| Environment variable   | Action                                            | Default value |
|------------------------|---------------------------------------------------|---------------|
| `VERSION`              | The version to upgrade to. Must be in the "VERSION" field of `kubectl get node` | _Unset_ |
| `DRY_RUN`              | Whether to actually delete the nodes, or just print out what the script would do. Any non-empty value forces a dry run. | `""` |
| `DRAIN_TIMEOUT`        | Maximum time for a node to finish draining before it gets forcefully terminated, in seconds. | `300` |
