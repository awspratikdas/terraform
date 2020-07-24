data "aws_availability_zones" "AZ" {}
resource "aws_vpc" "myVpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames = true
  enable_dns_support = true
  tags = {
    Name = "myVpc"
    Location = "Toronto-Canada"
  }
}
resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.myVpc.id}"
  tags = {
    Name = "myIgw - ${aws_vpc.myVpc.id}"
  }
}
resource "aws_route_table" "public_rt" {
  vpc_id = "${aws_vpc.myVpc.id}"
route {
      cidr_block = "0.0.0.0/0"
      gateway_id = "${aws_internet_gateway.igw.id}"
  }
}
resource "aws_subnet" "public_subnet" {
  count = "${length(data.aws_availability_zones.AZ.names)}"
  vpc_id = "${aws_vpc.myVpc.id}"
  cidr_block = "10.0.${10+count.index}.0/24"
  availability_zone = "${data.aws_availability_zones.AZ.names[count.index]}"
  map_public_ip_on_launch = true
  tags = {
    Name = "MyPublicSubnet-${10+count.index}"
  }
}
resource "aws_subnet" "private_subnet" {
  count = "${length(data.aws_availability_zones.AZ.names)}"
  vpc_id = "${aws_vpc.myVpc.id}"
  cidr_block = "10.0.${20+count.index}.0/24"
  availability_zone = "${data.aws_availability_zones.AZ.names[count.index]}"
  map_public_ip_on_launch = false
  tags = {
    Name = "MyPrivateSubnet-${20+count.index}"
  }
}
resource "aws_route_table_association" "public" {
  count = "${length(aws_subnet.public_subnet)}"
  route_table_id = "${aws_route_table.public_rt.id}"
  subnet_id = "${aws_subnet.public_subnet.*.id[count.index]}"
  depends_on = ["aws_route_table.public_rt", "aws_subnet.public_subnet"]
}
resource "aws_security_group" "elbSG" {
  name = "Myelb"
  vpc_id = "${aws_vpc.myVpc.id}"
  # Inbound HTTP from anywhere
  ingress {
    from_port   = "${var.elb_port}"
    to_port     = "${var.elb_port}"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "WebServerSG" {
  name = "WebServerSG"
  description = "Allow inbound traffic from LoadBalancer"
  vpc_id = "${aws_vpc.myVpc.id}"
  ingress {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
      from_port   = "${var.server_port}"
      to_port     = "${var.server_port}"
      protocol    = "tcp"
      #cidr_blocks = ["0.0.0.0/0"]
      security_groups = ["${aws_security_group.elbSG.id}"]
  }
  ingress {
      from_port   = -1
      to_port     = -1
      protocol    = "icmp"
      cidr_blocks = ["0.0.0.0/0"]
  }
 egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    #security_groups = ["${aws_security_group.elbSG.id}"]
  }
  #egress {
    #from_port   = 0
    #to_port     = 0
    #protocol    = "-1"
    #cidr_blocks = ["0.0.0.0/0"]
    #security_groups = ["${aws_security_group.elbSG.id}"]
  #}
}
resource "aws_security_group" "PrivateServerSG" {
  name = "PrivateServerSG"
  description = "Allow inbound traffic from Public Subnet"
  vpc_id = "${aws_vpc.myVpc.id}"
  #count = "${length(data.aws_availability_zones.AZ.names)}"
  ingress {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      #cidr_blocks = ["10.0.${10+count.index}.0/24"]
      security_groups = ["${aws_security_group.WebServerSG.id}"]
  }
  ingress {
      from_port   = -1
      to_port     = -1
      protocol    = "icmp"
      #cidr_blocks = ["10.0.${10+count.index}.0/24"]
      security_groups = ["${aws_security_group.WebServerSG.id}"]
  }
 egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    #cidr_blocks = ["10.0.${10+count.index}.0/24"]
    security_groups = ["${aws_security_group.WebServerSG.id}"]
  }
}
resource "aws_elb" "myelb" {
  name               = "my-classic-elb"
  #count = "${length(data.aws_availability_zones.AZ.names)}"
  availability_zones = "${data.aws_availability_zones.AZ.names}"
  #subnets = "${aws_subnet.public_subnet.*.id}"
  security_groups = "${aws_security_group.elbSG.*.id}"
  instances                   = "${aws_instance.MyPublicInstance.*.id}"
  cross_zone_load_balancing   = true
  #include_public_dns_record   = "yes"
  idle_timeout                = 300
  connection_draining         = true
  connection_draining_timeout = 300
  health_check {
    target              = "HTTP:${var.server_port}/"
    interval            = 5
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  # This adds a listener for incoming HTTP requests.
    listener {
    lb_port           = "${var.elb_port}"
    lb_protocol       = "http"
    instance_port     = "${var.server_port}"
    instance_protocol = "http"
  }
}
resource "aws_route53_record" "alias" {
     zone_id = "${aws_route53_zone.example.zone_id}"
     name    = "amazoncloudonline.net"
     type     = "A"

     alias {
      name                   = "${aws_elb.myelb.dns_name}"
      zone_id                = "${aws_elb.myelb.zone_id}"
      evaluate_target_health = true
           }
}
resource "aws_route53_zone" "example" {
  name = "www.amazoncloudonline.net"
}
resource "aws_route53_record" "example" {
      allow_overwrite = true
      name            = "www.amazoncloudonline.net"
      ttl             = 30
      type            = "NS"
      zone_id         = "${aws_route53_zone.example.zone_id}"

records = [
    "${aws_route53_zone.example.name_servers.0}",
    "${aws_route53_zone.example.name_servers.1}",
    "${aws_route53_zone.example.name_servers.2}",
    "${aws_route53_zone.example.name_servers.3}",
  ]
}
# Create a new load balancer attachment
#resource "aws_elb_attachment" "elb-ec2" {
    #elb      = "${aws_elb.myelb.id}"
    #instances = "${aws_instance.MyPublicInstance.*.id}"
#}
resource "aws_instance" "MyPublicInstance" {
  count = "${length(data.aws_availability_zones.AZ.names)}"
  subnet_id = "${aws_subnet.public_subnet.*.id[count.index]}"
  vpc_security_group_ids = "${aws_security_group.WebServerSG.*.id}"
  ami = "ami-0bf54ac1b628cf143"
  instance_type = "t2.micro"
  associate_public_ip_address = true
  source_dest_check = false
  tags = {
    Name = "MyWebServer : 10.0.${10+count.index}.0"
    Environment = "Operations"
  }
  key_name = "ca-central-1-key-pair"
  user_data = <<-EOF
                #!/bin/bash
                yum update -y
                yum install -y httpd
                systemctl start httpd.service
                systemctl enable httpd.service
                echo "<html><body><h1><b><i> Hello AWS Gurus, I am host $(hostname -f) with public identity $(curl -s http://169.254.169.254/latest/meta-data/public-hostname), public-ip of $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4), local-ip of $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4) and located in AZ $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone) </i></b></h1></body></html>" > /var/www/html/index.html
                EOF
} 
resource "aws_instance" "MyPrivateInstance" {
  count = "${length(data.aws_availability_zones.AZ.names)}"
  subnet_id = "${aws_subnet.private_subnet.*.id[count.index]}"
  vpc_security_group_ids = "${aws_security_group.PrivateServerSG.*.id}"
  ami = "ami-0bf54ac1b628cf143"
  instance_type = "t2.micro"
  associate_public_ip_address = false
  source_dest_check = false
  tags = {
    Name = "MyPrivateServer : 10.0.${20+count.index}.0"
    Environment = "Operations"
  }
  key_name = "ca-central-1-key-pair"
}
