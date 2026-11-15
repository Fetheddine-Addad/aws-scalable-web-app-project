# -----------------------------------------------------------------------------
# Application bundle (S3) and the instance role.
# Instances have no SSH keys and no inbound access: operators use Session Manager.
# -----------------------------------------------------------------------------

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "${local.name}-artifacts-${random_id.suffix.hex}"
  force_destroy = true # so `terraform destroy` removes the bundle too

  tags = { Name = "${local.name}-artifacts" }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "archive_file" "app" {
  type        = "zip"
  source_dir  = "${path.module}/../app"
  output_path = "${path.module}/build/app.zip"
  excludes    = ["tests", ".pytest_cache", "local.db", "instance", "__pycache__", "webapp/__pycache__", "pytest.ini"]
}

resource "aws_s3_object" "app" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "releases/${data.archive_file.app.output_md5}/app.zip"
  source = data.archive_file.app.output_path
  etag   = data.archive_file.app.output_md5

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.artifacts]
}

# --------------------------------------------------------------------- IAM

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name_prefix        = "${local.name}-app-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# Session Manager (and Run Command / Patch Manager) support.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "app" {
  statement {
    sid       = "ReadAppBundle"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/releases/*"]
  }

  statement {
    sid       = "ReadDatabaseSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.main.master_user_secret[0].secret_arn]
  }
}

resource "aws_iam_role_policy" "app" {
  name   = "app-runtime"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app.json
}

resource "aws_iam_instance_profile" "app" {
  name_prefix = "${local.name}-app-"
  role        = aws_iam_role.app.name
}
