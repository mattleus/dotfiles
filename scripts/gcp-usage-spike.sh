#!/usr/bin/env bash
# Investigate a GCP usage/cost spike across an org's billing account using
# Cloud Billing export to BigQuery. Renders a single self-contained HTML
# report with:
#   1. Daily cost by service, across all services, for the lookback window -
#      use this to confirm which day(s) spiked and which service(s) drove it.
#   2. Daily cost + usage by project and SKU, for the service(s) you're
#      drilling into (default: Vertex AI) - the detailed numbers.
#   3. Total cost + usage by project for those same service(s), ranked -
#      quickly answers "which project was using this."
#   4. Resource-level breakdown (cost + usage by project/service/resource),
#      if a resource-level ("detailed") billing export table is found -
#      otherwise a note explaining how to enable it.
#   5. Vertex AI caller breakdown from Cloud Audit Logs (caller identity +
#      method, request counts, first/last seen), if an audit log table is
#      configured - otherwise a note explaining how to configure it.
#
# Requires: `bq` CLI, authenticated (`gcloud auth login`) as an account with
# BigQuery read access to the billing export dataset.
#
# Usage:
#   BILLING_TABLE='my-billing-project.billing_export.gcp_billing_export_v1_XXXXXX' \
#     ./gcp-usage-spike.sh
#
# Env vars:
#   BILLING_TABLE          (required) Fully-qualified billing export table, e.g.
#                          `project.dataset.gcp_billing_export_v1_XXXXXX`. Find it
#                          in the GCP Console under Billing > Billing export >
#                          Detailed usage cost, or with `bq ls <billing-project>:<dataset>`.
#   SERVICES               (default: "Vertex AI") Comma-separated list of GCP
#                          service descriptions to drill into for reports 2 and
#                          3 (and 4), e.g. "Vertex AI,Compute Engine". Must match
#                          the `service.description` value in the billing export
#                          exactly (report 1's output shows the exact spelling
#                          for every service you're billed for).
#   DAYS                   (default: 3) How many days back to look, inclusive of
#                          today.
#   OUTPUT_HTML             (default: `gcp-usage-report-<timestamp>.html` in the
#                          current directory) Path to write the HTML report to.
#   RESOURCE_BILLING_TABLE  (optional) Fully-qualified resource-level ("detailed")
#                          billing export table, e.g.
#                          `project.dataset.gcp_billing_export_resource_v1_XXXXXX`.
#                          If unset, this is auto-detected by listing tables in
#                          BILLING_TABLE's project/dataset. If neither is found,
#                          the report section explains how to enable it.
#   AUDIT_LOG_TABLE         (optional) Fully-qualified BigQuery table that a Cloud
#                          Logging sink for Vertex AI Data Access audit logs
#                          writes to. If unset, or the table doesn't exist/query
#                          fails, the report section explains how to configure it.
set -euo pipefail

BILLING_TABLE="${BILLING_TABLE:-reliant-ai-data.billing_data.gcp_billing_export_v1_01F68A_65DD13_D61FC1}"
SERVICES="${SERVICES:-Vertex AI}"
DAYS="${DAYS:-3}"
OUTPUT_HTML="${OUTPUT_HTML:-gcp-usage-report-$(date +%Y%m%d-%H%M%S).html}"
RESOURCE_BILLING_TABLE="${RESOURCE_BILLING_TABLE:-}"
AUDIT_LOG_TABLE="${AUDIT_LOG_TABLE:-}"

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

html_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# Format a numeric string with thousands separators and exactly 2 decimal
# places, e.g. "7240.4" -> "7,240.40". Handles scientific notation input.
format_money() {
  awk -v n="$1" 'BEGIN{
    neg = (n < 0); if (neg) n = -n
    s = sprintf("%.2f", n)
    split(s, parts, ".")
    intpart = parts[1]; frac = parts[2]
    outp = ""; len = length(intpart); c = 0
    for (i = len; i >= 1; i--) {
      outp = substr(intpart, i, 1) outp
      c++
      if (c % 3 == 0 && i != 1) outp = "," outp
    }
    if (neg) outp = "-" outp
    printf "%s.%s", outp, frac
  }'
}

# Format a numeric string as a plain grouped integer, e.g. "24205149.0" or
# "2.4E7" -> "24,205,149". Handles scientific notation input.
format_int() {
  awk -v n="$1" 'BEGIN{
    neg = (n < 0); if (neg) n = -n
    s = sprintf("%.0f", n)
    outp = ""; len = length(s); c = 0
    for (i = len; i >= 1; i--) {
      outp = substr(s, i, 1) outp
      c++
      if (c % 3 == 0 && i != 1) outp = "," outp
    }
    if (neg) outp = "-" outp
    printf "%s", outp
  }'
}

