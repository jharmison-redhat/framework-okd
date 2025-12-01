-include .env

CLUSTER_NAME ?= okd
BASE_DOMAIN ?= jharmison.dev
MACHINE_CIDR ?= 10.1.1.0/24
INSTALL_DISK_ID ?= nvme-eui.e8238fa6bf530001001b448b4df1d24e
PULL_SECRET ?= $(shell jq -c . ~/.pull-secret.json)
SSH_PUB_KEY ?= $(shell cat ~/.ssh/id_ed25519.pub)

CLUSTER_URL := $(CLUSTER_NAME).$(BASE_DOMAIN)
INSTALL_DIR := install/$(CLUSTER_URL)
CLUSTER_DIR := clusters/$(CLUSTER_URL)

ARGO_GIT_URL ?= git@github.com:jharmison-redhat/framework-okd.git

-include $(INSTALL_DIR).env

export

.PHONY: bootstrap
bootstrap: $(INSTALL_DIR)/auth/kubeconfig $(INSTALL_DIR)/bootstrap/kustomization.yaml $(INSTALL_DIR)/age.txt $(INSTALL_DIR)/id_ed25519
	@hack/bootstrap.sh

$(INSTALL_DIR)/auth/kubeconfig: install.sh
	@if [ -e $@ ]; then touch $@; else hack/install.sh $(CLUSTER_NAME) $(BASE_DOMAIN) \
		$(MACHINE_CIDR) $(INSTALL_DISK_ID) \
		$(PULL_SECRET) $(SSH_PUB_KEY); fi

$(INSTALL_DIR)/age.txt:
	@if [ -e $@ ]; then touch $@; else age-keygen -o $@; fi

$(INSTALL_DIR)/id_ed25519:
	@if [ -e $@ ]; then touch $@; else ssh-keygen -t ed25519 -f $(INSTALL_DIR)/id_ed25519 -N '' -C argocd@$(CLUSTER_NAME).$(BASE_DOMAIN); fi

$(INSTALL_DIR)/bootstrap/kustomization.yaml: $(wildcard bootstrap/*.yaml) $(wildcard bootstrap/templates/*.yaml)
	cp -r bootstrap $(INSTALL_DIR)/

.PHONY: tools
tools:
	# Prints the tools image reference for the installed release
	@hack/tools-image.sh

.PHONY: encrypt
encrypt:
	@hack/encrypt-chart-secrets.sh

.PHONY: fix-argo
fix-argo:
	@KUBECONFIG=$(INSTALL_DIR)/auth/kubeconfig hack/fix-argo.sh

.PHONY: clean
clean:
	rm -rf $(INSTALL_DIR)
