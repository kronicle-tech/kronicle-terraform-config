#!/bin/bash

set -e

# Disable IPv6
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1

# Install microk8s
snap install microk8s --classic --channel=1.22/stable
microk8s status --wait-ready
microk8s enable dns ingress

ufw allow in on cni0 && ufw allow out on cni0
ufw default allow routed

# Install Argo CD
microk8s.kubectl create namespace argocd
microk8s.kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
microk8s.kubectl patch deploy argocd-server -n argocd -p '[{"op": "add", "path": "/spec/template/spec/containers/0/command/-", "value": "--disable-auth"}]' --type json
microk8s.kubectl create namespace bootstrap
echo <<EOF | microk8s.kubectl apply -n argocd
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: bootstrap
  namespace: bootstrap
  # Add a this finalizer ONLY if you want these to cascade delete.
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  # Source of the application manifests
  source:
    repoURL: https://github.com/kronicle-tech/kronicle-argo-cd-config.git
    targetRevision: HEAD
    path: bootstrap

    # helm specific config
    helm:
      valueFiles:
      - values-prod.yaml

  destination:
    server: https://kubernetes.default.svc
    namespace: bootstrap

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
