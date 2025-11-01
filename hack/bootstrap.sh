#!/bin/bash

cd "$(dirname "$(realpath "$0")")/.." || exit 1
set -eu

mkdir -p "${CLUSTER_DIR}"/{applications,values}

hack/encrypt-chart-secrets.sh

function argo_ssh_validate {
  # Makes sure the SSH key has been uploaded to some repository on GitHub at all
	{ ssh -i "${INSTALL_DIR}/id_ed25519" -o IdentityAgent=none -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null git@github.com 2>&1 || :; } | grep -qF 'successfully authenticated'
}
function gh_validate {
  # Checks if we're able to use the gh cli to manage deploy keys
	[ -n "$GH_TOKEN" ] || return 1
	gh repo deploy-key list >/dev/null 2>&1 || return 2
}
function cluster_file_pushed {
  # Checks if a given file was pushed to the remote
	git diff --quiet "@{u}...HEAD" -- "${@}" || return 1
}
function cluster_file_committed {
  # Checks if a given file has uncommitted changes
	if [ "$(git status -s -uall "${@}")" ]; then return 1; fi
}
function cluster_files {
  # Lists all files that belong to a given cluster
  find "${CLUSTER_DIR}" -maxdepth 2 -type f \
    \( -name '*.yaml' -o -name '*.yml' \) \
    -print0
}
function cluster_files_updated {
  # Goes over every file that belongs to a cluster to ensure it's committed and pushed
	ret=0
	while read -rd $'\0' cluster_file; do
		if ! cluster_file_committed "${cluster_file}"; then
			echo "uncommitted changes: $cluster_file" >&2
			((ret += 1))
			continue
		fi
		if ! cluster_file_pushed "${cluster_file}"; then
			echo "unpushed changes: ${cluster_file}" >&2
			((ret += 1))
		fi
  done < <(cluster_files)
	return "$ret"
}
function concat_with_comma {
	local IFS=,
	echo "$*"
}
function oc {
  KUBECONFIG="${INSTALL_DIR}/auth/kubeconfig" "${INSTALL_DIR}/oc" --insecure-skip-tls-verify=true "${@}"
}

if ! argo_ssh_validate; then
	if gh_validate; then
		for old_key in $(gh repo deploy-key list --json title,id -q '.[] | select(.title == "'"${CLUSTER_URL}"'") | .id'); do
			gh repo deploy-key delete "$old_key"
		done
		gh repo deploy-key add "${INSTALL_DIR}/id_ed25519.pub" -t "${CLUSTER_URL}"
	else
		echo "Unable to authenticate to github.com with your ArgoCD key - did you configure the deploy key?" >&2
		echo -n '  '
		cat "${INSTALL_DIR}/id_ed25519.pub"
		exit 1
	fi
fi

bootstrap_dir="${INSTALL_DIR}/bootstrap"
base64_argo_age_txt="$(base64 -w0 "${INSTALL_DIR}/age.txt")"
base64_argo_git_url="$(base64 -w0 <<<"${ARGO_GIT_URL}")"
base64_argo_private_key="$(base64 -w0 "${INSTALL_DIR}/id_ed25519")"
export base64_argo_age_txt base64_argo_git_url base64_argo_private_key
templated_variables=(
 \$base64_argo_age_txt
 \$base64_argo_git_url
 \$base64_argo_private_key
 \$CLUSTER_DIR
 \$ARGO_GIT_URL
)
vars=$(concat_with_comma "${templated_variables[@]}")
for template in age-secret ssh-key app-of-apps; do
  envsubst "$vars" < "${bootstrap_dir}/templates/${template}.yaml.tpl" > "${bootstrap_dir}/${template}.yaml"
done

if ! cluster_files_updated; then
	mapfile -t uncommitted < <(git status -su charts | awk '{print $NF}')
	mapfile -t unpushed < <(git diff --name-only "@{u}...HEAD" -- charts)
	declare -A needs_update
	for file in "${uncommitted[@]}" "${unpushed[@]}"; do
		needs_update["$file"]=""
	done
	echo "The following files need to be committed or pushed for bootstrap:" >&2
	printf '  %s\n' "${!needs_update[@]}" >&2
	exit 1
fi

timeout=1800
step=5
duration=0
echo -n "Applying bootstrap"
while true; do
	if ((duration >= timeout)); then
		exit 1
	fi
  if oc apply -k "${INSTALL_DIR}/bootstrap" >/dev/null 2>&1; then
		break
	fi
	sleep "$step"
	echo -n .
	((duration += step))
done
echo
if ! [ -e "${INSTALL_DIR}/auth/kubeconfig-orig" ]; then
  cp "${INSTALL_DIR}/auth/kubeconfig" "${INSTALL_DIR}/auth/kubeconfig-orig"
fi
sed -i '/certificate-authority-data/d' "${INSTALL_DIR}/auth/kubeconfig"

echo "Deleting hanging installer pods that remain in failed state"
oc delete pod --selector=app=installer --field-selector=status.phase=Failed --all-namespaces
