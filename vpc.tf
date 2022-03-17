resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr
  enable_dns_hostnames = false
}

resource "aws_subnet" "public" {
  map_public_ip_on_launch = true
  count                   = var.az_count
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index+1)
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = data.aws_availability_zones.available.names[count.index]
}

resource "aws_subnet" "private" {
  map_public_ip_on_launch = false
  count                   = var.az_count
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index+101)
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = data.aws_availability_zones.available.names[count.index]
}

resource "aws_internet_gateway" "igw" {
  vpc_id     = aws_vpc.vpc.id
}

resource "aws_eip" "nat_eip" {
  count      = var.az_count
}

resource "aws_nat_gateway" "nat" {
  count             = var.az_count
  allocation_id     = aws_eip.nat_eip.*.id[count.index]
  subnet_id         = aws_subnet.public.*.id[count.index]

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id                  = aws_vpc.vpc.id
}

resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public.*.id[count.index]
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count                   = var.az_count
  vpc_id                  = aws_vpc.vpc.id
}

resource "aws_route" "private" {
  count                  = var.az_count
  route_table_id         = aws_route_table.private.*.id[count.index]
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.*.id[count.index]
}

resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = aws_subnet.private.*.id[count.index]
  route_table_id = aws_route_table.private.*.id[count.index]
}
