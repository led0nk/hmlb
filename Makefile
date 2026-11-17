SRC_ROOT := $(shell git rev-parse --show-toplevel)
TOOLS_BIN_DIR := $(SRC_ROOT)/.tools

### tool versions: single source of truth for local and CI
KUBECONFORM_VERSION := v0.6.7
FLATE_VERSION := v0.7.3
KUBECONFORM_URL := github.com/yannh/kubeconform/cmd/kubeconform@$(KUBECONFORM_VERSION)
FLATE_URL := https://github.com/home-operations/flate/releases/download/$(FLATE_VERSION)/flate_$(FLATE_VERSION:v%=%)_linux_amd64.tar.gz
FLATE_SHA256 := 05d3c79447647e95329aa45c7035e7ebac3a120942972e78819deadc3bf0afeb
FLATE_KUBE_VERSION := 1.32.3

### tool references
KUBECONFORM := $(TOOLS_BIN_DIR)/kubeconform
FLATE := $(TOOLS_BIN_DIR)/flate

### bootstrap: one-off wiring on a fresh cluster (THESE TOUCH THE CLUSTER)
.PHONY: flux
flux:
	@kubectl apply -k homelab/flux
	@kubectl create ns jellyfin
	@kubectl -n flux-system create secret generic sops-age --from-file=age.agekey="$$HOME/.config/sops/age/keys.txt"
	@kubectl -n jellyfin create secret generic sops-age --from-file=age.agekey="$$HOME/.config/sops/age/keys.txt"

### tools: pinned go binaries, installed into .tools/ (pattern from benthos-umh Makefile.common)
$(TOOLS_BIN_DIR):
	@mkdir -p $@

$(KUBECONFORM): $(TOOLS_BIN_DIR)
	@GOBIN=$(TOOLS_BIN_DIR) go install $(KUBECONFORM_URL)

$(FLATE): $(TOOLS_BIN_DIR)
	@mkdir -p $(TOOLS_BIN_DIR)/flate-dl && \
	curl -sSfL -o $(TOOLS_BIN_DIR)/flate-dl/f.tar.gz $(FLATE_URL) && \
	echo "$(FLATE_SHA256)  $(TOOLS_BIN_DIR)/flate-dl/f.tar.gz" | sha256sum -c - && \
	tar -xzf $(TOOLS_BIN_DIR)/flate-dl/f.tar.gz -C $(TOOLS_BIN_DIR)/flate-dl flate && \
	mv $(TOOLS_BIN_DIR)/flate-dl/flate $(FLATE) && \
	rm -rf $(TOOLS_BIN_DIR)/flate-dl

.PHONY: install-tools
install-tools: $(KUBECONFORM) $(FLATE)

### print-%: print any make variable, e.g. make print-FLATE_KUBE_VERSION
print-%:
	@echo '$($*)'

.PHONY: clean
clean:
	@rm -rf $(TOOLS_BIN_DIR)

### smoke: read-only checks, safe anywhere (CI + local, no cluster)
.PHONY: smoke smoke-secrets
SECRET_NAME_RE := secret|credential|password|apikey|api-key|token|keys

smoke: $(KUBECONFORM)
	@kubectl kustomize homelab | $(KUBECONFORM) -strict -skip=Secret -ignore-missing-schemas -summary
	@$(MAKE) smoke-secrets

smoke-secrets:
	@err=0; \
	for f in $$(git ls-files '*.yaml' '*.yml' | grep -Ei '$(SECRET_NAME_RE)'); do \
		grep -q '^sops:' "$$f" || { echo "PLAINTEXT secret (missing sops metadata): $$f"; err=1; }; \
	done; \
	exit $$err
