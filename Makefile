.PHONY:
flux:
	@kubectl apply -k homelab/flux
	@kubectl -n flux-system create secret generic sops-age --from-file=age.agekey=~/.config/sops/age/keys.txt
