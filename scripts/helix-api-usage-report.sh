#!/usr/bin/env bash
# Report on helix-api Cloud Run usage from its auto-generated request log.
# Renders a single self-contained HTML report with:
#   1. Daily request count by endpoint pattern (method + normalized path).
#   2. Daily request count by remote IP.
#   3. Request count by endpoint pattern, remote IP, and day (the detailed
#      cross-tab).
#   4. Totals ranked - endpoint pattern totals and remote IP totals over the
#      whole window.
#
# IMPORTANT CAVEAT: there is no authenticated-user identity in these logs
# today, so remote IP is the only available proxy for "who called this", and
# it is a poor one - the observed IPs (e.g. 34.96.x.x, 2607:f8b0::/32) are
# Google-owned infrastructure addresses (GCP's load-balancer/frontend layer
# in front of Cloud Run), not distinct end-user IPs. Report 2 is not
# per-user attribution. See the note rendered in the HTML output itself.
#
# Requires: `gcloud` CLI, authenticated as an account with logging read
# access on the target project. Requires `python3` (stdlib only).
#
# Usage:
#   ./helix-api-usage-report.sh
#   PROJECT=my-project SERVICE=my-service DAYS=7 ./helix-api-usage-report.sh
#
# Env vars:
#   PROJECT      (default: reliant-ai-dev) GCP project the Cloud Run service
#                runs in.
#   SERVICE      (default: helix-api) Cloud Run service name.
#   DAYS         (default: 3) How many days back to look, inclusive of today.
#   OUTPUT_HTML  (default: `helix-api-usage-report-<timestamp>.html` in the
#                current directory) Path to write the HTML report to.
set -euo pipefail

PROJECT="${PROJECT:-reliant-ai-dev}"
SERVICE="${SERVICE:-helix-api}"
DAYS="${DAYS:-3}"
OUTPUT_HTML="${OUTPUT_HTML:-helix-api-usage-report-$(date +%Y%m%d-%H%M%S).html}"

command -v gcloud >/dev/null 2>&1 || { echo "error: gcloud CLI not found in PATH" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 not found in PATH" >&2; exit 1; }

FILTER="resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${SERVICE}\" AND logName=\"projects/${PROJECT}/logs/run.googleapis.com%2Frequests\""

PY_SCRIPT="$(mktemp -t helix-api-usage-report.XXXXXX.py)"
trap 'rm -f "$PY_SCRIPT"' EXIT

cat >"$PY_SCRIPT" <<'PYEOF'
import json
import os
import re
import sys
from collections import defaultdict
from datetime import datetime, timezone
from urllib.parse import urlsplit

PROJECT = os.environ["PROJECT"]
SERVICE = os.environ["SERVICE"]
DAYS = os.environ["DAYS"]
OUTPUT_HTML = os.environ["OUTPUT_HTML"]

UUID_RE = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
)


def normalize_path(path):
    return UUID_RE.sub("{id}", path)


print("parsing log entries...", file=sys.stderr)
entries = json.load(sys.stdin)

# rows: list of (date, endpoint, remote_ip)
rows = []
skipped = 0
for entry in entries:
    http_request = entry.get("httpRequest")
    timestamp = entry.get("timestamp")
    if not http_request or not timestamp:
        skipped += 1
        continue
    method = http_request.get("requestMethod", "?")
    request_url = http_request.get("requestUrl", "")
    remote_ip = http_request.get("remoteIp", "?")
    path = urlsplit(request_url).path or request_url
    endpoint = f"{method} {normalize_path(path)}"
    date = timestamp[:10]
    rows.append((date, endpoint, remote_ip))

print(f"parsed {len(rows)} request(s), skipped {skipped} entr(y/ies) without httpRequest/timestamp", file=sys.stderr)

by_endpoint_day = defaultdict(int)
by_ip_day = defaultdict(int)
by_endpoint_ip_day = defaultdict(int)
endpoint_totals = defaultdict(int)
ip_totals = defaultdict(int)

for date, endpoint, remote_ip in rows:
    by_endpoint_day[(date, endpoint)] += 1
    by_ip_day[(date, remote_ip)] += 1
    by_endpoint_ip_day[(endpoint, remote_ip, date)] += 1
    endpoint_totals[endpoint] += 1
    ip_totals[remote_ip] += 1


