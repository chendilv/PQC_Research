# ACME + Infoblox + IIS Integration Guide

## Overview

This guide demonstrates a complete end-to-end workflow for:
1. Retrieving ACME account keys and Infoblox credentials from Azure Key Vault
2. Connecting to an internal Entrust ACME server
3. Issuing certificates with DNS validation via Infoblox
4. Binding certificates to IIS sites

---

## Prerequisites

### PowerShell Modules
```powershell
# Install required modules
Install-Module -Name Posh-ACME -Force
Install-Module -Name Az.KeyVault -Force
Install-Module -Name Az.Accounts -Force
Install-Module -Name Posh-Infoblox -Force  # Or use REST calls directly
```

### Azure Authentication
```powershell
# If running on local machine
Connect-AzAccount -Subscription "your-subscription-id"

# If running on Azure VM with managed identity
# No explicit authentication needed (automatic)
```

### Azure Key Vault Setup

Store these secrets in Azure Key Vault:

| Secret Name | Description | Example Value |
|-------------|-------------|----------------|
| `acme-account-key` | ACME account key (JSON serialized) | `{"key": "..."}` |
| `infoblox-host` | Infoblox grid master FQDN | `infoblox.contoso.com` |
| `infoblox-credentials` | Infoblox API credentials (Base64 or plaintext) | `username:password` |

**Create secrets in Key Vault:**
```powershell
$vaultName = "my-enterprise-keyvault"

# Create ACME account key secret
$acmeKey = @{ key = "your-base64-encoded-key" } | ConvertTo-Json
Set-AzKeyVaultSecret -VaultName $vaultName -Name "acme-account-key" -SecretValue (ConvertTo-SecureString -String $acmeKey -AsPlainText -Force)

# Create Infoblox secrets
Set-AzKeyVaultSecret -VaultName $vaultName -Name "infoblox-host" -SecretValue (ConvertTo-SecureString -String "infoblox.contoso.com" -AsPlainText -Force)
Set-AzKeyVaultSecret -VaultName $vaultName -Name "infoblox-credentials" -SecretValue (ConvertTo-SecureString -String "apiuser:apipassword" -AsPlainText -Force)
```

---

## Usage

### Basic Example

```powershell
# Run the deployment script
.\ACME-IIS-Deployment-Script.ps1 `
    -DomainName "webserver1.contoso.com" `
    -IISServerName "webserver1.contoso.com" `
    -IISSiteName "Default Web Site" `
    -AzureKeyVaultName "my-enterprise-keyvault" `
    -ACMEServerUrl "https://acme.entrust-internal.local/acme/directory" `
    -ACMEEnvironment "Production"
```

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `DomainName` | Yes | FQDN of the domain to request certificate for |
| `IISServerName` | Yes | Server name/hostname where IIS is running |
| `IISSiteName` | Yes | IIS site name (e.g., "Default Web Site") |
| `AzureKeyVaultName` | No (default: my-enterprise-keyvault) | Azure Key Vault name |
| `ACMEServerUrl` | No | URL of ACME directory endpoint |
| `ACMEEnvironment` | No (default: Production) | "Production" or "Staging" |

### Advanced Example: Batch Deployment

```powershell
# Deploy certificates to multiple IIS servers
$servers = @(
    @{ Domain = "web1.contoso.com"; Server = "web1"; Site = "Default Web Site" }
    @{ Domain = "web2.contoso.com"; Server = "web2"; Site = "Default Web Site" }
    @{ Domain = "web3.contoso.com"; Server = "web3"; Site = "Default Web Site" }
)

foreach ($srv in $servers) {
    Write-Host "Deploying to $($srv.Server)..."
    
    try {
        .\ACME-IIS-Deployment-Script.ps1 `
            -DomainName $srv.Domain `
            -IISServerName $srv.Server `
            -IISSiteName $srv.Site `
            -AzureKeyVaultName "my-enterprise-keyvault"
    }
    catch {
        Write-Host "Failed for $($srv.Server): $_" -ForegroundColor Red
    }
}
```

---

## Key Components Explained

### Step 1: Get-VaultSecrets

Retrieves three secrets from Azure Key Vault:
- **acme-account-key**: Used to authenticate with ACME server
- **infoblox-host**: Infoblox server hostname
- **infoblox-credentials**: API credentials for Infoblox (user:password)

```powershell
$secrets = Get-VaultSecrets -VaultName "my-enterprise-keyvault"
# Returns: @{
#   ACMEAccountKey = "..."
#   InfobloxHost = "infoblox.contoso.com"
#   InfobloxCredential = "apiuser:apipass"
# }
```

### Step 2: Initialize-ACMEAccount

Sets up Posh-ACME with the ACME server and account:
- Connects to Entrust ACME server directory
- Uses stored account credentials
- Sets account as active for subsequent operations

```powershell
$account = Initialize-ACMEAccount `
    -AccountKey $secrets.ACMEAccountKey `
    -ACMEServer "https://acme.entrust-internal.local/acme/directory" `
    -EnvironmentName "Production"
```

### Step 3: Request-Certificate-DNSValidation

Issues certificate using Infoblox for DNS validation:
- Uses Posh-ACME DNS plugin system
- Passes Infoblox credentials to plugin
- Returns certificate files (PEM, KEY, PFX)

```powershell
$certificate = Request-Certificate-DNSValidation `
    -Domain "webserver1.contoso.com" `
    -InfobloxHost "infoblox.contoso.com" `
    -InfobloxCredential "apiuser:apipass"

# Returns certificate object with:
# - $certificate.PfxFile (PKCS#12 file path)
# - $certificate.CertFile (PEM certificate)
# - $certificate.KeyFile (Private key)
```

