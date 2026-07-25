# Production EU — Same as prod-us but in eu-west-1
aws_region          = "eu-west-1"
project_name        = "enterprise"
environment         = "prod-eu"
vpc_cidr            = "10.2.0.0/16"
cluster_version     = "1.31"
node_instance_types = ["t3.large"]
node_desired_size   = 3
node_min_size       = 3
node_max_size       = 10
