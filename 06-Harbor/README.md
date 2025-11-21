# Harbor Container Registry

## What is Harbor?

Harbor is an open-source, enterprise-grade container registry that extends the open-source Docker Distribution by adding the functionalities usually required by enterprises, such as security, identity, and management. Harbor is designed to help organizations consistently and securely manage container images and Helm charts across cloud-native compute platforms like Kubernetes and Docker.

### Key Characteristics

**Type**: Cloud-native container registry  
**License**: Apache License 2.0  
**Original Author**: VMware (now part of Broadcom)  
**Written in**: Go  
**First Release**: 2016  
**Current Status**: CNCF Graduated Project

---

## CNCF Status and Recognition

### 🎓 CNCF Graduated Project

Harbor is officially recognized by the Cloud Native Computing Foundation (CNCF) and has achieved **Graduated status**, which is the highest level of maturity in the CNCF ecosystem.

#### CNCF Journey Timeline

- **March 2018**: Harbor accepted as CNCF Sandbox project
- **November 2018**: Harbor promoted to CNCF Incubating project
- **June 2020**: Harbor graduated from CNCF Incubation

### What Does "Graduated" Status Mean?

CNCF Graduated projects have demonstrated:

1. **Production Adoption**: Used successfully in production environments by multiple organizations
2. **Healthy Growth**: Active contributor community and consistent development activity
3. **Best Practices**: Adherence to CNCF best practices for open-source projects
4. **Sustainability**: Long-term commitment to project health and community engagement
5. **Vendor Neutral**: Independent governance free from single-vendor control

### Industry Recognition

Harbor is one of the few container registries to achieve CNCF Graduated status, placing it alongside other graduated projects like:
- Kubernetes
- Prometheus
- Envoy
- Helm
- containerd

This makes Harbor a **recommended and trusted choice** for enterprise container registry needs within the cloud-native ecosystem.

---

## Why Harbor? Core Value Propositions

### 1. Security First

**Image Vulnerability Scanning**
- Integrated Trivy scanner for CVE detection
- Automatic scanning on image push
- Scan results visible in UI
- Configurable policies to prevent vulnerable images from running

**Content Trust & Image Signing**
- Integration with Notary for Docker Content Trust
- Ensure images are signed and verified
- Cryptographic validation of image publishers

**RBAC (Role-Based Access Control)**
- Project-based access control
- Fine-grained permissions (read, write, delete)
- Integration with LDAP/AD, OIDC
- Multi-tenancy support

**Image Retention Policies**
- Automatic cleanup of old/unused images
- Tag-based retention rules
- Save storage costs

### 2. Image Management

**Multi-Registry Replication**
- Push-based and pull-based replication
- Replicate between Harbor instances
- Proxy cache for DockerHub, gcr.io, quay.io
- Bandwidth optimization

**Helm Chart Repository**
- Native support for Helm charts
- ChartMuseum integration
- Version management for Kubernetes applications

**Image Proxying & Caching**
- Cache remote registries locally
- Reduce external bandwidth usage
- Improve pull performance

### 3. Audit & Compliance

**Comprehensive Audit Logging**
- All operations logged with timestamps
- User attribution for every action
- Support compliance requirements (SOC2, PCI-DSS)

**Image Provenance**
- Track image build information
- Artifact metadata and labels
- Build history and relationships

### 4. Enterprise Integration

**Authentication Backends**
- Local database
- LDAP/Active Directory
- OIDC (OAuth 2.0)
- UAA (User Account and Authentication)

**API & CLI**
- RESTful API for automation
- Harbor CLI for command-line operations
- Integration with CI/CD pipelines

**Webhook Notifications**
- Push, pull, scan, delete events
- Integrate with external systems
- Slack, HTTP endpoints support

---

## Harbor vs. Other Container Registries

### Comparison Matrix

| Feature | Harbor | Docker Hub | AWS ECR | Google GCR | Quay.io |
|---------|--------|------------|---------|------------|---------|
| **Self-hosted** | ✅ Yes | ❌ No | ❌ No | ❌ No | ✅ Yes |
| **Vulnerability Scanning** | ✅ Built-in | ⚠️ Limited | ✅ Yes | ✅ Yes | ✅ Yes |
| **Image Signing** | ✅ Notary | ✅ Yes | ❌ No | ✅ Yes | ❌ No |
| **Replication** | ✅ Advanced | ❌ No | ⚠️ Limited | ⚠️ Limited | ✅ Yes |
| **Helm Charts** | ✅ Native | ❌ No | ❌ No | ✅ Yes | ❌ No |
| **RBAC** | ✅ Advanced | ⚠️ Basic | ✅ IAM-based | ✅ IAM-based | ✅ Yes |
| **Cost** | 🆓 Free | 💰 Paid tiers | 💰 AWS costs | 💰 GCP costs | 💰 Paid |
| **CNCF Status** | ✅ Graduated | ❌ No | ❌ No | ❌ No | ❌ No |
| **Air-gapped Support** | ✅ Yes | ❌ No | ❌ No | ❌ No | ✅ Yes |

