# Run AI agents safely on GKE with Agent Sandbox

Workshop lab. You will deploy an ADK data-analysis agent on GKE. The Python code the agent writes runs in isolated gVisor sandboxes, a warm pool keeps them fast, and a network policy stops them reaching your project's credentials.

This repo is a tested, ready-to-run version of Google's codelab [AI agents on GKE](https://codelabs.developers.google.com/codelabs/gke/ai-agents-on-gke). Every file is already written for you, so you only run commands.

**Time:** about 45 minutes, most of it waiting for the cluster.
**You need:** a Google Cloud project with billing (your workshop credits), and Cloud Shell.

---

## Step 0: Open Cloud Shell and get the files

1. Open the [Google Cloud Console](https://console.cloud.google.com/) and select your workshop project at the top.
2. Click **Activate Cloud Shell** (the `>_` icon, top right).
3. Run:

```bash
gcloud config set project YOUR_PROJECT_ID
```

```bash
git clone https://github.com/mileke/gke-agent-sandbox-workshop.git ~/gke-agent-sandbox-workshop
cd ~/gke-agent-sandbox-workshop
source env.sh
```

You should see `Project: your-project-id  Cluster: gke-lab (us-central1-a)`.

> **Opened a new Cloud Shell tab, or it reconnected?** Run `cd ~/gke-agent-sandbox-workshop && source env.sh` again before carrying on. Every step below needs it.

---

## Step 1: Enable the APIs

```bash
gcloud services enable container.googleapis.com artifactregistry.googleapis.com \
  cloudbuild.googleapis.com aiplatform.googleapis.com
```

---

## Step 2: Create the cluster

A standard node pool runs the agent and the router. A second pool runs sandboxes under gVisor, which gives each sandbox its own kernel. `--enable-dataplane-v2` turns on network policy enforcement, which Step 6 needs.

```bash
gcloud container clusters create $CLUSTER --zone $ZONE \
  --num-nodes 2 --machine-type e2-standard-4 \
  --workload-pool=${PROJECT_ID}.svc.id.goog \
  --enable-dataplane-v2
```

This takes 5 to 10 minutes. Then add the gVisor pool:

```bash
gcloud container node-pools create sandboxed-pool --cluster $CLUSTER --zone $ZONE \
  --num-nodes 1 --machine-type e2-standard-4 \
  --image-type cos_containerd --sandbox type=gvisor
```

```bash
gcloud container clusters get-credentials $CLUSTER --zone $ZONE
kubectl get nodes
```

You should see 3 nodes, all `Ready`.

---

## Step 3: Install the Agent Sandbox controller

```bash
kubectl apply \
  -f https://github.com/kubernetes-sigs/agent-sandbox/releases/download/v0.1.0/manifest.yaml \
  -f https://github.com/kubernetes-sigs/agent-sandbox/releases/download/v0.1.0/extensions.yaml
```

```bash
kubectl get pods -n agent-sandbox-system
```

Wait until `agent-sandbox-controller-0` is `1/1 Running`.

---

## Step 4: Create the sandbox template and warm pool

The template describes one sandbox: a Python runtime with `runtimeClassName: gvisor`. The warm pool keeps 2 sandboxes started and waiting, so the agent never waits for a cold start.

```bash
kubectl apply -f k8s/sandbox-template-and-pool.yaml
kubectl get pods -w
```

Wait until two `python-sandbox-warmpool-…` pods are `1/1 Running`, then press `Ctrl+C`.

---

## Step 5: Deploy the sandbox router

The router forwards the agent's requests to the right sandbox.

```bash
kubectl apply -f k8s/sandbox-router.yaml
kubectl rollout status deployment/sandbox-router-deployment
```

---

## Step 6: Block sandboxes from your project's credentials

Any pod can ask the metadata server (`169.254.169.254`) for your project's details and access tokens. Code written by a model should not be able to. This policy applies to every sandbox pod (the agent and router pods have an `app` label, sandboxes don't). It blocks the `169.254.0.0/16` range, allows DNS to `kube-system`, and still allows normal internet access.

```bash
kubectl apply -f k8s/sandbox-policy.yaml
```

---

## Step 7: Build and deploy the agent

The agent is in `agent/root_agent/agent.py`. It is a Gemini agent with one tool that runs Python in a sandbox.

Create a registry and build the image (about 3 minutes):

