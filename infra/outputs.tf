output "api_endpoint" {
  description = "Role Fit API endpoint"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/match"
}

output "sagemaker_endpoint_name" {
  description = "SageMaker embedding endpoint name"
  value       = aws_sagemaker_endpoint.embeddings.name
}

output "embeddings_bucket" {
  description = "S3 bucket for profile embeddings"
  value       = aws_s3_bucket.embeddings.bucket
}
