# ACME Enterprise PKI Analysis for Fortune 500 Windows Infrastructure

**Date**: March 1, 2026

---

## Executive Context

### Environment Overview
- **Organization**: Fortune 500 company
- **Infrastructure Scale**: 500+ Windows Servers (IIS)
- **Deployment Model**: Domain-joined, internal private network
- **Current Setup**: Certificates installed via traditional issuances
- **Recent Migration**: Enterprise certificate infrastructure migrated to **Entrust PKIaaS**
- **Key Feature**: PKIaaS environment includes an ACME server (internal private network)

### Business Question
Is ACME a good fit for this environment? What are the pros and cons of HTTP vs DNS domain control validation? What are other key considerations?

---

## Analysis

### Is ACME a Good Fit? **YES, with Qualifications**

**Why ACME is Well-Suited:**
- **Automation Potential**: Replaces manual certificate issuance workflows across 500+ servers
- **Internal ACME Server**: Private network deployment eliminates external dependencies and security concerns
- **Windows/IIS Ecosystem**: Mature tooling exists (Certbot, ACMESharp.Net, Posh-ACME, custom scripts)
- **Entrust PKIaaS Foundation**: Enterprise-grade backend with compliance features

---

## HTTP vs DNS Validation: Context-Dependent

### HTTP Validation

**Advantages:**
- ✅ Simpler setup for IIS (ACME client drops verification file to `.well-known` folder)
- ✅ Faster validation (immediate server confirmation)
- ✅ No DNS API integrations required

**Disadvantages:**
- ❌ Requires inbound access to port 80 (HTTP challenge endpoint)
- ❌ Firewall rule complexity in private network environment
- ❌ Exposes ACME validation endpoints on production servers
- ❌ Network routing complexity if ACME server cannot directly reach all IIS servers

### DNS Validation

**Advantages:**
- ✅ Works without HTTP exposure; better for non-HTTP services
- ✅ No firewall inbound rule dependencies; inherently safer
- ✅ Batch operations possible (wildcard + multi-domain certificates)
- ✅ No exposed validation endpoints on production servers

**Disadvantages:**
- ❌ Requires DNS API integration or manual update capability
- ❌ Validation slower due to DNS propagation delays
- ❌ Requires DNS automation (additional integration complexity)

### Recommendation for Your Environment
**Choose DNS Validation** unless your DNS infrastructure is less reliable than IIS availability. DNS validation is:
- Industry standard for internal PKI automation at scale
- Safer in terms of attack surface (no exposed HTTP endpoints)
- Better aligned with private network security posture

---

## Key Considerations for Your Enterprise Deployment

### 1. Network Architecture
- **HTTP Challenge Routing**: Verify how internal ACME server reaches each IIS server on port 80. If servers aren't directly routable, HTTP validation becomes problematic.
- **DNS Capability**: If choosing DNS validation, ensure ACME server can query/update your DNS infrastructure (API or zone transfer capability).
- **Critical Question**: Is Split DNS in use? If so, verify ACME server can update internal DNS zones.

### 2. Certificate Lifecycle Management
- **Renewal Automation**: Critical for 500+ servers—cannot be manual
- **Recommended Implementation**:
  - Scheduled PowerShell task on each server running ACME client
  - Centralized monitoring/alerting for renewal failures
  - Consider infrastructure orchestration tools (Ansible, Puppet) if enterprise has them
- **IIS Certificate Binding**: Auto-rebinding after renewal requires post-renewal hook scripts
- **Renewal Frequency**: Default 90-day cert lifecycle requires quarterly automation cycles

### 3. Private Network Constraints
- ACME server must have network access to all 500+ servers OR servers must have bidirectional access to ACME server
- For DNS validation: ACME server needs DNS update capability
- **Bandwidth/Rate Limiting**: Monitor for ACME protocol overhead at scale

### 4. Entrust PKIaaS Specifics
- Verify which validation methods Entrust ACME implementation supports
- Check rate limits—500 servers × multiple renewals could hit quotas
- Confirm certificate policies allow automated re-issuance (some policy templates may restrict automated renewal)
- Integrate ACME event logging with enterprise SIEM/monitoring

