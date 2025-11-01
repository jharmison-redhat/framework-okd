#!/bin/bash -e

. hack/common-chart-secrets.sh

# rekey if necessary
while read -rd $'\0' ct; do
	rekey "$ct"
done < <(secrets_encrypted_files)
