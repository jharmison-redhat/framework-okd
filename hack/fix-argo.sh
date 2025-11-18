#!/bin/bash

set -ex

oc delete pod -n openshift-operators "$(oc get pod -n openshift-operators -ojson | jq -r '.items[] | select(.metadata.name|startswith("argocd")) | .metadata.name')"
sleep 5

oc delete pod -n argocd --all

oc wait --for=condition=Ready --timeout=90s -n argocd pod -l app.kubernetes.io/name=argocd-server