### When to Choose Harbor

**✅ Choose Harbor when you need:**

1. **On-premises deployment**: Self-hosted in your own infrastructure
2. **Air-gapped environments**: No internet connectivity required
3. **Multi-registry replication**: Sync across multiple locations
4. **Cost control**: No per-image or bandwidth charges
5. **Data sovereignty**: Keep images in your own datacenter/region
6. **Advanced security**: Built-in scanning, signing, policies
7. **Enterprise features**: LDAP, SSO, audit logs
8. **CNCF ecosystem alignment**: Production-proven, vendor-neutral

**⚠️ Consider alternatives when:**

1. You prefer fully managed cloud services (ECR, GCR)
2. Small team with simple needs (Docker Hub free tier)
3. Already heavily invested in specific cloud provider
4. Don't need self-hosted infrastructure

---

## Harbor Architecture

### High-Level Components

```
┌─────────────────────────────────────────────────────────────┐
│                        Load Balancer                         │
│                    (NGINX Ingress / MetalLB)                 │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────┴──────────────────────────────────────┐
│                      Harbor Core                             │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │   Portal    │  │  Harbor Core │  │   Job Service    │   │
│  │   (UI)      │  │   (API)      │  │  (Background)    │   │
│  └─────────────┘  └──────────────┘  └──────────────────┘   │
│                                                               │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │  Registry   │  │  ChartMuseum │  │     Notary       │   │
│  │  (Storage)  │  │  (Helm)      │  │   (Signing)      │   │
│  └─────────────┘  └──────────────┘  └──────────────────┘   │
│                                                               │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │   Trivy     │  │  PostgreSQL  │  │      Redis       │   │
│  │  (Scanner)  │  │  (Database)  │  │     (Cache)      │   │
│  └─────────────┘  └──────────────┘  └──────────────────┘   │
└───────────────────────────────────────────────────────────────┘
                       │
┌──────────────────────┴──────────────────────────────────────┐
│               Persistent Storage (Longhorn)                  │
│  - Registry images                                           │
│  - PostgreSQL data                                           │
│  - Redis data                                                │
│  - Trivy database                                            │
└──────────────────────────────────────────────────────────────┘
```

### Component Descriptions

**Portal (UI)**
- Web-based user interface
- Dashboard for managing projects, users, registries
- Image and chart browsing

**Core Service**
- RESTful API server
- Authentication and authorization
- Project and user management
- Webhook management

**Job Service**
- Background job execution
- Image replication
- Vulnerability scanning
- Garbage collection

**Registry**
- Docker Distribution (official Docker registry v2)
- Stores and serves container images
- OCI-compliant

**ChartMuseum**
- Helm chart repository
- Stores and serves Helm charts
- Version management

**Notary**
- Content trust service
- Image signing and verification
- Docker Content Trust implementation

**Trivy**
- Vulnerability scanner
- CVE database
- Comprehensive security checks

**PostgreSQL**
- Relational database
- Stores metadata, users, projects
- Audit logs

**Redis**
- In-memory cache
- Session management
- Job queue

---

## Use Cases

### 1. Enterprise Container Registry

**Scenario**: Large organization with multiple teams and applications

**Harbor Benefits**:
- Multi-tenancy with project-based isolation
- LDAP/AD integration for centralized user management
- RBAC for fine-grained access control
- Comprehensive audit logging for compliance

### 2. Air-Gapped Environments

**Scenario**: Government, military, financial institutions with strict network isolation

**Harbor Benefits**:
- Fully self-hosted, no external dependencies
- Pre-load images and charts
- Internal-only image distribution
- Complete data control

### 3. Multi-Cloud & Hybrid Cloud

**Scenario**: Applications running across AWS, Azure, GCP, and on-premises

**Harbor Benefits**:
- Multi-registry replication
- Sync images across regions/clouds
- Consistent image distribution
- Vendor-neutral solution

### 4. Secure DevSecOps

