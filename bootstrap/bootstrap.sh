#!/bin/bash
set -eou pipefail

function wait_for_created {
	kind=$1
	namespace=""
	if [ $# -eq 2 ]; then 
		namespace="-n $2"
	fi
	count=$(k3s kubectl get --no-headers --ignore-not-found $kind $namespace | wc -l)
	while [ $count -lt 1 ] ; do
		sleep 1
		count=$(k3s kubectl get --no-headers --ignore-not-found $kind $namespace | wc -l)
	done
}

[ $(which k3s) ] && echo "k3s is already installed; run /usr/local/bin/k3s-uninstall.sh to remove it" && exit 1

TOKENFILE=$(mktemp)
uuidgen --random > $TOKENFILE

curl -sfL https://get.k3s.io | K3S_TOKEN=$(cat $TOKENFILE) sh -s server --cluster-init 

echo "Waiting for cluster to come up completely"
systemctl start k3s
wait_for_created node
k3s kubectl wait --all node --for=condition=Ready
wait_for_created deployment kube-system
k3s kubectl rollout status -w --namespace kube-system deployment

echo "Bootstrapping Argo CD"
k3s kubectl apply -f https://raw.githubusercontent.com/stenwt/argo-capi/refs/heads/main/bootstrap/argo-k3s-helm.yaml

wait_for_created deployment argocd
k3s kubectl rollout status -w --namespace argocd deployment

echo "Applying app-of-apps"
k3s kubectl apply -f https://raw.githubusercontent.com/stenwt/argo-capi/refs/heads/main/clusters/capimgr1/capimgr1-app.yaml

echo "Ready! To join more nodes to this cluster, run: "
echo "curl -sfL https://get.k3s.io | K3S_TOKEN=$(cat $TOKENFILE) sh -s - server --server https://$(hostname):6443 --tls-san=$(hostname)"
