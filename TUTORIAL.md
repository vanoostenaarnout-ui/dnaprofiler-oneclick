# Deploy DNA Profiler / ER Engine (One-Click)

This will deploy the service to **Cloud Run** in **your** Google Cloud project.
Default is **private access** (auth required). You will be granted access automatically.

---

## 1) Open in Cloud Shell
If you’re not already in Cloud Shell, click the **“Open in Cloud Shell”** button on our website. It will open this repo with the deploy script ready.

---

## 2) Run the script (zero-config)
In the terminal:

./deploy/oneclick.sh


The script will:
- Pick your current `gcloud` project (or ask you once).
- Enable required APIs.
- Create a runtime service account.
- Create/ensure a Secret Manager secret for the license.
- Deploy Cloud Run with a **prebuilt image** (fast).
- Keep the service **private** (IAM auth required).
- Grant you **Cloud Run Invoker** on the service.

> Want a different region?  
> `./deploy/oneclick.sh -r europe-west3`

> Want to pass a license value now?  
> `./deploy/oneclick.sh -l "YOUR-LICENSE-STRING"`

---

## 3) Open the service
At the end, the script prints a URL like:

https://YOUR-SERVICE-******-a.run.app


Because the service is **private**, only authorized users can call it.

- To test quickly from Cloud Shell:

TOKEN=$(gcloud auth print-identity-token)
curl -H "Authorization: Bearer $TOKEN" https://YOUR-SERVICE-******-a.run.app/health


- To add a colleague later:

gcloud run services add-iam-policy-binding erengine
--region europe-west3
--member "user:colleague@example.com"
--role "roles/run.invoker"

- **Build from source in your project:**
./deploy/oneclick.sh --build


- **Customize size/concurrency:**
./deploy/oneclick.sh --cpu 2 --mem 1Gi --concurrency 200 --min 0 --max 5


- **Restrict ingress to internal/LB patterns:**
./deploy/oneclick.sh --ingress internal-and-cloud-load-balancing

---

## Troubleshooting

- **Project not set:** The script will prompt once. You can also run:
gcloud config set project YOUR-PROJECT


- **Permission denied:** Ensure you have `Editor` or appropriate roles to create service accounts, secrets, and deploy Cloud Run.

- **Windows/PowerShell quoting issues:** Use **Cloud Shell** (Linux bash) to avoid `$VAR` quoting problems.

---

That’s it! If you need a custom domain or an external LB/IAP front-end, we can add a follow-on command.