### 5. Account & Key Management
- **ACME Account Keys**: Store securely (not in plaintext scripts)
  - Options: Windows Credential Manager, Azure Key Vault (if hybrid-connected), encrypted scripts
- **Server-Level Credentials**: Secure storage of account credentials on each IIS server
- **Key Rotation Policy**: Define rotation schedule for ACME account keys

### 6. Rollback & Disaster Recovery
- Keep manual certificate processes in parallel during initial rollout
- Implement staged pilot rollout (do NOT go all 500 servers simultaneously)
- Test renewal automation on pilot subset (10-20 servers) for 2-4 cycles before expansion
- Document certificate thumbprint changes—automation will regenerate certs during renewals

### 7. Compliance & Auditing
- ACME logs all certificate issuance events—ensure logs flow to enterprise SIEM/audit system
- Audit trail required for regulatory compliance (SOX, HIPAA, PCI-DSS depending on cardholder data, etc.)
- **Certificate Transparency Logs**: Verify enterprise has no objections to public CT logging (if applicable to cert type)

### 8. Client Tooling Selection
**Recommended for Windows/IIS Environment:**
- **Posh-ACME** (PowerShell) — Most flexible, domain-joined server friendly, excellent for Windows
- **Certbot** (Windows Server 2019+, native or WSL) — Mature, excellent IIS plugin, battle-tested
- **ACMESharp.Net** — Consider if requiring deep .NET integration with custom applications

---

## Recommended Implementation Approach

### Phase 1: Pilot Study (2-4 weeks)
- Deploy DNS validation with 10-20 non-critical IIS servers
- Test renewal automation via PowerShell scheduled tasks
- Validate Entrust ACME behavior under load with pilot group
- Validate certificate binding updates in IIS
- **Success Criteria**: Automated renewal cycle completes 2-3 times successfully

### Phase 2: Tuning & Hardening (2 weeks)
- Implement comprehensive monitoring/alerting for renewal failures
- Document failure recovery procedures
- Create auto-rebinding scripts for IIS certificate updates
- Test rollback procedures
- **Success Criteria**: Renewable failure detection reliable, recovery documented

### Phase 3: Staged Enterprise Rollout (3-6 months)
- Roll out to 100 servers (Phase 3a)
- Expand to 300 servers (Phase 3b)
- Expand to full 500+ server fleet (Phase 3c)
- Maintain parallel manual process for 3-6 months as safety net
- **Success Criteria**: Each phase stable for 1+ month before next expansion

---

## Critical Success Factors

1. **Automation First**: Manual processes scale linearly; this environment requires full automation from day one
2. **Monitoring Second**: Visibility into certificate lifecycle across 500+ servers is non-negotiable
3. **Pilot-Driven Approach**: Avoid "big bang" deployment—problems amplified at scale
4. **Documentation**: Maintain runbooks for common failure scenarios
5. **Team Training**: Operations team must understand ACME renewal process and troubleshooting

---

## Summary Table: HTTP vs DNS for This Scenario

| Factor | HTTP Validation | DNS Validation | Winner |
|--------|-----------------|-----------------|--------|
| Network Complexity | High (firewall rules, routing) | Low (DNS queries) | DNS |
| Security Posture | Exposed endpoints on servers | No exposed endpoints | DNS |
| Implementation Ease | Simpler initial setup | Requires DNS integration | HTTP |
| Batch Operations | Single cert only | Wildcard + multi-domain | DNS |
| Private Network Fit | Problematic routing | Well-suited | DNS |
| Entrust Compatibility | TBD (verify) | TBD (verify) | Tie |
| **Overall Fit** | **Poor** | **Good** | **DNS** |

---

## Next Steps

1. **Validate Entrust ACME Support**: Confirm which validation methods Entrust PKIaaS ACME supports
2. **Network Assessment**: Map ACME server reachability to all 500+ IIS servers
3. **DNS Infrastructure Review**: Assess capability for DNS-based validation automation
4. **Tooling Selection**: Select ACME client (recommend Posh-ACME for Windows/PowerShell)
5. **Pilot Planning**: Define pilot server selection criteria (non-critical, representative workloads)
6. **Runbook Development**: Create operational procedures for common scenarios

---

*Analysis Date: March 1, 2026*
*Environment: Enterprise PKI, 500+ Windows/IIS Servers, Internal Private Network*
