provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  # HuggingFace PyTorch inference DLC — CPU, ap-southeast-2
  hf_image_uri = "763104351884.dkr.ecr.${var.aws_region}.amazonaws.com/huggingface-pytorch-inference:2.1.0-transformers4.37.0-cpu-py310-ubuntu22.04"
}

# ── SageMaker ────────────────────────────────────────────────────────────────

resource "aws_iam_role" "sagemaker" {
  name = "${var.project_name}-sagemaker"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sagemaker.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "sagemaker" {
  role       = aws_iam_role.sagemaker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_sagemaker_model" "embeddings" {
  name               = "${var.project_name}-embeddings"
  execution_role_arn = aws_iam_role.sagemaker.arn

  primary_container {
    image = local.hf_image_uri
    environment = {
      HF_MODEL_ID                   = "sentence-transformers/all-MiniLM-L6-v2"
      HF_TASK                       = "feature-extraction"
      SAGEMAKER_CONTAINER_LOG_LEVEL = "20"
    }
  }

  tags = var.tags
}

resource "aws_sagemaker_endpoint_configuration" "embeddings" {
  name = "${var.project_name}-embeddings-config"

  production_variants {
    variant_name = "AllTraffic"
    model_name   = aws_sagemaker_model.embeddings.name

    serverless_config {
      memory_size_in_mb = 2048
      max_concurrency   = 5
    }
  }

  tags = var.tags
}

resource "aws_sagemaker_endpoint" "embeddings" {
  name                 = "${var.project_name}-embeddings"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.embeddings.name
  tags                 = var.tags
}

# ── S3 (profile embeddings) ───────────────────────────────────────────────────

resource "aws_s3_bucket" "embeddings" {
  bucket = "${var.project_name}-embeddings"
  tags   = var.tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "embeddings" {
  bucket = aws_s3_bucket.embeddings.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "embeddings" {
  bucket                  = aws_s3_bucket.embeddings.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── Lambda ────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "lambda" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["sagemaker:InvokeEndpoint"]
        Resource = aws_sagemaker_endpoint.embeddings.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.embeddings.arn}/*"
      }
    ]
  })
}

resource "aws_lambda_function" "match" {
  function_name    = "${var.project_name}-match"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "match_handler.handler"
  filename         = "lambda_match.zip"
  source_code_hash = filebase64sha256("lambda_match.zip")
  timeout          = 60
  memory_size      = 512

  environment {
    variables = {
      SAGEMAKER_ENDPOINT = aws_sagemaker_endpoint.embeddings.name
      EMBEDDINGS_BUCKET  = aws_s3_bucket.embeddings.bucket
      EMBEDDINGS_KEY     = "profile_embeddings.json"
      CORS_ORIGIN        = var.cors_allowed_origin
    }
  }

  tags = var.tags
}

# ── API Gateway ───────────────────────────────────────────────────────────────

resource "aws_api_gateway_rest_api" "match" {
  name = "${var.project_name}-api"
  tags = var.tags
}

resource "aws_api_gateway_resource" "match" {
  rest_api_id = aws_api_gateway_rest_api.match.id
  parent_id   = aws_api_gateway_rest_api.match.root_resource_id
  path_part   = "match"
}

# POST /match
resource "aws_api_gateway_method" "post" {
  rest_api_id   = aws_api_gateway_rest_api.match.id
  resource_id   = aws_api_gateway_resource.match.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "post" {
  rest_api_id             = aws_api_gateway_rest_api.match.id
  resource_id             = aws_api_gateway_resource.match.id
  http_method             = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.match.invoke_arn
}

# OPTIONS /match (CORS preflight)
resource "aws_api_gateway_method" "options" {
  rest_api_id   = aws_api_gateway_rest_api.match.id
  resource_id   = aws_api_gateway_resource.match.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options" {
  rest_api_id = aws_api_gateway_rest_api.match.id
  resource_id = aws_api_gateway_resource.match.id
  http_method = aws_api_gateway_method.options.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options" {
  rest_api_id = aws_api_gateway_rest_api.match.id
  resource_id = aws_api_gateway_resource.match.id
  http_method = aws_api_gateway_method.options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options" {
  rest_api_id = aws_api_gateway_rest_api.match.id
  resource_id = aws_api_gateway_resource.match.id
  http_method = aws_api_gateway_method.options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${var.cors_allowed_origin}'"
  }
  depends_on = [aws_api_gateway_method_response.options]
}

resource "aws_api_gateway_deployment" "match" {
  rest_api_id = aws_api_gateway_rest_api.match.id
  depends_on  = [aws_api_gateway_integration.post, aws_api_gateway_integration_response.options]
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.match.id
  deployment_id = aws_api_gateway_deployment.match.id
  stage_name    = "prod"
  tags          = var.tags
}

resource "aws_api_gateway_method_settings" "throttle" {
  rest_api_id = aws_api_gateway_rest_api.match.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  method_path = "*/*"
  settings {
    throttling_rate_limit  = 5
    throttling_burst_limit = 10
  }
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.match.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.match.execution_arn}/*/*"
}

# ── SSM (portfolio site reads this at build time) ─────────────────────────────

resource "aws_ssm_parameter" "api_url" {
  name  = "/portfolio/match-api-url"
  type  = "String"
  value = "${aws_api_gateway_stage.prod.invoke_url}/match"
  tags  = var.tags
}
