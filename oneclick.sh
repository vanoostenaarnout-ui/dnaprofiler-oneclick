#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# DNA Profiler / ER Engine — one-click Cloud Run deploy
# Examples:
#   ./oneclick.sh -p YOUR-PROJECT -r europe-west3 -s dnaprofiler \
#     -i ghcr.io/dnahub/erengine:latest
#   PROJECT_ID=YOUR-PROJECT ./oneclick.sh                # env fallback
#   ./oneclick.sh --build                                # build in GCP (Cloud Build + Artifact Registry)
#   ./oneclick.sh -l "YOUR-LICENSE-STRING"               # store license in Secret Manager
# ------------------------------------------------------------

# Defaults / current config fallbacks
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
REGION="${REGION:-europe-west3}"
SERVICE="${SERVICE:-dnaprofiler}"

IMAGE="${IMAGE:-ghcr.io/dnahub/erengine:latest}"   # override with -i if you have a different image
LICENSE_VALUE="${LICENSE_VALUE:-}"                 # -l to set via Secret Manager
SECRET_NAME="${SECRET_NAME:-dna-profiler-license}"

ALLOW_UNAUTH="${ALLOW_UNAUTH:-false}"
BUILD_IMAGE="${BUILD_IMAGE:-false}"

REPO="${REPO:-apps}"          # Artifact Registry repo (when --build)
CPU="${CPU:-1}"
MEM="${MEM:-512Mi}"
CONCURRENCY="${CONCURRENCY:-80}"
MIN_INSTANCES="${MIN_INSTANCES:-0}"
MAX_INSTANCES="${MAX_INSTANCES:-3}"
PORT="${PORT:-8080}"
TIMEOUT="${TIMEOUT:-900s}"
ENV_VARS="${ENV_VARS:-}"      # e.g. ENV_VARS="LOG_LEVEL=info,FEATURE_X=true"

usage() {
  cat <<EOF
Usage: $0 [options]

Required (if not auto-detected):
  -p, --project        GCP project id
Optional:
  -r, --region         Region (default: ${REGION})
  -s, --service        Cloud Run service name (default: ${SERVICE})
  -i, --image          Container image to deploy (default: ${IMAGE})
  -l, --license        License string to store as Secret Manager secret (${SECRET_NAME})
      --allow-unauth   Allow unauthenticated (public) access [default: false]
      --build          Build image with Cloud Build into Artifact Registry (${REPO})
      --cpu N          vCPU (default: ${CPU})
      --mem SIZE       Memory (default: ${MEM})
      --concurrency N  Max requests per instance (default: ${CONCURRENCY})
      --min N          Min instances (default: ${MIN_INSTANCES})
      --max N          Max instances (default: ${MAX_INSTANCES})
      --port N         Container port (default: ${PORT})
      --timeout D      Request timeout (default: ${TIMEOUT})
      --env K=V,...    Extra env vars (comma-separated)
  -h, --help           Show this help

Env fallbacks: PROJECT_ID, REGION, SERVICE, IMAGE, LICENSE_VALUE, SECRET_NAME, ALLOW_UNAUTH, CPU, MEM, CONCURRENCY, MIN_INSTANCES, MAX_INSTANCES, PORT, TIMEOUT, ENV_VARS
EOF
}

# -------- arg parse (supports long flags) --------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project)        PROJECT_ID="$2"; shift 2;;
    -r|--region)         REGION="$2"; shift 2;;
    -s|--service)        SERVICE="$2"; shift 2;;
    -i|--image)          IMAGE="$2"; shift 2;;
    -l|--license)        LICENSE_VALUE="$2"; shift 2;;
        --allow-unauth|--allow-unauthenticated) ALLOW_UNAUTH=true; shift 1;;
        --build)         BUILD_IMAGE=true; shift 1;;
        --cpu)           CPU="$2"; shift 2;;
        --mem|--memory)  MEM="$2"; shift 2;;
        --concurrency)   CONCURRENCY="$2"; shift 2;;
        --min)           MIN_INSTANCES="$2"; shift 2;;
        --max)           MAX_INSTANCES="$2"; shift 2;;
        --port)          PORT="$2"; shift 2;;
        --timeout)       TIMEOUT="$2"; shift 2;;
        --env|--set-env) ENV_VARS="$2"; shift 2;;
    -h|--help)           usage; exit 0;;
    *) echo "Unknown option: $1"; usage; exit 2;;
  esac
done

say(){ printf "%b\n" "$*"; }
hr(){ printf "%s\n" "----------------------------------------"; }

