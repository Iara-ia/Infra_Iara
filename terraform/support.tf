// ============================================================
// Camada de DEPLOY-READINESS — o que faltava para o scaffold sair de "mapa" para algo
// efetivamente aplicável: IAM (logs/SQS/Secrets/S3), log groups, Secrets Manager, ECR.
// Inerente: o BUNDLE das Lambdas/containers vem do build do Back_Iara (CI) — aqui há um
// placeholder zip; troque por aws_lambda_function.*.filename/image_uri reais no pipeline.
// ============================================================

// ---------------------- IAM das Lambdas ----------------------
// Logging básico (CloudWatch) — sem isto a função nem registra logs.
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

// Permissões de aplicação: consumir/enfileirar SQS, ler o segredo da app, gravar mídia no S3.
resource "aws_iam_role_policy" "lambda_app" {
  name = "${local.name}-lambda-app"
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Sqs"
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:SendMessage"]
        Resource = [aws_sqs_queue.jobs.arn, aws_sqs_queue.jobs_dlq.arn]
      },
      {
        Sid      = "Secrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.app.arn]
      },
      {
        Sid      = "Media"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = ["${aws_s3_bucket.media.arn}/*"]
      }
    ]
  })
}

// ---------------------- Log groups (retenção = controle de custo) ----------------------
resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${local.name}-api"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/aws/lambda/${local.name}-worker"
  retention_in_days = 14
}

// ---------------------- Secrets Manager (config sensível da app) ----------------------
// Guarda DATABASE_URL, ANTHROPIC_API_KEY, AYRSHARE_API_KEY, STRIPE_SECRET_KEY, etc.
// Os VALORES entram no deploy/CI (nunca versionados). A Lambda lê via APP_SECRET_ARN no boot.
resource "aws_secretsmanager_secret" "app" {
  name        = "${local.name}-app"
  description = "IARA — variáveis sensíveis da aplicação (preenchidas no deploy/CI)."
}

// ---------------------- ECR (deploy alternativo por container) ----------------------
// Caminho container (ECS/Fargate ou Lambda-image) para Back_Iara/Front-Iara via CI.
resource "aws_ecr_repository" "back" {
  name                 = "${local.name}-back"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "front" {
  name                 = "${local.name}-front"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}
