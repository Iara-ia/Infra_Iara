# Infra_Iara

Infraestrutura da plataforma **IARA**: ambiente local de desenvolvimento (Docker) +
esqueleto de IaC para a arquitetura serverless AWS + esteira de CI dos 3 repositórios.

## Conteúdo

```
docker-compose.yml      # Postgres (pgvector) + Redis para dev local
terraform/              # ESQUELETO de IaC serverless (scaffold — não 100% deployável)
ci-templates/           # cópias de referência dos CIs do Back/Front (os ativos vivem nos repos)
.github/workflows/      # CI deste repo (terraform fmt/validate)
```

## 1. Dev local (Docker)

Sobe as dependências de runtime do **Back_Iara** (API + worker):

```bash
docker compose up -d        # Postgres :5433  +  Redis :6379
docker compose ps           # checar healthy
docker compose down         # derrubar (volume iara_pg persiste)
docker compose down -v      # derrubar e apagar dados
```

No **Back_Iara/.env**:
```
DATABASE_URL="postgresql://iara:iara@localhost:5433/iara?schema=public"
REDIS_URL="redis://localhost:6379"
```

Depois, no Back_Iara: `npm run db:migrate && npm run db:seed && npm run dev`.

## 2. IaC serverless (Terraform — scaffold)

Mapeia 1:1 os recursos do painel de custos da IARA. **Esqueleto**: handlers Lambda, ASLs
de Step Functions, certificados ACM e algumas policies estão como `TODO` placeholder — o
objetivo é a topologia, custos e dependências, não um apply pronto.

Recursos cobertos:

| Camada | Recurso AWS |
| --- | --- |
| Auth | Cognito (User Pool + Client) |
| Dados | Aurora Serverless v2 (PostgreSQL 16 + pgvector) |
| Mídia | S3 + CloudFront (OAC) |
| Fila | SQS (+ DLQ, maxReceiveCount=3 espelha o BullMQ) |
| Compute | Lambda (API via API Gateway proxy; worker via SQS event source) |
| API | API Gateway HTTP (`ANY /{proxy+}`) |
| Pipeline | Step Functions (GenImage → ConsistencyGate → GenCaption → SafetyGate) |
| Agente/cron | EventBridge (rule rate(1h) → worker) |

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # ajuste region/env
terraform fmt
terraform init -backend=false
terraform validate
# terraform plan   # exige credenciais AWS + substituir os placeholders (handlers/ASL/ACM)
```

> Evolução para deploy real: empacotar os bundles do Back_Iara (api/worker) para as
> Lambdas, escrever as ASLs reais das Tasks, configurar Secrets Manager para a senha do
> Aurora e o backend S3 de estado (já comentado em `versions.tf`).

## 3. CI dos 3 repositórios

| Repo | Workflow | O que roda |
| --- | --- | --- |
| **Back_Iara** | `.github/workflows/ci.yml` | `npm ci` → `prisma generate` → `typecheck` → `test` |
| **Front-Iara** | `.github/workflows/ci.yml` | `npm ci` → `typecheck` → `build` |
| **Infra_Iara** | `.github/workflows/terraform.yml` | `terraform fmt -check` → `init -backend=false` → `validate` |

Cópias de referência dos CIs de Back/Front estão em `ci-templates/` (os arquivos ativos
vivem em cada repositório).

## Org GitHub

Os três repositórios vivem na org **Iara-ia**: `Back_Iara`, `Front-Iara`, `Infra_Iara`.
