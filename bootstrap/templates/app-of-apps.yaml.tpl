---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-applications
  namespace: argocd
spec:
  destination:
    name: in-cluster
    namespace: argocd
  project: default
  source:
    path: ${CLUSTER_DIR}/applications
    repoURL: ${ARGO_GIT_URL}
    targetRevision: HEAD
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - RespectIgnoreDifferences=true
  ignoreDifferences:
    - group: argoproj.io
      kind: Application
      jsonPointers:
        - /spec/syncPolicy/automated
        - /metadata/finalizers
