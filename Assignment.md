Technical Assessment for Al Nafi Devops department
🚀 We’re Hiring: OpenEdX on Kubernetes (AWS EKS) | Global Permanent Role (Onsite / Remote)
Location: Global (Remote or Onsite)
Employment Type: Permanent
Hiring Model: Direct Hiring via Technical Assessment
Cloud Platform: AWS ONLY

At Al Nafi, we are entering a decisive global expansion phase. As part of our 2026 global hiring blitz, we are opening 2,000+ permanent roles, covering 36+ core sectors and hundreds of specialized fields worldwide.

This post marks the official starting point of that expansion.

We are looking for professionals who can deliver production-grade platforms on AWS, demonstrate architectural clarity, and operate with enterprise discipline.

🧪 Mandatory Hiring Test
Technical Assessment: OpenEdX Deployment on Kubernetes (AWS EKS)
This task is a mandatory hiring test.
It is designed to evaluate real execution capability, not theoretical knowledge.

This assessment is used for hiring across:

DevOps Engineering
Platform Engineering
Cloud Architecture
SRE
Infrastructure Engineering
🎯 Objective
Deploy a production-ready OpenEdX Learning Management System on AWS EKS, following enterprise-grade architecture, security, scalability, and observability standards.

⚠️ Important:

This task MUST be completed on AWS EKS
Deployments on local Kubernetes, Minikube, Kind, K3s, or non-AWS platforms will not be accepted
🧱 Project Requirements (AWS EKS Only)
Core Platform
AWS EKS
OpenEdX deployed using Tutor (latest stable version)
tutor-k8s plugin for Kubernetes deployment
Namespace isolation for OpenEdX components
External Database Services (Mandatory & Offloaded)
All data services must be external to the Kubernetes cluster (AWS managed services or dedicated EC2 instances):

MySQL – Relational database for OpenEdX application data
MongoDB – Document store for course and user data
Elasticsearch – Search and analytics engine
Redis – In-memory cache and message broker
Databases must not run inside Kubernetes.

Web Server & Traffic Management
Replace default Caddy server with Nginx
Configure Nginx as reverse proxy for OpenEdX services
SSL/TLS termination at Nginx level
HTTP/2 enabled
Security & Performance Layer
AWS CloudFront (CDN) for static assets
AWS WAF integration
Rate limiting and basic DDoS protection
Platform & Operations
Persistent Volumes (PV/PVC) for uploads and media
Horizontal Pod Autoscaling (HPA) for LMS & CMS
Ingress Controller with clean routing rules
Centralized logging and monitoring (Prometheus/Grafana or equivalent)
Backup strategy for:
External databases
Persistent volumes
Liveness and readiness probes for all services
🏗️ Reference Architecture
Security Layer:
AWS WAF → CloudFront → AWS Load Balancer

Web Layer:
Nginx (Ingress Controller)

Application Layer:
OpenEdX LMS, CMS, Workers (EKS Pods)

Data Layer:
External MySQL, MongoDB, Elasticsearch, Redis

Storage Layer:
Persistent Volumes (PV/PVC)

📦 Deliverables
Documentation
Step-by-step deployment guide
Architecture diagram
Network flow diagram
Configuration decisions & rationale
Troubleshooting guide
Configuration Artifacts
Kubernetes manifests (YAML)
Tutor configuration files
Nginx configuration files
Helm charts (if used)
Database connection and initialization scripts
Ingress controller and ingress resources
Automation
Deployment automation scripts
Backup and restore scripts
Monitoring and alerting configurations
Proof of Implementation
Screenshots or recordings of the deployment
Evidence of AWS WAF and CloudFront integration
Load testing results demonstrating HPA
Logs showing healthy service and database connectivity
🧮 Evaluation Criteria
Area Weight
OpenEdX deployment on AWS EKS 20%
External database integration (all four) 20%
Nginx replacing Caddy 15%
AWS CDN & WAF implementation 15%
Documentation quality 15%
High availability & scalability 10%
Security best practices 5%
🌟 Bonus (Competitive Edge)
CI/CD pipeline implementation
GitOps (ArgoCD or Flux)
Service mesh (Istio or Linkerd)
Advanced observability dashboards
Disaster recovery & failover strategy
Cost optimization and resource quotas
Multi-environment setup (dev / staging / production)
⏰ Submission Deadline
📅 9 February 2026

Submit via a Git repository with a well-structured README.md.

📩 Submit your submissions to:
Email:

hamza.mughal@alnafi.com
mohammad@alnafi.com
Subject: OpenEdX K8s Assessment – AWS EKS

🌍 What This Leads To
This assessment is the entry gate into:

A permanent global role
Onsite or remote opportunities
Long-term growth with Al Nafi
Participation in a global hiring blitz launching in 2026
📈 2,000+ roles
🌐 36+ core sectors
🧠 Hundreds of specialized fields

🔗 Stay Connected
To stay informed about upcoming roles and hiring waves:

👉 Follow & connect with the Global CEO of Al Nafi
Muhammad Faisal
🔗 https://www.linkedin.com/in/muhamadfaisal
and on facebook Muhammad Faisal https://www.facebook.com/UmerBinAlKhatab313

We are about to begin the global blitz of filling contract and permanent positions worldwide.

If you can architect, deploy, secure, and scale on AWS EKS — this is your proving ground.
