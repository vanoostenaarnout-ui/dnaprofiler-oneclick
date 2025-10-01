DNA Profiler — One-Click Deploy (GCP)

Fast, trustworthy data profiling & matching for migrations, quality, and MDM—deploy to Google Cloud Run in minutes, secure by default.

<a target="_blank" rel="noopener noreferrer" href="https://ssh.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/vanoostenaarnout-ui/dnaprofiler-oneclick.git&cloudshell_git_branch=main&cloudshell_tutorial=TUTORIAL.md&cloudshell_open_in_editor=start.sh"> <img alt="Open in Google Cloud Shell" src="https://gstatic.com/cloudssh/images/open-btn.png" /> </a>
Why DNA Profiler?

See truth fast: profile large CSV/Parquet datasets quickly with a Go-powered engine optimized for speed.

Ship with confidence: surface schema, type inference, anomalies, outliers, and data-quality failures before they hit production.

Kill dupes early: optional matching/deduplication and entity resolution help collapse duplicates and link entities across files.

Fit your stack: containerized HTTP service for Cloud Run/App Runner/ACA, plus a CLI for local batch runs.

Own your data: runs in your cloud project, with IAM-protected defaults.

Capabilities (at a glance)

Profiling & statistics

Field distributions, nulls/empties, min/max/length histograms

Type & format inference (dates, numbers, emails, phones, etc.)

Outlier & anomaly hints for rapid triage

Data Quality

Configurable DQ rules (required/unique/range/regex/format)

Fail-fast option for pipelines; structured JSON reports for CI

Pluggable regex library (extend your field/MDM rules)

Matching / Entity Resolution (optional)

Fuzzy/exact strategies with stable keys

Dedupe within files; link entities across files (ER mode)

Scores + explainability trail (what matched & why)

Outputs

JSON and CSV summaries; downloadable detail files

Ready for dashboards, notebooks, or automated gates

Operations

Stateless container; horizontal scaling on Cloud Run

Security by default (IAM only, unless you explicitly allow public)

What this repo contains

This is the installer for a frictionless, one-click deployment:

start.sh — guided setup (auto-detects/creates project, enables APIs)

oneclick.sh — deploys the service to Cloud Run

TUTORIAL.md — step-by-step instructions with copy-paste commands

The application image is published separately to GHCR:
ghcr.io/vanoostenaarnout-ui/erengine:latest
(You can later mirror to ghcr.io/dnahub/erengine:latest and update the scripts.)

One-click Quickstart

Click Open in Google Cloud Shell (above).

In the terminal:

chmod +x start.sh oneclick.sh
./start.sh


The wizard will:

Detect or help you create a GCP project

Enable required APIs (run.googleapis.com, artifactregistry.googleapis.com, cloudbuild.googleapis.com)

Deploy the service on Cloud Run

The script prints your Service URL. Since we default to IAM-protected:

gcloud run services add-iam-policy-binding dnaprofiler \
  --region=europe-west3 \
  --member="user:$(gcloud config get-value account)" \
  --role="roles/run.invoker"


Prefer no wizard?

./oneclick.sh -p "<YOUR_PROJECT_ID>" -r "europe-west3" -s "dnaprofiler"
# or pin the exact image:
./oneclick.sh -p "<YOUR_PROJECT_ID>" -i "ghcr.io/vanoostenaarnout-ui/erengine:latest"

Configuration

You can pass env vars (comma-separated) and secrets at deploy time:

Setting	How	Notes
Region	-r europe-west3	Change to your preferred region
Service name	-s dnaprofiler	Any valid Cloud Run service name
Image	-i ghcr.io/...:tag	Public GHCR tag or digest
Env vars	--env "LOG_LEVEL=info,FEATURE_X=1"	For feature flags & tuning
License key	-l "<YOUR_LICENSE>"	Stored in Secret Manager as LICENSE_KEY
Public access	--allow-unauth	Not recommended by default
Licensing

This software is proprietary and licensed by DNAHub Ltd.

You may deploy for evaluation in your own cloud.

Production use requires a license key. If your build enforces a key, provide it during deploy:

./oneclick.sh -l "<YOUR_LICENSE_KEY>"


The key is stored in Secret Manager and exposed to the container as LICENSE_KEY.

Need a key or pricing? Contact: licensing@dnahub.example

(Replace with your real contact page/email.)

Security & Privacy

IAM-protected by default (no public access unless you opt in).

Secrets via Secret Manager (not plain envs).

Runs entirely in your GCP project; data stays in your environment.

For private networks: front with a private load balancer and set Cloud Run ingress accordingly.

Roadmap

Azure one-click (Azure Container Apps)

AWS one-click (App Runner)

Prebuilt Terraform for enterprise baselines (VPC, LB, policies)

Troubleshooting

403 on service URL → grant roles/run.invoker to your user (see Quickstart).

Cannot enable services → your account lacks permissions; ask a project owner to enable run, artifactregistry, cloudbuild.

Script “permission denied” → run bash oneclick.sh; ensure *.sh has LF endings and exec bit (we ship .gitattributes + set the bit in git).

Image pull fails → ensure the GHCR package is Public (Package → Settings → Danger Zone → Change visibility: Public).

License

Copyright © 2025 DNAHub Ltd.
All rights reserved. See LICENSE for terms.