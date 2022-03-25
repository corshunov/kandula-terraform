# IAM policies.
resource "aws_iam_policy" "describe_instances" {
  name        = "describe-instances"
  policy      = file("${local.policies_path}/describe_instances.json")
}

resource "aws_iam_policy" "terminate_instances" {
  name        = "terminate-instances"
  policy      = file("${local.policies_path}/terminate_instances.json")
}

resource "aws_iam_policy" "full_eks" {
  name        = "full_eks"
  policy      = file("${local.policies_path}/full_eks.json")
}


# IAM roles.
resource "aws_iam_role" "consul" {
  name               = "consul"
  assume_role_policy = file("${local.policies_path}/assume_role.json")
}

resource "aws_iam_policy_attachment" "consul_describe_instances" {
  name       = "consul-describe-instances"
  roles      = [aws_iam_role.consul.name]
  policy_arn = aws_iam_policy.describe_instances.arn
}

resource "aws_iam_role" "jenkins_agent" {
  name               = "jenkins-agent"
  assume_role_policy = file("${local.policies_path}/assume_role.json")
}

resource "aws_iam_policy_attachment" "jenkins_agent_describe_instances" {
  name       = "jenkins-agent-describe-instances"
  roles      = [aws_iam_role.jenkins_agent.name]
  policy_arn = aws_iam_policy.describe_instances.arn
}

resource "aws_iam_policy_attachment" "jenkins_agent_full_eks" {
  name       = "jenkins-agent-full-eks"
  roles      = [aws_iam_role.jenkins_agent.name]
  policy_arn = aws_iam_policy.full_eks.arn
}

resource "aws_iam_role" "postgres" {
  name               = "postgres"
  assume_role_policy = file("${local.policies_path}/assume_role.json")
}

resource "aws_iam_policy_attachment" "postgres_describe_instances" {
  name       = "postgres-describe-instances"
  roles      = [aws_iam_role.postgres.name]
  policy_arn = aws_iam_policy.describe_instances.arn
}

resource "aws_iam_policy_attachment" "postgres_terminate_instances" {
  name       = "postgres-terminate-instances"
  roles      = [aws_iam_role.postgres.name]
  policy_arn = aws_iam_policy.terminate_instances.arn
}


# IAM instance profiles.
resource "aws_iam_instance_profile" "consul" {
  name  = "consul"
  role = aws_iam_role.consul.name
}

resource "aws_iam_instance_profile" "jenkins_agent" {
  name  = "jenkins_agent"
  role = aws_iam_role.jenkins_agent.name
}

resource "aws_iam_instance_profile" "postgres" {
  name  = "postgres"
  role = aws_iam_role.postgres.name
}
