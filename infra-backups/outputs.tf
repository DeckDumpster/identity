output "bucket" {
  value = aws_s3_bucket.backups.bucket
}

output "credential_secret" {
  value       = aws_secretsmanager_secret.backup.name
  description = "Secrets Manager secret holding the write-only AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY."
}
