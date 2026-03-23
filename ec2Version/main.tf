provider "aws" {
  region = "us-east-1"
}

resource "aws_security_group" "react_app_sg" {
  name = "react-app-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
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

resource "aws_instance" "react_app" {
  ami           = "ami-02dfbd4ff395f2a1b"
  instance_type = "t3.micro"

  key_name = "NDL3389_Virginia_2"

  security_groups = [aws_security_group.react_app_sg.name]

  user_data = file("userdata.sh")

  tags = {
    Name = "react-app-server"
  }
}