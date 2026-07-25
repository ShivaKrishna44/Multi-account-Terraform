# Production US — High availability, larger nodes
aws_region          = "us-east-1"
project_name        = "enterprise"
environment         = "prod-us"
vpc_cidr            = "10.0.0.0/16"
cluster_version     = "1.31"
node_instance_types = ["t3.large"]
node_desired_size   = 3
node_min_size       = 3
node_max_size       = 10
