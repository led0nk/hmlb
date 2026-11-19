SRC_ROOT := $(shell git rev-parse --show-toplevel)
TOOLS_BIN_DIR := $(SRC_ROOT)/.tools

### tool versions: single source of truth for local and CI
KUBECONFORM_VERSION := v0.6.7
FLATE_VERSION := v0.7.3
TALOSCTL_VERSION := v1.9.5
TALHELPER_VERSION := v3.1.17
KUBECONFORM_URL := github.com/yannh/kubeconform/cmd/kubeconform@$(KUBECONFORM_VERSION)
FLATE_URL := https://github.com/home-operations/flate/releases/download/$(FLATE_VERSION)/flate_$(FLATE_VERSION:v%=%)_linux_amd64.tar.gz
FLATE_SHA256 := 05d3c79447647e95329aa45c7035e7ebac3a120942972e78819deadc3bf0afeb
FLATE_KUBE_VERSION := 1.32.3
TALOSCTL_URL := https://github.com/siderolabs/talos/releases/download/$(TALOSCTL_VERSION)/talosctl-linux-amd64
TALOSCTL_SHA256 := 085b089dfd2c28dbe9489ff218abd1f6ea4ad8520c34b162d079ba5b45ccda62
TALHELPER_URL := github.com/budimanjojo/talhelper/v3@$(TALHELPER_VERSION)
YAMLLINT_VERSION := 1.38.0
TRIVY_VERSION := v0.76.2
TRIVY_URL := https://github.com/aquasecurity/trivy/releases/download/$(TRIVY_VERSION)/trivy_$(TRIVY_VERSION:v%=%)_Linux-64bit.tar.gz
TRIVY_SHA256 := bc0fc726e017b8927a62b2d3531d7a84ee01769daf5c99ed866dced54089fdbf

### tool references
KUBECONFORM := $(TOOLS_BIN_DIR)/kubeconform
FLATE := $(TOOLS_BIN_DIR)/flate
TALOSCTL := $(TOOLS_BIN_DIR)/talosctl
TALHELPER := $(TOOLS_BIN_DIR)/talhelper
YAMLLINT := $(TOOLS_BIN_DIR)/yaml-lint-venv/bin/yamllint
TRIVY := $(TOOLS_BIN_DIR)/trivy

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

$(TALOSCTL): $(TOOLS_BIN_DIR)
	@mkdir -p $(TOOLS_BIN_DIR)/talosctl-dl && \
	curl -sSfL -o $(TOOLS_BIN_DIR)/talosctl-dl/talosctl $(TALOSCTL_URL) && \
	echo "$(TALOSCTL_SHA256)  $(TOOLS_BIN_DIR)/talosctl-dl/talosctl" | sha256sum -c - && \
	mv $(TOOLS_BIN_DIR)/talosctl-dl/talosctl $(TALOSCTL) && \
	rmdir $(TOOLS_BIN_DIR)/talosctl-dl

$(TALHELPER): $(TOOLS_BIN_DIR)
	@GOBIN=$(TOOLS_BIN_DIR) go install $(TALHELPER_URL)

$(YAMLLINT): $(TOOLS_BIN_DIR)
	@python3 -m venv $(TOOLS_BIN_DIR)/yaml-lint-venv && \
	$(TOOLS_BIN_DIR)/yaml-lint-venv/bin/pip install -q yamllint==$(YAMLLINT_VERSION)

$(TRIVY): $(TOOLS_BIN_DIR)
	@mkdir -p $(TOOLS_BIN_DIR)/trivy-dl && \
	curl -sSfL -o $(TOOLS_BIN_DIR)/trivy-dl/trivy.tar.gz $(TRIVY_URL) && \
	echo "$(TRIVY_SHA256)  $(TOOLS_BIN_DIR)/trivy-dl/trivy.tar.gz" | sha256sum -c - && \
	tar -xzf $(TOOLS_BIN_DIR)/trivy-dl/trivy.tar.gz -C $(TOOLS_BIN_DIR)/trivy-dl trivy && \
	mv $(TOOLS_BIN_DIR)/trivy-dl/trivy $(TRIVY) && \
	rm -rf $(TOOLS_BIN_DIR)/trivy-dl

.PHONY: install-tools
install-tools: $(KUBECONFORM) $(FLATE) $(TALHELPER) $(TALOSCTL) $(YAMLLINT) $(TRIVY)

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

.PHONY: lint
lint: $(YAMLLINT)
	@$(YAMLLINT) -s .

.PHONY: scan-images
scan-images: $(TRIVY)
	@bash scripts/ci/scan-images.sh

smoke-secrets:
	@err=0; \
	for f in $$(git ls-files '*.yaml' '*.yml' | grep -Ei '$(SECRET_NAME_RE)'); do \
		grep -q '^sops:' "$$f" || { echo "PLAINTEXT secret (missing sops metadata): $$f"; err=1; }; \
	done; \
	exit $$err
