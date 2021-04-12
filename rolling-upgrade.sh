#!/usr/bin/env bash
set -euo pipefail

# Perform a rolling upgrade on a Kubernetes cluster.
#
# See README.md for details

VERSION=${VERSION:-noversion}
DRY_RUN=${1:-}
DRAIN_TIMEOUT=${DRAIN_TIMEOUT:-120}

if [ "$VERSION" == "noversion" ]
then
  echo "Missing env var VERSION"
  echo "This is the version you want to end up with; e.g. run \`VERSION=1.19 $0\` if you want to upgrade from 1.18 to 1.19."
  exit 1
fi

function run() {
  echo "$@"
  if [ -z "$DRY_RUN" ]; then
    "$@"
  fi
}
bold=$(tput bold)
normal=$(tput sgr0)

while true
do
  echo "Looking for upgradeable nodes..."
  UPGRADEABLE_NODES=$(kubectl get node --no-headers | { grep -v "$VERSION" || true; } | awk '{print $1}')
  if [ -z "$UPGRADEABLE_NODES" ]
  then
    echo "No more upgradeable nodes - rollout finished!"
    exit 0
  else
    echo "Found the following upgradeable nodes:"
    echo "$UPGRADEABLE_NODES"
  fi

  echo ""
  echo "Upgrading all nodes. 🚀"

  for NODE in $UPGRADEABLE_NODES
  do
    echo "Upgrading node $NODE"

    echo "${bold}Step 1: drain${normal}"
    set +e
    run kubectl drain --timeout="$DRAIN_TIMEOUT"s --ignore-daemonsets --delete-local-data "$NODE"
    STATUS=$?
    if [ $STATUS -eq 0 ]
    then
      echo "Node drained successfully"
    elif [ $STATUS -eq 124 ]
    then
      echo "⚠️ Drain went over timeout, terminating node anyway"
    else
      echo "⚠️ Drain failed, skipping node"
      continue
    fi

    echo "${bold}Step 2: terminate${normal}"
    INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=private-dns-name,Values=$NODE" --output text --query 'Reservations[*].Instances[*].InstanceId')
    if [ -z "$INSTANCE_ID" ]
    then
      echo "Instance disappeared, skipping"
      continue
    fi
    run aws ec2 terminate-instances --instance-ids="$INSTANCE_ID"

    echo "${bold}Step 3: wait for pending pods${normal}"
    PODS=$(kubectl get pods --all-namespaces)
    while echo "$PODS" | grep -e 'Pending' -e 'ContainerCreating' -e 'Terminating'
    do
      echo "^ Found pending / terminating pods, waiting 5 seconds..."
      sleep 5
      PODS=$(kubectl get pods --all-namespaces)
    done
    echo "No unscheduled pods!"

    echo ""
  done
done
