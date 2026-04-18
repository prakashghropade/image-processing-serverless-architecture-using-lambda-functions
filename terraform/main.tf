
#  random id resource for the uniqe resource name
resource "random_id" "suffix" {
    byte_length = 4
}

# local variables for the use in the project
locals {
  bucket_prefix = "${var.project_name}-${var.environment}"
  upload_bucket_name = "${local.bucket_prefix}-upload-${random_id.suffix.hex}"
  process_bucket_name = "${local.bucket_prefix}-processed-${random_id.suffix.hex}"
  lamda_function_name = "${var.project_name}-${var.environment}-prcessor"
}

# ===============================================
# upload bucket resources 
# ===============================================

# s3 bucket resource for upload bucket
resource "aws_s3_bucket" "upload_bucket" {
    bucket = local.upload_bucket_name
}

# s3 bucket versioning for the upload bucket
resource "aws_s3_bucket_versioning" "upload_bucket" {
    bucket = aws_s3_bucket.upload_bucket.id
    versioning_configuration {
      status = "Enabled"
    }
}

# s3 bucket server side encryption for the upload bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "upload_bucket" {
    bucket = aws_s3_bucket.upload_bucket.id
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  
}

# s3 bucket making it private for the  upload bucket
resource "aws_s3_bucket_public_access_block" "upload_bucket" {
  bucket = aws_s3_bucket.upload_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ===============================================
# processed bucket resources 
# ===============================================

# s3 bucket resource for the processed bucket
resource "aws_s3_bucket" "processed_bucket" {
    bucket = local.process_bucket_name
}

# s3 bucket versioning for the processed bucket
resource "aws_s3_bucket_versioning" "processed_bucket" {
  bucket = aws_s3_bucket.processed_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# s3 bucket server side encryption for the processed bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "processed_bucket" {
    bucket = aws_s3_bucket.processed_bucket.id

    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  
}

# s3 bucket making it private for the processed bucket
resource "aws_s3_bucket_public_access_block" "processed_bucket" {
    bucket = aws_s3_bucket.processed_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

}

# ===========================================
# IAM roles and policies
# ===========================================

# IAM role for the lamda function
resource "aws_iam_role" "lamda_role" {
   name = "${local.lamda_function_name}-role"

   assume_role_policy = jsonencode({
   Version = "2012-10-17"
   Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for the lamda fuction
resource "aws_iam_role_policy" "lamda_policy" {
    name = "${local.lamda_function_name}-policy"
    role = aws_iam_role.lamda_role.id

      policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.upload_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.processed_bucket.arn}/*"
      }
    ]
  })
  
}

# lamda layer for the pillow
resource "aws_lambda_layer_version" "pillow_layer" {
    filename = "${path.module}/pillow_layer.zip"
    layer_name = "${var.project_name}-pillow-layer"
    compatible_runtimes = ["python3.12"]
    description = "Pillow library for image processing"
}

# data source for the  lamda function zip
data "archive_file" "lambda_zip" {
    type = "zip"
    source_file = "${path.module}/../lamda/lamda_fuction.py"
    output_path = "${path.module}/lamda_function.zip"
}

# lamda function for the image processing
resource "aws_lambda_function" "image_processing" {
     filename = data.archive_file.lambda_zip.output_path
     function_name = local.lamda_function_name
     role = aws_iam_role.lamda_role.arn
     handler = "lambda_function.lambda_handler"
     source_code_hash = data.archive_file.lambda_zip.output_base64sha256
     runtime = "python3.12"
     timeout = var.lambda_timeout
     memory_size = var.lambda_memory_size

     layers = [aws_lambda_layer_version.pillow_layer.arn]

     environment {
       variables = {
         PROCESSED_BUCKET = aws_s3_bucket.processed_bucket.id
         LOG_LEVEL = "INFO"
       }
     }
}

# cloudwatch log group for lambda
resource "aws_cloudwatch_log_group" "lambda_processor" {
    name = "/aws/lamdba/${local.lamda_function_name}"
    retention_in_days = 7
}

# lambda permission to  be invoked by the s3
resource "aws_lambda_permission" "allow_s3" {
   statement_id = "AllowExecutionFromS3"
   action = "lambda:InvokeFunction"
   function_name = aws_lambda_function.image_processing.function_name
   principal = "s3.amazonaws.com"
   source_arn = aws_s3_bucket.upload_bucket.arn
}

# s3 bucket notification to trigger lamda function
resource "aws_s3_bucket_notification" "upload_bucket_notification" {
    bucket = aws_s3_bucket.upload_bucket.id

    lambda_function {
      lambda_function_arn = aws_lambda_function.image_processing.arn
      events = ["s3:ObjectCreated:*"]
    }

    depends_on = [ aws_lambda_permission.allow_s3 ]
}

