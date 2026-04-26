# Acceptance Criteria: hosted-agents-v2-py

**Service**: Microsoft Foundry Hosted Agents
**Primary packages**: `azure-ai-agentserver-responses`, `azure-ai-agentserver-invocations`, `agent-framework-foundry-hosting`, `azure-ai-projects>=2.1.0`
**Purpose**: Validate refreshed public preview hosted-agent guidance across protocols, frameworks, deployment, and migration.

---

## 1. Protocol Selection

### 1.1 Correct Protocol Guidance

#### ✅ CORRECT: Responses for conversational agents

```text
Use the Responses protocol for conversational assistants, multi-turn chat, RAG, tools, streaming, and background processing that fits the OpenAI Responses contract.
```

#### ✅ CORRECT: Invocations for arbitrary JSON

```text
Use the Invocations protocol for webhooks, structured processing, custom payloads, protocol bridges, custom SSE, and non-OpenAI callers.
```

#### ✅ CORRECT: Both protocols can be exposed

```yaml
protocols:
  - protocol: responses
    version: 1.0.0
  - protocol: invocations
    version: 1.0.0
```

### 1.2 Anti-Patterns

#### ❌ INCORRECT: Old protocol version

Do not use the initial-preview protocol version `v1`; refreshed hosted agents require protocol version `1.0.0`.

#### ❌ INCORRECT: Treating Invocations as a chat-history protocol

```text
Use Invocations for normal chat because Foundry manages conversation history automatically.
```

---

## 2. Protocol Libraries

### 2.1 Correct Python Imports

#### ✅ CORRECT: Responses protocol host

```python
from azure.ai.agentserver.responses import (
    CreateResponse,
    ResponseContext,
    ResponsesAgentServerHost,
    TextResponse,
)
```

#### ✅ CORRECT: Invocations protocol host

```python
from azure.ai.agentserver.invocations import InvocationAgentServerHost
from starlette.requests import Request
from starlette.responses import JSONResponse, Response
```

#### ✅ CORRECT: Agent Framework hosting bridge

```python
from agent_framework import Agent
from agent_framework.foundry import FoundryChatClient
from agent_framework_foundry_hosting import ResponsesHostServer
```

### 2.2 Correct .NET Packages

#### ✅ CORRECT: .NET protocol packages

```bash
dotnet add package Azure.AI.AgentServer.Responses
dotnet add package Azure.AI.AgentServer.Invocations
dotnet add package Azure.Identity
```

### 2.3 Anti-Patterns

#### ❌ INCORRECT: Removed framework adapter package

```python
from azure.ai.agentserver.agentframework import from_agent_framework
```

#### ❌ INCORRECT: Removed LangGraph adapter package

```python
from azure.ai.agentserver.langgraph import from_langgraph
```

#### ❌ INCORRECT: Old .NET Agent Framework adapter package

```bash
dotnet add package Azure.AI.AgentServer.AgentFramework
```

---

## 3. Agent Framework Pattern

### 3.1 Correct Python Agent Framework Host

#### ✅ CORRECT: `FoundryChatClient` with `ResponsesHostServer`

```python
import os

from agent_framework import Agent
from agent_framework.foundry import FoundryChatClient
from agent_framework_foundry_hosting import ResponsesHostServer
from azure.identity import DefaultAzureCredential

client = FoundryChatClient(
    project_endpoint=os.environ["FOUNDRY_PROJECT_ENDPOINT"],
    model=os.environ["AZURE_AI_MODEL_DEPLOYMENT_NAME"],
    credential=DefaultAzureCredential(),
)

agent = Agent(
    client=client,
    instructions="You are a helpful assistant.",
    default_options={"store": False},
)

ResponsesHostServer(agent).run()
```

### 3.2 Anti-Patterns

#### ❌ INCORRECT: Initial-preview Agent Framework APIs

```python
from azure.ai.agentserver.agentframework import from_agent_framework
from agent_framework import ChatAgent
from agent_framework.azure import AzureAIAgentClient

agent = ChatAgent(...)
from_agent_framework(agent).run()
```

#### ❌ INCORRECT: Duplicating Responses history by default

If you omit `default_options={"store": False}` in Agent Framework Responses agents, you risk duplicating conversation history because the hosted Responses platform already manages it.

---

## 4. BYO Protocol Host Patterns

### 4.1 Correct Responses Host

#### ✅ CORRECT: `ResponsesAgentServerHost` handler

```python
import asyncio

from azure.ai.agentserver.responses import (
    CreateResponse,
    ResponseContext,
    ResponsesAgentServerHost,
    TextResponse,
)

app = ResponsesAgentServerHost()

@app.response_handler
async def handle_response(
    request: CreateResponse,
    context: ResponseContext,
    cancellation_signal: asyncio.Event,
):
    user_text = await context.get_input_text()
    return TextResponse(context, request, text=f"Echo: {user_text}")

app.run()
```

