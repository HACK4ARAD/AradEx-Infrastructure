# Pozele încărcate din panoul Primăriei / Adminului (media, T05). Bucket privat: nimic public, nicio politică de bucket.
# API-ul le scrie și le servește prin `GET /api/v1/media/**` (cu cache lung), deci ajunge accesul rolului task-ului.
resource "aws_s3_bucket" "media" {
  bucket        = "aradex-media-712710404828"
  force_destroy = true # ca destroy.sh să poată șterge tot după demo (ca ECR cu force_delete)
}

resource "aws_s3_bucket_ownership_controls" "media" {
  bucket = aws_s3_bucket.media.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "media" {
  bucket                  = aws_s3_bucket.media.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = aws_s3_bucket.media.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Rolul aplicației: scrie și citește pozele. ListBucket ca o cheie lipsă să dea 404 (NoSuchKey), nu 403.
resource "aws_iam_role_policy" "task_media" {
  name = "media-bucket"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.media.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.media.arn
      },
    ]
  })
}
