# ==========================================
# 1. GLOBAL & PROVIDER VARIABLES
# ==========================================

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

# ==========================================
# 2. NETWORKING VARIABLES (VPC & Subnets)
# ==========================================

variable "vpc_cidr" {
  description = "CIDR block for the custom VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the internet-facing public subnets"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the isolated private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

# ==========================================
# 3. COMPUTE VARIABLES (App Tier)
# ==========================================

variable "instance_type" {
  description = "EC2 instance size for the application web servers"
  type        = string
  default     = "t2.micro"
}

variable "target_env" {
  description = "Enter the target environment for the deployment"
  type        = string # Must be a string so you can type a single input

  validation {
    # This checks if the entered string exists inside the allowed list
    condition     = contains(["dev", "stage", "prod"], var.target_env)
    error_message = "Invalid environment! You must enter either 'dev', 'stage', or 'prod'."
  }
}

resource "random_password" "db_password" {
  length  = 20
  special = true
  override_special = "!#$%^&*()-_=+"
}

# ==========================================
# 4. DATABASE VARIABLES (Data Tier)
# ==========================================

variable "db_username" {
  description = "Administrator master username for the RDS PostgreSQL database"
  type        = string
  default     = "dbadmin"
}

# variable "db_password" {
#   description = "Administrator master password for the RDS instance. Must be at least 8 characters."
#   type        = string
#   sensitive   = true # Hides the value from printing in the terminal and deployment logs
#   default     = "s3cr3t#123"
# }

variable "db_name" {
  description = "Name of the initial database to create in the RDS instance"
  type        = string
  default     = "pplmgtdb"
}