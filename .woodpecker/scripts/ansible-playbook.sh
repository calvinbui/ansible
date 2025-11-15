#!/usr/bin/env bash

set -eo pipefail

allplaybooks=( )

# playbook updates
mapfile -t allplaybooks < <(echo "$CI_PIPELINE_FILES" | jq -r '.[]' | grep -E '^[^/]+\.yml$' | grep -v '^requirements\.yml$')
echo "Playbooks changed: ${allplaybooks[*]}"

# role updates
mapfile -t roles < <(echo "$CI_PIPELINE_FILES" | jq -r '.[]' | grep -E "^roles/(\w|-|_)+/.*" | cut -d "/" -f2)
echo "Roles changed: ${roles[*]}"
if (( ${#roles[@]} != 0 )); then
  for role in "${roles[@]}"; do
    mapfile -t playbooks < <(grep "role: ${role}" ./*.yml -l)
    if (( ${#playbooks[@]} != 0 )); then
      for pb in "${playbooks[@]}"; do
        if [[ ! " ${allplaybooks[*]} " =~ $pb ]]; then
          allplaybooks+=( "$pb" )
        fi
      done
    fi
  done
fi

if [[ "${#allplaybooks[@]}" -eq 0 ]]; then
  echo "No playbooks or roles changed"
  exit 0
else
  echo "Playbooks to run: ${allplaybooks[*]}"
fi

echo "Put vault key"
echo "$ANSIBLE_VAULT_PASSWORD" > ~/.vault_pass.txt
trap 'rm -f ~/.vault_pass.txt' EXIT

# shellcheck disable=SC2068
# i want it to split
ANSIBLE_HOST_KEY_CHECKING=false ansible-playbook ${allplaybooks[@]}
