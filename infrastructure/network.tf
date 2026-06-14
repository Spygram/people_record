resource "aws_vpc" "main" {
    cidr_block           = var.vpc_cidr
    enable_dns_hostnames = true
    enable_dns_support   = true
        tags = {
            Name = "${var.target_env}-vpc"
        }
}

# Create an Internet Gateway and attach it to the VPC
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.target_env}-igw" }
}

# Create public subnets
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.target_env}-public-subnet" }
}

# Create a route table for public subnets
resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.target_env}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public-rt.id
}

# Create private subnets in the same availability zones as the public subnets
resource "aws_subnet" "private_subnet" {
  count                   = length(var.private_subnet_cidrs) # Creates as many private subnets as there are CIDR blocks in the variable
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.target_env}-private-subnet" }
}

# aws route table - private
resource "aws_route_table" "private-rt" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.target_env}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs) # Associates each private subnet with the private route table
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private-rt.id
}

# Create a DB subnet group for RDS using the private subnets
resource "aws_db_subnet_group" "rds" {
  name       = "${var.target_env}-rds-subnet-group"
  subnet_ids = aws_subnet.private_subnet[*].id # Uses your private subnet IDs automatically

  tags = { Name = "${var.target_env}-rds-subnet-group" }
}