# ============================================================================
# ACME Certificate Issuance and IIS Deployment with Azure Key Vault
# 
# Purpose: 
#   - Retrieve secrets from Azure Key Vault (ACME account key, Infoblox credentials)
#   - Connect to Entrust ACME server
#   - Issue certificate with DNS validation via Infoblox
#   - Deploy certificate to IIS server and bind
#
# Prerequisites:
#   - Posh-ACME module installed (Install-Module Posh-ACME)
#   - Az.KeyVault module installed (Install-Module Az.KeyVault)
#   - Az.Accounts module installed (Install-Module Az.Accounts)
#   - Posh-Infoblox module (Install-Module Posh-Infoblox) OR manual REST calls
#   - Azure authentication established (Connect-AzAccount)
#   - IIS role installed on target server
#
# Author: Enterprise PKI Team
# Date: March 2026
# ============================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,  # e.g., "webserver1.contoso.com"
    
    [Parameter(Mandatory=$true)]
    [string]$IISServerName,  # e.g., "webserver1.contoso.com"
    
    [Parameter(Mandatory=$true)]
    [string]$IISSiteName,  # e.g., "Default Web Site"
    
    [Parameter(Mandatory=$false)]
    [string]$AzureKeyVaultName = "my-enterprise-keyvault",  # Your KV name
    
    [Parameter(Mandatory=$false)]
    [string]$ACMEServerUrl = "https://acme.entrust-internal.local/acme/directory",  # Internal Entrust ACME
    
    [Parameter(Mandatory=$false)]
    [string]$ACMEEnvironment = "Production"  # or "Staging" for testing
)

# ============================================================================
# STEP 1: Connect to Azure and Retrieve Secrets from Key Vault
# ============================================================================

function Get-VaultSecrets {
    param(
        [string]$VaultName
    )
    
    Write-Host "[*] Connecting to Azure Key Vault: $VaultName" -ForegroundColor Cyan
    
    try {
        # Authenticate to Azure (assumes already authenticated or managed identity)
        # If running as managed identity on Azure VM, no explicit Connect-AzAccount needed
        
        # Retrieve ACME account key from Key Vault
        $acmeAccountKeySecret = Get-AzKeyVaultSecret -VaultName $VaultName -Name "acme-account-key" -AsPlainText
        if (-not $acmeAccountKeySecret) {
            throw "ACME account key not found in Key Vault"
        }
        
        # Retrieve Infoblox credentials from Key Vault
        $infobloxHostSecret = Get-AzKeyVaultSecret -VaultName $VaultName -Name "infoblox-host" -AsPlainText
        $infobloxCredentialSecret = Get-AzKeyVaultSecret -VaultName $VaultName -Name "infoblox-credentials" -AsPlainText
        
        if (-not $infobloxHostSecret -or -not $infobloxCredentialSecret) {
            throw "Infoblox credentials not found in Key Vault"
        }
        
        Write-Host "[✓] Successfully retrieved secrets from Key Vault" -ForegroundColor Green
        
        return @{
            ACMEAccountKey = $acmeAccountKeySecret
            InfobloxHost = $infobloxHostSecret
            InfobloxCredential = $infobloxCredentialSecret
        }
    }
    catch {
        Write-Host "[✗] Failed to retrieve secrets: $_" -ForegroundColor Red
        throw
    }
}

# ============================================================================
# STEP 2: Initialize Posh-ACME with Account Key
# ============================================================================

function Initialize-ACMEAccount {
    param(
        [string]$AccountKey,
        [string]$ACMEServer,
        [string]$EnvironmentName
    )
    
    Write-Host "[*] Initializing Posh-ACME account..." -ForegroundColor Cyan
    
    try {
        # Set ACME server
        Set-PAServer -DirectoryUrl $ACMEServer
        
        # Import account key from Key Vault (convert from JSON if stored as JSON)
        # Posh-ACME expects account to be pre-created, so if Key Vault stores serialized key:
        $keyObject = $AccountKey | ConvertFrom-Json
        
        # In practice, you'd either:
        # 1. Create account once manually and store only the account ID
        # 2. Or recreate account from stored key material
        
        # Get or create account
        $account = Get-PAAccount -Identity $EnvironmentName -ErrorAction SilentlyContinue
        if (-not $account) {
            Write-Host "[!] Account not found, creating new account..." -ForegroundColor Yellow
            # This requires account key setup; in production, manage this carefully
            # Using New-PAAccount with contact email would be typical
            $account = New-PAAccount -Contact "admin@contoso.com" -AcceptTOS
        } else {
            Write-Host "[✓] Account found: $($account.id)" -ForegroundColor Green
        }
        
        # Set as current account for subsequent operations
        $account | Set-PAAccount
        
        return $account
    }
    catch {
        Write-Host "[✗] Failed to initialize ACME account: $_" -ForegroundColor Red
        throw
    }
}

