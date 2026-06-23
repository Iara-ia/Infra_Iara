output "api_url" {
  description = "URL pública da API (API Gateway)."
  value       = aws_apigatewayv2_api.http.api_endpoint
}

output "media_cdn_domain" {
  description = "Domínio do CloudFront para mídia."
  value       = aws_cloudfront_distribution.media.domain_name
}

output "aurora_endpoint" {
  description = "Endpoint do cluster Aurora (writer)."
  value       = aws_rds_cluster.aurora.endpoint
}

output "jobs_queue_url" {
  description = "URL da fila SQS de jobs."
  value       = aws_sqs_queue.jobs.url
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "ecr_back_repo_url" {
  description = "URL do repositório ECR do Back_Iara (push da imagem no CI)."
  value       = aws_ecr_repository.back.repository_url
}

output "ecr_front_repo_url" {
  description = "URL do repositório ECR do Front-Iara."
  value       = aws_ecr_repository.front.repository_url
}

output "app_secret_arn" {
  description = "ARN do segredo da app (preencher valores no deploy/CI)."
  value       = aws_secretsmanager_secret.app.arn
}
