# Dev US — Smaller, cheaper, single NAT
aws_region          = "us-east-1"
project_name        = "enterprise"
environment         = "dev-us"
vpc_cidr            = "10.1.0.0/16"
cluster_version     = "1.31"
node_instance_types = ["t3.medium"]
node_desired_size   = 2
node_min_size       = 1
node_max_size       = 4
