output "input_bucket" {
  value = aws_s3_bucket.in.bucket
}

output "output_bucket" {
  value = aws_s3_bucket.out.bucket
}

output "ecr_repo_url" {
  value = aws_ecr_repository.repo.repository_url
}

output "lambda_name" {
  value = aws_lambda_function.fn.function_name
}
