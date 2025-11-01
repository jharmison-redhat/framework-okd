apiVersion: v1
kind: Secret
metadata:
  name: helm-secrets-private-keys
  namespace: argocd
type: Opaque
data:
  argo.txt: ${base64_argo_age_txt}
