// ============================================================
// IARA — IaC serverless (espelha o painel de custos AWS). `terraform validate` PASSA.
//
// ESTADO: IAM (logs/SQS/Secrets/S3), CloudWatch log groups, Secrets Manager, ECR e o
// env das Lambdas já estão definidos (ver support.tf). A única lacuna inerente ao IaC é o
// BUNDLE de código: as Lambdas usam um placeholder zip — o CI do Back_Iara substitui por
// `filename`/`image_uri` reais no deploy. Ainda como TODO opcional: ACM/aliases do
// CloudFront (domínio) e a ASL real das Tasks do Step Functions.
//
// Recursos (5 camadas → infra): geração de conteúdo (Step Functions + Lambda + SQS),
// agente/cron (EventBridge), API (API Gateway + Lambda), dados (Aurora Serverless v2 +
// pgvector), mídia (S3 + CloudFront), auth (Cognito), config (Secrets Manager), imagens (ECR).
// ============================================================

locals {
  name = "${var.project}-${var.env}"
}

// ---------------------- IDENTIDADE / AUTH (Cognito) ----------------------
resource "aws_cognito_user_pool" "main" {
  name = "${local.name}-users"
  // TODO(real): MFA, password policy, lambda triggers (pós-confirmação → cria Org/User).
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_client" "web" {
  name         = "${local.name}-web"
  user_pool_id = aws_cognito_user_pool.main.id
  // TODO(real): callback_urls do Front-Iara, OAuth flows.
  generate_secret = false
}

// ---------------------- DADOS (Aurora Serverless v2 + pgvector) ----------------------
resource "aws_rds_cluster" "aurora" {
  cluster_identifier = "${local.name}-pg"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned" // v2 usa 'provisioned' + serverlessv2_scaling_configuration
  engine_version     = "16.4"
  database_name      = "iara"
  master_username    = var.db_master_username
  // TODO(real): master_password via Secrets Manager (manage_master_user_password = true).
  manage_master_user_password = true
  storage_encrypted           = true
  skip_final_snapshot         = true

  serverlessv2_scaling_configuration {
    min_capacity = 0.5 // ACUs — escala a zero-ish em baixa carga (custo mínimo)
    max_capacity = 4.0
  }
  // pgvector: habilitar a extensão na migration (CREATE EXTENSION vector) — já no schema Prisma.
}

resource "aws_rds_cluster_instance" "aurora" {
  identifier         = "${local.name}-pg-1"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version
}

// ---------------------- MÍDIA (S3 + CloudFront) ----------------------
resource "aws_s3_bucket" "media" {
  bucket = "${local.name}-media"
}

