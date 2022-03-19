# IAM policies.
resource "aws_iam_policy" "describe_instances" {
  name        = "describe-instances"
  policy      = file("${local.policies_path}/describe_instances.json")
}

resource "aws_iam_policy" "eks" {
  name        = "eks"
  policy      = file("${local.policies_path}/eks.json")
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

resource "aws_iam_policy_attachment" "jenkins_agent_eks" {
  name       = "jenkins-agent-eks"
  roles      = [aws_iam_role.jenkins_agent.name]
  policy_arn = aws_iam_policy.eks.arn
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
