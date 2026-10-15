#!/usr/bin/env bash
# Deploys the relay to Cloud Run as a single instance with request-based billing.
#
# Matches are kept in process memory, so the service must never scale past one
# instance, and a redeploy ends every live match (clients get "server_restart").
# Deploy during quiet hours (GET /health shows live clients and matches).
#
# The instance scales to zero when no WebSocket is open, so billing only runs
# while someone is queued or playing; the first player after an idle spell
# waits for a cold start. Each open WebSocket counts as an active request, so
# CPU stays allocated for the whole match.
#
#   PROJECT=my-gcp-project ./deploy_cloud_run.sh
set -euo pipefail

SERVICE="${SERVICE:-aiquiz-relay}"
REGION="${REGION:-asia-northeast1}"
PROJECT="${PROJECT:-$(gcloud config get-value project 2>/dev/null)}"

cd "$(dirname "$0")"
gcloud run deploy "$SERVICE" \
  --project "$PROJECT" \
  --region "$REGION" \
  --source . \
  --allow-unauthenticated \
  --min-instances 0 \
  --max-instances 1 \
  --concurrency 1000 \
  --timeout 3600 \
  --session-affinity \
  --cpu-throttling \
  --cpu 1 \
  --memory 512Mi

gcloud run services describe "$SERVICE" --project "$PROJECT" --region "$REGION" --format 'value(status.url)'
