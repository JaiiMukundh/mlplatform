# AWS parity for Postgres: single-AZ db.t4g.micro in private subnets, no
# deletion protection and no final snapshot so the demo tears down cleanly.
# The master password avoids Secrets Manager (billed) and is never committed.
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.identifier}-db-subnets"
  subnet_ids = var.private_subnet_ids
  tags       = var.tags
}

resource "aws_security_group" "db" {
  name        = "${var.identifier}-db"
  description = "Postgres from inside the VPC only."
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
  security_group_id = aws_security_group.db.id
  description       = "Postgres from the VPC."
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_db_instance" "this" {
  identifier     = var.identifier
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = "mlp"
  username = var.username
  password = random_password.db.result

  allocated_storage = 20
  storage_type      = "gp3"

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period = 0
  deletion_protection     = false
  skip_final_snapshot     = true

  tags = var.tags
}
