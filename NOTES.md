# Preconditions
- use Rancher Desktop with Ingress **Traefik** enabled
- use Kubernetes 1.25 or higher

# Sources
- Keptn Lifecycle Toolkit Demo Tutorial on k3s, with ArgoCD for GitOps, OTel, Prometheus and Grafana
- https://github.com/malon875875/klt-on-k3s-with-argocd/blob/main/simplenode-dev/simplenode-dev-deployment.yaml
- https://itnext.io/argo-cd-rancher-desktop-for-a-local-gitops-lab-8d044089f50a
  - https://github.com/jwsy/argocd-rd

# Install Cert Manager 
- kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.10.0/cert-manager.yaml
- kubectl wait --for=condition=Available deployment/cert-manager-webhook -n cert-manager --timeout=60s

# Install Keptn Lifecycle Toolkit
- kubectl apply -f https://github.com/keptn/lifecycle-toolkit/releases/download/v0.5.0/manifest.yaml
- kubectl wait --for=condition=Available deployment/klc-controller-manager -n keptn-lifecycle-toolkit-system --timeout=120s

# Install ArgoCD
- cd setup/argo
- make install
- cd marcos
- kubectl -n argocd apply -f argocd-ingress-server-traefik.yaml
- https://argocd.rancher.localhost
  - user: admin
  - password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Install Observability (Jaeger, Grafana and Prometheus)
- cd setup/observability
- make install
- cd marcos
- kubectl -n monitoring apply -f grafana-ingress-server-traefik.yaml
- kubectl -n keptn-lifecycle-toolkit-system apply -f jaeger-ingress-server-traefik.yaml
- https://grafana.rancher.localhost/
  - admin/admin
- https://jaeger.rancher.localhost/

# Install Slack Notification
- https://api.slack.com/messaging/webhooks
  - https://api.slack.com/apps/A04NHPXHGSG/incoming-webhooks
- kubectl create secret generic slack-notification --from-literal=SECURE_DATA='{"slack_hook":"AAAA/BBBB/CCCC","text":"Deployed Simplenode"}' -n simplenode-dev -oyaml --dry-run=client > tmp-slack-secret.yaml
- kubectl create ns simplenode-dev
- kubectl apply -f tmp-slack-secret.yaml
  - make sure to apply it at the next deployment
- rm tmp-slack-secret.yaml

# Prepare simplenode application as an Argo deployment
- cd simplenode-dev
- kubectl -n simplenode-dev apply -f simplenode-dev-ingress-server-traefik.yaml
- cd marcos
- kubectl apply -f app-dev.yaml
- https://simplenode-dev.rancher.localhost/

# Important
- Sending notifications to Slack will not work through VPN
- https://keptn.slack.com/archives/CNRCGFU3U/p1675860640974959?thread_ts=1675790550.141669&cid=CNRCGFU3U
