# 1. AWS Load Balancer Controller를 위한 IAM 역할(IRSA) 생성
module "alb_controller_irsa" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  # 모듈 버전은 사용하는 Terraform 버전에 맞게 지정하는 것이 좋습니다.
  version   = "5.39.0"

  role_name = "${data.terraform_remote_state.infra.outputs.eks_cluster_name}-alb-controller"

  # 이 옵션은 필요한 IAM 정책을 자동으로 생성하고 연결해줍니다.
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = data.terraform_remote_state.infra.outputs.eks_oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# 2. Helm을 사용하여 AWS Load Balancer Controller 설치
resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.7.1" # 사용하는 컨트롤러 버전에 맞는 차트 버전을 사용하세요.

   values = [
    yamlencode({
      clusterName = data.terraform_remote_state.infra.outputs.eks_cluster_name
      region      = var.aws_region
      vpcId       = data.terraform_remote_state.infra.outputs.vpc_id

      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
        annotations = {
          # 키를 따옴표로 묶어 명확하게 표현
          "eks.amazonaws.com/role-arn" = module.alb_controller_irsa.iam_role_arn
        }
      }
    })
  ]
}