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
