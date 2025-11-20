
# K3s Cluster Documentation ✍️

Hey there 👋

✍️ Welcome to my K3s cluster documentation repository! This repo contains all guides, playbooks, and notes for spinning up and managing my home Kubernetes (K3s) cluster.

---

## Cluster Overview

This K3s cluster is designed for home lab experimentation, DevOps projects, and learning Kubernetes in a controlled environment. The cluster comprises **3 nodes**, each carefully selected for balance between performance and energy efficiency:

| Node Name | Role                      | Specs                                                 |
|-----------|---------------------------|-------------------------------------------------------|
| Tywin     | Master/Server             | Intel NUC, Intel i3-5010U, 16GB RAM, 256GB NVME       |
| Jaime     | Worker                    | Lenovo M93, Intel i5-4570T, 16GB RAM, 512GB 2.5" SSD  |
| Tyrion    | Worker                    | Lenovo M93, Intel i5-4570T, 16GB RAM, 512GB 2.5" SSD  |
| Cersei    | Worker                    | Lenovo M93, Intel i5-4570T, 16GB RAM, 512GB 2.5" SSD  | #Still being built. Not yet live
| Varys     | Ansible / kubectl host    | Raspberry Pi 3B+, 1GB RAM, 128GB 2.5" SSD             | 


*Bonus Node / Local Dev Host:*  
- **RPi** – Raspberry Pi running `kubectl` for cluster management and dev/test purposes.

---

## Why “Lannisters” for Node Names?

Inspired by *Game of Thrones*, the cluster nodes are named after members of House Lannister. Why Lannisters?  

- **Tywin** – Master node, the strategic leader of the cluster.  
- **Jaime** – Worker node, strong and dependable, always executing tasks efficiently.  
- **Tyrion** – Worker node, clever and versatile, handling dynamic workloads with intelligence.  

House Lannister is known for its power, influence, and cunning strategy — just like a well-planned, resilient K3s cluster.  

---

## Ansible-Powered Cluster Deployment

All cluster setup and node preparation are handled via **Ansible**. The playbooks in this repo will:

- Update the OS on all server nodes  
- Install necessary packages, including Ansible itself  
- Configure server nodes for Kubernetes readiness  
- Deploy K3s and essential components like Longhorn and Cert-Manager  

### Why Ansible?

Ansible is a powerful automation tool for configuration management, orchestration, and application deployment. Its key benefits include:

- **Agentless** – No software needs to run on the managed nodes; everything is done over SSH.  
- **Idempotent** – Running the playbooks multiple times produces consistent results without breaking your setup.  
- **Readable & Maintainable** – Written in YAML, making it easy to read, share, and modify.  
- **Scalable** – Can manage a handful of nodes or hundreds, all using the same playbooks.  

Using Ansible ensures a repeatable, reliable, and fully automated cluster setup process.

## 🔄 To-Do / Future Plans

- [ ] Complete 3rd node build - Cersei
- [ ] Replace all worker node CPUs. From i5-4570T to Xeon E3-1260l v3.


---
--

    > *“A Lannister always pays his debts… and in this cluster, every deployment always succeeds.”* 🙏
