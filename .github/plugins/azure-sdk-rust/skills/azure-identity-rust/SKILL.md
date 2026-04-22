---
name: azure-identity-rust
description: |
  Azure Identity SDK for Rust (v0.34.0). Use for DeveloperToolsCredential, ManagedIdentityCredential, ClientSecretCredential, and token-based auth with Azure services.
  Triggers: "azure identity rust", "DeveloperToolsCredential", "authentication rust", "managed identity rust", "credential rust".
---

# Azure Identity SDK for Rust

> `azure_identity` v0.34.0 — Authentication for Azure SDK clients using Microsoft Entra ID.

> **Note:** Rust SDK does not have `DefaultAzureCredential`. Use `DeveloperToolsCredential` for local dev.

## Installation

```sh
cargo add azure_identity azure_core tokio
```

## Environment Variables

```bash
# Service Principal (for CI/production)
AZURE_TENANT_ID=<your-tenant-id>
AZURE_CLIENT_ID=<your-client-id>
AZURE_CLIENT_SECRET=<your-client-secret>

# User-assigned Managed Identity (optional)
AZURE_CLIENT_ID=<managed-identity-client-id>
```

## DeveloperToolsCredential

Recommended for local development. Tries Azure CLI then Azure Developer CLI:

```rust
use azure_identity::DeveloperToolsCredential;
use azure_security_keyvault_secrets::SecretClient;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let credential = DeveloperToolsCredential::new(None)?;
    let client = SecretClient::new(
        "https://<your-key-vault-name>.vault.azure.net/",
        credential.clone(),
        None,
    )?;

    let secret = client.get_secret("secret-name", None).await?.into_model()?;
    println!("Secret: {:?}", secret.value);

    Ok(())
}
```

Ensure you are logged in first:

```sh
az login
```

### Credential Chain Order

| Order | Credential                  | Login Command    |
| ----- | --------------------------- | ---------------- |
| 1     | AzureCliCredential          | `az login`       |
| 2     | AzureDeveloperCliCredential | `azd auth login` |

## Credential Types

| Credential                    | Use Case                               |
| ----------------------------- | -------------------------------------- |
| `DeveloperToolsCredential`    | Local development — tries CLI tools    |
| `ManagedIdentityCredential`   | Azure VMs, App Service, Functions, AKS |
| `WorkloadIdentityCredential`  | Kubernetes workload identity           |
| `ClientSecretCredential`      | Service principal with secret          |
| `ClientCertificateCredential` | Service principal with certificate     |
| `AzureCliCredential`          | Direct Azure CLI auth                  |
| `AzureDeveloperCliCredential` | Direct azd CLI auth                    |
| `AzurePipelinesCredential`    | Azure Pipelines service connection     |
| `ClientAssertionCredential`   | Custom assertions (federated identity) |

## ManagedIdentityCredential

For Azure-hosted resources (VMs, App Service, AKS):

```rust
use azure_identity::ManagedIdentityCredential;

// System-assigned managed identity
let credential = ManagedIdentityCredential::new(None)?;

// User-assigned managed identity
let options = ManagedIdentityCredentialOptions {
    client_id: Some("<user-assigned-mi-client-id>".into()),
    ..Default::default()
};
let credential = ManagedIdentityCredential::new(Some(options))?;
```

## ClientSecretCredential

For service principal authentication:

```rust
use azure_identity::ClientSecretCredential;

let credential = ClientSecretCredential::new(
    "<tenant-id>".into(),
    "<client-id>".into(),
    "<client-secret>".into(),
    None,
)?;
```

## Best Practices

1. **Use `DeveloperToolsCredential` for local dev** — automatically picks up Azure CLI login
2. **Use `ManagedIdentityCredential` in production** — no secrets to manage
3. **Clone credentials** — credentials are `Arc`-wrapped and cheap to clone
4. **Reuse credential instances** — same credential works with multiple clients

## Reference Links

| Resource      | Link                                                                               |
| ------------- | ---------------------------------------------------------------------------------- |
| API Reference | https://docs.rs/azure_identity                                                     |
| Source Code   | https://github.com/Azure/azure-sdk-for-rust/tree/main/sdk/identity/azure_identity  |
| crates.io     | https://crates.io/crates/azure_identity                                            |