# Convert CSV (as produced by `bq query --format=csv`) into an HTML <table>.
# Reads CSV from stdin, writes HTML to stdout. Assumes no embedded commas or
# quoted fields, which holds for all queries in this script. Cost and usage
# columns (matched by header name) are rendered with grouped-thousands
# formatting.
csv_to_html_table() {
  local -a headers=()
  local row_index=0
  echo "<table>"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    IFS=',' read -r -a fields <<<"$line"
    if [ "$row_index" -eq 0 ]; then
      headers=("${fields[@]}")
      echo "<thead><tr>"
      for f in "${fields[@]}"; do
        echo "<th>$(printf '%s' "$f" | html_escape)</th>"
      done
      echo "</tr></thead><tbody>"
    else
      echo "<tr>"
      for i in "${!fields[@]}"; do
        local col="${headers[$i]:-}"
        local val="${fields[$i]}"
        local display="$val"
        local cls=""
        if [ -n "$val" ]; then
          case "$col" in
            cost|total_cost) display="$(format_money "$val")"; cls=" class=\"num\"" ;;
            usage_amount|total_usage_amount) display="$(format_int "$val")"; cls=" class=\"num\"" ;;
          esac
        fi
        echo "<td${cls}>$(printf '%s' "$display" | html_escape)</td>"
      done
      echo "</tr>"
    fi
    row_index=$((row_index + 1))
  done
  if [ "$row_index" -eq 0 ]; then
    echo "</thead><tbody>"
  fi
  echo "</tbody></table>"
  if [ "$row_index" -le 1 ]; then
    echo "<p class=\"empty-note\">No rows returned.</p>"
  fi
}

# Auto-detect a resource-level billing export table by listing tables in the
# same project/dataset as BILLING_TABLE, unless RESOURCE_BILLING_TABLE is set.
detect_resource_billing_table() {
  if [ -n "$RESOURCE_BILLING_TABLE" ]; then
    printf '%s' "$RESOURCE_BILLING_TABLE"
    return 0
  fi
  local project dataset
  project="$(printf '%s' "$BILLING_TABLE" | cut -d. -f1)"
  dataset="$(printf '%s' "$BILLING_TABLE" | cut -d. -f2)"
  local table
  table="$(bq ls "${project}:${dataset}" 2>/dev/null | awk '$1 ~ /^gcp_billing_export_resource_v1_/ {print $1; exit}')"
  if [ -n "$table" ]; then
    printf '%s.%s.%s' "$project" "$dataset" "$table"
  fi
}

echo "detecting resource-level billing export table..."
DETECTED_RESOURCE_TABLE="$(detect_resource_billing_table || true)"

WINDOW_START="$(date -v-"${DAYS}"d +%Y-%m-%d 2>/dev/null || date -d "${DAYS} days ago" +%Y-%m-%d)"
WINDOW_END="$(date +%Y-%m-%d)"
GENERATED_AT="$(date '+%Y-%m-%d %H:%M:%S %Z')"

