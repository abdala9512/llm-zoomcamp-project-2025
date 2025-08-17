locals {
  name          = "${var.project}-${var.env}"
  input_bucket  = coalesce(var.input_bucket, "${var.project}-in-${var.env}")
  output_bucket = coalesce(var.output_bucket, "${var.project}-out-${var.env}")

  tags = {
    project = var.project
    env     = var.env
  }
}

# -----------------------
# S3 buckets (private + SSE + block public access)
# -----------------------

resource "aws_s3_bucket" "in" {
  bucket = local.input_bucket
  tags   = local.tags
}

resource "aws_s3_bucket" "out" {
  bucket = local.output_bucket
  tags   = local.tags
}

resource "aws_s3_bucket_public_access_block" "in" {
  bucket                  = aws_s3_bucket.in.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "out" {
  bucket                  = aws_s3_bucket.out.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "in" {
  bucket = aws_s3_bucket.in.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "out" {
  bucket = aws_s3_bucket.out.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# -----------------------
# ECR repository
# -----------------------

resource "aws_ecr_repository" "repo" {
  name                 = var.project
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

# -----------------------
# IAM for Lambda
# -----------------------

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = local.tags
}

data "aws_iam_policy_document" "lambda" {
  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }

  statement {
    sid     = "ReadInputBucket"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.in.arn,
      "${aws_s3_bucket.in.arn}/*"
    ]
  }

  statement {
    sid       = "WriteOutputBucket"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.out.arn}/*"]
  }
}

resource "aws_iam_policy" "lambda" {
  name   = "${local.name}-policy"
  policy = data.aws_iam_policy_document.lambda.json
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn
}

# -----------------------
# Lambda function (container image)
# -----------------------

data "aws_ecr_image" "lambda_image" {
  repository_name = aws_ecr_repository.repo.name
  image_tag       = var.image_tag
  registry_id     = aws_ecr_repository.repo.registry_id

  # If your build produced a Docker v2 manifest, this is fine.
  # If it's OCI, Lambda also accepts it — using a digest avoids media-type ambiguity.
}

resource "aws_lambda_function" "fn" {
  function_name = local.name
  role          = aws_iam_role.lambda.arn

  package_type = "Image"
  image_uri    = "${aws_ecr_repository.repo.repository_url}@${data.aws_ecr_image.lambda_image.image_digest}"


  timeout       = var.timeout_s
  memory_size   = var.memory_mb
  architectures = ["x86_64"]

  ephemeral_storage {
    size = var.ephemeral_mb
  }

  environment {
    variables = {
      OUT_BUCKET       = aws_s3_bucket.out.bucket
      ENABLE_OCR       = var.enable_ocr
      OCR_MODELS_DIR   = "/opt/models/rapidocr"
      PYTHONUNBUFFERED = "1"
    }
  }

  tags = local.tags
}

# -----------------------
# S3 -> Lambda trigger
# -----------------------

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.in.arn
}

resource "aws_s3_bucket_notification" "in" {
  bucket = aws_s3_bucket.in.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.fn.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = var.prefix
    filter_suffix       = var.suffix
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
