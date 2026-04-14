# Advanced KQL Patterns

Reference for specialized KQL features: graph queries, vector similarity, geospatial operations, time series, and external data. Consult this when a task requires these capabilities.

> **Try it yourself**: Examples marked with `// try it!` can be run on the public help cluster:
> `https://help.kusto.windows.net`, database `Samples`.

## Table of Contents

1. [Graph Queries](#1-graph-queries)
2. [Vector Similarity](#2-vector-similarity)
3. [Geospatial Operations](#3-geospatial-operations)
4. [Time Series Analysis](#4-time-series-analysis)
5. [External Data](#5-external-data)
6. [Stored Functions](#6-stored-functions)
7. [Materialized Views & Caching](#7-materialized-views--caching)
8. [Good Query Habits](#8-good-query-habits)

---

## 1. Graph Queries

KQL supports two approaches for building and querying graphs. The `graph-match` syntax is the same for both — only how the graph is constructed differs.
- **Transient graphs** — built inline with the `make-graph` operator. Useful for verifying an approach before committing to persistent graph building, or for smaller graphs (~1M entities).
- **Persistent (snapshot) graphs** — defined as a graph model and queried with `graph("ModelName")`. Best for large graphs and repeated queries where rebuilding the graph each time is too expensive.

### Querying a persistent graph model

Persistent graph models are defined once and queried repeatedly with `graph("ModelName")`. The function picks up the latest snapshot automatically. You can also target a specific snapshot with `graph("ModelName", "SnapshotName")`.

```kql
// Query the latest snapshot of a persistent graph model
graph("YaccNetwork")
| graph-match (src)-[e]->(dst)
  where src.AppName == "Gateway"
  project src.AppName, dst.AppName, e.Protocol
```

### Creating a persistent graph model

Use `.create-or-alter graph_model` to define the schema and how nodes/edges are built from tables:

````kql
// Management command — define the graph model
.create-or-alter graph_model YaccNetwork ```
{
  "Schema": {
    "Nodes": {
      "Application": {"AppName": "string", "HostingIp": "string"}
    },
    "Edges": {
      "Connection": {"Protocol": "string", "Port": "int"}
    }
  },
  "Definition": {
    "Steps": [
      {
        "Kind": "AddNodes",
        "Query": "YaccApplications | project NodeId = AppId, AppName, HostingIp",
        "NodeIdColumn": "NodeId",
        "Labels": ["Application"]
      },
      {
        "Kind": "AddEdges",
        "Query": "YaccConnections | project SourceId = SourceAppId, TargetId = TargetAppId, Protocol, Port",
        "SourceColumn": "SourceId",
        "TargetColumn": "TargetId",
        "Labels": ["Connection"]
      }
    ]
  }
}
```
````

### Ad-hoc graphs with make-graph

For one-time analysis, use the `make-graph` operator to build a transient graph inline:

```kql
// try it! — uses SimpleGraph_Nodes and SimpleGraph_Edges from help cluster
SimpleGraph_Edges
| make-graph source --> target with SimpleGraph_Nodes on id
| graph-match (src)-[e]->(dst)
  where src.name == "Alice"
  project src.name, dst.name, e.lbl
```

### Variable-length traversal

```kql
// try it! — find all paths up to 5 hops from Alice
SimpleGraph_Edges
| make-graph source --> target with SimpleGraph_Nodes on id
| graph-match (start)-[path*1..5]->(target)
  where start.name == "Alice"
  project start.name, target.name, hops = array_length(path)
```

### Pre-filtering edges (the key pattern)

Edge properties are not accessible on variable-length paths during `graph-match`. Use `all()` / `any()` for label-based filtering, or pre-filter edges before building the graph.

```kql
// ❌ WRONG — can't access properties on variable-length edge
graph-match (src)-[path*1..3]->(dst)
  where path.IsVulnerable == true

// ✅ RIGHT (persistent) — filter in graph model definition
// In the AddEdges step, set Query to: "Edges | where IsVulnerable == true | project ..."

// ✅ RIGHT (ad-hoc) — pre-filter edges before make-graph
Edges
| where IsVulnerable == true
| make-graph SourceId --> TargetId with Nodes on NodeId
| graph-match (src)-[path*1..3]->(dst)
  project src.Name, dst.Name

// ✅ RIGHT (label-based) — use all() on variable-length paths
graph("MyGraph")
| graph-match (src)-[path*1..3]->(dst)
  where all(path, labels() has "Vulnerable")
  project src.Name, dst.Name
```

### Graph snapshots

For persistent models, create materialized snapshots for faster queries:

```kql
// Create a snapshot (management command, async)
.make graph_snapshot YaccNetwork_20240115
  with (source = graph_model("YaccNetwork"))

// Query — picks up latest snapshot automatically
graph("YaccNetwork")
| graph-match (src)-[e]->(dst)
  where labels(src) has "Application"
  project src.AppName, dst.AppName

// Query a specific snapshot
graph("YaccNetwork", "YaccNetwork_20240115")
| graph-match (src)-[e]->(dst)
  project src.AppName, dst.AppName
```

### Post-processing graph results

After `graph-match` with a `project` clause, results are tabular and can be piped to any KQL operator:

```kql
graph("YaccNetwork")
| graph-match (src)-[e]->(dst)
  project src.AppName, dst.AppName, e.Port
| summarize ConnectionCount = count() by src_AppName
| top 10 by ConnectionCount desc
```

Use the `graph-to-table` operator when you need to export all nodes and edges from a graph as raw tables (without pattern matching):

```kql
graph("YaccNetwork")
| graph-to-table nodes as N, edges as E;
N | summarize count() by labels(N)
```

---

## 2. Vector Similarity

KQL has native vector operations — **don't export to Python** for cosine similarity.

### series_cosine_similarity

The most common vector operation.

```kql
// Find the most similar items to a target vector
let target_vec = toscalar(
    Embeddings | where Word == "test" | project Vec
);
Embeddings
| extend similarity = series_cosine_similarity(parse_json(Vec), target_vec)
| top 10 by similarity desc
```

### Combining vectors

```kql
// Weighted vector combination (e.g., word1 * 0.5 + word2 * 0.3 + word3 * 0.2)
let v1 = toscalar(Vecs | where Word == "hello" | project Vec);
let v2 = toscalar(Vecs | where Word == "world" | project Vec);
let v3 = toscalar(Vecs | where Word == "test" | project Vec);
let combined = series_add(
    series_add(
        series_multiply(v1, repeat(0.5, array_length(v1))),
        series_multiply(v2, repeat(0.3, array_length(v2)))
    ),
    series_multiply(v3, repeat(0.2, array_length(v3)))
);
```

### Performance consideration

Pairwise cosine similarity on 1536-dim vectors is expensive (~20s for large tables). Strategies:

1. **Pre-filter** — narrow candidates before computing similarity
2. **Round-and-join** — bucket vector dimensions to integers, join on buckets for approximate matching
3. **Project away vectors** — never include vector columns in results unless needed

```kql
// Round-and-join for approximate nearest neighbor
let target_rounded = toscalar(
    Vecs | where Word == "test"
    | project r = array_sort_asc(series_multiply(Vec, repeat(100, array_length(Vec))))
);
Vecs
| extend rounded = array_sort_asc(series_multiply(Vec, repeat(100, array_length(Vec))))
| where rounded[0] between (target_rounded[0]-10 .. target_rounded[0]+10)
| extend sim = series_cosine_similarity(Vec, toscalar(Vecs | where Word == "test" | project Vec))
| top 10 by sim desc
```

### Other series functions

| Function | Purpose |
|----------|---------|
| `series_cosine_similarity(a, b)` | Cosine similarity between two vectors |
| `series_pearson_correlation(a, b)` | Pearson correlation |
| `series_dot_product(a, b)` | Dot product |
| `series_add(a, b)` | Element-wise addition |
| `series_multiply(a, b)` | Element-wise multiplication |
| `series_subtract(a, b)` | Element-wise subtraction |
| `series_magnitude(a)` | L2 norm |

---

## 3. Geospatial Operations

### Point-in-polygon

```kql
// Check if a point is inside a polygon
| where geo_point_in_polygon(Longitude, Latitude,
    dynamic({"type":"Polygon","coordinates":[[[lon1,lat1],[lon2,lat2],...,[lon1,lat1]]]}))
```

Note: `geo_point_in_polygon` is a **scalar function**, not a plugin. It works on free clusters. Don't try to `evaluate` it as a plugin — use it directly in `| where` or `| extend`.

### Distance calculations

```kql
// try it! — distance between start and end points of storm events (meters)
StormEvents
| where isnotempty(BeginLat) and isnotempty(EndLat)
| extend distance_m = geo_distance_2points(BeginLon, BeginLat, EndLon, EndLat)
| project EventType, State, distance_m
| top 5 by distance_m desc

// Filter by distance — storms within 50km of Houston (-95.37, 29.76)
StormEvents
| where geo_distance_2points(BeginLon, BeginLat, -95.37, 29.76) < 50000
| summarize count() by EventType
```

### Spatial bucketing for joins

KQL joins are equality-only, so spatial proximity joins need pre-bucketing:

```kql
// try it! — S2 cells on storm events
StormEvents
| extend cell = geo_point_to_s2cell(BeginLon, BeginLat, 8)
| summarize count() by cell
| top 10 by count_ desc

// Then join on cell IDs (e.g., storm events near taxi pickups)
StormEvents
| extend cell = geo_point_to_s2cell(BeginLon, BeginLat, 5)
| join kind=inner (nyc_taxi | extend cell = geo_point_to_s2cell(pickup_longitude, pickup_latitude, 5)) on cell
| take 10
```

### IP geolocation

```kql
// Lookup IP addresses against a geo table
| evaluate ipv4_lookup(IpGeoTable, ClientIP, IpRange)

// Check if IP is in a range
| where ipv4_is_in_range(ClientIP, "10.0.0.0/8")

// Compare two IPs for subnet membership
| where ipv4_is_in_any_range(ClientIP, dynamic(["10.0.0.0/8", "172.16.0.0/12"]))
```

---

## 4. Time Series Analysis

### Creating time series

```kql
// try it! — basic time series from storm events
StormEvents
| make-series count() default=0 on StartTime step 1d
| render timechart

// Multi-series (one per event type)
StormEvents
| make-series count() default=0 on StartTime step 1d by EventType
| take 5
```

### Anomaly detection

```kql
// try it! — decompose and find anomalies in daily storm counts
StormEvents
| make-series count() default=0 on StartTime step 1d
| extend (anomalies, score, baseline) = series_decompose_anomalies(count_)
| mv-expand StartTime, count_, anomalies, score, baseline
| where anomalies != 0
| take 10
```

### Period detection

```kql
// Find periodic patterns
Events
| make-series count() default=0 on Timestamp step 1m
| extend (periods, scores) = series_periods_detect(count_, 4.0, 1440.0, 2)
```

### Sessionization

```kql
// Group events into sessions with 30-minute gap
Events
| order by UserId, Timestamp asc
| extend SessionId = row_window_session(Timestamp, 30m, 24h, UserId != prev(UserId))
```

### Sliding window statistics

```kql
// Rolling average over 7 days
| make-series val=avg(Value) on Timestamp step 1d
| extend rolling_avg = series_fir(val, repeat(1.0/7, 7), false)
```

---

## 5. External Data

Load small reference tables (up to ~100 MB) directly into KQL without ingestion using the `externaldata` operator:

```kql
// CSV from blob storage
let external_csv = externaldata(col1:string, col2:long)
  [h@'https://storage.blob.core.windows.net/container/file.csv']
  with (ignoreFirstRecord=true);
external_csv | where col2 > 100
```

```kql
// Gzipped CSV
let primes = externaldata(prime:long)
  [h@'https://yourstorage.blob.core.windows.net/prime-numbers/prime-numbers.csv.gz']
  with (ignoreFirstRecord=true);
primes | where prime < 100000000 | summarize max(prime)
```

```kql
// JSON with ingestion mapping (required for hierarchical formats like JSON, Parquet, Avro, ORC)
externaldata(Timestamp:datetime, TenantId:guid, MethodName:string)
  [h@'https://storage.blob.core.windows.net/events/data.json?...SAS...']
  with (format='multijson', ingestionMapping='[{"Column":"Timestamp","Properties":{"Path":"$.timestamp"}},{"Column":"TenantId","Properties":{"Path":"$.data.tenant"}},{"Column":"MethodName","Properties":{"Path":"$.data.method"}}]')
```

**Notes**:
- `externaldata` supports all [ingestion data formats](https://learn.microsoft.com/en-us/kusto/ingestion-supported-formats) (CSV, TSV, JSON, Parquet, Avro, ORC, etc.). For hierarchical formats, specify `ingestionMapping`.
- Not designed for large data volumes — for larger datasets, use **external tables** (see below) or ingest the data into a table.
- For non-tabular content (images, PDFs, JavaScript), use Python or the browser.

### External tables for larger datasets

For data too large for `externaldata` or queried repeatedly, define a persistent [external table](https://learn.microsoft.com/en-us/kusto/query/schema-entities/external-tables). External tables have a stored schema and point to data in Azure Blob Storage, ADLS, Delta Lake, or SQL databases (SQL Server, MySQL, PostgreSQL, Cosmos DB).

```kql
// Create an external table (management command)
.create external table ExternalLogs (Timestamp:datetime, Level:string, Message:string)
  kind=storage
  dataformat=csv
  (h@'https://storage.blob.core.windows.net/logs/2024/;managed_identity=system')
  with (ignoreFirstRecord=true)
```

```kql
// Query an external table using external_table()
external_table("ExternalLogs")
| where Timestamp > ago(1d)
| summarize count() by Level
```

```kql
// Discover available external tables
.show external tables
```

**When to use which**:
| Approach | Best for |
|----------|----------|
| `externaldata` | Small reference lookups (≤100 MB), one-off queries |
| External tables | Larger datasets, repeated queries, partitioned data, Delta Lake / SQL sources |
| Ingested tables | Highest performance, full indexing, data you own and query frequently |

---

## 6. Stored Functions

Some databases include pre-built stored functions (e.g., `Decrypt`, `Dekrypt`, `Verify`).

### Discovering stored functions

```kql
// Management command
.show functions
```

### Invoking stored functions

```kql
// Call a stored function
Decrypt(ciphertext, key)

// Use in a query pipeline
Logs
| extend plaintext = Decrypt(EncryptedField, "MYKEY")
| where plaintext contains "suspicious"
```

### Common pitfalls with stored functions

1. **String escaping**: KQL supports both single (`'...'`) and double (`"..."`) quotes for string literals. If a string contains special characters or backslashes, use verbatim syntax `@"..."` or `@'...'`:
   ```kql
   Decrypt(field, @"C:\path\with\backslashes")
   ```
2. **Argument types**: Ensure you pass the right type. If the function expects `string` and you have `dynamic`, cast with `tostring()`.
3. **Function not found**: Check the database — functions are database-scoped. Use `.show functions` to list available ones.

---

## 7. Materialized Views & Caching

### materialize() for subquery reuse

When a subquery is referenced multiple times, `materialize()` computes it once:

```kql
let expensive_result = materialize(
    HugeLogs
    | where Timestamp > ago(1d)
    | summarize count() by SourceIP
    | where count_ > 1000
);
// Use it twice without recomputing
expensive_result | summarize total = sum(count_)
| union (expensive_result | top 10 by count_ desc)
```

### toscalar() for single-value subqueries

```kql
// Extract a single value to use as a constant
let threshold = toscalar(Stats | summarize percentile(Value, 95));
Events | where Value > threshold
```

### datatable for inline test data

```kql
// Create test data without touching the database
let test_data = datatable(Name:string, Score:long) [
    "Alice", 95,
    "Bob", 87,
    "Charlie", 92
];
test_data | where Score > 90
```

---

## 8. Good Query Habits

Patterns that prevent wasted time, runaway queries, and unnecessary retries.

### Test transformations on small data first

Use `datatable` or `print` to validate logic before running on full tables. This catches syntax errors and logic bugs without touching real data.

```kql
// Test a regex extraction before running on millions of rows
let sample = datatable(Msg:string) [
    "User 'alice' sent 1024 bytes",
    "User 'bob' sent 512 bytes",
    "Invalid line with no match"
];
sample
| parse Msg with * "User '" Username "' sent " ByteCount " bytes"
| where isnotempty(Username)
```

```kql
// Test a datetime format with print
print result = format_datetime(datetime(2024-03-15T10:30:00Z), "yyyy-MM")
```

### Start with count, then sample, then full query

```kql
// Step 1: How big is this table?
StormEvents | count

// Step 2: What does the data look like?
StormEvents | take 10

// Step 3: Now write the real query with filters
StormEvents
| where StartTime between (datetime(2007-06-01) .. datetime(2007-06-30T23:59:59))
| summarize count() by EventType
| top 20 by count_ desc
```

### Use materialize() to avoid redundant computation

When referencing the same subquery more than once, wrap it in `materialize()` (see Section 7).

### Project early, project often

Drop columns you don't need as early as possible — especially wide columns like vectors, JSON blobs, or free-text fields. This reduces memory pressure and speeds up downstream operators.

```kql
// ❌ Carries all columns through the pipeline
StormEvents | where State == "TEXAS" | summarize count() by EventType

// ✅ Drop unneeded columns immediately
StormEvents | where State == "TEXAS" | project State, EventType | summarize count() by EventType
```

### Order predicates for maximum pruning

Kusto has efficient indexes on `datetime` and `string` term columns. Order your `where` predicates to exploit this:

1. **`datetime` filters first** — enables shard pruning (entire data extents skipped)
2. **`string`/`dynamic` term filters next** — `has`, `==`, `in` use the term index
3. **Numeric filters** — less selective but still cheap
4. **Substring scans last** — `contains`, `matches regex` must scan column data

```kql
// ❌ Substring scan runs first on all data
StormEvents
| where EventNarrative contains "power line"
| where StartTime between (datetime(2007-06-01) .. datetime(2007-06-30T23:59:59))

// ✅ Datetime prunes shards, then term filter, then substring
StormEvents
| where StartTime between (datetime(2007-06-01) .. datetime(2007-06-30T23:59:59))
| where EventType has "Wind"
| where EventNarrative contains "power line"
```

### Join performance hints

```kql
// hint.shufflekey — for high-cardinality join keys (>1M distinct values)
// Distributes data across nodes by key for parallel processing
TableA
| join hint.shufflekey=UserId kind=inner (TableB) on UserId

// hint.strategy=broadcast — when left side is small (<100 MB)
// Broadcasts the small table to all nodes
SmallLookup
| join hint.strategy=broadcast kind=inner (HugeTable) on Key

// Use lookup instead of join when right side is small
HugeTable
| lookup kind=leftouter (SmallLookup) on Key
```

### Use `in` instead of left semi join

For filtering by a single column, `in` is simpler and often faster:

```kql
// ❌ Verbose
Events
| join kind=leftsemi (AllowList | project UserId) on UserId

// ✅ Simpler and often faster
Events
| where UserId in (AllowList | project UserId)
```

### Pre-filter dynamic columns with `has`

Parsing dynamic/JSON columns is expensive. Use `has` to filter out non-matching rows before parsing:

```kql
// ❌ Parses JSON for every row
StormEvents
| where StormSummary.Details.Description has "tornado"

// ✅ Term filter first, then parse — skips JSON parsing on non-matching rows
StormEvents
| where StormSummary has "tornado"
| where StormSummary.Details.Description has "tornado"
```

### Summarize with shuffle strategy

When `summarize` has high-cardinality group keys, use `hint.strategy=shuffle` to parallelize across nodes:

```kql
// ❌ Single-node bottleneck with millions of distinct keys
Events | summarize count() by UserId

// ✅ Shuffle distributes work across all nodes
Events | summarize hint.strategy=shuffle count() by UserId
```

### Query materialized views efficiently

Use the `materialized_view()` function to query only the pre-aggregated part (faster), rather than the full view which may include un-materialized delta records:

```kql
// Queries only the materialized (pre-computed) part — fastest
materialized_view("MyAggView")

// Queries materialized + delta records — complete but slower
MyAggView
```
