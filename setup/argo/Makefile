ARGO_NAMESPACE ?= argocd
# renovate: datasource=github-tags depName=argoproj/argo-cd
ARGO_VERSION ?= v2.5.2
# renovate: datasource=github-tags depName=cert-manager/cert-manager
ARGO_SECRET = $(shell kubectl -n ${ARGO_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo)

.PHONY: install
install:
	@echo "-----------------------------------"
	@echo "Create Namespace and install ArgoCD"
	@echo "-----------------------------------"
	kubectl create namespace $(ARGO_NAMESPACE)
	kubectl apply -n $(ARGO_NAMESPACE) -f https://raw.githubusercontent.com/argoproj/argo-cd/$(ARGO_VERSION)/manifests/install.yaml
	kubectl apply -n $(ARGO_NAMESPACE) -f ./config/argocd-cm.yaml
	kubectl apply -n $(ARGO_NAMESPACE) -f ./config/argocd-cmd-params-cm.yaml

	@echo ""
	@echo "-------------------------------"
	@echo "Wait for Resources to get ready"
	@echo "-------------------------------"
	kubectl wait --for=condition=available deployment/argocd-dex-server -n "$(ARGO_NAMESPACE)" --timeout=120s
	kubectl wait --for=condition=available deployment/argocd-redis -n "$(ARGO_NAMESPACE)" --timeout=120s
	kubectl wait --for=condition=available deployment/argocd-repo-server -n "$(ARGO_NAMESPACE)" --timeout=120s
	kubectl wait --for=condition=available deployment/argocd-server  -n "$(ARGO_NAMESPACE)" --timeout=120s

	@echo ""
	@echo "#######################################################"
	@echo "ArgoCD Demo installed"
	@echo "#######################################################"

.PHONY: uninstall
uninstall:
	kubectl delete -n $(ARGO_NAMESPACE) -f https://raw.githubusercontent.com/argoproj/argo-cd/v$(ARGO_VERSION)/manifests/install.yaml --ignore-not-found=true
	kubectl delete namespace $(ARGO_NAMESPACE) --ignore-not-found=true
	@echo ""
	@echo "##########################"
	@echo "Argo Demo deleted"
	@echo "##########################"