need_cmd(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1"; exit 127; }; }
need_cmd gcloud

# Auto-prompt for project if still empty
if [[ -z "${PROJECT_ID:-}" || "${PROJECT_ID}" == "(unset)" ]]; then
  say "No PROJECT_ID detected."
  mapfile -t PROJS < <(gcloud projects list --format="value(projectId)")
  if [[ "${#PROJS[@]}" -eq 0 ]]; then
    say "⚠️  No projects available. Please create one (or run ./start.sh)."
    exit 2
  fi
  if [[ "${#PROJS[@]}" -eq 1 ]]; then
    PROJECT_ID="${PROJS[0]}"
    say "Using your only project: ${PROJECT_ID}"
  else
    say "Select a project:"
    for i in "${!PROJS[@]}"; do printf "%2d) %s\n" "$((i+1))" "${PROJS[$i]}"; done
    read -rp "Choice [1-${#PROJS[@]}]: " sel
    PROJECT_ID="${PROJS[$((sel-1))]}"
  fi
fi

gcloud config set project "${PROJECT_ID}" >/dev/null

# Enable required APIs (idempotent)
hr
say "Enabling required services on ${PROJECT_ID} (may take ~1–2 min)..."
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  --project "${PROJECT_ID}"

# Optional: build image via Cloud Build into Artifact Registry
if [[ "${BUILD_IMAGE}" == "true" ]]; then
  hr
  say "Building container via Cloud Build → Artifact Registry (${REPO}) in ${REGION}..."
  # Create repo if missing
  gcloud artifacts repositories describe "${REPO}" --location="${REGION}" >/dev/null 2>&1 \
    || gcloud artifacts repositories create "${REPO}" --repository-format=docker --location="${REGION}" --description="DNA Profiler apps"
  TAG="$(date +%Y%m%d%H%M%S)"
  IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${SERVICE}:${TAG}"
  gcloud builds submit --tag "${IMAGE}"
fi

# Secret Manager: license (if provided)
SECRET_ARGS=()
if [[ -n "${LICENSE_VALUE}" ]]; then
  hr
  say "Storing license value in Secret Manager: ${SECRET_NAME}"
  TMP="$(mktemp)"; printf "%s" "${LICENSE_VALUE}" > "${TMP}"
  if gcloud secrets describe "${SECRET_NAME}" >/dev/null 2>&1; then
    gcloud secrets versions add "${SECRET_NAME}" --data-file="${TMP}" >/dev/null
  else
    gcloud secrets create "${SECRET_NAME}" --replication-policy="automatic" --data-file="${TMP}" >/dev/null
  fi
  rm -f "${TMP}"
  SECRET_ARGS+=( --set-secrets="LICENSE_KEY=${SECRET_NAME}:latest" )
  say "Secret configured; container will receive LICENSE_KEY via secrets."
fi

# Build deploy args
AUTH_FLAG="--no-allow-unauthenticated"
[[ "${ALLOW_UNAUTH}" == "true" ]] && AUTH_FLAG="--allow-unauthenticated"

ENV_ARGS=()
[[ -n "${ENV_VARS}" ]] && ENV_ARGS+=( --set-env-vars="${ENV_VARS}" )

DEPLOY_ARGS=(
  --project="${PROJECT_ID}"
  --region="${REGION}"
  --platform=managed
  --image="${IMAGE}"
  --service-account=""
  --port="${PORT}"
  --cpu="${CPU}"
  --memory="${MEM}"
  --concurrency="${CONCURRENCY}"
  --min-instances="${MIN_INSTANCES}"
  --max-instances="${MAX_INSTANCES}"
  --timeout="${TIMEOUT}"
  "${AUTH_FLAG}"
  "${ENV_ARGS[@]}"
  "${SECRET_ARGS[@]}"
)

hr
say "Deploying ${SERVICE} to Cloud Run in ${REGION}..."
gcloud run deploy "${SERVICE}" "${DEPLOY_ARGS[@]}"

URL="$(gcloud run services describe "${SERVICE}" --region="${REGION}" --format='value(status.url)')"

hr
say "✅ Deployed"
say "Service URL: ${URL}"
if [[ "${ALLOW_UNAUTH}" == "true" ]]; then
  say "Public access enabled. Try:  curl -s ${URL}"
else
  ACC="$(gcloud config get-value account 2>/dev/null || true)"
  say "🔒 IAM-protected. Grant yourself access (example):"
  say "  gcloud run services add-iam-policy-binding ${SERVICE} --region=${REGION} \\"
  say "    --member='user:${ACC}' --role='roles/run.invoker'"
  say "Then open: ${URL}"
fi
