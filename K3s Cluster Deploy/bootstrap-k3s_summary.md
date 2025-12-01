## K3s Bootstrap Script Explained 📝

This Bash script automates the **initial setup of a K3s cluster** from a controller node. It ensures essential tools and services are installed in a consistent, automated way.

---

### Key Features

1. **Pre-checks**
   - Verifies required commands are installed: `kubectl`, `helm`, and `curl`.
   - Uses `set -euo pipefail` to fail on errors, unset variables, or pipeline failures.

2. **Pod Readiness Helper**
   - Function `wait_for_pods(namespace, timeout)` waits until all pods in a namespace are ready.
   - Ensures services are fully up before moving to the next step.

3. **Cert-Manager Installation**
   - Creates the `cert-manager` namespace.
   - Installs Cert-Manager v1.19.1 from the official GitHub manifest.
   - Waits for all pods to be ready.
   - **Purpose:** Provides certificate management for the cluster, including TLS for Ingress.

4. **MetalLB Installation**
   - Installs MetalLB for bare-metal load balancing.
   - Waits for `controller` and `speaker` pods to be ready.
   - Applies an IP pool (`10.0.10.110-10.0.10.130`) and L2 advertisement.
   - **Purpose:** Provides external IPs for services like Traefik or ArgoCD.

5. **Traefik Installation (via Helm)**
   - Adds Traefik Helm repository and updates it.
   - Creates `traefik` namespace.
   - Installs Traefik with custom values (`traefik-values.yaml`) and waits for pods to be ready.
   - **Purpose:** Acts as the Ingress controller for routing external traffic to cluster services.

6. **ArgoCD Installation**
   - Creates `argocd` namespace.
   - Installs ArgoCD from the official manifests.
   - Waits for all ArgoCD pods to be ready.
   - **Purpose:** Provides GitOps-based application deployment and cluster management.

---

### How It Works

1. **Checks** for required commands and ensures the script fails safely on errors.  
2. **Installs and configures core cluster services** in the correct order:
   - Cert-Manager → MetalLB → Traefik → ArgoCD  
3. **Ensures readiness** after each step before moving on.  
4. **Outputs progress messages** for clarity during execution.

---

✅ **Outcome:**  
After running this script, a K3s cluster is fully bootstrapped with TLS management (Cert-Manager), external load balancing (MetalLB), Ingress routing (Traefik), and GitOps deployment capabilities (ArgoCD), ready for production workloads.
