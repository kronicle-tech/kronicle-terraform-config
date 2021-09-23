#!/bin/bash

set -e

# Send standard out and standard error to a log file that will be shipped to CloudWatch by the CloudWatch agent
exec > /var/log/user-data
exec 2>&1

echo '# Starting user-data script'

# Export HOME so cm-verifier can find "~/.kube/config"
export HOME=/root

echo '# Updating packages metadata'
apt-get update -y

echo '# Installing AWS CLI'
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
apt-get install -y unzip
unzip awscliv2.zip
./aws/install

echo '# Disabling IPv6'
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1

echo '# Associate Elastic IP'
aws ec2 associate-address --instance-id "$(wget -q -O - http://169.254.169.254/latest/meta-data/instance-id)" --allocation-id ${elastic_ip_id}

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
                  "log_group_name":"microk8s",
                  "log_stream_name":"{instance_id}/var/log/user-data"
               }
            ]
         }
      }
   }
}
EOF
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

echo '# Setting Route 53 DNS A record for private IP'
cat > change-resource-record-sets.json <<EOF
{
    "Comment": "Set private IP record for microk8s",
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "argocd.${internal_domain}",
                "Type": "A",
                "TTL": 60,
                "ResourceRecords": [
                    {
                        "Value": "$(wget -q -O - http://169.254.169.254/latest/meta-data/local-ipv4)"
                    }
                ]
            }
        }
    ]
}
EOF
aws route53 change-resource-record-sets --hosted-zone-id ${hosted_zone_id} --change-batch file://change-resource-record-sets.json

echo '# Installing microk8s'
snap install microk8s --classic --channel=1.22/stable

echo '# Waiting for microk8s to be ready'
microk8s status --wait-ready

echo '# Creating kube config file'
mkdir -p ~/.kube
microk8s config > ~/.kube/config

echo '# Enabling dns and ingress microk8s features'
microk8s enable dns ingress storage

echo '# Adjusting firewall rules for microk8s'
ufw allow in on cni0 && ufw allow out on cni0
ufw default allow routed

echo '# Installing cert-manager'
microk8s.kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.5.3/cert-manager.yaml

echo '# Waiting for cert-manager to fully start'
wget https://github.com/alenkacz/cert-manager-verifier/releases/download/v0.2.0/cert-manager-verifier_0.2.0_Linux_x86_64.tar.gz
tar zxvf cert-manager-verifier_0.2.0_Linux_x86_64.tar.gz
./cm-verifier
# cm-verifier output is missing a final newline
echo ''

echo '# Installing Argo CD'
microk8s.kubectl create namespace argocd
microk8s.kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo '# Disabling auth and HTTPS for Argo CD server'
microk8s.kubectl patch deploy argocd-server -n argocd -p '[{"op": "add", "path": "/spec/template/spec/containers/0/command/-", "value": "--disable-auth"}, {"op": "add", "path": "/spec/template/spec/containers/0/command/-", "value": "--insecure"}]' --type json

echo '# Deploying ingress for Argo CD server UI'
cat <<EOF | microk8s.kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  namespace: kube-system
  name: zerossl-eab-hmac-key
data:
  secret: ${zerossl_eab_hmac_key}
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: kronicle-tech-zerossl
spec:
  acme:
    server: https://acme.zerossl.com/v2/DV90
    externalAccountBinding:
      keyID: ${zerossl_eab_kid}
      keySecretRef:
        name: zerossl-eab-hmac-key
        key: secret
      keyAlgorithm: HS256
    privateKeySecretRef:
      name: kronicle-tech-zerossl
    solvers:
    - http01:
        ingress:
          class: public
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: internal-domain-zerossl
spec:
  acme:
    server: https://acme.zerossl.com/v2/DV90
    externalAccountBinding:
      keyID: ${zerossl_eab_kid}
      keySecretRef:
        name: zerossl-eab-hmac-key
        key: secret
      keyAlgorithm: HS256
    privateKeySecretRef:
      name: internal-domain-zerossl
    solvers:
    - dns01:
        cnameStrategy: Follow
        route53:
          region: ${aws_region}
          role: ${cert_manager_role}
EOF

echo '# Deploying ingress for Argo CD server UI'
cat <<EOF | microk8s.kubectl apply -n argocd -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-http
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: "public"   # The "public" ingress class is specific to microk8s
    nginx.ingress.kubernetes.io/whitelist-source-range: "${argocd_ip_allowlist}"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    cert-manager.io/cluster-issuer: "internal-domain-zerossl"
spec:
  rules:
  - host: argocd.${internal_domain}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
  tls:
  - hosts:
    - argocd.${internal_domain}
    secretName: argocd-server-http-tls
EOF

echo '# Deploying bootstrap Argo CD app'
microk8s.kubectl create namespace bootstrap
cat <<EOF | microk8s.kubectl apply -n argocd -f -
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: bootstrap
  namespace: argocd   # namespace must be "argocd"
  # Finalizer that ensures that project is not deleted until it is not referenced by any application
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  description: Project for the Kronicle live demo

  sourceRepos:
    - 'https://github.com/kronicle-tech/kronicle-argocd-config.git'

  destinations:
    - namespace: '*'
      server: https://kubernetes.default.svc

  # Allow all cluster-scoped resources to be created
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'

  # Allow all namespace-scoped resources to be created
  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'

  orphanedResources:
    warn: false
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: bootstrap
  namespace: argocd
  # Add a this finalizer ONLY if you want these to cascade delete.
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: bootstrap

  # Source of the application manifests
  source:
    repoURL: https://github.com/kronicle-tech/kronicle-argocd-config.git
    targetRevision: HEAD
    path: bootstrap

    # helm specific config
    helm:
      parameters:
        - name: "externalSecrets.awsRegion"
          value: "${aws_region}"
        - name: "externalSecrets.awsRole"
          value: "${external_secrets_aws_role}"

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
