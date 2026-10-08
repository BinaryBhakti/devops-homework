# Least privilege for the backup job: it may write and list backups in ONE bucket, under ONE
# prefix — nothing else. (On EKS this role would be bound to the backup CronJob's service
# account via IRSA / Pod Identity.)

data "aws_iam_policy_document" "backup_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  name               = "${local.name}-db-backup"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json
}

data "aws_iam_policy_document" "backup_access" {
  statement {
    sid       = "WriteBackups"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${aws_s3_bucket.backups.arn}/postgres/*"]
  }
  statement {
    sid       = "ListBackupPrefix"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.backups.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["postgres/*"]
    }
  }
}

resource "aws_iam_policy" "backup" {
  name   = "${local.name}-db-backup"
  policy = data.aws_iam_policy_document.backup_access.json
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = aws_iam_policy.backup.arn
}