**Scenario**: Security-conscious organization requiring image validation

**Harbor Benefits**:
- Automated vulnerability scanning
- Image signing with Notary
- Prevent vulnerable images from deployment
- Policy-based image management

### 5. CI/CD Pipeline Integration

**Scenario**: Automated build and deployment workflows

**Harbor Benefits**:
- Robot accounts for CI/CD
- Webhook integrations
- RESTful API for automation
- Jenkins, GitLab CI, GitHub Actions integration

---

## Production Readiness Checklist

### ✅ Why Harbor is Production-Ready

1. **Battle-Tested**: Used by thousands of organizations worldwide
2. **Active Development**: Regular releases and security patches
3. **Strong Community**: Active contributors and support channels
4. **Enterprise Support**: Commercial support available from multiple vendors
5. **Comprehensive Documentation**: Extensive guides and tutorials
6. **High Availability**: Supports HA deployments
7. **Backup & Recovery**: Well-documented procedures
8. **Performance**: Handles large-scale deployments
9. **Security**: Regular CVE scanning and security audits
10. **Integration Ecosystem**: Works with CNCF projects (Kubernetes, Helm, Prometheus)

### 📊 Adoption Statistics

- **10,000+** organizations using Harbor
- **30 million+** Docker Hub pulls
- **400+** contributors
- **20,000+** GitHub stars
- **Used by**: VMware, Tencent, Bosch, Trend Micro, JD.com, and many more

---

## Getting Started

### Quick Installation Options

1. **Kubernetes/RKE2** (Recommended for Production)
   ```bash
   helm repo add harbor https://helm.goharbor.io
   helm install harbor harbor/harbor -n harbor
   ```

2. **Docker Compose** (Development/Testing)
   ```bash
   wget https://github.com/goharbor/harbor/releases/download/v2.10.0/harbor-offline-installer-v2.10.0.tgz
   tar xvf harbor-offline-installer-v2.10.0.tgz
   cd harbor
   ./install.sh
   ```

3. **Harbor Operator** (Kubernetes Native)
   ```bash
   kubectl apply -f https://github.com/goharbor/harbor-operator/releases/download/v1.4.0/harbor-operator.yaml
   ```

---

## Recommendations

### ✅ Harbor is Recommended When:

1. **Self-hosting is required** for compliance, cost, or control reasons
2. **Enterprise security features** are mandatory (scanning, signing, RBAC)
3. **Multi-registry replication** is needed for DR or multi-region deployments
4. **Air-gapped environments** require isolated image management
5. **CNCF ecosystem alignment** is important for your organization
6. **Cost predictability** is preferred over usage-based cloud pricing
7. **Helm chart repository** is needed alongside container images
8. **Vendor independence** is a strategic requirement

### 🎯 CNCF Recommendation

As a **CNCF Graduated project**, Harbor carries the CNCF's stamp of approval for:
- Production readiness
- Community health
- Technical quality
- Long-term sustainability

This makes Harbor the **de facto standard** for self-hosted, enterprise-grade container registries in the cloud-native ecosystem.

---

## Resources

### Official Links

- **Website**: https://goharbor.io
- **GitHub**: https://github.com/goharbor/harbor
- **Documentation**: https://goharbor.io/docs
- **CNCF Project Page**: https://www.cncf.io/projects/harbor/
- **Community**: https://github.com/goharbor/harbor/discussions

### Learning Resources

- Harbor Documentation: https://goharbor.io/docs/latest/
- Harbor Blog: https://goharbor.io/blog/
- CNCF Harbor Webinars: https://www.cncf.io/webinars/
- YouTube Channel: Search "Harbor Container Registry"

### Support

- **Community Support**: GitHub Discussions, Slack
- **Commercial Support**: Available from multiple vendors (VMware, etc.)
- **Professional Services**: Available for deployment and customization

---

## Conclusion

Harbor is not just a container registry—it's a **production-grade, enterprise-ready platform** for managing container images and Helm charts with security, compliance, and operational efficiency built-in.

Its **CNCF Graduated status** is a strong endorsement from the cloud-native community, indicating that Harbor is:
- Mature and stable
- Widely adopted
- Vendor-neutral
- Community-driven
- Production-proven

For organizations building on Kubernetes and requiring a self-hosted registry with enterprise features, **Harbor is the recommended choice** and aligns perfectly with CNCF best practices and ecosystem standards.

---

**Last Updated**: November 2025  
**Harbor Version**: 2.14.x  
**CNCF Status**: Graduated