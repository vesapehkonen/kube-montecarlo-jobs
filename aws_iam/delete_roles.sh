#!/usr/bin/env bash
set -euo pipefail

ACCOUNT_ID="${ACCOUNT_ID:-}"
: "${ACCOUNT_ID:?Must set ACCOUNT_ID (e.g. export ACCOUNT_ID=123456789012)}"

ROLES=(
  "kube-montecarlo-jobs-ec2"
  "kube-montecarlo-jobs-ecr"
  "kube-montecarlo-jobs-runtime"
  "kube-montecarlo-jobs-infra"
  "kube-montecarlo-jobs-ansible"
)

INSTANCE_PROFILES=(
  "kube-montecarlo-jobs-ec2"
)

POLICY_NAMES=(
  "kube-montecarlo-jobs-ec2-runtime"
  "kube-montecarlo-jobs-ecr-push"
  "kube-montecarlo-jobs-runtime-sqs-ddb"
  "kube-montecarlo-jobs-ec2-network"
  "kube-montecarlo-jobs-ec2-passrole"
  "kube-montecarlo-jobs-sqs-ddb"
  "kube-montecarlo-jobs-s3"
  "kube-montecarlo-jobs-install-kube"
)

POLICY_ARNS=()
for name in "${POLICY_NAMES[@]}"; do
  POLICY_ARNS+=("arn:aws:iam::${ACCOUNT_ID}:policy/${name}")
done

OIDC_URL="https://token.actions.githubusercontent.com"

log() { printf "\n==> %s\n" "$*"; }

exists_role() {
  aws iam get-role --role-name "$1" >/dev/null 2>&1
}

exists_instance_profile() {
  aws iam get-instance-profile --instance-profile-name "$1" >/dev/null 2>&1
}

detach_all_managed_policies_from_role() {
  local role="$1"
  local arns
  arns="$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || true)"
  if [[ -n "${arns// }" ]]; then
    for arn in $arns; do
      log "Detaching managed policy from role ${role}: ${arn}"
      aws iam detach-role-policy --role-name "$role" --policy-arn "$arn" >/dev/null || true
    done
  fi
}

delete_all_inline_policies_from_role() {
  local role="$1"
  local names
  names="$(aws iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text 2>/dev/null || true)"
  if [[ -n "${names// }" ]]; then
    for pname in $names; do
      log "Deleting inline policy from role ${role}: ${pname}"
      aws iam delete-role-policy --role-name "$role" --policy-name "$pname" >/dev/null || true
    done
  fi
}

remove_role_from_all_instance_profiles() {
  local role="$1"
  local profiles
  profiles="$(aws iam list-instance-profiles-for-role --role-name "$role" --query 'InstanceProfiles[].InstanceProfileName' --output text 2>/dev/null || true)"
  if [[ -n "${profiles// }" ]]; then
    for ip in $profiles; do
      log "Removing role ${role} from instance profile ${ip}"
      aws iam remove-role-from-instance-profile --instance-profile-name "$ip" --role-name "$role" >/dev/null || true
    done
  fi
}

delete_instance_profile() {
  local ip="$1"
  if ! exists_instance_profile "$ip"; then
    log "Instance profile not found (skip): ${ip}"
    return 0
  fi

  # Remove any roles attached to the instance profile
  local roles
  roles="$(aws iam get-instance-profile --instance-profile-name "$ip" --query 'InstanceProfile.Roles[].RoleName' --output text 2>/dev/null || true)"
  if [[ -n "${roles// }" ]]; then
    for r in $roles; do
      log "Removing role ${r} from instance profile ${ip}"
      aws iam remove-role-from-instance-profile --instance-profile-name "$ip" --role-name "$r" >/dev/null || true
    done
  fi

  log "Deleting instance profile: ${ip}"
  aws iam delete-instance-profile --instance-profile-name "$ip" >/dev/null || true
}

delete_role_fully() {
  local role="$1"
  if ! exists_role "$role"; then
    log "Role not found (skip): ${role}"
    return 0
  fi

  detach_all_managed_policies_from_role "$role"
  delete_all_inline_policies_from_role "$role"
  remove_role_from_all_instance_profiles "$role"

  log "Deleting role: ${role}"
  aws iam delete-role --role-name "$role" >/dev/null || true
}