### Step 4: Deploy-CertificateToIIS

Imports certificate and binds to IIS site:
1. Imports PFX file into `Cert:\LocalMachine\My` store
2. Creates or updates HTTPS binding on IIS site
3. Associates certificate by thumbprint

```powershell
$thumbprint = Deploy-CertificateToIIS `
    -ServerName "webserver1" `
    -SiteName "Default Web Site" `
    -CertificatePath "C:\path\to\cert.pfx"
```

### Step 5: Verify-CertificateBinding

Confirms certificate is properly bound:
- Retrieves current HTTPS binding
- Compares thumbprint with deployed certificate
- Returns $true/$false

```powershell
$verified = Verify-CertificateBinding `
    -SiteName "Default Web Site" `
    -ExpectedThumbprint "ABC123..."
```

---

## Infoblox DNS Validation Flow

### How DNS Validation Works

1. **ACME Challenge**: Entrust ACME server sends challenge: "Prove you own contoso.com"
2. **DNS Record Creation**: Posh-ACME + Infoblox plugin creates TXT record:
   ```
   _acme-challenge.webserver1.contoso.com = "validation-token-xyz"
   ```
3. **Validation**: ACME server queries DNS for the TXT record
4. **Success**: If record exists and matches, certificate is issued
5. **Cleanup**: TXT record is automatically removed

### Infoblox API Integration Points

The script calls Infoblox API during DNS validation:

```powershell
# Behind the scenes, Posh-ACME Infoblox plugin does:
POST https://infoblox.contoso.com/wapi/v2.x/zone_auth
Authorization: Basic BASE64(apiuser:apipass)
{
  "fqdn": "webserver1.contoso.com",
  "view": "default"
}

POST https://infoblox.contoso.com/wapi/v2.x/record:txt
{
  "name": "_acme-challenge.webserver1.contoso.com",
  "text": "validation-token-xyz"
}
```

---

## Practical Enterprise Scenario: Automated Renewal

### Scheduled Task Setup

Deploy as scheduled task for automated renewals:

```powershell
# Create scheduled task that runs script daily
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -File C:\Scripts\ACME-IIS-Deployment-Script.ps1 -DomainName webserver1.contoso.com -IISServerName webserver1 -IISSiteName 'Default Web Site'"

$trigger = New-ScheduledTaskTrigger -Daily -At 2:00AM

$principal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "ACME-Cert-Renewal-webserver1" `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Description "Automated ACME certificate renewal and IIS binding"
```

### Renewal Monitoring

```powershell
# Monitor certificate expiration
Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*contoso.com" } | 
    Select-Object Subject, Thumbprint, NotAfter | 
    Where-Object { $_.NotAfter -lt (Get-Date).AddDays(30) } |
    ForEach-Object { Write-Host "Certificate expires in < 30 days: $($_.Subject)" }
```

---

## Error Handling & Troubleshooting

### Common Issues

#### 1. Azure Authentication Failed
```powershell
# Solution: Authenticate explicitly
Connect-AzAccount -Subscription "subscription-id"
```

#### 2. Key Vault Secret Not Found
```powershell
# Verify secrets exist
Get-AzKeyVaultSecret -VaultName "my-enterprise-keyvault" | Format-Table Name

# Create missing secret
Set-AzKeyVaultSecret -VaultName "my-enterprise-keyvault" `
    -Name "acme-account-key" `
    -SecretValue (ConvertTo-SecureString -String "..." -AsPlainText -Force)
```

#### 3. Infoblox Validation Fails
```powershell
# Check Infoblox API connectivity
$credential = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("user:pass"))
$headers = @{ "Authorization" = "Basic $credential" }
Invoke-RestMethod -Uri "https://infoblox.contoso.com/wapi/v2.5/grid" -Headers $headers
```

#### 4. IIS Binding Error
```powershell
# Verify IIS site exists
Get-IISSite -Name "Default Web Site"

# Check current bindings
Get-IISSiteBinding -Name "Default Web Site"

# Verify certificate exists in store
Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq "ABC123..." }
```

### Logging

Deployment logs are saved to: `C:\Logs\ACME-Deployment\acme-deployment.log`

```powershell
# View recent logs
Get-Content C:\Logs\ACME-Deployment\acme-deployment.log -Tail 50
```

---

## Security Best Practices

1. **ACME Account Key**:
   - Store only in Azure Key Vault
   - Never log or display
   - Rotate annually

2. **Infoblox Credentials**:
   - Use read-only service account if possible
   - Store in Key Vault as secure string
   - Rotate credentials quarterly

3. **Script Execution**:
   - Run as SYSTEM or managed service account
   - Store scripts in secured location
   - Enable PowerShell logging

4. **Certificate Binding**:
   - Verify thumbprint after deployment
   - Monitor certificate expiration
   - Maintain audit logs

---

## Reference Links

- [Posh-ACME Documentation](https://github.com/rmbolger/Posh-ACME)
- [Entrust PKIaaS ACME API](https://www.entrustdatacard.com/pki/acme)
- [Infoblox WAPI Documentation](https://infoblox.readthedocs.io/)
- [IIS Certificate Binding](https://learn.microsoft.com/en-us/iis/manage/configuring-security/configuring-ssl-certificate-bindings)

---

**Version**: 1.0 | **Last Updated**: March 2026 | **Author**: Enterprise PKI Team
