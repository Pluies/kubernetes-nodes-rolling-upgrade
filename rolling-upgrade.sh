#!/usr/bin/env bash
set -euo pipefail

# Perform a rolling upgrade on a Kubernetes cluster.
#
# See README.md for details

TARGET_VERSION=${TARGET_VERSION:-noversion}
DRY_RUN=${DRY_RUN:-}
DRAIN_TIMEOUT=${DRAIN_TIMEOUT:-300}

if [ "$TARGET_VERSION" == "noversion" ]
then
  echo "Missing env var TARGET_VERSION"
  echo "This is the version you want to end up with; e.g. run \`TARGET_VERSION=1.30 $0\` if you want to upgrade from 1.29 to 1.30."
  exit 1
fi

function run() {
  if [ -z "$DRY_RUN" ]; then
    echo "Running: $*"
    "$@"
  else
    echo "Dry run mode enabled 🍃"
    echo "Would run: $*"
  fi
}
bold=$(tput bold)
normal=$(tput sgr0)

echo "First things first: let's cordon upgradeable nodes so that new workloads will only be deployed on newer nodes"
UPGRADEABLE_NODES_WITH_VERSION=$(kubectl get node --no-headers | { grep -v "$TARGET_VERSION" || true; } | awk '{print $1 " (current version: " $5 ")" }')
if [ -z "$UPGRADEABLE_NODES_WITH_VERSION" ]
then
  echo "No upgradeable nodes - rollout finished!"
  exit 0
else
  echo "Found the following upgradeable nodes:"
  echo "$UPGRADEABLE_NODES_WITH_VERSION"
fi

UPGRADEABLE_NODES=$(kubectl get node --no-headers | { grep -v "$TARGET_VERSION" || true; } | awk '{print $1}')
echo ""
echo "Cordoning off upgradeable nodes 📴"
for NODE in $UPGRADEABLE_NODES
do
  run kubectl cordon "$NODE"
done

while true
do
  echo "Looking for upgradeable nodes..."
  UPGRADEABLE_NODES=$(kubectl get node --no-headers | { grep -v "$TARGET_VERSION" || true; } | awk '{print $1}')
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
    echo ""
    echo "• Upgrading node ${bold}$NODE${normal}"
    echo ""

    echo "${bold}Step 1: drain${normal}"
    set +e
    run kubectl drain --timeout="$DRAIN_TIMEOUT"s --ignore-daemonsets --delete-emptydir-data "$NODE"
    STATUS=$?
    if [ $STATUS -eq 0 ]
    then
      echo "Node drained successfully"
    elif [ $STATUS -eq 124 ]
    then
      echo "⚠️  Drain went over timeout, terminating node anyway"
    else
      echo "⚠️  Drain failed, skipping node"
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
    if [ -z "$DRY_RUN" ]; then
      while echo "$PODS" | grep -e 'Pending' -e 'ContainerCreating' -e 'Terminating'
      do
        echo "^ Found pending / creating / terminating pods, waiting 5 seconds..."
        sleep 5
        PODS=$(kubectl get pods --all-namespaces)
      done
    else
      echo "Dry run mode enabled 🍃"
      echo "Would wait for pods"
    fi

    echo "No unscheduled pods!"
    echo ""
  done
done