# ============================================================================
# STEP 3: Request Certificate with DNS Validation (Infoblox)
# ============================================================================

function Request-Certificate-DNSValidation {
    param(
        [string]$Domain,
        [string]$InfobloxHost,
        [string]$InfobloxCredential
    )
    
    Write-Host "[*] Requesting certificate for domain: $Domain" -ForegroundColor Cyan
    
    try {
        # Create DNS plugin parameters for Infoblox
        # Posh-ACME has DNS plugin support for various providers
        
        $dnsPlugin = "Infoblox"
        
        # Prepare Infoblox credentials for DNS plugin
        # Note: Exact format depends on Posh-ACME Infoblox plugin implementation
        # This is a conceptual example
        
        $pluginArgs = @{
            IBServer = $InfobloxHost
            IBCredential = (ConvertTo-SecureString -String $InfobloxCredential -AsPlainText -Force | Get-Credential)
            IBView = "default"  # DNS view in Infoblox
        }
        
        # Request certificate using Posh-ACME with Infoblox DNS validation
        $cert = New-PACertificate -Domain $Domain `
                                  -DnsPlugin $dnsPlugin `
                                  -PluginArgs $pluginArgs `
                                  -PfxPassWord (ConvertTo-SecureString -String (New-Guid).Guid -AsPlainText -Force) `
                                  -Force
        
        if ($cert) {
            Write-Host "[✓] Certificate requested successfully" -ForegroundColor Green
            Write-Host "    Cert Path: $($cert.CertFile)" -ForegroundColor Gray
            Write-Host "    Key Path: $($cert.KeyFile)" -ForegroundColor Gray
            Write-Host "    PFX Path: $($cert.PfxFile)" -ForegroundColor Gray
            return $cert
        }
        else {
            throw "Certificate creation returned null"
        }
    }
    catch {
        Write-Host "[✗] Failed to request certificate: $_" -ForegroundColor Red
        throw
    }
}

# ============================================================================
# STEP 4: Deploy Certificate to IIS Server
# ============================================================================

