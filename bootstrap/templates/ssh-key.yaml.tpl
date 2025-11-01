---
apiVersion: v1
kind: Secret
metadata:
  name: git-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repo-creds
type: Opaque
data:
  type: Z2l0
  url: ${base64_argo_git_url}
  sshPrivateKey: ${base64_argo_private_key}
  enableLfs: dHJ1ZQ==