### 4.2 Correct Invocations Host

#### ✅ CORRECT: `InvocationAgentServerHost` handler

```python
from azure.ai.agentserver.invocations import InvocationAgentServerHost
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

app = InvocationAgentServerHost()

@app.invoke_handler
async def handle_invocation(request: Request) -> Response:
    payload = await request.json()
    return JSONResponse({"response": payload.get("message", "")})

app.run()
```

### 4.3 Correct Multi-Protocol Host

#### ✅ CORRECT: Cooperative inheritance

```python
from azure.ai.agentserver.invocations import InvocationAgentServerHost
from azure.ai.agentserver.responses import ResponsesAgentServerHost

class HostedAgentHost(InvocationAgentServerHost, ResponsesAgentServerHost):
    pass
```

### 4.4 Anti-Patterns

#### ❌ INCORRECT: Hand-rolled health endpoint instead of protocol libraries

```python
@app.get("/readiness")
def readiness():
    return {"ok": True}
```

#### ❌ INCORRECT: Invocations handler returning raw dict

```python
@app.invoke_handler
async def handle_invocation(request: Request):
    return {"response": "ok"}
```

---

## 5. Deployment Configuration

### 5.1 Correct Manifest

#### ✅ CORRECT: `agent.manifest.yaml`

```yaml
name: basic-responses-agent
template:
  name: basic-responses-agent
  kind: hosted
  protocols:
    - protocol: responses
      version: 1.0.0
  environment_variables:
    - name: AZURE_AI_MODEL_DEPLOYMENT_NAME
      value: "{{AZURE_AI_MODEL_DEPLOYMENT_NAME}}"
resources:
  - kind: model
    id: gpt-4.1-mini
    name: AZURE_AI_MODEL_DEPLOYMENT_NAME
```

#### ✅ CORRECT: `agent.yaml`

```yaml
kind: hosted
name: basic-responses-agent
protocols:
  - protocol: responses
    version: 1.0.0
resources:
  cpu: "0.25"
  memory: "0.5Gi"
```

### 5.2 Anti-Patterns

#### ❌ INCORRECT: Redeclaring platform-injected variables

```yaml
environment_variables:
  - name: FOUNDRY_PROJECT_ENDPOINT
    value: "https://example.services.ai.azure.com/api/projects/project"
  - name: APPLICATIONINSIGHTS_CONNECTION_STRING
    value: "InstrumentationKey=..."
```

#### ❌ INCORRECT: Old `v1` protocol version

Do not use `version: "v1"` in `agent.yaml` or `agent.manifest.yaml`; use `version: 1.0.0`.

#### ❌ INCORRECT: Defining tools in agent deployment config

```yaml
tools:
  - type: code_interpreter
```

---

## 6. Azure Developer CLI Workflow

### 6.1 Correct Commands

#### ✅ CORRECT: Scaffold, run, deploy, inspect, monitor

```bash
azd ext install azure.ai.agents
azd ai agent init
azd ai agent run
azd ai agent invoke --local "Hello"
azd up
azd ai agent show --output table
azd ai agent monitor --tail 20
azd down
```

### 6.2 Anti-Patterns

#### ❌ INCORRECT: Removed `az cognitiveservices agent` commands

```bash
az cognitiveservices agent start --name my-agent --agent-version 1
az cognitiveservices agent stop --name my-agent --agent-version 1
az cognitiveservices agent list-versions --name my-agent
```

#### ❌ INCORRECT: Manual capability host setup

```bash
az rest --method PUT --url "$ACCOUNT_URL/capabilityHosts/accountcaphost"
```

---

## 7. Direct Python SDK Deployment

### 7.1 Correct SDK Version Creation

#### ✅ CORRECT: `HostedAgentDefinition`, `allow_preview=True`, protocol `1.0.0`

```python
import os

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import AgentProtocol, HostedAgentDefinition, ProtocolVersionRecord
from azure.identity import DefaultAzureCredential

project = AIProjectClient(
    endpoint=os.environ["AZURE_AI_PROJECT_ENDPOINT"],
    credential=DefaultAzureCredential(),
    allow_preview=True,
)

agent = project.agents.create_version(
    agent_name="my-hosted-agent",
    definition=HostedAgentDefinition(
        container_protocol_versions=[
            ProtocolVersionRecord(protocol=AgentProtocol.RESPONSES, version="1.0.0"),
            ProtocolVersionRecord(protocol=AgentProtocol.INVOCATIONS, version="1.0.0"),
        ],
        image="myregistry.azurecr.io/my-agent:v1",
        cpu="1",
        memory="2Gi",
        environment_variables={
            "AZURE_AI_MODEL_DEPLOYMENT_NAME": os.environ["AZURE_AI_MODEL_DEPLOYMENT_NAME"],
        },
    ),
)
```