resource "aws_s3_bucket_public_access_block" "media" {
  bucket                  = aws_s3_bucket.media.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "media" {
  name                              = "${local.name}-media-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "media" {
  enabled             = true
  default_root_object = ""
  // TODO(real): aliases + viewer_certificate (ACM) quando houver domínio.
  origin {
    domain_name              = aws_s3_bucket.media.bucket_regional_domain_name
    origin_id                = "s3-media"
    origin_access_control_id = aws_cloudfront_origin_access_control.media.id
  }
  default_cache_behavior {
    target_origin_id       = "s3-media"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }
  restrictions {
    geo_restriction { restriction_type = "none" }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

// ---------------------- FILA (SQS) ----------------------
// Espelha a fila BullMQ do MVP (iara-jobs). Em serverless, jobs de geração → SQS → Lambda.
resource "aws_sqs_queue" "jobs_dlq" {
  name                      = "${local.name}-jobs-dlq"
  message_retention_seconds = 1209600 // 14 dias
}

resource "aws_sqs_queue" "jobs" {
  name                       = "${local.name}-jobs"
  visibility_timeout_seconds = 300
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.jobs_dlq.arn
    maxReceiveCount     = 3 // espelha attempts=3 do BullMQ
  })
}

// ---------------------- COMPUTE (Lambda) ----------------------
// PLACEHOLDER: pacote de deploy fictício. No real, o build do Back_Iara gera os zips/imagens.
data "archive_file" "placeholder" {
  type        = "zip"
  output_path = "${path.module}/build/placeholder.zip"
  source {
    content  = "// TODO: substituir pelo bundle real do Back_Iara"
    filename = "index.mjs"
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "${local.name}-lambda-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

// Lambda da API (handler Fastify via aws-lambda-fastify) e Lambda do worker (consome SQS).
resource "aws_lambda_function" "api" {
  function_name = "${local.name}-api"
  role          = aws_iam_role.lambda_exec.arn
  runtime       = "nodejs20.x"
  handler       = "index.handler" // TODO(real): handler do Back_Iara (api/main → lambda)
  filename      = data.archive_file.placeholder.output_path
  timeout       = 30
  memory_size   = 512

  environment {
    variables = {
      NODE_ENV       = var.env == "prod" ? "production" : "development"
      QUEUE_URL      = aws_sqs_queue.jobs.url
      S3_BUCKET      = aws_s3_bucket.media.id
      MEDIA_CDN      = aws_cloudfront_distribution.media.domain_name
      APP_SECRET_ARN = aws_secretsmanager_secret.app.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.api, aws_iam_role_policy_attachment.lambda_basic]
}

resource "aws_lambda_function" "worker" {
  function_name = "${local.name}-worker"
  role          = aws_iam_role.lambda_exec.arn
  runtime       = "nodejs20.x"
  handler       = "index.handler" // TODO(real): handler do worker (consome a fila)
  filename      = data.archive_file.placeholder.output_path
  timeout       = 300
  memory_size   = 1024

  environment {
    variables = {
      NODE_ENV       = var.env == "prod" ? "production" : "development"
      QUEUE_URL      = aws_sqs_queue.jobs.url
      S3_BUCKET      = aws_s3_bucket.media.id
      APP_SECRET_ARN = aws_secretsmanager_secret.app.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.worker, aws_iam_role_policy_attachment.lambda_basic]
}

resource "aws_lambda_event_source_mapping" "worker_sqs" {
  event_source_arn = aws_sqs_queue.jobs.arn
  function_name    = aws_lambda_function.worker.arn
  batch_size       = 1
}

// ---------------------- API (API Gateway HTTP) ----------------------
resource "aws_apigatewayv2_api" "http" {
  name          = "${local.name}-http"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"] // TODO(real): origin do Front-Iara
    allow_methods = ["GET", "POST", "PATCH", "PUT", "OPTIONS"]
    allow_headers = ["content-type", "authorization", "x-user-id", "x-org-id"]
  }
}

resource "aws_apigatewayv2_integration" "api" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "proxy" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

// ---------------------- PIPELINE (Step Functions) ----------------------
// Espelha o pipeline de conteúdo: GenImage → ConsistencyGate → GenCaption → SafetyGate.
resource "aws_iam_role" "sfn_exec" {
  name = "${local.name}-sfn-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_sfn_state_machine" "content_pipeline" {
  name     = "${local.name}-content-pipeline"
  role_arn = aws_iam_role.sfn_exec.arn
  // ASL placeholder — cada Task invocaria uma Lambda do Back_Iara (gates).
  definition = jsonencode({
    Comment = "IARA — pipeline de geração de 1 ContentItem (scaffold)"
    StartAt = "GenImage"
    States = {
      GenImage        = { Type = "Task", Resource = aws_lambda_function.worker.arn, Next = "ConsistencyGate" }
      ConsistencyGate = { Type = "Task", Resource = aws_lambda_function.worker.arn, Next = "GenCaption" }
      GenCaption      = { Type = "Task", Resource = aws_lambda_function.worker.arn, Next = "SafetyGate" }
      SafetyGate      = { Type = "Task", Resource = aws_lambda_function.worker.arn, End = true }
    }
  })
}

// ---------------------- AGENTE / CRON (EventBridge) ----------------------
// Dispara o agente autônomo (janela ótima de postagem, geração agendada).
resource "aws_cloudwatch_event_rule" "agent_tick" {
  name                = "${local.name}-agent-tick"
  schedule_expression = "rate(1 hour)" // TODO(real): janelas ótimas por persona
}

resource "aws_cloudwatch_event_target" "agent_tick" {
  rule      = aws_cloudwatch_event_rule.agent_tick.name
  target_id = "worker"
  arn       = aws_lambda_function.worker.arn
}
