# argo-capi
using Argo to manage capi and apps on downstream clusters

install argo: 
```
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```
clone, then kubectl apply -f capimgr1/
