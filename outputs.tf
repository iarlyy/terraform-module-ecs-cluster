output "cluster_id" {
  value = "${aws_ecs_cluster.ecs_cluster.id}"
}

output "cluster_name" {
  value = "${aws_ecs_cluster.ecs_cluster.name}"
}

output "sg_id" {
  value = "${aws_security_group.ecs.id}"
}
