#!/bin/bash -e

. hack/common-chart-secrets.sh

# application secrets
while read -rd $'\0' pt; do
    encrypt "$pt"
done < <(secrets_files)