{
cat <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>GCP usage report</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; margin: 2rem; color: #1a1a1a; background: #fff; }
  header { margin-bottom: 2rem; border-bottom: 2px solid #333; padding-bottom: 1rem; }
  header h1 { margin: 0 0 0.5rem 0; font-size: 1.5rem; }
  header dl { display: grid; grid-template-columns: max-content 1fr; gap: 0.25rem 1rem; margin: 0; font-size: 0.9rem; color: #444; }
  header dt { font-weight: 600; }
  header dd { margin: 0; }
  section { margin-bottom: 2.5rem; }
  h2 { font-size: 1.15rem; border-bottom: 1px solid #ddd; padding-bottom: 0.4rem; }
  table { border-collapse: collapse; width: 100%; font-size: 0.9rem; }
  th, td { border: 1px solid #ccc; padding: 0.4rem 0.7rem; text-align: left; }
  td.num { text-align: right; font-variant-numeric: tabular-nums; }
  th { background: #333; color: #fff; position: sticky; top: 0; }
  tbody tr:nth-child(even) { background: #f4f4f4; }
  tbody tr:hover { background: #eaf2ff; }
  .empty-note { color: #666; font-style: italic; }
  .fallback-note { background: #fff8e1; border: 1px solid #e6c860; padding: 0.75rem 1rem; border-radius: 4px; color: #6b5300; }
</style>
</head>
<body>
<header>
  <h1>GCP usage report</h1>
  <dl>
    <dt>Window</dt><dd>${WINDOW_START} to ${WINDOW_END} (${DAYS} day(s))</dd>
    <dt>Services</dt><dd>$(printf '%s' "$SERVICES" | html_escape)</dd>
    <dt>Generated</dt><dd>${GENERATED_AT}</dd>
  </dl>
</header>
HTML

echo "querying report 1 (daily cost by service, all services)..." >&2
cat <<HTML
<section>
<h2>Report 1: daily cost by service, last ${DAYS} day(s) - all services</h2>
HTML
bq query --use_legacy_sql=false --format=csv "
SELECT
  DATE(usage_start_time) AS usage_date,
  service.description AS service,
  ROUND(SUM(cost), 2) AS total_cost,
  currency
FROM \`${BILLING_TABLE}\`
WHERE DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL ${DAYS} DAY)
GROUP BY usage_date, service, currency
ORDER BY usage_date DESC, total_cost DESC
" | csv_to_html_table
echo "</section>"

echo "querying report 2 (daily cost + usage by project/SKU)..." >&2
cat <<HTML
<section>
<h2>Report 2: daily cost + usage by project and SKU - services: $(printf '%s' "$SERVICES" | html_escape)</h2>
HTML
bq query --use_legacy_sql=false --format=csv "
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
" | csv_to_html_table
echo "</section>"

echo "querying report 3 (total cost + usage by project, ranked)..." >&2
cat <<HTML
<section>
<h2>Report 3: total cost + usage by project, ranked - services: $(printf '%s' "$SERVICES" | html_escape)</h2>
HTML
bq query --use_legacy_sql=false --format=csv "
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
" | csv_to_html_table
echo "</section>"

cat <<HTML
<section>
<h2>Report 4: resource-level breakdown - services: $(printf '%s' "$SERVICES" | html_escape)</h2>
HTML
if [ -n "$DETECTED_RESOURCE_TABLE" ]; then
  echo "querying report 4 (resource-level breakdown, table: ${DETECTED_RESOURCE_TABLE})..." >&2
  bq query --use_legacy_sql=false --format=csv "
SELECT
  project.id AS project_id,
  service.description AS service,
  COALESCE(resource.name, resource.global_name) AS resource_name,
  ROUND(SUM(cost), 2) AS cost,
  currency,
  SUM(usage.amount) AS usage_amount,
  ANY_VALUE(usage.unit) AS usage_unit
FROM \`${DETECTED_RESOURCE_TABLE}\`
WHERE DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL ${DAYS} DAY)
  AND service.description IN UNNEST(${SERVICES_ARRAY})
GROUP BY project_id, service, resource_name, currency
ORDER BY cost DESC
" | csv_to_html_table
else
  echo "resource-level billing export not detected, skipping report 4 query" >&2
  cat <<HTML
<p class="fallback-note">Resource-level billing export not detected - enable it under
Billing &gt; Billing export &gt; Detailed usage cost; it only covers usage from
enablement forward.</p>
HTML
fi
echo "</section>"

cat <<HTML
<section>
<h2>Report 5: Vertex AI caller breakdown (Cloud Audit Logs)</h2>
HTML
if [ -n "$AUDIT_LOG_TABLE" ] && bq query --use_legacy_sql=false --format=csv "
SELECT
  protoPayload.authenticationInfo.principalEmail AS caller,
  protoPayload.methodName AS method,
  COUNT(*) AS request_count,
  MIN(timestamp) AS first_seen,
  MAX(timestamp) AS last_seen
FROM \`${AUDIT_LOG_TABLE}\`
WHERE DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL ${DAYS} DAY)
  AND protoPayload.serviceName = 'aiplatform.googleapis.com'
GROUP BY caller, method
ORDER BY request_count DESC
" > /tmp/gcp-usage-spike-report5.csv 2>/tmp/gcp-usage-spike-report5.err; then
  echo "querying report 5 (Vertex AI caller breakdown, table: ${AUDIT_LOG_TABLE})..." >&2
  csv_to_html_table < /tmp/gcp-usage-spike-report5.csv
else
  if [ -n "$AUDIT_LOG_TABLE" ]; then
    echo "AUDIT_LOG_TABLE query failed, skipping report 5:" >&2
    cat /tmp/gcp-usage-spike-report5.err >&2 || true
  else
    echo "AUDIT_LOG_TABLE not set, skipping report 5 query" >&2
  fi
  cat <<HTML
<p class="fallback-note">Vertex AI Data Access audit log table not configured - set
AUDIT_LOG_TABLE once the log sink's BigQuery table exists.</p>
HTML
fi
rm -f /tmp/gcp-usage-spike-report5.csv /tmp/gcp-usage-spike-report5.err
echo "</section>"

echo "</body></html>"
} > "$OUTPUT_HTML"

echo "wrote report to ${OUTPUT_HTML}"

if command -v open >/dev/null 2>&1; then
  open "$OUTPUT_HTML"
fi
