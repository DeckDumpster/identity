# Plan-free assertions with a mocked provider: no credentials, no network.
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  deploy_role_arn = "arn:aws:iam::123456789012:role/terraform-deploy"
}

override_resource {
  target          = aws_s3_bucket.backups
  override_during = plan
  values = {
    arn = "arn:aws:s3:::identity-backups"
  }
}

run "bucket_is_private_versioned_encrypted" {
  command = plan

  assert {
    condition     = startswith(aws_s3_bucket.backups.bucket, "identity-")
    error_message = "bucket must carry the identity- prefix the deploy role admits"
  }
  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.backups.block_public_acls,
      aws_s3_bucket_public_access_block.backups.block_public_policy,
      aws_s3_bucket_public_access_block.backups.ignore_public_acls,
      aws_s3_bucket_public_access_block.backups.restrict_public_buckets,
    ])
    error_message = "all public access must be blocked"
  }
  assert {
    condition     = aws_s3_bucket_versioning.backups.versioning_configuration[0].status == "Enabled"
    error_message = "versioning must be enabled"
  }
  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.backups.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "SSE-S3 required"
  }
  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.backups.rule).noncurrent_version_expiration[0].noncurrent_days == 30
    error_message = "noncurrent versions must expire after 30 days"
  }
  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.backups.rule).expiration == null || length(one(aws_s3_bucket_lifecycle_configuration.backups.rule).expiration) == 0
    error_message = "current backups must never expire: a stopped writer would age out every backup"
  }
  assert {
    condition     = one(data.aws_iam_policy_document.tls_only.statement).effect == "Deny" && one([for c in one(data.aws_iam_policy_document.tls_only.statement).condition : c.variable]) == "aws:SecureTransport"
    error_message = "plain-HTTP access must be denied"
  }
}

run "writer_can_only_upload" {
  command = plan

  assert {
    condition     = length(data.aws_iam_policy_document.backup.statement) == 1
    error_message = "the backup user gets exactly one statement"
  }
  assert {
    condition     = coalesce(one(data.aws_iam_policy_document.backup.statement).effect, "Allow") == "Allow" && toset(one(data.aws_iam_policy_document.backup.statement).actions) == toset(["s3:PutObject"])
    error_message = "the backup user may only s3:PutObject (no list, read, overwrite-by-read or delete)"
  }
  assert {
    condition     = aws_iam_user.backup.name == "identity-backup" && aws_iam_user.backup.tags["terraform-deploy-boundary"] == "true"
    error_message = "the user must carry the identity prefix and the boundary tag"
  }
  assert {
    condition     = aws_iam_user.backup.permissions_boundary == var.permissions_boundary_arn
    error_message = "the user must be created under the permissions boundary"
  }
  assert {
    condition     = startswith(aws_secretsmanager_secret.backup.name, "identity/")
    error_message = "the secret must sit under the identity/ prefix"
  }
}
