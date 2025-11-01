#!/bin/bash

. hack/common-chart-secrets.sh

while read -rd $'\0' ct; do
    decrypt "$ct"
done < <(secrets_files)
