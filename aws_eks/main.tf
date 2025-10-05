# ------------------------------------------------------------------------------
# VPC (Virtual Private Cloud)
# ------------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.team_name}-vpc"
  }
}

# ------------------------------------------------------------------------------
# Subnets - public 1개, private 2개
# ------------------------------------------------------------------------------
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.101.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
      Name = "${var.team_name}-public-subnet-1"
    }
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 1}.0/24" # 10.0.1.0/24, 10.0.2.0/24
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
      Name = "${var.team_name}-private-subnet-${count.index + 1}"
    }
}

# ------------------------------------------------------------------------------
# IGW, NAT
# ------------------------------------------------------------------------------
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
      Name = "${var.team_name}-igw"
    }
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags = {
      Name = "${var.team_name}-nat-eip"
    }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public.id

  tags = {
      Name = "${var.team_name}-nat-gw"
    }

  depends_on = [aws_internet_gateway.gw]
}

# ------------------------------------------------------------------------------
# Route Tables (네트워크 경로 설정)
# ------------------------------------------------------------------------------
resource "aws_route_table" "igw" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
      Name = "${var.team_name}-public-rt"
    }
}

resource "aws_route_table" "nat" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
      Name = "${var.team_name}-private-rt"
    }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.igw.id
}

resource "aws_route_table_association" "private_assoc" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.nat.id
}


