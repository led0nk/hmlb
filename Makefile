### test
.PHONY:
flux:
	@kubectl apply -k homelab/flux
	@kubectl -n flux-system create secret generic sops-age --from-file=age.agekey=$HOME/.config/sops/age/keys.txt
	@kubectl -n jellyfin create secret generic sops-age --from-file=age.agekey=$HOME/.config/sops/age/keys.txt
