# Define AWS provider
provider "aws" {
  region = "us-west-2"  # Update with your desired region
}

# Create security group for EC2 instances
resource "aws_security_group" "instance_sg" {
  name        = "instance_sg"
  description = "Security group for EC2 instances"

  ingress {
    from_port   = 22  # SSH
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80  # HTTP
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create DynamoDB table
resource "aws_dynamodb_table" "candidate-table" {
  name           = "Candidates"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "CandidateName"
  attribute {
    name = "CandidateName"
    type = "S"
  }
  ttl {
    attribute_name = "TimeToExist"
    enabled        = false
  }
  lifecycle {
    ignore_changes = [
      ttl
    ]
  }
}
# Create EC2 instances
resource "aws_instance" "web" {
  count         = 2
  ami           = "ami-0c94855ba95c71c99"  # Update with your desired AMI ID
  instance_type = "t2.micro"
  key_name      = "your_key_pair_name"  # Update with your key pair name

  security_group_names = [aws_security_group.instance_sg.name]

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y python3-pip
              pip3 install flask gunicorn boto3

              # Sample Flask app
              cat <<APP > app.py
              from flask import Flask
              import boto3

              app = Flask(__name__)

              @app.route("/")
              def hello():
                  dynamodb = boto3.resource('dynamodb', region_name='us-west-2')
                  table = dynamodb.Table('${aws_dynamodb_table.sample_table.name}')
                  response = table.get_item(
                      Key={
                          'id': '1'
                      }
                  )
                  item = response['Item']
                  return f"Hello, {item['name']}!"

              if __name__ == "__main__":
                  app.run(host='0.0.0.0')
              APP

              # Start Flask app with Gunicorn
              gunicorn app:app -b 0.0.0.0:80
              EOF

  tags = {
    Name = "web-instance-${count.index}"
  }
}

# Create Elastic Load Balancer
resource "aws_elb" "web_lb" {
  name               = "web-lb"
  security_groups    = [aws_security_group.instance_sg.id]
  availability_zones = ["us-west-2a", "us-west-2b"]  # Update with your desired availability zones

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }

  instances = aws_instance.web.*.id
}

terraform {
  backend "s3" {
    bucket         = "fastapi-test-bucket-09"
    key            = "terraform.tfstate"
    region         = "us-west-2"  # Update with your desired region
    dynamodb_table = "terraform_locks"  # Optional: Enable DynamoDB locking
  }
}

output "load_balancer_dns" {
  value = aws_elb.web_lb.dns_name
}