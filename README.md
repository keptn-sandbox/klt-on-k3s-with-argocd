# Keptn Lifecycle Toolkit Demo with ArgoCD

This is a demo repository for Keptn Lifecycle Toolkit (https://lifecycle.keptn.sh/)
The purpose is experiment with KLT on some simple demo apps and show different Use Cases such as
* Sending Slack Notifications for every deployment
* Post Deployment Validations against Prometheus and Dynatrace SLOs
* Pre Deployment Dependency Checks
* ...

# Preparation for Demo

Here is what I have installed
1. k3s on an AWS Linux with Traefik Ingress Controller
2. KLT based on https://lifecycle.keptn.sh/docs/getting-started/
3. ArgoCD based on https://github.com/keptn-sandbox/lifecycle-toolkit-examples/tree/main/support/argo
4. Exposed Grafana, Jaeger and ArgoCD through Ingress


# Running the demo

```
kubectl apply -f https://raw.githubusercontent.com/grabnerandi/klt-demo-with-argocd/main/argocd/app.yaml
```