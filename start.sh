#!/usr/bin/env bash
set -euo pipefail

REGION="${REGION:-europe-west3}"
SERVICE="${SERVICE:-dnaprofiler}"

say(){ printf "%b\n" "$*"; }
hr(){ printf "%s\n" "----------------------------------------"; }

need_cmd(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1"; exit 127; }; }
need_cmd gcloud

choose_project() {
  local PROJECT_ID_CUR
  PROJECT_ID_CUR="$(gcloud config get-value project 2>/dev/null || true)"
  if [[ -n "$PROJECT_ID_CUR" && "$PROJECT_ID_CUR" != "(unset)" ]]; then
    say "Detected active project: $PROJECT_ID_CUR"
    read -rp "Use this project? [Y/n]: " yn
    yn=${yn:-Y}
    if [[ "$yn" =~ ^[Yy]$ ]]; then echo "$PROJECT_ID_CUR"; return; fi
  fi

  mapfile -t PROJS < <(gcloud projects list --format="value(projectId)")
  if [[ "${#PROJS[@]}" -eq 0 ]]; then
    say "No projects found. Let's create one."
    local TS pid pname ORG_ID BILL
    TS="$(date +%y%m%d%H%M%S)"
    read -rp "Project ID [dnaprofiler-${TS}]: " pid; pid="${pid:-dnaprofiler-${TS}}"
    read -rp "Project Name [DNA Profiler]: " pname; pname="${pname:-DNA Profiler}"
    ORG_ID="$(gcloud organizations list --format='value(ID)' 2>/dev/null | head -n1 || true)"
    if [[ -n "$ORG_ID" ]]; then
      gcloud projects create "$pid" --name="$pname" --organization="$ORG_ID"
    else
      gcloud projects create "$pid" --name="$pname"
    fi
    mapfile -t BILLS < <(gcloud beta billing accounts list --format="value(ACCOUNT_ID)" --filter="OPEN=True")
    if [[ "${#BILLS[@]}" -eq 0 ]]; then
      say "⚠️  No open billing accounts found. Link one later, then re-run."
      exit 1
    fi
    BILL="${BILLS[0]}"
    gcloud beta billing projects link "$pid" --billing-account="$BILL"
    echo "$pid"; return
  fi

  if [[ "${#PROJS[@]}" -eq 1 ]]; then
    echo "${PROJS[0]}"; return
  fi

  say "Select a project:"
  for i in "${!PROJS[@]}"; do printf "%2d) %s\n" "$((i+1))" "${PROJS[$i]}"; done
  read -rp "Choice [1-${#PROJS[@]}]: " sel
  echo "${PROJS[$((sel-1))]}"
}

main() {
  hr; say "DNA Profiler – Guided Setup"
  PROJECT_ID="$(choose_project)"
  gcloud config set project "${PROJECT_ID}" >/dev/null

  hr; say "Enabling required services..."
  gcloud services enable run.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com

  hr; say "Deploying..."
  chmod +x oneclick.sh
  ./oneclick.sh -p "${PROJECT_ID}" -r "${REGION}" -s "${SERVICE}"
}
main "$@"
