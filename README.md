# DNA Profiler — One-Click Deploy (GCP)

**Fast, trustworthy data profiling & matching** for migrations, data quality, and MDM — deploy to **Google Cloud Run** in minutes, **secure by default**.

<p>
  <a target="_blank" rel="noopener noreferrer" href="https://ssh.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/vanoostenaarnout-ui/dnaprofiler-oneclick.git&cloudshell_git_branch=main&cloudshell_tutorial=TUTORIAL.md&cloudshell_open_in_editor=start.sh">
    <img alt="Open in Google Cloud Shell" src="https://gstatic.com/cloudssh/images/open-btn.png" />
  </a>
</p>

---

## 🔗 Quick links

- ▶️ **Deploy now:** click the button above, then run `./start.sh`
- 📦 **Container image:** `ghcr.io/vanoostenaarnout-ui/erengine:latest`
- 📘 **Tutorial:** `TUTORIAL.md`
- 🔒 **License:** proprietary — see `LICENSE`

---

## ✨ Why DNA Profiler

- **See truth fast** — Go-powered engine profiles large CSV/Parquet quickly.  
- **Quality you can trust** — schema/type inference, anomalies, outliers, and DQ rule failures.  
- **Reduce duplicates** — optional matching/dedupe + entity resolution with explainability.  
- **Own your data** — runs in *your* cloud project; defaults to **IAM-protected**.  
- **Two modes** — containerized HTTP service (Cloud Run/App Runner/ACA) and CLI for batch.

---

## 🧩 Capabilities at a glance

### Profiling & Stats
- Distributions, nulls, min/max, length histograms  
- Type & format inference (dates, numbers, email, phone, etc.)  
- Outlier/anomaly hints for rapid triage

### Data Quality
- Configurable **DQ rules** (required/unique/range/regex/format)  
- **Fail-fast** option; structured JSON for CI/CD gates  
- Extensible regex library (plug in your field/MDM rules)

### Matching / Entity Resolution *(optional)*
- Fuzzy/exact strategies with stable keys  
- Dedupe within files; link entities across files (ER mode)  
- Scores + “why it matched” trail

### Outputs
- JSON & CSV summaries + downloadable details  
- Ready for dashboards, notebooks, or automated checks

### Operations
- Stateless container; autoscaling on Cloud Run  
- **Secure by default** (no public access unless you opt in)

---

## 🚀 Quickstart (One-Click)

1. **Open Cloud Shell** with the button at the top of this page.  
2. In the Cloud Shell terminal:
   ```bash
   chmod +x start.sh oneclick.sh
   ./start.sh

### The wizard will

- Detect (or help create) a **GCP project**
- Enable APIs: `run.googleapis.com`, `artifactregistry.googleapis.com`, `cloudbuild.googleapis.com`
- Deploy to **Cloud Run**

After deploy, copy the printed **Service URL**. Because we default to IAM-only, grant yourself access:

```bash
gcloud run services add-iam-policy-binding dnaprofiler \
  --region=europe-west3 \
  --member="user:$(gcloud config get-value account)" \
  --role="roles/run.invoker"

