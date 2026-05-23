provider "aws" {
  region = "ap-south-1"
}

data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "aws_key_pair" "devops" {
  key_name   = "devops-key"
  public_key = file("${path.module}/devops-key.pub")
}

# VPC and networking (same as before)
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "alchemyst-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true
  tags = { Name = "public-subnet" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-1a"
  tags = { Name = "private-subnet" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private_rt.id
}

# Security Groups
resource "aws_security_group" "gateway_sg" {
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "gateway-sg" }
}

resource "aws_security_group" "worker_sg" {
  vpc_id = aws_vpc.main.id
  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.gateway_sg.id]
  }
  ingress {
    from_port = 49134
    to_port   = 49134
    protocol  = "tcp"
    self      = true
  }
  # SSH access from the gateway (or from anywhere for debugging; here from gateway SG)
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.gateway_sg.id]   # only gateway can SSH into workers
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "worker-sg" }
}

# EC2 Instances
resource "aws_instance" "gateway" {
  ami                    = data.aws_ssm_parameter.ubuntu.value
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.gateway_sg.id]
  key_name               = aws_key_pair.devops.key_name
  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx
    cat > /etc/nginx/sites-available/default <<'NGINXCONF'
server {
    listen 80 default_server;
    server_name _;
    location / {
        proxy_pass http://${aws_instance.caller.private_ip}:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
NGINXCONF
    systemctl restart nginx
  EOF
  tags = { Name = "gateway-vm" }
}

resource "aws_instance" "caller" {
  ami                    = data.aws_ssm_parameter.ubuntu.value
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.worker_sg.id]
  key_name               = aws_key_pair.devops.key_name   # <-- Added key
  user_data = <<-EOF
    #!/bin/bash
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs git
    git clone https://github.com/Alchemyst-ai/hiring.git /home/ubuntu/hiring
    cd /home/ubuntu/hiring/may-2026/devops
    cd workers/caller-worker
    npm install
    npx iii dev --host 0.0.0.0 --port 49134 &
    sleep 10
    export III_URL=ws://localhost:49134
    npx tsx src/worker.ts &
  EOF
  tags = { Name = "caller-vm" }
}

resource "aws_instance" "inference" {
  ami                    = data.aws_ssm_parameter.ubuntu.value
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.worker_sg.id]
  key_name               = aws_key_pair.devops.key_name   # <-- Added key
  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y python3-pip git
    pip3 install transformers accelerate gguf torch --break-system-packages
    git clone https://github.com/Alchemyst-ai/hiring.git /home/ubuntu/hiring
    cd /home/ubuntu/hiring/may-2026/devops/workers/inference-worker
    export III_URL=ws://${aws_instance.caller.private_ip}:49134
    python3 inference_worker.py &
  EOF
  tags = { Name = "inference-vm" }
}

output "gateway_public_ip" {
  value = aws_instance.gateway.public_ip
}

output "caller_private_ip" {
  value = aws_instance.caller.private_ip
}