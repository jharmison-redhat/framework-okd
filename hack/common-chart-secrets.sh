set -e

cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." || exit 1

. .env

if [ -z "$INSTALL_DIR" ] || [ -z "$CLUSTER_DIR" ]; then
    read -ra cluster_installs < <(find install -mindepth 1 -maxdepth 1 -type d)
    if (( ${#cluster_installs[@]} == 1 )); then
        CLUSTER_URL=$(basename "${cluster_installs[0]}")
        INSTALL_DIR=install/${CLUSTER_URL}
        CLUSTER_DIR=clusters/${CLUSTER_URL}
    else
        echo "Unable to automatically determine your cluster! Please configure CLUSTER_DIR and INSTALL_DIR in .env file" >&2
        exit 1
    fi
fi


public_keys=(
	age1ky5amdnkwzj03gwal0cnk7ue7vsd0n64pxm50nxgycssp7vgpqvq9s7lyw # james
)
public_keys+=("$(awk '/public key:/{print $NF}' "${INSTALL_DIR}/age.txt")")
keystring="$(
	IFS=,
	echo "${public_keys[*]}"
)"

prereqs=(sops age podman)

if ! command -v yq | grep -q '^/'; then
	function yq {
		${RUNTIME:-podman} run --rm --interactive \
			--security-opt label=disable --user root \
			--volume "${PWD}:/workdir" --workdir /workdir \
			docker.io/mikefarah/yq:latest "${@}"
	}
fi

failed=false
for prereq in "${prereqs[@]}"; do
	if ! command -v "$prereq" &>/dev/null; then
		echo "Prereq $prereq is not found in path - please install it." >&2
		failed=true
	fi
done
if ! command -v sha256sum &>/dev/null; then
	if ! command -v shasum &>/dev/null; then
		echo "Prereq sha256sum or shasum is not found in path - please install one." >&2
		failed=true
	else
		shacmd=(shasum -a 256)
	fi
else
	shacmd=(sha256sum)
fi
if $failed; then
	exit 1
fi

function ct_needs_update {
	local pt ct
	pt="$1"
	ct="$2"
	if [ ! -f "$ct" ]; then
		# If ciphertext doesn't exist, we need to generate it
		sops --encrypt --age "$keystring" "$pt" | yq e
		return 0
	fi
	# If the plaintext is modified more recently, we need to check if it's the same
	if [ "$pt" -nt "$ct" ]; then
		pt_content="$(sops --decrypt "$ct" | yq e)"
		sha256sum="$(echo "$pt_content" | "${shacmd[@]}" | cut -d' ' -f1)"
		if ! echo "$sha256sum  $pt" | "${shacmd[@]}" -c - >/dev/null 2>&1; then
			# If we need to update the plaintext, return the content
			sops --encrypt --age "$keystring" "$pt" | yq e
			return 0
		else
			# If we don't need to update, touch the ciphertext to short circuit later
			touch "$ct"
		fi
	fi
	# If none of those is true, we need no update
	return 1
}

function encrypt {
	local pt ct
	pt="$1"
	# Build out the ciphertext name
	dir="$(dirname "$pt")"
	fn="$(basename "$pt")"
	ext="${fn##*.}"
	fn="${fn%.*}"
	ct="$dir/$fn.enc.$ext"

	if ! content=$(ct_needs_update "$pt" "$ct"); then
		# If no update is necessary just continue to the next file
		return
	fi
	echo "Updating $ct" >&2
	echo "$content" >"$ct"
	git add "$ct"
}

function pt_needs_update {
	local pt ct
	pt="$1"
	ct="$2"

	if [ ! -f "$pt" ]; then
		# If plaintext doesn't exist, we need to generate it
		sops --decrypt "$ct" | yq e
		return 0
	fi
	if [ "$ct" -nt "$pt" ]; then
		# If the ciphertext is modified more recently, we need to check if we have to update the content
		content="$(sops --decrypt "$ct" | yq e)"
		sha256sum="$(echo "$content" | "${shacmd[@]}" | cut -d' ' -f1)"
		if ! echo "$sha256sum  $pt" | "${shacmd[@]}" -c - >/dev/null 2>&1; then
			# If we need to update the plaintext, return the content
			echo "$content"
			return 0
			# Don't touch the plaintext, as we decrypt less often than we encrypt (with git hooks)
		fi
	fi
	# If none of that is true, we need no update
	return 1
}

function decrypt {
	local pt ct
	ct="$1"
	pt="${ct//\.enc/}"
	if ! content=$(pt_needs_update "$pt" "$ct"); then
		# If no update is necessary just continue to the next file
		return
	fi
	echo "Updating $pt" >&2
	echo "$content" >"$pt"
}

function rekey {
	local pt ct
	ct="$1"
	pt="${ct//\.enc/}"

	# If the recipients have changed, we need to reencrypt
	recipients=$(yq e '.sops.age | map(.recipient) | join(",")' <"$ct")
	if [ "$recipients" != "$keystring" ]; then
		# Ensure we have the latest version of the PT
		decrypt "$ct"
		echo "Rekeying $ct" >&2
		sops --encrypt --age "$keystring" "$pt" | yq e >"$ct"
		git add "$ct"
	fi
}

function secrets_files {
    find "${CLUSTER_DIR}" -maxdepth 2 -type f \
        \( -name secrets.enc.yaml -o -name secrets.enc.yml \) \
        -print0
}

while [ ! -L .git/hooks/pre-commit ] && [ ! -e .skip-pre-commit ]; do
    read -rn1 -p 'Do you want to encrypt all secrets.yaml files on every git commit (Y/n): ' answer
    echo
    case "$answer" in
    y | Y | "")
        echo "Making symlink in git hooks for pre-commit" >&2
        ln -s -f ../../hack/encrypt-chart-secrets.sh .git/hooks/pre-commit
        ;;
    n | N)
        touch .skip-pre-commit
        ;;
    *)
        echo "Please respond with a Y or N" >&2
        ;;
    esac
done
