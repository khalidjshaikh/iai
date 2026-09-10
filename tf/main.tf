# ---------------------------------------------------------------------------
# Data sources (used only when NOT creating a custom VPC)
# ---------------------------------------------------------------------------

data "aws_vpc" "default" {
  count   = local.should_create_vpc ? 0 : 1
  default = true
}

data "aws_vpc" "selected" {
  count = local.should_create_vpc ? 0 : 1
  id    = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id

  # When IPv6 is requested, only match a VPC that actually has IPv6 enabled.
  dynamic "filter" {
    for_each = var.enable_ipv6 ? [1] : []
    content {
      name   = "ipv6-cidr-block-association.ipv6-cidr-block"
      values = ["*"]
    }
  }
}

data "aws_subnets" "selected" {
  count = local.should_create_vpc ? 0 : 1

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected[0].id]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = [tostring(var.associate_public_ip)]
  }

  # When IPv6 is requested, only match subnets that have an IPv6 CIDR block
  # associated, so the instance can actually get an IPv6 address.
  dynamic "filter" {
    for_each = var.enable_ipv6 ? [1] : []
    content {
      name   = "ipv6-cidr-block-association.ipv6-cidr-block"
      values = ["*"]
    }
  }
}

data "aws_subnet" "selected" {
  count = local.should_create_vpc ? 0 : (var.subnet_id != "" ? 0 : 1)
  id    = var.subnet_id != "" ? var.subnet_id : data.aws_subnets.selected[0].ids[0]
}

# Validates that an explicitly provided subnet supports IPv6 when IPv6 is enabled.
data "aws_subnet" "ipv6_check" {
  count = local.should_create_vpc ? 0 : (var.enable_ipv6 && var.subnet_id != "" ? 1 : 0)
  id    = var.subnet_id
}

data "aws_ssm_parameter" "ubuntu_ami" {
  count = var.ami == "" ? 1 : 0
  name  = "/aws/service/canonical/ubuntu/server/${var.ubuntu_release}/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

# ---------------------------------------------------------------------------
# Custom VPC with IPv6 (used when create_vpc = true, typically for IPv6)
# ---------------------------------------------------------------------------

resource "aws_vpc" "this" {
  count = local.should_create_vpc ? 1 : 0

  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Must stay true: the provider records this as true whenever the VPC has an
  # Amazon-provided IPv6 CIDR (assigned by aws_vpc_ipv6_cidr_block_association
  # below). Setting it to null would attempt to disassociate the CIDR and fail.
  assign_generated_ipv6_cidr_block = true

  tags = merge(var.tags, { Name = "${var.instance_name}-vpc" })
}

resource "aws_vpc_ipv6_cidr_block_association" "this" {
  count = local.should_create_vpc ? 1 : 0

  vpc_id                           = aws_vpc.this[0].id
  assign_generated_ipv6_cidr_block = true
}

resource "aws_internet_gateway" "this" {
  count = local.should_create_vpc ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  tags = merge(var.tags, { Name = "${var.instance_name}-igw" })
}

resource "aws_subnet" "this" {
  count = local.should_create_vpc ? 1 : 0

  vpc_id                          = aws_vpc.this[0].id
  cidr_block                      = var.subnet_cidr
  availability_zone               = var.availability_zone
  map_public_ip_on_launch         = var.associate_public_ip
  assign_ipv6_address_on_creation = true
  ipv6_cidr_block                 = cidrsubnet(aws_vpc_ipv6_cidr_block_association.this[0].ipv6_cidr_block, 8, 0)

  tags = merge(var.tags, { Name = "${var.instance_name}-subnet" })
}

resource "aws_route_table" "this" {
  count = local.should_create_vpc ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.this[0].id
  }

  tags = merge(var.tags, { Name = "${var.instance_name}-rt" })
}

