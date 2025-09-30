#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# DNA Profiler / ER Engine — one-click Cloud Run deploy
# Usage (typical):
#   ./deploy/oneclick.sh -p YOUR-PROJECT -r europe-west3 -s erengine \
#     -i gcr.io/the-tree-beneath-400715/erengine:latest --allow-unauth
#
# Or build from source (Dockerfile in repo):
#   ./deploy/oneclick.sh -p YOUR-PROJECT -r europe-west3 -s erengine --build
#
# Optionally pass a license value at deploy time:
#   ./deploy/oneclick.sh ... -l "YOUR-LICENSE-STRING"
# ------------------------------------------------------------

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
REGION="${REGION:-europe-west3}"
SERVICE="erengine"
IMAGE=""            # e.g. gcr.io/public-project/erengine:latest
LICENSE_VALUE=""    # if provided, we'll create/overwrite the secret
ALLOW_UNAUTH=false
BUILD_IMAGE=false
REPO="apps"         # Artifact Registry repo name if building
CPU="1"
MEM="512Mi"
CONCURRENCY="80"
MIN_INSTANCES="0"
MAX_INSTANCES="3"
PORT="8080"
SECRET_NAME="dna-profiler-license"

usage() {
  cat <<EOF
Usage: $0 -p PROJECT_ID -r REGION -s SERVICE [options]

Required:
  -p  GCP project id
  -r  Region (default: ${REGION})
  -s  Cloud Run service name (default: ${SERVICE})

Options:
  -i  Container image to deploy (skips build if set)
  -l  License value to store in Secret Manager (${SECRET_NAME})
  --allow-unauth       Make service public (no auth)
  --build              Build image from the repo Dockerfile into Artifact Registry
  --cpu N              vCPU (default: ${CPU})
  --mem SIZE           Memory (default: ${MEM})
  --concurrency N      Concurrency (default: ${CONCURRENCY})
  --min N              Min instances (default: ${MIN_INSTANCES})
  --max N              Max instances (default: ${MAX_INSTANCES})
  --port N             Container port (default: ${PORT})
  -h, --help           Show help
EOF
  exit 1
}

# parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p) PROJECT_ID="$2"; shift 2;;
    -r) REGION="$2"; shift 2;;
    -s) SERVICE="$2"; shift 2;;
    -i) IMAGE="$2"; shift 2;;
    -l) LICENSE_VALUE="$2"; shift 2;;
    --allow-unauth) ALLOW_UNAUTH=true; shift;;
    --build) BUILD_IMAGE=true; shift;;
    --cpu) CPU="$2"; shift 2;;
    --mem) MEM="$2"; shift 2;;
    --concurrency) CONCURRENCY="$2"; shift 2;;
    --min) MIN_INSTANCES="$2"; shift 2;;
    --max) MAX_INSTANCES="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

if [[ -z "${PROJECT_ID}" ]]; then
  echo "ERROR: project id not set (-p)."
  usage
fi

echo ">>> Project: ${PROJECT_ID}"
echo ">>> Region : ${REGION}"
echo ">>> Service: ${SERVICE}"

gcloud config set project "${PROJECT_ID}" >/dev/null

echo ">>> Enabling required APIs (idempotent)..."
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  cloudbuild.googleapis.com \
  logging.googleapis.com \
  --project "${PROJECT_ID}"

SA_NAME="${SERVICE}-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if ! gcloud iam service-accounts describe "${SA_EMAIL}" --project "${PROJECT_ID}" >/dev/null 2>&1; then
  echo ">>> Creating service account: ${SA_EMAIL}"
  gcloud iam service-accounts create "${SA_NAME}" \
    --display-name "${SERVICE} runtime" \
    --project "${PROJECT_ID}"
fi

echo ">>> Ensuring Secret Manager secret: ${SECRET_NAME}"
if ! gcloud secrets describe "${SECRET_NAME}" --project "${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud secrets create "${SECRET_NAME}" --replication-policy=automatic --project "${PROJECT_ID}"
fi

# Grant the runtime SA access to the secret
gcloud secrets add-iam-policy-binding "${SECRET_NAME}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/secretmanager.secretAccessor" \
  --project "${PROJECT_ID}" >/dev/null

# If a license value is provided, add it as the latest version (overwrites via new version)
if [[ -n "${LICENSE_VALUE}" ]]; then
  echo -n "${LICENSE_VALUE}" | gcloud secrets versions add "${SECRET_NAME}" \
    --data-file=- --project "${PROJECT_ID}" >/dev/null
fi

# Build image if requested and IMAGE not explicitly provided
if [[ "${BUILD_IMAGE}" == true ]]; then
  REPO_LOCATION="${REGION}"
  REPO_NAME="${REPO}"
  AR_REPO="${REPO_LOCATION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}"
  if ! gcloud artifacts repositories describe "${REPO_NAME}" --location="${REPO_LOCATION}" --project "${PROJECT_ID}" >/dev/null 2>&1; then
    echo ">>> Creating Artifact Registry repo: ${REPO_NAME} (${REPO_LOCATION})"
    gcloud artifacts repositories create "${REPO_NAME}" \
      --location="${REPO_LOCATION}" \
      --repository-format=docker \
      --description="App images" \
      --project "${PROJECT_ID}"
  fi

  IMAGE="${AR_REPO}/${SERVICE}:$(date +%Y%m%d-%H%M%S)"
  echo ">>> Building image to ${IMAGE}"
  gcloud builds submit --tag "${IMAGE}" --project "${PROJECT_ID}"
elif [[ -z "${IMAGE}" ]]; then
  echo "ERROR: No image specified (-i) and --build not set."
  exit 2
fi

echo ">>> Deploying to Cloud Run..."
DEPLOY_FLAGS=(
  --project "${PROJECT_ID}"
  --region "${REGION}"
  --image "${IMAGE}"
  --service-account "${SA_EMAIL}"
  --port "${PORT}"
  --cpu "${CPU}"
  --memory "${MEM}"
  --concurrency "${CONCURRENCY}"
  --min-instances "${MIN_INSTANCES}"
  --max-instances "${MAX_INSTANCES}"
  --set-secrets "DNA_PROFILER_LICENSE=${SECRET_NAME}:latest"
)

if [[ "${ALLOW_UNAUTH}" == true ]]; then
  DEPLOY_FLAGS+=(--allow-unauthenticated)
fi

gcloud run deploy "${SERVICE}" "${DEPLOY_FLAGS[@]}"

URL="$(gcloud run services describe "${SERVICE}" --region "${REGION}" --format='value(status.url)')"
echo ">>> Deployed: ${URL}"
echo "Done."
