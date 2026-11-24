#!/usr/bin/env bash
# Copy your newest ontology-dev Platform token to the clipboard.
# Sign in first at https://ontology-platform-dev.tail5566.ts.net/auth/login
set -euo pipefail

CLUSTER=north-managed-ontology-dev
PROJECT=cohere-ontology-dev
REGION=us-central1
PRINCIPAL="${PRINCIPAL:-$(gcloud config get-value account 2>/dev/null)}"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export KUBECONFIG="$tmp/kubeconfig"

endpoint=$(gcloud container clusters describe "$CLUSTER" --project "$PROJECT" --region "$REGION" --format='value(endpoint)')
gcloud container clusters describe "$CLUSTER" --project "$PROJECT" --region "$REGION" \
  --format='value(masterAuth.clusterCaCertificate)' | base64 --decode > "$tmp/ca.crt"
kubectl config set-cluster c --server="https://$endpoint" --certificate-authority="$tmp/ca.crt" --embed-certs=true >/dev/null
kubectl config set-credentials u --token="$(gcloud auth print-access-token)" >/dev/null
kubectl config set-context c --cluster=c --user=u >/dev/null
kubectl config use-context c >/dev/null

token=$(kubectl -n ontology exec ontology-db-1 -c postgres -- psql -d platform -tA -v p="$PRINCIPAL" <<'SQL'
SELECT platform_token FROM platform.session
WHERE principal = lower(:'p') AND expires_at > now()
ORDER BY created_at DESC LIMIT 1;
SQL
)

if [[ -z "$token" ]]; then
  echo "No live session for '$PRINCIPAL'. Sign in again, or set PRINCIPAL=<value> if your principal isn't your gcloud email." >&2
  kubectl -n ontology exec ontology-db-1 -c postgres -- psql -d platform -c \
    "SELECT principal, expires_at, expires_at > now() AS live FROM platform.session ORDER BY created_at DESC LIMIT 5" >&2
  exit 1
fi

printf '%s' "$token" | pbcopy
echo "Platform token for $PRINCIPAL copied to clipboard (expires within an hour of sign-in)."
