#!/usr/bin/env bash

set -eu

# Shall we install tooling, k3s?
INSTALL_TOOLS=${INSTALL_TOOLS:-true}
INSTALL_K3S=${INSTALL_K3S:-true}

# version defaults
KLT_VERSION=${KLT_VERSION:-v0.7.0}
K3S_VERSION=${K3S_VERSION:-v1.25}

# namespace for KLT
TOOLKIT_NAMESPACE=${TOOLKIT_NAMESPACE:-keptn-lifecycle-toolkit-system}

# Got your own INGRESS_DOMAIN? If so then INGRESS_DOMAIN=yourdomain. Otherwise it defaults to your public IP
INGRESS_DOMAIN=${INGRESS_DOMAIN:-none}

# Install Dynatrace OneAgent Operator for k8s? Then provide these details
DT_TENANT=${DT_TENANT:-none}
DT_OPERATOR_TOKEN=${DT_OPERATOR_TOKEN:-none}
DT_INGEST_TOKEN=${DT_INGEST_TOKEN:-none}
DT_OTEL_INGEST_TOKEN=${DT_OTEL_INGEST_TOKEN:-none}

# Shall we setup the Slack Webhook integration? if so - set SLACK_HOOK=YOURHOOKAAAAAAAA/BBBBBBB/CCCCCCCC
SLACK_HOOK=${SLACK_HOOK:-none}

# Create Argo App based on your forked Git repo? Then set GITHUBREPO=yourgithubaccount/your-klt-demo-repo
GITHUBREPO=${GITHUBREPO:-none}

function install_tools {
    if [[ "${INSTALL_TOOLS}" == "true" ]]; then
        echo "STEP: Installing Tools"
        sudo yum update -y
        sudo yum install git -y
        sudo yum install curl -y
        sudo yum install jq -y
        sudo yum install tree -y
        sudo wget https://github.com/mikefarah/yq/releases/download/3.4.1/yq_linux_amd64 -O /usr/bin/yq && sudo chmod +x /usr/bin/yq
        sudo yum install docker
    fi 
}

function install_k3s {
    if [[ "${INSTALL_K3S}" == "true" ]]; then
        echo "STEP: Installing k3s"
        sudo curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL="${K3S_VERSION}" K3S_KUBECONFIG_MODE="644"  sh -

        # now lets make sure k3s is fully started
        k3s_started=false
        while [[ ! "${k3s_started}" ]]; do
            sleep 5
            if kubectl get nodes; then
            k3s_started=true
            fi
        done

        # need to sleep to avoid a timing issue on k3s
        echo "Waiting until k3s is ready!"
        sleep 30
    else
        echo "SKIP STEP: Not installing k3s. Assuming k8s cluster is ready and kubectl has context!"
    fi 
}

function set_ingress_domain {
    if [[ "${INGRESS_DOMAIN}" == "none" ]]; then
        INGRESS_DOMAIN=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4).nip.io
    fi 

    echo "Using INGRESS_DOMAIN: ${INGRESS_DOMAIN}"
}

function install_oneagent {
    if [[ "$DT_TENANT" == "none" ]] || [[ "$DT_OPERATOR_TOKEN" == "none" ]] ||[[ "$DT_INGEST_TOKEN" == "none" ]]; then 
        echo "SKIP STEP: Not installing Dynatrace OneAgent as DT_TENANT, DT_OPERATOR_TOKEN or DT_INGEST_TOKEN not set"
        return;
    fi

    K8S_CLUSTERNAME="keptn-${INGRESS_DOMAIN}"

    echo "STEP: Installing Dynatrace OneAgent for $DT_TENANT for name '$K8S_CLUSTERNAME'"
    kubectl create namespace dynatrace | true
    kubectl apply -f https://github.com/Dynatrace/dynatrace-operator/releases/download/v0.10.1/kubernetes.yaml
    kubectl -n dynatrace wait pod --for=condition=ready --selector=app.kubernetes.io/name=dynatrace-operator,app.kubernetes.io/component=webhook --timeout=300s

    kubectl -n dynatrace create secret generic keptn --from-literal="apiToken=$DT_OPERATOR_TOKEN" --from-literal="dataIngestToken=$DT_INGEST_TOKEN" | true
    sed -e 's~DT_TENANT~'"$DT_TENANT"'~' -e 's~K8S_CLUSTERNAME~'"$K8S_CLUSTERNAME"'~' ./setup/dynatrace/dynakube_10.yaml > dynakube_10_tmp.yaml
    kubectl apply -f dynakube_10_tmp.yaml
    rm dynakube_10_tmp.yaml
}

