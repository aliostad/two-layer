# Two-layer REST application with Azure Terraform

This repository contains two ASP.NET Core Web APIs:

- Layer 1 (`Layer1.BatchApi`): receives a batch request with up to 100 items and calls Layer 2 for each item.
- Layer 2 (`Layer2.Simulator`): simulates database operation latency using `Task.Delay` where delay is sampled from a normal distribution per operation profile.

Both services are dockerized.

## Architecture

- `POST /api/batch/process` on Layer 1 accepts:
  - `{ "items": [{ "id": "1", "operation": "insert" }, ...] }`
  - max 100 items
- Layer 1 calls Layer 2 `POST /api/simulate` for each item.
- Layer 2 supports configured operations with mean/stdev delay profiles:
  - `insert`, `update`, `delete`, `query`

## Local run

Open two terminals in repo root.

1. Run Layer 2:

```bash
dotnet run --project Layer2.Simulator
```

2. Run Layer 1:

```bash
dotnet run --project Layer1.BatchApi
```

Default local URLs from launch settings:

- Layer 2: `http://localhost:5196`
- Layer 1: `http://localhost:5007`

## Local run with Docker

Build and run both services using Docker Compose:

```bash
export DD_API_KEY=<your_datadog_api_key>
export DD_SITE=datadoghq.eu
docker compose up --build
```

Endpoints:

- Layer 1: `http://localhost:5007`
- Layer 2: `http://localhost:5196`

Stop:

```bash
docker compose down
```

### Datadog profiling notes

- Both service Docker images install Datadog .NET auto-instrumentation and enable continuous profiling.
- Both containers use Datadog `serverless-init` as entrypoint and run the .NET app via container `CMD`.
- `DD_API_KEY` is intentionally runtime-injected (for example via environment variable) and not baked into images.
- `DD_SITE` is configurable at runtime (defaults to `datadoghq.eu` in docker-compose).
- Service-level Datadog config placeholders are available in each appsettings file under `Datadog`.

## Build container images manually

From repository root:

```bash
docker build -f Layer1.BatchApi/Dockerfile -t <registry>/<layer1-image>:<tag> .
docker build -f Layer2.Simulator/Dockerfile -t <registry>/<layer2-image>:<tag> .
```

Push images:

```bash
docker push <registry>/<layer1-image>:<tag>
docker push <registry>/<layer2-image>:<tag>
```

## Test request

```bash
curl -X POST http://localhost:5007/api/batch/process \
  -H "Content-Type: application/json" \
  -d '{
    "items": [
      {"id": "1", "operation": "insert"},
      {"id": "2", "operation": "query"},
      {"id": "3", "operation": "update"}
    ]
  }'
```

## Terraform deployment to Azure

Terraform files are under `terraform/`.

### Prerequisites

- Azure CLI logged in: `az login`
- Terraform installed
- Docker installed
- Container images pushed to a reachable registry (Docker Hub or ACR)

### Configure Terraform variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Update `terraform.tfvars` with:

- globally unique app names
- `layer1_container_image`
- `layer2_container_image`
- `container_registry_url`

If you use Docker Hub, registry URL is `https://index.docker.io`.

### Deploy

```bash
terraform init
terraform plan
terraform apply
```

Terraform outputs:

- `layer1_url`
- `layer2_url`

Layer 1 gets `Layer2__BaseUrl` set automatically to Layer 2's Azure URL.
