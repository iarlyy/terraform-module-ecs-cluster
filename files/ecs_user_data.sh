Content-Type: multipart/mixed; boundary="==BOUNDARY=="
MIME-Version: 1.0

--==BOUNDARY==
MIME-Version: 1.0
Content-Type: text/text/x-shellscript; charset="us-ascii"
#!/bin/bash
# Install awslogs, aws-cli, jq and more dependencies
yum install -y awslogs jq aws-cli python36
pip-3.6 install boto3
cat > /etc/ecs/ecs.config <<EOF
ECS_CLUSTER=${cluster_name}
ECS_AVAILABLE_LOGGING_DRIVERS=["json-file","awslogs","syslog","gelf"]
ECS_ENABLE_TASK_IAM_ROLE=true
ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true
ECS_ENGINE_TASK_CLEANUP_WAIT_DURATION=30m
ECS_IMAGE_CLEANUP_INTERVAL=1h
ECS_IMAGE_MINIMUM_CLEANUP_AGE=15m
ECS_NUM_IMAGES_DELETE_PER_CYCLE=10
EOF

# Let tasks access aws metadata
sysctl -w net.ipv4.conf.all.route_localnet=1
iptables -t nat -A PREROUTING -p tcp -d 169.254.170.2 --dport 80 -j DNAT --to-destination 127.0.0.1:51679
iptables -t nat -A OUTPUT -d 169.254.170.2 -p tcp -m tcp --dport 80 -j REDIRECT --to-ports 51679
service iptables save

--==BOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"
#!/bin/bash
# Inject the CloudWatch Logs configuration file contents
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/using_cloudwatch_logs.html
cat > /etc/awslogs/awslogs.conf <<EOF
[general]
state_file = /var/lib/awslogs/agent-state

[/var/log/dmesg]
file = /var/log/dmesg
log_group_name = {cluster}-/var/log/dmesg
log_stream_name = {container_instance_id}

[/var/log/messages]
file = /var/log/messages
log_group_name = {cluster}-/var/log/messages
log_stream_name = {container_instance_id}
datetime_format = %b %d %H:%M:%S

[/var/log/docker]
file = /var/log/docker
log_group_name = {cluster}-/var/log/docker
log_stream_name = {container_instance_id}
datetime_format = %Y-%m-%dT%H:%M:%S.%f

[/var/log/ecs/ecs-init.log]
file = /var/log/ecs/ecs-init.log
log_group_name = {cluster}-/var/log/ecs/ecs-init.log
log_stream_name = {container_instance_id}
datetime_format = %Y-%m-%dT%H:%M:%SZ

[/var/log/ecs/ecs-agent.log]
file = /var/log/ecs/ecs-agent.log.*
log_group_name = {cluster}-/var/log/ecs/ecs-agent.log
log_stream_name = {container_instance_id}
datetime_format = %Y-%m-%dT%H:%M:%SZ

[/var/log/ecs/audit.log]
file = /var/log/ecs/audit.log.*
log_group_name = {cluster}-/var/log/ecs/audit.log
log_stream_name = {container_instance_id}
datetime_format = %Y-%m-%dT%H:%M:%SZ

EOF

--==BOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"
#!/bin/bash
# Set the region to send CloudWatch Logs data to (the region where the container instance is located)
region=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
sed -i -e "s/region = us-east-1/region = $region/g" /etc/awslogs/awscli.conf

--==BOUNDARY==
Content-Type: text/upstart-job; charset="us-ascii"

#upstart-job
description "Configure and start CloudWatch Logs agent on Amazon ECS container instance"
author "Amazon Web Services"
start on started ecs

script
	exec 2>>/var/log/ecs/cloudwatch-logs-start.log
	set -x

	until curl -s http://localhost:51678/v1/metadata
	do
		sleep 1
	done

	# Grab the cluster and container instance ARN from instance metadata
	cluster=$(curl -s http://localhost:51678/v1/metadata | jq -r '. | .Cluster')
	container_instance_id=$(curl -s http://localhost:51678/v1/metadata | jq -r '. | .ContainerInstanceArn' | awk -F/ '{print $2}' )

	# Replace the cluster name and container instance ID placeholders with the actual values
	sed -i -e "s/{cluster}/$cluster/g" /etc/awslogs/awslogs.conf
	sed -i -e "s/{container_instance_id}/$container_instance_id/g" /etc/awslogs/awslogs.conf

	service awslogs start
	chkconfig awslogs on
end script

--==BOUNDARY==
