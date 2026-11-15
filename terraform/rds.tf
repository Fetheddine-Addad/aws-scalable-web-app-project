# -----------------------------------------------------------------------------
# RDS PostgreSQL, Multi-AZ, in the isolated data subnets.
# The master password is generated and stored by RDS in Secrets Manager
# (manage_master_user_password), so it never appears in Terraform state or code.
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  name_prefix = "${local.name}-"
  subnet_ids  = aws_subnet.data[*].id

  tags = { Name = "${local.name}-db-subnets" }
}

resource "aws_db_instance" "main" {
  identifier_prefix = "${local.name}-"

  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name                     = "appdb"
  username                    = "dbadmin"
  manage_master_user_password = true

  multi_az               = var.db_multi_az
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  backup_retention_period    = 1
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  # Demo settings so `terraform destroy` is clean. Flip both for anything real.
  deletion_protection = false
  skip_final_snapshot = true
  apply_immediately   = true

  tags = { Name = "${local.name}-postgres" }
}
