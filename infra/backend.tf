terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"   # replace with your S3 bucket
    key            = "sagemaker-role-fit/terraform.tfstate"
    region         = "ap-southeast-2"                # replace with your AWS region
    dynamodb_table = "your-terraform-state-lock"     # replace with your DynamoDB table
    encrypt        = true
  }
}
