# ------------------------------------------------------------------------------
# LB Controller
# ------------------------------------------------------------------------------

module "alb_controller_irsa" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version   = "5.39.0"

  role_name = "${data.terraform_remote_state.infra.outputs.eks_cluster_name}-alb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = data.terraform_remote_state.infra.outputs.eks_oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.7.1"

   values = [
    yamlencode({
      clusterName = data.terraform_remote_state.infra.outputs.eks_cluster_name
      region      = var.aws_region
      vpcId       = data.terraform_remote_state.infra.outputs.vpc_id

      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.alb_controller_irsa.iam_role_arn
        }
      }
    })
  ]
}

# ------------------------------------------------------------------------------
# ExternalDNS
# ------------------------------------------------------------------------------

module "external_dns_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.39.0"

  role_name = "${data.terraform_remote_state.infra.outputs.eks_cluster_name}-external-dns"

  attach_external_dns_policy = true

  oidc_providers = {
    main = {
      provider_arn               = data.terraform_remote_state.infra.outputs.eks_oidc_provider_arn
      namespace_service_accounts = ["kube-system:external-dns"]
    }
  }
}

resource "helm_release" "external_dns" {
  name       = "external-dns"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = "1.14.4"

  values = [
    yamlencode({
      provider      = "aws"
      policy        = "upsert-only"
      aws = {
        zoneType = "public"
      }
      domainFilters = ["neves-box.com"]
      txtOwnerId    = data.terraform_remote_state.infra.outputs.eks_cluster_name
      logLevel      = "info"

      serviceAccount = {
        create = true
        name   = "external-dns"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.external_dns_irsa.iam_role_arn
        }
      }
    })
  ]
}