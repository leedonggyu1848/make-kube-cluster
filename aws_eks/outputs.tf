output "rds_endpoint" {
  description = "RDS의 endpoint 주소"
  value = aws_db_instance.postgresql.endpoint
}

output "eks_cluster_endpoint" {
  description = "EKS 클러스터 API 서버 엔드포인트"
  value       = module.eks.cluster_endpoint
}

output "efs_id" {
  description = "EFS 파일 시스템 ID"
  value       = aws_efs_file_system.main.id
}

output "access_bestion_host" {
  description = "베스천호스트 접속"
  value = "ssh -i ${local_file.ssh_private_key.filename} ubuntu@${aws_instance.bastion.public_ip}"
}

output "s3_bucket_name" {
  description = "생성된 S3 버킷의 이름"
  value       = aws_s3_bucket.main.bucket
}
