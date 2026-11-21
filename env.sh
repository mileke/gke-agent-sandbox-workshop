export PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
if [ -z "$PROJECT_ID" ]; then
  echo "ERROR: no project selected. Run: gcloud config set project YOUR_PROJECT_ID"
  return 1 2>/dev/null || exit 1
fi
export PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
export REGION=us-central1
export ZONE=us-central1-a
export CLUSTER=gke-lab
export IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/agent-repo/data-agent:v1"
echo "Project: $PROJECT_ID  Cluster: $CLUSTER ($ZONE)"