```bash
gcloud artifacts repositories create agent-repo --repository-format=docker --location=$REGION
gcloud builds submit agent/ --tag $IMAGE
```

Let the agent's Kubernetes service account call Gemini, using Workload Identity (no keys):

```bash
gcloud projects add-iam-policy-binding projects/$PROJECT_ID \
  --role=roles/aiplatform.user \
  --member=principal://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$PROJECT_ID.svc.id.goog/subject/ns/default/sa/adk-agent-sa \
  --condition=None
```

Give the agent only the Kubernetes permissions it needs to claim sandboxes, then deploy it:

```bash
kubectl apply -f k8s/agent-rbac.yaml
envsubst < k8s/data-agent.yaml | kubectl apply -f -
kubectl rollout status deployment/data-agent
```

---

## Step 8: Use the agent

Get the agent's public IP. It can take a minute to appear. Run this until `EXTERNAL-IP` shows an address:

```bash
kubectl get service data-agent-service
```

Open `http://EXTERNAL-IP` in your browser. Pick **root_agent** in the top-left dropdown if it isn't selected, and send:

```text
Here is some inventory data in CSV format. Can you calculate the total value of all items in inventory?
product,quantity,msrp
Laptop,10,1200
Keyboard,50,75
Mouse,75,25
Monitor,20,300
Webcam,40,50
```

The agent writes pandas code, runs it in a sandbox, and answers **$25,625**. Click the tool call in the UI to see the code it ran.

---

## Step 9: Test the isolation

Ask the agent to read `/etc/shadow` or call the metadata server and Gemini will refuse. That is good, but it tests the model, not the sandbox. To test the sandbox itself, run code in one directly.

Run this in **Cloud Shell**, not in the ADK web UI. The script uses `kubectl` to claim a real sandbox and run four checks inside it:

```bash
cd ~/gke-agent-sandbox-workshop && ./scripts/test-isolation.sh
```

Expected:

```text
Kernel             4.19.0-gvisor
Host /etc/shadow   cat: /etc/shadow: Permission denied
Metadata server    urllib.error.URLError: <urlopen error timed out>
Public internet    200
```

| Line | What it shows |
|---|---|
| Kernel `…-gvisor` | The code runs on gVisor's kernel, not the node's. |
| `/etc/shadow` denied | The sandbox sees only its own filesystem. |
| Metadata server fails | The network policy blocks your project's credentials. |
| Public internet `200` | Everything else still works. |

---

## Step 10: Clean up

Delete everything so it stops costing money:

```bash
gcloud container clusters delete $CLUSTER --zone $ZONE --quiet
gcloud artifacts repositories delete agent-repo --location=$REGION --quiet
```

---

## If something goes wrong

| You see | Fix |
|---|---|
| `ERROR: no project selected` | Run `gcloud config set project YOUR_PROJECT_ID`, then `source env.sh`. |
| A command says a variable is empty, or an image path has `//` in it | Cloud Shell lost your variables. Run `cd ~/gke-agent-sandbox-workshop && source env.sh`. |
| `data-agent` pod in `ImagePullBackOff` | The build in Step 7 didn't finish. Run the `gcloud builds submit` line again, then `kubectl rollout restart deployment/data-agent`. |
| UI shows `403 PERMISSION_DENIED` from Gemini | The IAM binding in Step 7 takes a minute or two to apply. Wait, then send the prompt again. |
| `Insufficient project quota … CPUS_ALL_REGIONS` | The lab needs 12 vCPUs. Delete clusters or VMs you aren't using (`gcloud container clusters list`), then run the failed command again. |
| Warm pool pods stay `Pending` | The gVisor node pool isn't ready. Check `kubectl get nodes` shows 3 nodes. |

## What's different from the original codelab

- The router image the codelab pins was deleted from Google's staging registry. This repo uses a current router build, set to run without auth, as the original did.
- The codelab installs the sandbox client from GitHub `main`, which no longer matches its agent code. This repo pins the version that does.
- New projects can't call `gemini-2.5-flash`. This repo uses `gemini-3.8-flash` at the `global` location.
- The codelab's network policy matches no sandbox pods, and its cluster doesn't enforce network policy. Both are fixed here.
- The agent passes code to the sandbox base64-encoded, so the model doesn't have to avoid double quotes.
- Every file is in the repo, so there are no heredocs to paste and no empty `$PROJECT_ID` surprises.
