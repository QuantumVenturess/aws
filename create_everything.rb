# http://docs.aws.amazon.com/sdkforruby/api/frames.html

require "aws-sdk-v1"
require "aws-sdk"

timestamp = Time.now.strftime("%Y%m%d%S%M%I")

credentials = Aws::Credentials.new(
  ENV["AWS_ACCESS_KEY_ID"],
  ENV["AWS_SECRET_ACCESS_KEY"]
)

region            = "us-west-2"
availability_zone = "us-west-2a"

# AWS EC2 Client
ec2_client = Aws::EC2::Client.new(
  credentials: credentials,
  region:      region
)
# EC2 Resource
ec2_resource = Aws::EC2::Resource.new(client: ec2_client)

# VPC
# Peer VPC
vpcs       = ec2_resource.vpcs
peer_vpc   = vpcs.first
cidr_block = "10.0.0.0/24"
vpc        = ec2_resource.create_vpc(cidr_block: cidr_block)
puts "VPC created"
# Peering connection
unless peer_vpc.nil?
  peering_connection = ec2_resource.create_vpc_peering_connection(
    peer_vpc_id: peer_vpc.id,
    vpc_id:      vpc.id
  )
  puts "Peering Connection created"
  peering_connection.accept
  puts "Peering Connection accepted"
  # or
  # peering_connection = vpc.requested_vpc_peering_connections.first
end
# Create Internet Gateway

# Subnet
subnet = ec2_resource.create_subnet(
  cidr_block: cidr_block,
  vpc_id:     vpc.id
)

# Security Group
security_group = ec2_resource.create_security_group(
  description: "a security group created from create_everything.rb",
  group_name:  "security-group-#{timestamp}",
  vpc_id:      vpc.id
)
puts "Security Group created"
# Authorize
# Inbound rules
security_group.authorize_ingress(
  cidr_ip:        "0.0.0.0/0",
  from_port:      80,
  ip_protocol:    "tcp",
  # source_security_group_owner_id: "",
  to_port:        80
)
puts "Security Group inboud rule created"
# Outbound rules
security_group.authorize_egress(
  ip_permissions: [
    {
      ip_protocol: "tcp",
      from_port:   22,
      to_port:     22,
      ip_ranges: [
        {
          cidr_ip: "0.0.0.0/0"
        }
      ]
    }
  ]
)
puts "Security Group outbound rule created"

# Key Pair
# Create a new key pair
key_pair_name = "key-pair-#{timestamp}"
key_pair      = ec2_resource.create_key_pair(key_name: key_pair_name)
private_key   = key_pair.key_fingerprint # you can only call this once
puts "Key Pair created"

# EC2
count = 2
# Fetch an existing key pair
existing_key_pair = ec2_resource.key_pairs.find(name: key_pair_name).first
# image_id  = "ami-076e6542" # us-west-1 region
image_id      = "ami-3d50120d" # us-west-2 region
instance_type = "t2.medium"
instances     = ec2_resource.create_instances(
  image_id:        image_id,
  instance_type:   instance_type,
  key_name:        existing_key_pair.key_name,
  min_count:       count,
  max_count:       count,
  security_group_ids: [security_group.id],
  subnet_id:          subnet.id
)
puts "EC2 Instances created"
single_instance = instances.first

# Internet Gateway
internet_gateway = ec2_resource.create_internet_gateway
puts "Internet Gateway created"
# Attach internet gateway to vpc
ec2_client.attach_internet_gateway(
  internet_gateway_id: internet_gateway.id,
  vpc_id:              vpc.id
)
puts "Internet Gateway attached"

# Waiting
puts "Waiting for EC2 Instance to be running..."
single_instance.wait_until_running do |w|
  w.interval     = 10
  w.max_attempts = 100
end

# ELB Client
elb_client = Aws::ElasticLoadBalancing::Client.new(
  credentials: credentials,
  region:      region
)
# ELB Resource
elb_resource = Aws::ElasticLoadBalancing::Resource.new(client: elb_client)

# ELB
load_balancer_name = "elb-#{timestamp}"
elb = elb_client.create_load_balancer(
  listeners: [
    {
      load_balancer_port: 80,
      protocol:           :http,
      instance_port:      80,
      instance_protocol:  :http
    }
  ],
  load_balancer_name: load_balancer_name,
  security_groups:    [security_group.id],
  subnets:            [subnet.id]
)
puts "Elastic Load Balancer created"
# Add instance to load balancer
elb_client.register_instances_with_load_balancer(
  load_balancer_name: load_balancer_name,
  instances: instances.map { |i| { instance_id: i.id } }
)
puts "Elastic Load Balancer registered EC2 Instances"

# Create AMI
image = single_instance.create_image(
  name:        "ami-#{timestamp}",
  description: "image for create_everything.rb",
  no_reboot:   false
)
puts "AMI created"

# Auto Scaling
# Client
auto_scaling_client = Aws::AutoScaling::Client.new(
  credentials: credentials,
  region:      region
)
# Create Launch Configuration
# If you use instance id, you don't have to use any of the other parameters
launch_configuration_name = "launch-config-#{timestamp}"
auto_scaling_client.create_launch_configuration(
  instance_id: single_instance.id,
  # block_device_mappings: [
  #   {
  #     device_name: "/dev/sda1",
  #     ebs: {
  #       volume_size: 8
  #     }
  #   }
  # ],
  # ebs_optimized: true,
  # image_id: image.id,
  # instance_monitoring: {
  #   enabled: true
  # },
  # instance_type: instance_type,
  # key_name: key_pair.key_name,
  launch_configuration_name: launch_configuration_name,
  # security_groups: [security_group.id]
)
puts "Launch Configuration created"
# Auto Scaling Groups
# If you use instance id here, 
# you don't need to create a previous launch config
# This method will create a launch configuration for you using the instance id
auto_scaling_client.create_auto_scaling_group(
  auto_scaling_group_name:   "group-#{timestamp}",
  default_cooldown:          500,
  desired_capacity:          count,
  health_check_grace_period: 1000,
  instance_id:         single_instance.id,
  load_balancer_names: [load_balancer_name],
  max_size:            count * 5,
  min_size:            count,
  # launch_configuration_name: launch_configuration_name,
  vpc_zone_identifier: subnet.id
)
puts "Auto Scaling Group created"

# CloudFormation