def html_escape(s):
    return (
        str(s)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
    )


def format_int(n):
    return f"{n:,}"


def render_table(headers, records, num_cols=()):
    out = ['<table class="sortable">', "<thead><tr>"]
    for h in headers:
        out.append(f"<th>{html_escape(h)}</th>")
    out.append("</tr></thead><tbody>")
    for record in records:
        out.append("<tr>")
        for i, val in enumerate(record):
            if i in num_cols:
                out.append(
                    f'<td class="num" data-sort="{html_escape(val)}">{html_escape(format_int(val))}</td>'
                )
            else:
                out.append(f"<td>{html_escape(val)}</td>")
        out.append("</tr>")
    out.append("</tbody></table>")
    if not records:
        out.append('<p class="empty-note">No rows returned.</p>')
    return "\n".join(out)


report1_records = sorted(
    ((date, endpoint, count) for (date, endpoint), count in by_endpoint_day.items()),
    key=lambda r: (r[0], r[2]),
    reverse=True,
)

report2_records = sorted(
    ((date, ip, count) for (date, ip), count in by_ip_day.items()),
    key=lambda r: (r[0], r[2]),
    reverse=True,
)

report3_records = sorted(
    (
        (endpoint, ip, date, count)
        for (endpoint, ip, date), count in by_endpoint_ip_day.items()
    ),
    key=lambda r: (r[2], r[3]),
    reverse=True,
)

report4_endpoint_records = sorted(
    ((endpoint, count) for endpoint, count in endpoint_totals.items()),
    key=lambda r: r[1],
    reverse=True,
)
report4_ip_records = sorted(
    ((ip, count) for ip, count in ip_totals.items()),
    key=lambda r: r[1],
    reverse=True,
)

window_end = datetime.now(timezone.utc).strftime("%Y-%m-%d")
generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

IP_CAVEAT_HTML = """
<p class="fallback-note">
<strong>Caveat:</strong> there is no authenticated-user identity in these logs today, so
remote IP is the only available proxy for "who called this" - and it is a poor one. The
IPs observed here (e.g. <code>34.96.x.x</code>, <code>2607:f8b0::/32</code>) are
Google-owned infrastructure addresses - GCP's own load-balancer/frontend layer in front of
Cloud Run - not distinct end-user IPs. Do not read this table as per-user attribution.
</p>
"""