resource "aws_route_table_association" "this" {
  count = local.should_create_vpc ? 1 : 0

  subnet_id      = aws_subnet.this[0].id
  route_table_id = aws_route_table.this[0].id
}

# ---------------------------------------------------------------------------
# Locals — pick the right VPC / subnet / etc.
# ---------------------------------------------------------------------------

locals {
  should_create_vpc  = var.enable_ipv6 && var.vpc_id == ""
  vpc_id             = local.should_create_vpc ? aws_vpc.this[0].id : (var.vpc_id != "" ? var.vpc_id : data.aws_vpc.selected[0].id)
  subnet_id          = local.should_create_vpc ? aws_subnet.this[0].id : (var.subnet_id != "" ? var.subnet_id : data.aws_subnet.selected[0].id)
  ami_id             = var.ami != "" ? var.ami : data.aws_ssm_parameter.ubuntu_ami[0].value
  ipv6_address_count = var.enable_ipv6 ? var.ipv6_address_count : 0
}

# ---------------------------------------------------------------------------
# SSH key pair
# ---------------------------------------------------------------------------

resource "aws_key_pair" "this" {
  key_name   = "${var.instance_name}-key"
  public_key = file(var.ssh_public_key_path)

  tags = merge(var.tags, { Name = "${var.instance_name}-key" })
}

# ---------------------------------------------------------------------------
# Security group
# ---------------------------------------------------------------------------

