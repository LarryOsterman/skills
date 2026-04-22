---
name: azure-keyvault-certificates-rust
description: |
  Azure Key Vault Certificates SDK for Rust (v0.12.0). Use for creating, importing, and managing certificates.
  Triggers: "keyvault certificates rust", "CertificateClient rust", "create certificate rust", "import certificate rust".
---

# Azure Key Vault Certificates SDK for Rust

> `azure_security_keyvault_certificates` v0.12.0 — Secure storage and management of certificates.

## Installation

```sh
cargo add azure_security_keyvault_certificates azure_identity tokio futures
```

## Environment Variables

```bash
AZURE_KEYVAULT_URL=https://<vault-name>.vault.azure.net/
```

## Client Setup

```rust
use azure_core::base64;
use azure_identity::DeveloperToolsCredential;
use azure_security_keyvault_certificates::CertificateClient;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let credential = DeveloperToolsCredential::new(None)?;
    let client = CertificateClient::new(
        "https://<your-key-vault-name>.vault.azure.net/",
        credential.clone(),
        None,
    )?;

    let certificate = client
        .get_certificate("certificate-name", None)
        .await?
        .into_model()?;
    println!(
        "Thumbprint: {:?}",
        certificate.x509_thumbprint.map(base64::encode_url_safe)
    );

    Ok(())
}
```

## Create Self-Signed Certificate

`create_certificate` returns a `Poller` — note the `?` before `.await?`:

```rust
use azure_security_keyvault_certificates::models::{
    CertificatePolicy, CreateCertificateParameters, IssuerParameters, X509CertificateProperties,
};

let policy = CertificatePolicy {
    x509_certificate_properties: Some(X509CertificateProperties {
        subject: Some("CN=DefaultPolicy".into()),
        ..Default::default()
    }),
    issuer_parameters: Some(IssuerParameters {
        name: Some("Self".into()),
        ..Default::default()
    }),
    ..Default::default()
};
let body = CreateCertificateParameters {
    certificate_policy: Some(policy),
    ..Default::default()
};

// Wait for the certificate operation to complete.
// The Poller implements futures::Stream and automatically waits between polls.
let certificate = client
    .create_certificate("certificate-name", body.try_into()?, None)?
    .await?
    .into_model()?;
```

## Update Certificate Properties

```rust
use azure_security_keyvault_certificates::models::UpdateCertificatePropertiesParameters;
use std::collections::HashMap;

let certificate_update_parameters = UpdateCertificatePropertiesParameters {
    tags: Some(HashMap::from_iter(vec![("tag-name".into(), "tag-value".into())])),
    ..Default::default()
};

client
    .update_certificate_properties(
        "certificate-name",
        certificate_update_parameters.try_into()?,
        None,
    )
    .await?
    .into_model()?;
```

## Delete Certificate

```rust
client.delete_certificate("certificate-name", None).await?;
```

## List Certificates

```rust
use azure_security_keyvault_certificates::ResourceExt;
use futures::TryStreamExt;

let mut pager = client.list_certificate_properties(None)?.into_stream();
while let Some(certificate) = pager.try_next().await? {
    let name = certificate.resource_id()?.name;
    println!("Found Certificate with Name: {}", name);
}
```

## Key Operations Using Certificates

Sign data using an EC certificate key via the `KeyClient`:

```rust
use azure_security_keyvault_certificates::{
    models::{
        CertificatePolicy, CreateCertificateParameters, CurveName, IssuerParameters,
        KeyProperties, KeyType, KeyUsageType, X509CertificateProperties,
    },
    ResourceExt,
};
use azure_security_keyvault_keys::models::{SignParameters, SignatureAlgorithm};
use openssl::sha::sha256;

let policy = CertificatePolicy {
    x509_certificate_properties: Some(X509CertificateProperties {
        subject: Some("CN=DefaultPolicy".into()),
        key_usage: Some(vec![KeyUsageType::DigitalSignature]),
        ..Default::default()
    }),
    issuer_parameters: Some(IssuerParameters {
        name: Some("Self".into()),
        ..Default::default()
    }),
    key_properties: Some(KeyProperties {
        key_type: Some(KeyType::Ec),
        curve: Some(CurveName::P256),
        ..Default::default()
    }),
    ..Default::default()
};

let body = CreateCertificateParameters {
    certificate_policy: Some(policy),
    ..Default::default()
};

let certificate = client
    .create_certificate("ec-signing-certificate", body.try_into()?, None)?
    .await?
    .into_model()?;
let certificate_version = certificate
    .resource_id()?
    .version
    .expect("certificate version required");

let digest = sha256("plaintext".as_bytes()).to_vec();

let body = SignParameters {
    algorithm: Some(SignatureAlgorithm::Es256),
    value: Some(digest),
};

let signature = key_client
    .sign("ec-signing-certificate", &certificate_version, body.try_into()?, None)
    .await?
    .into_model()?;
```

## Error Handling

```rust
match client.get_certificate("certificate-name", None).await {
    Ok(response) => println!("Certificate: {:#?}", response.into_model()?.x509_thumbprint),
    Err(err) => println!("Error: {:#?}", err.into_inner()?),
}
```

## RBAC Permissions

| Role                            | Access                     |
| ------------------------------- | -------------------------- |
| `Key Vault Certificates Officer` | Full CRUD on certificates  |
| `Key Vault Reader`              | Read certificate metadata  |

## Best Practices

1. **Use Entra ID auth** — `DeveloperToolsCredential` for dev, `ManagedIdentityCredential` for production
2. **Note the `?` before `.await?` on `create_certificate`** — it returns a Poller
3. **Use `ResourceExt`** — for extracting names and versions from resource IDs
4. **Use managed certificates** — auto-renewal with supported issuers
5. **Monitor expiration** — set up alerts for expiring certificates

## Reference Links

| Resource      | Link                                                                                                    |
| ------------- | ------------------------------------------------------------------------------------------------------- |
| API Reference | https://docs.rs/azure_security_keyvault_certificates                                                    |
| Source Code   | https://github.com/Azure/azure-sdk-for-rust/tree/main/sdk/keyvault/azure_security_keyvault_certificates |
| crates.io     | https://crates.io/crates/azure_security_keyvault_certificates                                           |
