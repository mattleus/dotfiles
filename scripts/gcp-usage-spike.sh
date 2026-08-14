#!/usr/bin/env bash
# Investigate a GCP usage/cost spike across an org's billing account using
# Cloud Billing export to BigQuery. Prints three reports:
#   1. Daily cost by service, across all services, for the lookback window -
#      use this to confirm which day(s) spiked and which service(s) drove it.
#   2. Daily cost + usage by project and SKU, for the service(s) you're
#      drilling into (default: Vertex AI) - the detailed numbers.
#   3. Total cost + usage by project for those same service(s), ranked -
#      quickly answers "which project was using this."
#
# Requires: `bq` CLI, authenticated (`gcloud auth login`) as an account with
# BigQuery read access to the billing export dataset.
#
# Usage:
#   BILLING_TABLE='my-billing-project.billing_export.gcp_billing_export_v1_XXXXXX' \
#     ./gcp-usage-spike.sh
#
# Env vars:
#   BILLING_TABLE  (required) Fully-qualified billing export table, e.g.
#                  `project.dataset.gcp_billing_export_v1_XXXXXX`. Find it in
#                  the GCP Console under Billing > Billing export > Detailed
#                  usage cost, or with `bq ls <billing-project>:<dataset>`.
#   SERVICES       (default: "Vertex AI") Comma-separated list of GCP service
#                  descriptions to drill into for reports 2 and 3, e.g.
#                  "Vertex AI,Compute Engine". Must match the `service.description`
#                  value in the billing export exactly (report 1's output shows
#                  the exact spelling for every service you're billed for).
#   DAYS           (default: 3) How many days back to look, inclusive of today.
set -euo pipefail

BILLING_TABLE="${BILLING_TABLE:-reliant-ai-data.billing_data.gcp_billing_export_v1_01F68A_65DD13_D61FC1}"
SERVICES="${SERVICES:-Vertex AI}"
DAYS="${DAYS:-3}"

command -v bq >/dev/null 2>&1 || { echo "error: bq CLI not found in PATH" >&2; exit 1; }

# Turn "Vertex AI,Compute Engine" into a BigQuery UNNEST-able array literal:
# ["Vertex AI", "Compute Engine"]
services_array_literal() {
  local IFS=','
  local -a parts=($SERVICES)
  local out="["
  local first=1
  for p in "${parts[@]}"; do
    p="$(echo "$p" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ "$first" -eq 1 ] || out+=", "
    out+="\"$(printf '%s' "$p" | sed 's/"/\\"/g')\""
    first=0
  done
  out+="]"
  printf '%s' "$out"
}
SERVICES_ARRAY="$(services_array_literal)"

echo "=================================================================="
echo "Report 1: daily cost by service, last ${DAYS} day(s) - all services"
echo "=================================================================="
bq query --use_legacy_sql=false --format=pretty "
SELECT
  DATE(usage_start_time) AS usage_date,
  service.description AS service,
  ROUND(SUM(cost), 2) AS total_cost,
  currency
FROM \`${BILLING_TABLE}\`
WHERE DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL ${DAYS} DAY)
GROUP BY usage_date, service, currency
ORDER BY usage_date DESC, total_cost DESC
"

echo
echo "=================================================================="
echo "Report 2: daily cost + usage by project and SKU - services: ${SERVICES}"
echo "=================================================================="
bq query --use_legacy_sql=false --format=pretty "
SELECT
  DATE(usage_start_time) AS usage_date,
  project.id AS project_id,
  service.description AS service,
  sku.description AS sku,
  ROUND(SUM(cost), 2) AS cost,
  currency,
  SUM(usage.amount) AS usage_amount,
  ANY_VALUE(usage.unit) AS usage_unit
FROM \`${BILLING_TABLE}\`
WHERE DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL ${DAYS} DAY)
  AND service.description IN UNNEST(${SERVICES_ARRAY})
GROUP BY usage_date, project_id, service, sku, currency
ORDER BY usage_date DESC, cost DESC
"

echo
echo "=================================================================="
echo "Report 3: total cost + usage by project, ranked - services: ${SERVICES}"
echo "=================================================================="
bq query --use_legacy_sql=false --format=pretty "
SELECT
  project.id AS project_id,
  ANY_VALUE(project.name) AS project_name,
  ROUND(SUM(cost), 2) AS total_cost,
  currency,
  SUM(usage.amount) AS total_usage_amount
FROM \`${BILLING_TABLE}\`
WHERE DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL ${DAYS} DAY)
  AND service.description IN UNNEST(${SERVICES_ARRAY})
GROUP BY project_id, currency
ORDER BY total_cost DESC
"
