#!/usr/bin/env bash
set -euo pipefail

# Defaults (Andy can override with env or flags)
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-europe-west3}"
SERVICE_NAME="${SERVICE_NAME:-dnaprofiler}"

# Parse minimal flags (optional)
while getopts ":p:r:s:" opt; do
  case "$opt" in
    p) PROJECT_ID="$OPTARG" ;;
    r) REGION="$OPTARG" ;;
    s) SERVICE_NAME="$OPTARG" ;;
    \?) echo "Unknown option -$OPTARG" >&2; exit 2 ;;
    :)  echo "Option -$OPTARG requires an argument" >&2; exit 2 ;;
  esac
done

say() { printf "%b\n" "$*"; }
hr()  { printf "%s\n" "----------------------------------------"; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 127; }; }

need_cmd gcloud

choose_project() {
  # If PROJECT_ID already set (flag/env), just use it.
  if [[ -n "${PROJECT_ID}" ]]; then return; fi

  # If gcloud has a current project, offer to use it.
  CUR="$(gcloud config get-value project 2>/dev/null || true)"
  if [[ -n "$CUR" && "$CUR" != "(unset)" ]]; then
    say "Detected active project: $CUR"
    read -rp "Use this project? [Y/n]: " yn
    yn=${yn:-Y}
    if [[ "$yn" =~ ^[Yy]$ ]]; then PROJECT_ID="$CUR"; return; fi
  fi

  # List available projects
  mapfile -t PROJS < <(gcloud projects list --format="value(projectId)")
  COUNT="${#PROJS[@]}"

  if [[ "$COUNT" -eq 0 ]]; then
    say "No projects found under your account."
    create_project
    return
  fi

  if [[ "$COUNT" -eq 1 ]]; then
    PROJECT_ID="${PROJS[0]}"
    say "Using your only project: $PROJECT_ID"
    return
  fi

  say "Select a project:"
  for i in "${!PROJS[@]}"; do
    printf "%2d) %s\n" "$((i+1))" "${PROJS[$i]}"
  done
  printf "%2d) %s\n" "$((COUNT+1))" "Create a new project"
  read -rp "Enter choice [1-$((COUNT+1))]: " choice
  if [[ "$choice" -ge 1 && "$choice" -le "$COUNT" ]]; then
    PROJECT_ID="${PROJS[$((choice-1))]}"
  else
    create_project
  fi
}

create_project() {
  hr
  say "Let's create a new GCP project for you."

  # Build a globally unique ID: starts with a letter, lower-case
  TS="$(date +%y%m%d%H%M%S)"
  SUGGEST="dnaprofiler-${TS}"
  read -rp "Project ID [${SUGGEST}]: " pid
  PROJECT_ID="${pid:-$SUGGEST}"
  read -rp "Project Name [DNA Profiler]: " pname
  pname="${pname:-DNA Profiler}"

  # If you're in an org, attach it; otherwise create with no parent
  ORG_ID="$(gcloud organizations list --format='value(ID)' 2>/dev/null | head -n1 || true)"
  if [[ -n "$ORG_ID" ]]; then
    gcloud projects create "$PROJECT_ID" --name="$pname" --organization="$ORG_ID"
  else
    gcloud projects create "$PROJECT_ID" --name="$pname"
  fi

  # Link billing (try to auto-pick if only one open account)
  mapfile -t BILLS < <(gcloud beta billing accounts list --format="value(ACCOUNT_ID)" --filter="OPEN=True")
  if [[ "${#BILLS[@]}" -eq 0 ]]; then
    say ""
    say "⚠️  No open billing accounts found for your user."
    say "   Please create/assign a billing account in the Console, then run:"
    say "   gcloud beta billing projects link ${PROJECT_ID} --billing-account YOUR_BILLING_ACCOUNT_ID"
    exit 1
  elif [[ "${#BILLS[@]}" -eq 1 ]]; then
    BILLING_ACCOUNT="${BILLS[0]}"
  else
    say "Select a billing account to link:"
    for i in "${!BILLS[@]}"; do
      printf "%2d) %s\n" "$((i+1))" "${BILLS[$i]}"
    done
    read -rp "Enter choice [1-${#BILLS[@]}]: " bsel
    BILLING_ACCOUNT="${BILLS[$((bsel-1))]}"
  fi

  gcloud beta billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"
}

enable_services() {
  hr
  say "Enabling required services in $PROJECT_ID (may take ~1–2 min)..."
  set +e
  gcloud services enable \
    run.googleapis.com \
    artifactregistry.googleapis.com \
    cloudbuild.googleapis.com \
    --project "$PROJECT_ID"
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    say ""
    say "⚠️  Could not enable one or more services. This usually means your user lacks"
    say "   permission (Service Usage Admin) or org policy blocks it."
    say "   Ask a project/org admin to enable:"
    say "     run.googleapis.com, artifactregistry.googleapis.com, cloudbuild.googleapis.com"
    exit $rc
  fi
}

main() {
  hr
  say "DNA Profiler – Guided Setup"
  choose_project
  gcloud config set project "$PROJECT_ID" >/dev/null
  enable_services

  hr
  say "Deploying to Cloud Run..."
  ./oneclick.sh -p "$PROJECT_ID" -r "$REGION" -s "$SERVICE_NAME"
}
main "$@"