function Deploy-CertificateToIIS {
    param(
        [string]$ServerName,
        [string]$SiteName,
        [string]$CertificatePath,
        [string]$CertificateThumbprint
    )
    
    Write-Host "[*] Deploying certificate to IIS: $ServerName > $SiteName" -ForegroundColor Cyan
    
    try {
        # Import certificate into local machine store
        Write-Host "[→] Importing certificate into certificate store..." -ForegroundColor Gray
        
        $cert = Import-PfxCertificate -FilePath $CertificatePath `
                                       -CertStoreLocation "Cert:\LocalMachine\My" `
                                       -ErrorAction Stop
        
        $thumbprint = $cert.Thumbprint
        Write-Host "[✓] Certificate imported. Thumbprint: $thumbprint" -ForegroundColor Green
        
        # Bind certificate to IIS site
        Write-Host "[→] Binding certificate to IIS site..." -ForegroundColor Gray
        
        # Connect to IIS via WebAdministration module
        Import-Module WebAdministration -ErrorAction Stop
        
        # Get the site
        $site = Get-IISSite -Name $SiteName -ErrorAction Stop
        if (-not $site) {
            throw "IIS site '$SiteName' not found"
        }
        
        # Get the HTTPS binding (or create if doesn't exist)
        $binding = $site.Bindings.Collection | Where-Object { $_.Protocol -eq "https" }
        
        if ($binding) {
            # Update existing HTTPS binding
            Write-Host "[→] Updating existing HTTPS binding..." -ForegroundColor Gray
            $binding.certificateHash = $thumbprint
            $binding.certificateStoreName = "MY"
        }
        else {
            # Create new HTTPS binding
            Write-Host "[→] Creating new HTTPS binding..." -ForegroundColor Gray
            New-IISSiteBinding -Name $SiteName `
                              -BindingInformation "*:443:$ServerName" `
                              -CertificateThumbprint $thumbprint `
                              -CertificateStoreName "My" `
                              -Protocol "https" `
                              -ErrorAction Stop
        }
        
        Write-Host "[✓] Certificate successfully bound to IIS site" -ForegroundColor Green
        Write-Host "    Site: $SiteName" -ForegroundColor Gray
        Write-Host "    Protocol: HTTPS" -ForegroundColor Gray
        Write-Host "    Thumbprint: $thumbprint" -ForegroundColor Gray
        
        return $thumbprint
    }
    catch {
        Write-Host "[✗] Failed to deploy certificate to IIS: $_" -ForegroundColor Red
        throw
    }
}

# ============================================================================
# STEP 5: Verify Certificate Binding
# ============================================================================

function Verify-CertificateBinding {
    param(
        [string]$SiteName,
        [string]$ExpectedThumbprint
    )
    
    Write-Host "[*] Verifying certificate binding..." -ForegroundColor Cyan
    
    try {
        Import-Module WebAdministration -ErrorAction Stop
        
        $site = Get-IISSite -Name $SiteName -ErrorAction Stop
        $binding = $site.Bindings.Collection | Where-Object { $_.Protocol -eq "https" }
        
        if ($binding -and $binding.certificateHash -eq $ExpectedThumbprint) {
            Write-Host "[✓] Certificate binding verified successfully" -ForegroundColor Green
            Write-Host "    Expected Thumbprint: $ExpectedThumbprint" -ForegroundColor Gray
            Write-Host "    Actual Thumbprint:   $($binding.certificateHash)" -ForegroundColor Gray
            return $true
        }
        else {
            Write-Host "[✗] Certificate binding verification failed" -ForegroundColor Red
            if ($binding) {
                Write-Host "    Expected: $ExpectedThumbprint" -ForegroundColor Gray
                Write-Host "    Actual:   $($binding.certificateHash)" -ForegroundColor Gray
            }
            else {
                Write-Host "[!] No HTTPS binding found" -ForegroundColor Yellow
            }
            return $false
        }
    }
    catch {
        Write-Host "[✗] Verification failed: $_" -ForegroundColor Red
        return $false
    }
}

# ============================================================================
# STEP 6: Logging and Error Handling
# ============================================================================

function Write-ActivityLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Log to file
    $logPath = "C:\Logs\ACME-Deployment"
    if (-not (Test-Path $logPath)) { New-Item -ItemType Directory -Path $logPath -Force | Out-Null }
    
    Add-Content -Path "$logPath\acme-deployment.log" -Value $logEntry
}

# ============================================================================
# MAIN EXECUTION FLOW
# ============================================================================

try {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "ACME Certificate Deployment Pipeline" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-ActivityLog "Starting ACME certificate deployment for domain: $DomainName"
    
    # Step 1: Get secrets from Azure Key Vault
    Write-Host ""
    $secrets = Get-VaultSecrets -VaultName $AzureKeyVaultName
    Write-ActivityLog "Retrieved secrets from Azure Key Vault"
    
    # Step 2: Initialize ACME account
    Write-Host ""
    $account = Initialize-ACMEAccount -AccountKey $secrets.ACMEAccountKey `
                                      -ACMEServer $ACMEServerUrl `
                                      -EnvironmentName $ACMEEnvironment
    Write-ActivityLog "ACME account initialized: $($account.id)"
    
    # Step 3: Request certificate with DNS validation via Infoblox
    Write-Host ""
    $certificate = Request-Certificate-DNSValidation -Domain $DomainName `
                                                      -InfobloxHost $secrets.InfobloxHost `
                                                      -InfobloxCredential $secrets.InfobloxCredential
    Write-ActivityLog "Certificate requested successfully: $($certificate.CertFile)"
    
    # Step 4: Deploy to IIS
    Write-Host ""
    $thumbprint = Deploy-CertificateToIIS -ServerName $IISServerName `
                                          -SiteName $IISSiteName `
                                          -CertificatePath $certificate.PfxFile
    Write-ActivityLog "Certificate deployed to IIS: $thumbprint"
    
    # Step 5: Verify binding
    Write-Host ""
    $verified = Verify-CertificateBinding -SiteName $IISSiteName -ExpectedThumbprint $thumbprint
    Write-ActivityLog "Certificate binding verification: $(if ($verified) { 'SUCCESS' } else { 'FAILED' })"
    
    Write-Host ""
    if ($verified) {
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "✓ DEPLOYMENT SUCCESSFUL" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Summary:" -ForegroundColor Green
        Write-Host "  Domain: $DomainName" -ForegroundColor Gray
        Write-Host "  IIS Server: $IISServerName" -ForegroundColor Gray
        Write-Host "  Site: $IISSiteName" -ForegroundColor Gray
        Write-Host "  Certificate Thumbprint: $thumbprint" -ForegroundColor Gray
        Write-Host "  Status: Deployed and Bound" -ForegroundColor Gray
        
        exit 0
    }
    else {
        throw "Certificate binding verification failed"
    }
}
catch {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "✗ DEPLOYMENT FAILED" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $_" -ForegroundColor Red
    
    Write-ActivityLog "Deployment failed: $_" -Level "ERROR"
    
    exit 1
}
finally {
    Write-Host ""
    Write-Host "Deployment pipeline completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
}
