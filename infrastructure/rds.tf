resource "aws_security_group" "rds_sg" {
  name        = "${var.target_env}-rds-sg"
  description = "Allow inbound PostgreSQL traffic from Web Server"
  vpc_id      = aws_vpc.main.id

  # Strict firewall rule: Only allow connections on 5432 from the Public VM's Security Group
  ingress {
    description = "PostgreSQL from Public Web Server"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    # cidr_blocks = [data.aws_vpc.selected.cidr_block]
    security_groups = [aws_security_group.kind_cluster_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.target_env}-rds-sg" }
}

# Free-Tier AWS RDS PostgreSQL Instance
resource "aws_db_instance" "postgres_db" {
  identifier                 = "${var.target_env}-postgres"
  engine                     = "postgres"
  engine_version             = "18.3"
  auto_minor_version_upgrade = true
  instance_class             = "db.t3.micro" # AWS Free Tier eligible
  allocated_storage          = 20            # 20 GB (Within 30GB free limit)
  storage_type               = "gp3"

  db_name  = var.db_name
  username = var.db_username
  # password = var.db_password
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true
  publicly_accessible    = false

  tags = { Name = "${var.target_env}-postgres-db" }
}

resource "local_file" "db_config" {
  filename = "../backend/db-config.json"

  content = jsonencode({
    host     = aws_db_instance.postgres_db.address
    port     = aws_db_instance.postgres_db.port
    database = aws_db_instance.postgres_db.db_name
    username = var.db_username
    password = random_password.db_password.result
  })
}