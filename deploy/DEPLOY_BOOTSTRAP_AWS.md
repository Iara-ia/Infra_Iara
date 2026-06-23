# Deploy BOOTSTRAP da IARA na AWS (operar só a Isabella, ~R$ 150–400/mês)

Sobe a **mesma aplicação** (sem mexer no código) num **único host barato** na AWS, via Docker.
Não usa o Terraform serverless (Aurora/Lambda) — esse é o de **escala**, fica pra quando vender o SaaS.

> 💡 **O app não muda.** Aqui só há empacotamento (Dockerfiles) + um compose + variáveis de
> ambiente. Tudo é provider-agnostic: trocar de banco/host/publicador depois é só env.

---

## 1. O que provisionar na AWS (escolha UM host)

| Opção | Specs sugeridos | Custo aprox. | Quando |
|---|---|---|---|
| **Lightsail** (recomendado) | 2–4 GB RAM / 2 vCPU | US$ 12–24/mês | mais simples, preço fixo |
| **EC2** `t4g.small` (ARM) | 2 GB RAM | ~US$ 12/mês + EBS | se já curte EC2 |

Ambos rodam o mesmo Docker. 2 GB RAM dá conta de Postgres + Redis + API + Worker + Painel
no começo (Reels em volume baixo). Suba para 4 GB se for gerar muita mídia.

> Não rode `terraform apply` da pasta `terraform/` agora — aquilo provisiona Aurora/Lambda/etc.
> (o caro). É o caminho de upgrade, não o de bootstrap.

## 2. Preparar o host (uma vez)

```bash
# Ubuntu 22.04 (Lightsail/EC2)
sudo apt-get update && sudo apt-get install -y docker.io docker-compose-plugin git
sudo usermod -aG docker $USER && newgrp docker

# clonar os 3 repos como pastas IRMÃS
mkdir -p ~/iara && cd ~/iara
git clone https://github.com/Iara-ia/Back_Iara.git
git clone https://github.com/Iara-ia/Front-Iara.git
git clone https://github.com/Iara-ia/Infra_Iara.git
```

## 3. Configurar variáveis

```bash
cd ~/iara/Infra_Iara
cp deploy/.env.prod.example deploy/.env.prod
nano deploy/.env.prod   # preencha senhas, domínio e (quando tiver) chaves
```
Mínimo para subir: `POSTGRES_*`, `DATABASE_URL`, `TOKEN_ENC_KEY`, `NEXT_PUBLIC_API_BASE_URL`.
Os `PROVIDER_*` podem ficar em `mock` no início (sobe e roda; mídia vira placeholder).

## 4. Subir

```bash
docker compose -f deploy/docker-compose.prod.yml --env-file deploy/.env.prod up -d --build
# a API aplica as migrations sozinha no start (prisma migrate deploy)

# (opcional) popular o seed inicial:
docker compose -f deploy/docker-compose.prod.yml exec api npx tsx prisma/seed.ts
```
- Painel: `http://SEU-IP:3000`  ·  API: `http://SEU-IP:3333/health`

## 5. Domínio + HTTPS (recomendado)

Coloque um **Caddy** na frente (HTTPS automático). No mesmo host:
```bash
docker run -d --network host --restart unless-stopped \
  -v caddy_data:/data -v $PWD/Caddyfile:/etc/caddy/Caddyfile caddy
```
`Caddyfile`:
```
SEU-DOMINIO        { reverse_proxy localhost:3000 }   # painel
api.SEU-DOMINIO    { reverse_proxy localhost:3333 }   # API
```
Aponte os DNS (A record) para o IP do host. Depois ajuste `NEXT_PUBLIC_API_BASE_URL` e
`API_BASE_URL` para `https://...` e refaça o build do front (`up -d --build front`).

## 6. Firewall (Lightsail/EC2 Security Group)

Abra **80/443** (Caddy). Mantenha **3000/3333 fechados** ao público se usar o Caddy
(eles ficam só internos). **Nunca** exponha 5432/6379.

## 7. Custo mensal (bootstrap, só a Isabella)

| Item | Aprox. |
|---|---|
| Host (Lightsail 2–4 GB) | US$ 12–24 |
| Storage (S3/R2 ou disco) | US$ 0–2 |
| IA: Claude + Flux | US$ 5–10 |
| Vídeo+voz (Reels) | US$ 5–11 |
| Publicação (direto Meta/TikTok) | US$ 0 |
| **Total** | **~US$ 28–55 ≈ R$ 150–400/mês** |

> A maior economia vs. serverless: **sair do Ayrshare** (−US$ 99) e **não usar Aurora**
> (−US$ 45). Reels são o maior custo variável — comece com poucos.

## 8. Operação

```bash
docker compose -f deploy/docker-compose.prod.yml logs -f api worker   # logs
docker compose -f deploy/docker-compose.prod.yml pull && \
  docker compose -f deploy/docker-compose.prod.yml up -d --build        # atualizar (git pull antes)
docker compose -f deploy/docker-compose.prod.yml exec postgres \
  pg_dump -U iara iara > backup_$(date +%F).sql                         # backup do banco
```

## 9. Ligar o "real" depois (sem mexer no código)

- **Imagem com o rosto da Isabella:** `PROVIDER_IMAGE=flux` + `REPLICATE_API_TOKEN` + colar o
  `loraId` no painel (ver `Back_Iara/docs/COMO_TREINAR_LORA.md`).
- **Publicar de verdade:** `PROVIDER_DISTRIBUTION=ayrshare` + `AYRSHARE_API_KEY` — ou o
  publicador **direto Meta/TikTok** (de graça) quando esse provider existir.
- **Storage durável:** `STORAGE_PROVIDER=r2` + chaves (Cloudflare R2, egress grátis).

## 10. Upgrade para o SaaS (quando captar)

Sem reescrever nada: `cd terraform && terraform apply` (infra serverless já pronta),
apontar os envs (Neon/container → Aurora/Lambda), migrar o banco (`pg_dump` → restore) e
ligar o Ayrshare/Cognito. O mesmo binário roda nos dois mundos.