#### ✅ CORRECT: Dedicated endpoint SDK invocation

```python
openai_client = project.get_openai_client(agent_name="my-hosted-agent")
response = openai_client.responses.create(input="Hello!")
print(response.output_text)
```

### 7.2 Anti-Patterns

#### ❌ INCORRECT: Initial-preview hosted agent definition

```python
from azure.ai.projects.models import ImageBasedHostedAgentDefinition

agent = project.agents.create_version(
    agent_name="my-hosted-agent",
    definition=ImageBasedHostedAgentDefinition(
        container_protocol_versions=[
            ProtocolVersionRecord(protocol=AgentProtocol.RESPONSES, version="v1")
        ],
        tools=[{"type": "code_interpreter"}],
    ),
)
```

#### ❌ INCORRECT: Shared endpoint `agent_reference` routing

```python
openai_client = project.get_openai_client()
openai_client.responses.create(
    input="Hello!",
    extra_body={"agent_reference": {"name": "my-hosted-agent", "type": "agent_reference"}},
)
```

#### ❌ INCORRECT: Missing preview flag for agent-bound OpenAI client

If you use `project.get_openai_client(agent_name="...")`, construct `AIProjectClient` with `allow_preview=True` during preview.

---

## 8. REST Invocation

### 8.1 Correct REST Endpoints

#### ✅ CORRECT: Responses endpoint with preview header

```bash
curl -X POST "$BASE_URL/agents/my-hosted-agent/endpoint/protocols/openai/responses?api-version=v1" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Foundry-Features: HostedAgents=V1Preview" \
  -d '{"input": "Hello!", "stream": false}'
```

#### ✅ CORRECT: Invocations endpoint with preview header

```bash
curl -X POST "$BASE_URL/agents/my-hosted-agent/endpoint/protocols/invocations?api-version=v1" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Foundry-Features: HostedAgents=V1Preview" \
  -d '{"message": "Process this task"}'
```

### 8.2 Anti-Patterns

#### ❌ INCORRECT: Shared project responses endpoint

```bash
curl -X POST "$BASE_URL/openai/responses?api-version=v1" \
  -d '{"input": "Hello!", "agent_reference": {"name": "my-agent"}}'
```

#### ❌ INCORRECT: Missing preview header during preview

During preview, REST calls to hosted-agent endpoints must include `Foundry-Features: HostedAgents=V1Preview`.

---

## 9. Identity, RBAC, and Container Requirements

### 9.1 Correct Requirements

#### ✅ CORRECT: Build linux/amd64 image

```bash
docker build --platform linux/amd64 -t my-agent:v1 .
```

#### ✅ CORRECT: Assign downstream permissions to agent identity

```text
Grant downstream Azure resource access to the dedicated agent Entra identity created at deploy time.
```

#### ✅ CORRECT: Project managed identity used for image pulls

```text
Grant Container Registry Repository Reader or AcrPull to the Foundry project managed identity for ACR image pulls.
```

### 9.2 Anti-Patterns

#### ❌ INCORRECT: Treating project managed identity as runtime identity

```text
Grant all runtime model and storage access only to the project managed identity.
```

#### ❌ INCORRECT: ARM-only image build

```bash
docker build -t my-agent:v1 .
```

---

## Summary Checklist

Before submitting hosted-agent guidance or code, verify:

- [ ] Protocol choice is explicit: Responses for OpenAI-compatible chat; Invocations for arbitrary JSON/custom protocols.
- [ ] Protocol libraries are `azure-ai-agentserver-responses` and/or `azure-ai-agentserver-invocations` for Python, or `Azure.AI.AgentServer.Responses`/`Azure.AI.AgentServer.Invocations` for .NET.
- [ ] Agent Framework Python uses `FoundryChatClient`, `Agent`, and `ResponsesHostServer`.
- [ ] BYO code uses `ResponsesAgentServerHost` or `InvocationAgentServerHost`.
- [ ] `agent.yaml` uses `version: 1.0.0`.
- [ ] Platform-injected `FOUNDRY_*` and Application Insights variables are not redeclared.
- [ ] Direct SDK deployment uses `HostedAgentDefinition`, `azure-ai-projects>=2.1.0`, `allow_preview=True`, and waits for `active`.
- [ ] Invocation uses the dedicated agent endpoint or `project.get_openai_client(agent_name=...)`.
- [ ] Removed APIs and old packages are not recommended.
- [ ] Identity/RBAC guidance distinguishes agent Entra identity from project managed identity.
