---
name: azure-eventhub-rust
description: |
  Azure Event Hubs SDK for Rust (v0.13.0). Use for sending and receiving events, streaming data ingestion, and batch processing.
  Triggers: "event hubs rust", "ProducerClient rust", "ConsumerClient rust", "send event rust", "streaming rust".
---

# Azure Event Hubs SDK for Rust

> `azure_messaging_eventhubs` v0.13.0 — Client library for Azure Event Hubs.

## Installation

```sh
cargo add azure_messaging_eventhubs azure_identity tokio futures
```

## Environment Variables

```bash
EVENTHUBS_HOST=<namespace>.servicebus.windows.net
EVENTHUB_NAME=<eventhub-name>
```

## Key Concepts

| Concept       | Description                                         |
| ------------- | --------------------------------------------------- |
| **Namespace** | Container for one or more Event Hubs                |
| **Event Hub** | Stream of events, partitioned for parallel reads    |
| **Partition** | Ordered, append-only sequence of events             |
| **Producer**  | Sends events via `ProducerClient`                   |
| **Consumer**  | Receives events from partitions via `ConsumerClient` |

## Producer — Send Events

```rust
use azure_identity::DeveloperToolsCredential;
use azure_messaging_eventhubs::ProducerClient;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let host = "<EVENTHUBS_HOST>";
    let eventhub = "<EVENTHUB_NAME>";

    let credential = DeveloperToolsCredential::new(None)?;

    let producer = ProducerClient::builder()
        .open(host, eventhub, credential.clone())
        .await?;

    // Send a single event
    producer.send_event(vec![1, 2, 3, 4], None).await?;

    Ok(())
}
```

### Send Batch

```rust
let batch = producer.create_batch(None).await?;
assert_eq!(batch.len(), 0);
assert!(batch.try_add_event_data(vec![1, 2, 3, 4], None)?);

producer.send_batch(batch, None).await?;
```

## Consumer — Receive Events

```rust
use azure_identity::DeveloperToolsCredential;
use azure_messaging_eventhubs::ConsumerClient;

async fn open_consumer() -> Result<ConsumerClient, Box<dyn std::error::Error>> {
    let host = "<EVENTHUBS_HOST>".to_string();
    let eventhub = "<EVENTHUB_NAME>".to_string();

    let credential = DeveloperToolsCredential::new(None)?;

    let consumer = ConsumerClient::builder()
        .open(&host, eventhub, credential.clone())
        .await?;

    Ok(consumer)
}
```

### Receive from Partition

```rust
use futures::stream::StreamExt;
use azure_messaging_eventhubs::{
    ConsumerClient, OpenReceiverOptions, StartLocation, StartPosition,
};

async fn receive_events(client: &ConsumerClient) -> Result<(), Box<dyn std::error::Error>> {
    let message_receiver = client
        .open_receiver_on_partition(
            "0".to_string(),
            Some(OpenReceiverOptions {
                start_position: Some(StartPosition {
                    location: StartLocation::Earliest,
                    ..Default::default()
                }),
                ..Default::default()
            }),
        )
        .await?;

    let mut event_stream = message_receiver.stream_events();

    while let Some(event_result) = event_stream.next().await {
        match event_result {
            Ok(event) => {
                println!("Received event: {:?}", event);
            }
            Err(err) => {
                eprintln!("Error receiving event: {:?}", err);
            }
        }
    }

    Ok(())
}
```

## Best Practices

1. **Reuse clients** — create once, send many events
2. **Use batches** — more efficient than individual sends
3. **Check batch capacity** — `try_add_event_data` returns false when full
4. **Process partitions in parallel** — each partition consumed independently
5. **Use consumer groups** — isolate different consuming applications

## Checkpoint Store (Optional)

For distributed consumers with checkpointing:

```sh
cargo add azure_messaging_eventhubs_checkpointstore_blob
```

## Reference Links

| Resource      | Link                                                                                          |
| ------------- | --------------------------------------------------------------------------------------------- |
| API Reference | https://docs.rs/azure_messaging_eventhubs                                                     |
| Source Code   | https://github.com/Azure/azure-sdk-for-rust/tree/main/sdk/eventhubs/azure_messaging_eventhubs |
| crates.io     | https://crates.io/crates/azure_messaging_eventhubs                                            |
