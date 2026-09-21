#!/usr/bin/env bash
# One-time setup for GitHub Actions -> GCS pushes via Workload Identity
# Federation, for the Pastiche website.
#
# Same project, Workload Identity pool and OIDC provider as the other sites
# (blog, klimax, claude-status, porthole); this only adds a service account scoped
# to this repo. The load balancer, backend bucket and TLS certificate for
# pastiche.runlocal.dev are NOT created here: they live in gcp-load-balancer-bco.
#
# This script lives outside website/ on purpose, so it is never published.
#
# Run from a workstation with gcloud authenticated as the project owner. Every
# step is idempotent, so re-running is safe.

set -euo pipefail

# The `perso` gcloud configuration for this process only. The other scripts run
# `gcloud config configurations activate perso`, which silently changes your
# global default; this leaves it alone.
export CLOUDSDK_ACTIVE_CONFIG_NAME=perso

# ── Inputs ────────────────────────────────────────────────────────────
PROJECT_ID="personal-218506"
SA_NAME="gha-push-gcs-pastiche"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
# Not `pastiche.runlocal.dev`: a domain-named bucket needs Search Console
# ownership verification. See the backend bucket in gcp-load-balancer-bco/main.tf.
BUCKET="pastiche-runlocal-dev"
LOCATION="europe-west1"
WI_POOL="gitops-pool"                  # shared with the other sites
WI_PROVIDER="gh-provider"              # shared with the other sites
GH_REPO_OWNER="bcollard"
GH_REPO_NAME="pastiche"
BUCKET_ROLE="projects/${PROJECT_ID}/roles/claudecodebucketadmin"   # shared custom role

ACCOUNT="$(gcloud config get-value account 2>/dev/null)"
echo "→ Project: ${PROJECT_ID}"
echo "→ Account: ${ACCOUNT}"
echo "→ Bucket:  gs://${BUCKET}  (created only if missing)"
echo "→ SA:      ${SA_EMAIL}"
echo "→ Repo:    github.com/${GH_REPO_OWNER}/${GH_REPO_NAME}"
echo

# This changes IAM in the project, so make the identity explicit before going on.
# (gcloud may have several accounts and projects configured on one machine.)
if [[ "${1:-}" != "--yes" ]]; then
  read -r -p "Apply to project ${PROJECT_ID} as ${ACCOUNT}? [y/N] " answer
  [[ "${answer}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

# ── 0. The shared bucket-admin custom role must already exist ─────────
if ! gcloud iam roles describe "claudecodebucketadmin" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "→ Creating custom role ${BUCKET_ROLE}"
  gcloud iam roles create "claudecodebucketadmin" --project="${PROJECT_ID}" \
    --title="Static-site bucket admin" \
    --permissions="storage.buckets.get,storage.buckets.update,storage.objects.create,storage.objects.delete,storage.objects.get,storage.objects.list,storage.objects.update" \
    --stage=GA
else
  echo "✓ Custom role ${BUCKET_ROLE} already exists (reusing)"
fi

# ── 1. Service account ────────────────────────────────────────────────
if ! gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "→ Creating service account ${SA_NAME}"
  gcloud iam service-accounts create "${SA_NAME}" \
    --project "${PROJECT_ID}" \
    --display-name "GHA pusher · pastiche website"
else
  echo "✓ Service account ${SA_NAME} already exists"
fi

# ── 2. Grant the bucket-admin role ────────────────────────────────────
# NB: like the other sites this binds the role on the whole project, so the SA
# can write to every bucket in it, not only this one. Binding it on the bucket
# instead would be tighter. That is a deliberate deviation from the other sites,
# so test a deploy afterwards if you change it.
echo "→ Granting ${BUCKET_ROLE} to ${SA_NAME}"
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member "serviceAccount:${SA_EMAIL}" \
  --role "${BUCKET_ROLE}" \
  --condition=None \
  --quiet >/dev/null

# ── 3. The website bucket ─────────────────────────────────────────────
if ! gcloud storage buckets describe "gs://${BUCKET}" >/dev/null 2>&1; then
  echo "→ Creating bucket gs://${BUCKET}"
  gcloud storage buckets create "gs://${BUCKET}" \
    --project="${PROJECT_ID}" \
    --location="${LOCATION}" \
    --uniform-bucket-level-access
else
  echo "✓ Bucket gs://${BUCKET} already exists"
fi

echo "→ Ensuring the bucket is world-readable"
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
  --member="allUsers" --role="roles/storage.objectViewer" --quiet >/dev/null

echo "→ Ensuring website main page + 404"
gcloud storage buckets update "gs://${BUCKET}" \
  --web-main-page-suffix="index.html" \
  --web-error-page="404.html"

# ── 4. Workload Identity pool + provider (shared; normally already there) ─
if ! gcloud iam workload-identity-pools describe "${WI_POOL}" \
       --project="${PROJECT_ID}" --location="global" >/dev/null 2>&1; then
  echo "→ Creating Workload Identity pool ${WI_POOL}"
  gcloud iam workload-identity-pools create "${WI_POOL}" \
    --project="${PROJECT_ID}" --location="global" \
    --display-name="Personal GitOps pool"
else
  echo "✓ WI pool ${WI_POOL} already exists (reusing)"
fi

POOL_ID=$(gcloud iam workload-identity-pools describe "${WI_POOL}" \
  --project="${PROJECT_ID}" --location="global" --format="value(name)")

if ! gcloud iam workload-identity-pools providers describe "${WI_PROVIDER}" \
       --project="${PROJECT_ID}" --location="global" \
       --workload-identity-pool="${WI_POOL}" >/dev/null 2>&1; then
  echo "→ Creating OIDC provider ${WI_PROVIDER}"
  gcloud iam workload-identity-pools providers create-oidc "${WI_PROVIDER}" \
    --project="${PROJECT_ID}" --location="global" \
    --workload-identity-pool="${WI_POOL}" \
    --display-name="GitHub provider" \
    --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
    --issuer-uri="https://token.actions.githubusercontent.com"
else
  echo "✓ OIDC provider ${WI_PROVIDER} already exists (reusing)"
fi

# ── 5. Let this repo, and only this repo, impersonate the SA ──────────
echo "→ Allowing ${GH_REPO_OWNER}/${GH_REPO_NAME} to impersonate ${SA_NAME}"
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${POOL_ID}/attribute.repository/${GH_REPO_OWNER}/${GH_REPO_NAME}" \
  --condition=None \
  --quiet >/dev/null

PROVIDER_ID=$(gcloud iam workload-identity-pools providers describe "${WI_PROVIDER}" \
  --project="${PROJECT_ID}" --location="global" \
  --workload-identity-pool="${WI_POOL}" --format="value(name)")

echo
echo "✓ Setup complete."
echo
echo "── What .github/workflows/deploy-website.yaml must say ──────────"
echo "workload_identity_provider: ${PROVIDER_ID}"
echo "service_account:            ${SA_EMAIL}"
echo "bucket:                     gs://${BUCKET}"
echo
echo "Still to do, outside this repo:"
echo "  1. DNS: an A record for pastiche.runlocal.dev -> the load balancer IP"
echo "     (35.227.220.156), in the Cloud DNS zone runlocal-dev. That zone is not"
echo "     managed by gcp-load-balancer-bco."
echo "  2. Apply the pastiche changes in gcp-load-balancer-bco (backend bucket,"
echo "     managed certificate, host rule). The certificate takes 10-60 minutes to"
echo "     go ACTIVE, and only after the A record resolves."
echo "  3. Push to main, or run the workflow from the Actions tab."