function install_klt {
    echo "STEP: Installing Keptn Lifecycle Toolkit $KLT_VERSION"
    # REMOVED: since 0.6 no need for cert-manager anymore
    # kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.10.0/cert-manager.yaml
    # kubectl wait --for=condition=Available deployment/cert-manager-webhook -n cert-manager --timeout=60s

    kubectl create ns ${TOOLKIT_NAMESPACE} | true
    kubectl apply -f https://github.com/keptn/lifecycle-toolkit/releases/download/$KLT_VERSION/manifest.yaml -n ${TOOLKIT_NAMESPACE}
    kubectl wait --for=condition=Available deployment/klc-controller-manager -n ${TOOLKIT_NAMESPACE} --timeout=120s
}

function install_observabilty {
    echo "STEP: Installing Observability Tools"
    cd setup/observability
    make install

    cd ../..
    sed -e 's~domain.placeholder~'"$INGRESS_DOMAIN"'~' ./setup/ingress/grafana-ingress.yaml.tmp > grafana-ingress_gen.yaml
    kubectl apply -f grafana-ingress_gen.yaml
    rm grafana-ingress_gen.yaml
    echo "Access me via http://grafana.$INGRESS_DOMAIN and http://jaeger.$INGRESS_DOMAIN"

    # If Dynatrace is installed we configure the OTel-Collector to send traces & metrics to Dynatrace
    if [[ "$DT_TENANT" != "none" ]] && [[ "$DT_OTEL_INGEST_TOKEN" != "none" ]]; then 
        echo "STEP: Configuring OpenTelemetry Collector with Dynatrace"

        sed -e 's~DT_URL_TO_REPLACE~'"$DT_TENANT"'~'  -e 's~DT_TOKEN_TO_REPLACE~'"$DT_OTEL_INGEST_TOKEN"'~' ./setup/observability/config/otel-collector-with-dt.yaml > otel-collector-with-dt_tmp.yaml
        kubectl apply -f otel-collector-with-dt_tmp.yaml -n "${TOOLKIT_NAMESPACE}"
        rm otel-collector-with-dt_tmp.yaml

        # restart collector to read the new configmap
        kubectl rollout restart deployment -n "${TOOLKIT_NAMESPACE}" otel-collector
    	kubectl wait --for=condition=available deployment/otel-collector -n "${TOOLKIT_NAMESPACE}" --timeout=120s
    fi
}

function install_argocd {
    echo "STEP: Installing Argo CD"
    cd setup/argo
    make install

    cd ../..
    sed -e 's~domain.placeholder~'"$INGRESS_DOMAIN"'~' ./setup/ingress/argocd-ingress.yaml.tmp > argocd-ingress_gen.yaml
    kubectl apply -f argocd-ingress_gen.yaml
    rm argocd-ingress_gen.yaml

    ARGOPWD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    echo "Access me via http://argocd.$INGRESS_DOMAIN"
    echo "Login with admin/$ARGOPWD"
}

function setup_slacknotification {
    if [[ "${SLACK_HOOK}" == "none" ]]; then
        echo "SKIP STEP: No SLACK_HOOK specified. Therefore not configuring slack webhook secret"
    else
        echo "STEP: Creating Slack Webhook Secret!"
        slack_hook_secret="{\"slack_hook\":\"${SLACK_HOOK}\",\"text\":\"Deployed Simplenode\"}"
        kubectl create secret generic slack-notification --from-literal=SECURE_DATA="$slack_hook_secret" -n simplenode-dev -oyaml --dry-run=client > tmp-slack-secret.yaml
        kubectl create ns simplenode-dev | true
        kubectl apply -f tmp-slack-secret.yaml | true
        rm tmp-slack-secret.yaml
    fi 
}

function create_argocdapp {
    if [[ "${GITHUBREPO}" == "none" ]]; then
        echo "SKIP STEP: No GITHUBREPO specified. Therefore not creating the ArgoCD App based on your git repo"
    else
        echo "STEP: Create ArgoCD app pointing to ${GITHUBREPO}"
        sed -e 's~gitrepo.placeholder~'"$GITHUBREPO"'~' ./argocd/app-dev.yaml.tmp > app-dev.yaml
        kubectl apply -f app-dev.yaml
        rm app-dev.yaml
    fi 
}

function print_info {
    echo " "
    echo "===================================================================="
    echo "                         INSTALLATION DONE"
    echo "===================================================================="
    echo "ArgoCD: http://argocd.$INGRESS_DOMAIN using admin/$ARGOPWD"
    echo "Grafana: http://grafana.$INGRESS_DOMAIN using admin/admin (change after first login)"
    echo "Jaeger: http://jaeger.$INGRESS_DOMAIN"
    echo "===================================================================="
}

# now lets go through all the steps
install_tools
install_k3s
set_ingress_domain
install_oneagent
install_klt
install_observabilty
install_argocd
setup_slacknotification
create_argocdapp
print_info