delete_managed_policy() {
  local policy_arn="$1"

  # If policy doesn't exist, skip
  if ! aws iam get-policy --policy-arn "$policy_arn" >/dev/null 2>&1; then
    log "Managed policy not found (skip): ${policy_arn}"
    return 0
  fi

  # Detach policy from any entities (roles/users/groups) just in case
  local attached_roles attached_users attached_groups
  attached_roles="$(aws iam list-entities-for-policy --policy-arn "$policy_arn" --query 'PolicyRoles[].RoleName' --output text 2>/dev/null || true)"
  attached_users="$(aws iam list-entities-for-policy --policy-arn "$policy_arn" --query 'PolicyUsers[].UserName' --output text 2>/dev/null || true)"
  attached_groups="$(aws iam list-entities-for-policy --policy-arn "$policy_arn" --query 'PolicyGroups[].GroupName' --output text 2>/dev/null || true)"

  if [[ -n "${attached_roles// }" ]]; then
    for r in $attached_roles; do
      log "Detaching policy from role ${r}: ${policy_arn}"
      aws iam detach-role-policy --role-name "$r" --policy-arn "$policy_arn" >/dev/null || true
    done
  fi
  if [[ -n "${attached_users// }" ]]; then
    for u in $attached_users; do
      log "Detaching policy from user ${u}: ${policy_arn}"
      aws iam detach-user-policy --user-name "$u" --policy-arn "$policy_arn" >/dev/null || true
    done
  fi
  if [[ -n "${attached_groups// }" ]]; then
    for g in $attached_groups; do
      log "Detaching policy from group ${g}: ${policy_arn}"
      aws iam detach-group-policy --group-name "$g" --policy-arn "$policy_arn" >/dev/null || true
    done
  fi

  # Delete non-default versions first
  local versions
  versions="$(aws iam list-policy-versions --policy-arn "$policy_arn" --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text 2>/dev/null || true)"
  if [[ -n "${versions// }" ]]; then
    for vid in $versions; do
      log "Deleting policy version ${vid}: ${policy_arn}"
      aws iam delete-policy-version --policy-arn "$policy_arn" --version-id "$vid" >/dev/null || true
    done
  fi

  log "Deleting managed policy: ${policy_arn}"
  aws iam delete-policy --policy-arn "$policy_arn" >/dev/null || true
}

delete_github_oidc_provider_if_present() {
  # Find provider ARN(s) for the GitHub OIDC URL and delete them
  local provider_arns
  provider_arns="$(aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[].Arn' --output text 2>/dev/null || true)"
  if [[ -z "${provider_arns// }" ]]; then
    log "No OIDC providers found (skip GitHub OIDC deletion)."
    return 0
  fi

  local deleted_any="false"
  for arn in $provider_arns; do
    local url
    url="$(aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$arn" --query 'Url' --output text 2>/dev/null || true)"
    if [[ "$url" == "$OIDC_URL" ]]; then
      log "Deleting GitHub OIDC provider: ${arn} (url=${url})"
      aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$arn" >/dev/null || true
      deleted_any="true"
    fi
  done

  if [[ "$deleted_any" == "false" ]]; then
    log "GitHub OIDC provider not found (skip)."
  fi
}

main() {
  log "Deleting instance profiles (and removing roles from them)"
  for ip in "${INSTANCE_PROFILES[@]}"; do
    delete_instance_profile "$ip"
  done

  log "Deleting roles (detaching policies, removing inline policies, removing from instance profiles)"
  for role in "${ROLES[@]}"; do
    delete_role_fully "$role"
  done

  log "Deleting managed policies (detach from all entities, delete versions, delete policy)"
  for arn in "${POLICY_ARNS[@]}"; do
    delete_managed_policy "$arn"
  done

  # Optional but included since your scripts create it.
  log "Deleting GitHub OIDC provider (if it exists)"
  delete_github_oidc_provider_if_present

  log "Done."
}

main "$@"
