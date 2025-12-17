# Homelab Edge Security


### Multi layered security approach to securty

### 🧠 CrowdSec + Raspberry Pi Bouncer

✔ **What it does**
- Behavioral detection (brute force, scanners, bots)
- Global & local threat intelligence
- Blocks at **Layer 3 / 4**
- Drops traffic before it reaches Kubernetes

✔ **What it does NOT do**
- ❌ No login screens
- ❌ No authentication
- ❌ No user management

📌 CrowdSec answers:
> “Is this IP behaving maliciously?”

---

### 🔐 Authentik 

✔ **What it does**
- Single Sign-On (SSO)
- MFA / Passkeys
- Identity management
- Application-level access control (Layer 7)

✔ **What it does NOT do**
- ❌ Does not block scanners or bots by itself
- ❌ Does not stop raw TCP abuse

📌 Authentik answers:
> “Is this user allowed to access this app?”

---
## 1. Crowdsec

### What is CrowdSec?
CrowdSec is an **open-source intrusion prevention system** designed to protect against attacks like:
- Brute-force login attempts
- Credential stuffing
- Scanners and bots
- Suspicious IPs identified via community threat intelligence

CrowdSec works in **two main layers**:
1. **Detection (Cluster agent)**: Parses logs (Traefik, Nextcloud, Immich, SSH etc), runs scenarios to detect malicious behavior, sends decisions to LAPI.
2. **Enforcement (Bouncer, on Pi edge)**: Receives decisions from LAPI, blocks malicious IPs at network layer, keeps cluster and apps safe while allowing legitimate traffic.

### Why deploy this on a dedicated Raspberry Pi?
- Blocks malicious IPs **before they reach Traefik**.
- Legitimate uploads flow uninterrupted.
- Cluster resources remain free.
- Provides **physical isolation** for network security.

### Architecture Diagram

```
         ┌───────────────┐
         │   Internet    │
         └──────┬────────┘
                │
      ┌─────────▼──────────┐
      │ Raspberry Pi Edge  │
      │ CrowdSec Bouncer   │
      └─────────┬──────────┘
                │
        ┌───────▼─────────┐
        │ k3s Cluster     │
        │ CrowdSec Agent  │
        │ Traefik Ingress │
        └───────┬─────────┘
                │
  ┌─────────────▼─────────────────┐
  │ Nextcloud | Immich | WordPress│
  └───────────────────────────────┘
```

✅ **Key Takeaways**:
- Pi: Dedicated edge node, enforces network-level blocking  
- Cluster: CrowdSec agent for detection  
- Traffic flow: Malicious requests blocked before hitting apps  
- Uploads: Large media transfers fully unaffected  
- Monitoring: Metrics and logs for visibility and troubleshooting  
- Maintenance: Weekly updates, log monitoring, backups  
---

## 2. Hashicorp Vault
Coming...

--- 


## 3. Authentik


```yaml
      ┌───────────────┐
      │   Internet    │
      └───────┬───────┘
              │
    ┌─────────▼─────────┐
    │ Pi Edge: Bouncer  │
    └─────────┬─────────┘
              │
    ┌─────────▼───────────────┐
    │   Traefik Ingress       │
    │ Authentik FW Middleware │
    └──────────┬──────────────┘
               │
┌──────────────▼─────────────────────┐
│ Apps: Nextcloud, Immich, WordPress │
└────────────────────────────────────┘

```
Coming...

--- 
