#!/bin/bash

set -e

# Send standard out and standard error to a log file that will be shipped to CloudWatch by the CloudWatch agent
exec > /var/log/user-data
exec 2>&1

echo '# Starting user-data script'

echo '# Installing CloudWatch agent'
wget https://s3.${aws_region}.amazonaws.com/amazoncloudwatch-agent-${aws_region}/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i -E ./amazon-cloudwatch-agent.deb
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOF
{
   "logs":{
      "logs_collected":{
         "files":{
            "collect_list":[
               {
                  "file_path":"/var/log/user-data",
                  "log_group_name":"wireguard",
                  "log_stream_name":"{instance_id}/var/log/user-data"
               }
            ]
         }
      }
   }
}
EOF

echo '# Disabling IPv6'
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1

echo '# Installing microk8s'
snap install microk8s --classic --channel=1.22/stable
echo '# Waiting for microk8s to be ready'
microk8s status --wait-ready
echo '# Enabling dns and ingress microk8s features'
microk8s enable dns ingress storage

echo '# Adjusting firewall rules for microk8s'
ufw allow in on cni0 && ufw allow out on cni0
ufw default allow routed

echo '# Installing Argo CD'
microk8s.kubectl create namespace argocd
microk8s.kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo '# Disabling auth and HTTPS for Argo CD server'
microk8s.kubectl patch deploy argocd-server -n argocd -p '[{"op": "add", "path": "/spec/template/spec/containers/0/command/-", "value": "--disable-auth"}, {"op": "add", "path": "/spec/template/spec/containers/0/command/-", "value": "--insecure"}]' --type json

echo '# Deploying ingress for Argo CD server UI'
cat <<EOF | microk8s.kubectl apply -n argocd -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-http-ingress
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: "public"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
    host: argocd.${internal_domain}
  tls:
  - hosts:
    - argocd.${internal_domain}
    secretName: argocd-secret # do not change, this is provided by Argo CD
EOF

echo '# Deploying bootstrap Argo CD app'
microk8s.kubectl create namespace bootstrap
cat <<EOF | microk8s.kubectl apply -n bootstrap -f -
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
    repoURL: https://github.com/kronicle-tech/kronicle-argocd-config.git
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

echo '# Finished user-data script'