html_parts = []
html_parts.append(f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>helix-api usage report</title>
<style>
  body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; margin: 2rem; color: #1a1a1a; background: #fff; }}
  header {{ margin-bottom: 2rem; border-bottom: 2px solid #333; padding-bottom: 1rem; }}
  header h1 {{ margin: 0 0 0.5rem 0; font-size: 1.5rem; }}
  header dl {{ display: grid; grid-template-columns: max-content 1fr; gap: 0.25rem 1rem; margin: 0; font-size: 0.9rem; color: #444; }}
  header dt {{ font-weight: 600; }}
  header dd {{ margin: 0; }}
  section {{ margin-bottom: 2.5rem; }}
  h2 {{ font-size: 1.15rem; border-bottom: 1px solid #ddd; padding-bottom: 0.4rem; }}
  table {{ border-collapse: collapse; width: 100%; font-size: 0.9rem; }}
  th, td {{ border: 1px solid #ccc; padding: 0.4rem 0.7rem; text-align: left; }}
  td.num {{ text-align: right; font-variant-numeric: tabular-nums; }}
  th {{ background: #333; color: #fff; position: sticky; top: 0; }}
  tbody tr:nth-child(even) {{ background: #f4f4f4; }}
  tbody tr:hover {{ background: #eaf2ff; }}
  .empty-note {{ color: #666; font-style: italic; }}
  .fallback-note {{ background: #fff8e1; border: 1px solid #e6c860; padding: 0.75rem 1rem; border-radius: 4px; color: #6b5300; }}
  table.sortable th {{ cursor: pointer; user-select: none; }}
  table.sortable th:hover {{ background: #4a4a4a; }}
  table.sortable th.sorted {{ background: #1a4d8f; }}
</style>
</head>
<body>
<header>
  <h1>helix-api usage report</h1>
  <dl>
    <dt>Project</dt><dd>{html_escape(PROJECT)}</dd>
    <dt>Service</dt><dd>{html_escape(SERVICE)}</dd>
    <dt>Window</dt><dd>last {html_escape(DAYS)} day(s), through {window_end}</dd>
    <dt>Generated</dt><dd>{generated_at}</dd>
    <dt>Total requests</dt><dd>{format_int(len(rows))}</dd>
  </dl>
</header>
""")

html_parts.append(f"""
<section>
<h2>Report 1: daily request count by endpoint pattern</h2>
{render_table(["date", "endpoint", "requests"], report1_records, num_cols={2})}
</section>
""")

html_parts.append(f"""
<section>
<h2>Report 2: daily request count by remote IP</h2>
{IP_CAVEAT_HTML}
{render_table(["date", "remote_ip", "requests"], report2_records, num_cols={2})}
</section>
""")

html_parts.append(f"""
<section>
<h2>Report 3: request count by endpoint pattern, remote IP, and day</h2>
{render_table(["endpoint", "remote_ip", "date", "requests"], report3_records, num_cols={3})}
</section>
""")

html_parts.append(f"""
<section>
<h2>Report 4a: endpoint pattern totals, ranked</h2>
{render_table(["endpoint", "requests"], report4_endpoint_records, num_cols={1})}
</section>

<section>
<h2>Report 4b: remote IP totals, ranked</h2>
{IP_CAVEAT_HTML}
{render_table(["remote_ip", "requests"], report4_ip_records, num_cols={1})}
</section>
""")

html_parts.append("""
<script>
document.querySelectorAll('table.sortable').forEach(function (table) {
  var thead = table.tHead;
  if (!thead) return;
  var ths = Array.prototype.slice.call(thead.querySelectorAll('th'));

  function cellValue(row, colIndex) {
    var cell = row.cells[colIndex];
    if (!cell) return '';
    return cell.hasAttribute('data-sort') ? cell.getAttribute('data-sort') : cell.textContent.trim();
  }

  ths.forEach(function (th, colIndex) {
    if (!th.dataset.label) th.dataset.label = th.textContent.trim();
    th.addEventListener('click', function () {
      var dir = th.dataset.sortDir === 'asc' ? 'desc' : 'asc';
      ths.forEach(function (other) {
        delete other.dataset.sortDir;
        other.classList.remove('sorted');
        other.textContent = other.dataset.label;
      });
      th.dataset.sortDir = dir;
      th.classList.add('sorted');
      th.textContent = th.dataset.label + (dir === 'asc' ? ' ▲' : ' ▼');

      var tbody = table.tBodies[0];
      var rows = Array.prototype.slice.call(tbody.rows);
      rows.sort(function (a, b) {
        var av = cellValue(a, colIndex), bv = cellValue(b, colIndex);
        var an = parseFloat(av), bn = parseFloat(bv);
        var cmp = (av !== '' && bv !== '' && !isNaN(an) && !isNaN(bn))
          ? an - bn
          : av.localeCompare(bv, undefined, { numeric: true });
        return dir === 'asc' ? cmp : -cmp;
      });
      rows.forEach(function (row) { tbody.appendChild(row); });
    });
  });
});
</script>
</body>
</html>
""")

with open(OUTPUT_HTML, "w") as f:
    f.write("".join(html_parts))

print(f"wrote report to {OUTPUT_HTML}", file=sys.stderr)
PYEOF

echo "querying request logs for ${SERVICE} in ${PROJECT}, last ${DAYS} day(s)..." >&2
gcloud logging read "$FILTER" \
  --project="$PROJECT" \
  --format=json \
  --freshness="${DAYS}d" \
  | PROJECT="$PROJECT" SERVICE="$SERVICE" DAYS="$DAYS" OUTPUT_HTML="$OUTPUT_HTML" python3 "$PY_SCRIPT"

echo "wrote report to ${OUTPUT_HTML}"

if command -v open >/dev/null 2>&1; then
  open "$OUTPUT_HTML"
fi