resource "aws_security_group" "this" {
  name        = "${var.instance_name}-sg"
  description = "SSH access"
  vpc_id      = local.vpc_id

  ingress {
    description = "SSH from allowed CIDRs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ingress_cidr_blocks
  }

  dynamic "ingress" {
    for_each = var.enable_ipv6 ? [1] : []
    content {
      description      = "SSH from allowed IPv6 CIDRs"
      from_port        = 22
      to_port          = 22
      protocol         = "tcp"
      ipv6_cidr_blocks = var.ingress_ipv6_cidr_blocks
    }
  }

  ingress {
    description = "HTTP from allowed CIDRs"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.ingress_cidr_blocks
  }

  dynamic "ingress" {
    for_each = var.enable_ipv6 ? [1] : []
    content {
      description      = "HTTP from allowed IPv6 CIDRs"
      from_port        = 80
      to_port          = 80
      protocol         = "tcp"
      ipv6_cidr_blocks = var.ingress_ipv6_cidr_blocks
    }
  }

  ingress {
    description = "HTTPS from allowed CIDRs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.ingress_cidr_blocks
  }

  dynamic "ingress" {
    for_each = var.enable_ipv6 ? [1] : []
    content {
      description      = "HTTPS from allowed IPv6 CIDRs"
      from_port        = 443
      to_port          = 443
      protocol         = "tcp"
      ipv6_cidr_blocks = var.ingress_ipv6_cidr_blocks
    }
  }

  ingress {
    description = "UDP/443 (QUIC) from allowed CIDRs"
    from_port   = 443
    to_port     = 443
    protocol    = "udp"
    cidr_blocks = var.ingress_cidr_blocks
  }

  dynamic "ingress" {
    for_each = var.enable_ipv6 ? [1] : []
    content {
      description      = "UDP/443 (QUIC) from allowed IPv6 CIDRs"
      from_port        = 443
      to_port          = 443
      protocol         = "udp"
      ipv6_cidr_blocks = var.ingress_ipv6_cidr_blocks
    }
  }

  ingress {
    description = "UDP/80 (QUIC) from allowed CIDRs"
    from_port   = 80
    to_port     = 80
    protocol    = "udp"
    cidr_blocks = var.ingress_cidr_blocks
  }

  dynamic "ingress" {
    for_each = var.enable_ipv6 ? [1] : []
    content {
      description      = "UDP/80 (QUIC) from allowed IPv6 CIDRs"
      from_port        = 80
      to_port          = 80
      protocol         = "udp"
      ipv6_cidr_blocks = var.ingress_ipv6_cidr_blocks
    }
  }

  ingress {
    description = "rsync from allowed CIDRs"
    from_port   = 873
    to_port     = 873
    protocol    = "tcp"
    cidr_blocks = var.ingress_cidr_blocks
  }

  dynamic "ingress" {
    for_each = var.enable_ipv6 ? [1] : []
    content {
      description      = "rsync from allowed IPv6 CIDRs"
      from_port        = 873
      to_port          = 873
      protocol         = "tcp"
      ipv6_cidr_blocks = var.ingress_ipv6_cidr_blocks
    }
  }

  ingress {
    description = "Ollama API from allowed CIDRs"
    from_port   = 11434
    to_port     = 11434
    protocol    = "tcp"
    cidr_blocks = var.ingress_cidr_blocks
  }

  dynamic "ingress" {
    for_each = var.enable_ipv6 ? [1] : []
    content {
      description      = "Ollama API from allowed IPv6 CIDRs"
      from_port        = 11434
      to_port          = 11434
      protocol         = "tcp"
      ipv6_cidr_blocks = var.ingress_ipv6_cidr_blocks
    }
  }

  ingress {
    description = "UDP/11434 (Ollama API) from allowed CIDRs"
    from_port   = 11434
    to_port     = 11434
    protocol    = "udp"
    cidr_blocks = var.ingress_cidr_blocks
  }

  dynamic "ingress" {
    for_each = var.enable_ipv6 ? [1] : []
    content {
      description      = "UDP/11434 (Ollama API) from allowed IPv6 CIDRs"
      from_port        = 11434
      to_port          = 11434
      protocol         = "udp"
      ipv6_cidr_blocks = var.ingress_ipv6_cidr_blocks
    }
  }

  ingress {
    description = "ICMP (ping) from allowed CIDRs"
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = var.ingress_cidr_blocks
  }

  dynamic "ingress" {
    for_each = var.enable_ipv6 ? [1] : []
    content {
      description      = "ICMPv6 (ping) from allowed IPv6 CIDRs"
      from_port        = -1
      to_port          = -1
      protocol         = "icmpv6"
      ipv6_cidr_blocks = var.ingress_ipv6_cidr_blocks
    }
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "egress" {
    for_each = var.enable_ipv6 ? [1] : []
    content {
      description      = "All outbound IPv6 traffic"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  tags = merge(var.tags, { Name = "${var.instance_name}-sg" })
}

# ---------------------------------------------------------------------------
# EC2 instance
# ---------------------------------------------------------------------------

resource "aws_instance" "this" {
  ami                         = local.ami_id
  instance_type               = var.instance_type
  subnet_id                   = local.subnet_id
  associate_public_ip_address = var.associate_public_ip
  ipv6_address_count          = local.ipv6_address_count
  key_name                    = aws_key_pair.this.key_name
  vpc_security_group_ids      = [aws_security_group.this.id]

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size_gb
    encrypted   = true

    tags = merge(var.tags, { Name = "${var.instance_name}-root" })
  }

  tags = merge(var.tags, { Name = var.instance_name })

  lifecycle {
    precondition {
      condition     = !var.enable_ipv6 || var.subnet_id == "" || length(data.aws_subnet.ipv6_check[0].ipv6_cidr_block) > 0
      error_message = "Subnet '${var.subnet_id}' has no IPv6 CIDR block; associate one (and enable IPv6 on its VPC) before setting enable_ipv6 = true, or leave subnet_id empty to auto-select an IPv6-capable subnet."
    }
  }
}

# ---------------------------------------------------------------------------
# Optional: Elastic IP (uncomment to get a static public IP)
# ---------------------------------------------------------------------------

# resource "aws_eip" "this" {
#   domain   = "vpc"
#   instance = aws_instance.this.id
#   tags     = merge(var.tags, { Name = "${var.instance_name}-eip" })
# }
