## Installation & Deployment Guide

```scss
Internet
   ↓
Router (port forward)
   ↓
Raspberry Pi (nftables + CrowdSec bouncer)
   ↓
Kubernetes Ingress (Traefik)
   ↓
Apps (Immich, Nextcloud, Jellyfin, etc.)
```
---

### Step 1: Prepare & Secure the Raspberry Pi (EDGE FIREWALL)
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install nftables -y
sudo systemctl enable nftables
sudo systemctl start nftables
```
- Set static IP and harden SSH (key-only auth). See SSH guide here.
- Apply basic nftables firewall rules allowing SSH, HTTP/HTTPS to cluster IP.
- *nftables* is the modern Linux firewall (replacement for iptables). CrowdSec will dynamically inject block rules into nftables.

| Traffic                   | Allowed? | Why             |
| ------------------------- | -------- | --------------- |
| SSH (22) from your LAN    | ✅        | Admin access    |
| HTTP (80) from internet   | ✅        | ACME / redirect |
| HTTPS (443) from internet | ✅        | Public services |
| Everything else           | ❌        | Attack surface  |

#### Create a real nftables ruleset
Edit the nftables config:
```bash
sudo nano /etc/nftables.conf
```
#### Replace *everything* with this:
```nft
#!/usr/sbin/nft -f

flush ruleset

table inet filter {

  chain input {
    type filter hook input priority 0;
    policy drop; #Default deny — if it’s not explicitly allowed, it’s blocked.

    # Allow loopback
    iif lo accept

    # Allow established connections
    ct state established,related accept #Allows return traffic (otherwise the internet breaks).

    # Allow SSH from LAN only
    ip saddr 10.0.10.0/24 tcp dport 22 accept #SSH only from your home LAN — not from the internet.

    # Allow HTTP & HTTPS from anywhere
    tcp dport {80, 443} accept #Public web traffic allowed.

    # Allow ICMP (ping)
    ip protocol icmp accept
  }

  chain forward {
    type filter hook forward priority 0;
    policy drop;
  }

  chain output {
    type filter hook output priority 0;
    policy accept;
  }
}

```
#### Apply & test firewall:
```bash
sudo nft -f /etc/nftables.conf
sudo nft list ruleset
```
---

### Step 2: Install CrowdSec Agent in Cluster (DETECTION)

#### What runs in the cluster?
    CrowdSec agent
        → Watches logs (Traefik, apps)

    LAPI (Local API)
        → Exposes ban decisions to the Pi

    The cluster detects, the Pi blocks.



1. Add Helm repo:
```bash
helm repo add crowdsec https://crowdsecurity.github.io/helm-charts
helm repo update
```

2. Create `values.yaml`:
```yaml
agent:
  enabled: true          # Run CrowdSec agent in cluster
  name: cluster-agent    # Agent name
  logLevel: info         # Normal verbosity
  parsers:
    enabled: true        # Enable parsing for logs (HTTP, auth, etc)
  scenarios:
    enabled: true        # Enable detection scenarios (bruteforce, scans)
lapi:
  enabled: true          # Enable API for Pi bouncer
  listenUri: "http://0.0.0.0:8080"
  apiKey: "<generate-with-cscli>"
```
Why LAPI is enabled:
Your Pi bouncer needs a single API endpoint to ask:

“Is this IP banned?”

3. Deploy:
```bash
helm install crowdsec crowdsec/crowdsec-agent -f values.yaml
kubectl get pods 
```
---

### Step 3: Install Firewall Bouncer on Raspberry Pi (ENFORCEMENT)
```bash
sudo apt install crowdsec-firewall-bouncer-nftables -y
```
Configure bouncer:
```bash
sudo nano /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml
```

```yaml
mode: nftables
api_key: "<same-key-as-lapi>"
url: "http://<cluster-lb-ip>:8080"  #MetalLB-assigned Service IP of the CrowdSec LAPI service
```
Enable and start:
```bash
sudo systemctl enable crowdsec-firewall-bouncer
sudo systemctl start crowdsec-firewall-bouncer
sudo journalctl -u crowdsec-firewall-bouncer -f
sudo cscli decisions list
```

---

### Step 4: Configure Log Sources in Cluster
CrowdSec is useless without logs.

- Traefik access logs:
```yaml
additionalArguments:
  - "--accesslog=true"
  - "--accesslog.format=json"
```
This enables:

 - Bruteforce detection
 - Path scanning detection
 - Rate abuse detection

---

### Step 5: Test & Validate
- Normal access → allowed
- Simulated failed login → banned by bouncer
- Confirm uploads for Immich / Nextcloud unaffected.

    1. Trigger multiple failed logins
    2. Check CrowdSec:

```bash
kubectl logs <crowdsec-pod>
```
    3. Check Pi:
    
```bash
sudo cscli decisions list
```    
---

### Step 6: Monitoring & Maintenance
- node_exporter on Pi for Prometheus metrics
- Optional: Uptime Kuma
- Update OS and CrowdSec weekly:
```bash
sudo apt update && sudo apt upgrade -y
cscli update
cscli hub update
```
- Backup Pi firewall rules and bouncer config

#### Maintenance:

| Task                 | Why                   |
| -------------------- | --------------------- |
| OS updates           | Kernel & nft fixes    |
| CrowdSec hub update  | New attack signatures |
| Backup nftables.conf | Disaster recovery     |
