# NetAutober 2025 Hackathon 🚀

Welcome to the **NetAutober 2025 Hackathon**!  
This repo is your launchpad for building, automating, and monitoring network systems with Terraform, Ansible, Python, Docker, Kubernetes, and more.  

---
## ⚠️ Disclaimer

Didn’t find the tool you want to use? Go ahead, install it and use it!
Don’t want to use Codespaces? No problem — use your local setup. Just make sure you:

Install all the tools yourself, or

Use the postCreate.sh under .devcontainer for a quick install.

Codespaces can sometimes be tricky, and we totally understand if you prefer your own environment.
👉 The only requirement: make a Pull Request to showcase your work.

---

## 🎯 Philosophy

This hackathon is not a competition.

No grades.

No bonus marks if you use a certain tool.

No penalties if you do things your way.

This is real-life NetOps: if your solution works, it’s good! 🎉

---

## ⚡ Getting Started with Codespaces

We’ve set up ready-to-use environments for you — no need to fight with installs!

1. Go to the green **`<> Code`** button in this repo.  
2. Select the **Codespaces** tab.  
3. Click **“… → New with options”**.  
4. Choose:  
   - Your **branch**  
   - Your **Hackathon level** (Beginner, Intermediate, Expert).
  
NOTE: Use 4 core in Beginner level else 3 router will NOT work in codespace use to lack of RAM. Once you start your level there is no way to upgrade the RAM unless you destroy the codespace!

---

## 📝 Contribution Workflow

- Create a new fork with the format: (participantname)-(level)

    - alice-beginner
    - raj-intermediate
    - fatima-expert

- Inside the repo, create a folder with **your name** under /workspace. All your work for the task goes there. Create a PR after finished.

- If you have time, add a **mini README.md** inside your folder explaining:  
- What you built  
- How it works  
- Any gotchas or lessons learned  

---

## 🏆 Rewards & Recognition

- **Finishers** will get a **shoutout on the NetAuto LinkedIn page** 🎉  
- If you’re up for it, you’ll also be invited to **present your solution** at the upcoming **NetAuto event**.  
This is your chance to showcase your skills to the community!  

---

## 📚 Hackathon Tasks

### 🟢 Beginner – Automate IP Addressing & Verify Connectivity

- **Deploy** a 3-router topology (Nokia/Arista) with Containerlab.  
- **Configure** IPs and static routes using Ansible modules [Custom ansible collection for SR LInux](https://github.com/NetOpsChic/srlinux-ansible-collection#) but this collection is not listed in ansible galaxy collection so make sure you install it properly. If not use python either is fine.
- **Validate** end-to-end connectivity with a Python ping script.  

🔑 Skills covered:  
Containerlab, Ansible basics, Python scripting

---

### 🟡 Intermediate – Monitor Linux VMs with Docker Compose

- **Provision** a AWS Ubuntu VMs using Terraform and ansible 
- **Install & Configure** exporters (Node Exporter + Promtail) with Ansible.  
- **Deploy** a monitoring stack (Prometheus, Loki, Grafana) using Docker Compose.  
- **Validate** with Python (Prometheus API & Loki API).  
- **Visualize** system metrics and logs in Grafana dashboards.  

🔑 Skills covered:  
AWS, Terraform, Ansible, Observability (Prometheus, Grafana, Loki), Docker.  

---

### 🔴 Expert – Cloud Router + Kubernetes FRR Pod Peering (GitOps Workflow)

- **Provision** an AWS EC2 “cloud router” and a **Kubernetes FRR pod**.  
- **Configure** BGP peering between them using Ansible.  
- **Validate** route exchange with Python.  
- **Automate** the entire workflow (if you wish something else? Go ahead).  

🔑 Skills covered:  
AWS networking, Kubernetes, FRR, BGP, Ansible, Terraform, GitOps CI/CD pipelines.  

---

✨ Hack, automate, break things (and fix them), and most importantly — **learn by building**.  
