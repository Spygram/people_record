# SSH Key Pair Generation
resource "tls_private_key" "vm_key" { algorithm = "ED25519" }

resource "aws_key_pair" "deployer_key" {
  key_name   = "${var.target_env}-key"
  public_key = tls_private_key.vm_key.public_key_openssh
}

resource "local_file" "private_key_pem" {
  content         = tls_private_key.vm_key.private_key_openssh
  filename        = "${path.module}/../${var.target_env}-key.pem"
  file_permission = "0600"
}

# Security Groups
resource "aws_security_group" "jenkins_sg" {
  name   = "${var.target_env}-jenkins-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "app_server_sg" {
  name   = "${var.target_env}-app-server-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins_sg.id]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Public VM with Jenkins Remote Provisioner
resource "aws_instance" "jenkins_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  key_name               = aws_key_pair.deployer_key.key_name
  iam_instance_profile   = data.aws_iam_instance_profile.labInstanceProfile.name

  tags = { Name = "${var.target_env}-jenkins-server" }

  # Connection block tells the provisioner how to SSH into the box
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.vm_key.private_key_openssh
    host        = self.public_ip
  }

  provisioner "file" {
    source      = "${path.module}/install_jenkins.sh"
    destination = "/tmp/install_jenkins.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/install_jenkins.sh",
      "/tmp/install_jenkins.sh"
    ]
  }
}

resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.app_server_sg.id]
  key_name               = aws_key_pair.deployer_key.key_name
  iam_instance_profile   = data.aws_iam_instance_profile.labInstanceProfile.name

  tags = { Name = "${var.target_env}-app-server" }

  user_data = file("${path.module}/install_docker.sh")
  
  user_data_replace_on_change = true


}


