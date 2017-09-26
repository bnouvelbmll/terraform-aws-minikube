module "minikube" {
  source = "github.com/scholzj/terraform-aws-minikube"

  aws_region    = "eu-central-1"
  cluster_name  = "my-minikube"
  aws_instance_type = "t2.medium"
  ssh_public_key = "~/.ssh/id_rsa.pub"
  aws_subnet_id = "subnet-8a3517f8"
  hosted_zone = "my-domain.com"
  hosted_zone_private = false

  tags = {
    Application = "Minikube"
  }

  addons = [
    "https://raw.githubusercontent.com/scholzj/aws-minikube/master/addons//storage-class.yaml",
    "https://raw.githubusercontent.com/scholzj/aws-minikube/master/addons//heapster.yaml",
    "https://raw.githubusercontent.com/scholzj/aws-minikube/master/addons//dashboard.yaml",
    "https://raw.githubusercontent.com/scholzj/aws-minikube/master/addons//external-dns.yaml"
  ]
}