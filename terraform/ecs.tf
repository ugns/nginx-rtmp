module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 3.0"

  name = "rtmp"

  container_insights = true

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy = [
    {
      capacity_provider = "FARGATE_SPOT"
      base              = 0
      weight            = 1
    }
  ]

  tags = {
    App       = "nginx-rtmp"
    ManagedBy = "Terraform"
  }
}

module "container_definition" {
  source  = "cloudposse/ecs-container-definition/aws"
  version = "~> 0.58"

  container_name  = "rtmp"
  container_image = format("%s:%s", data.aws_ecr_repository.rtmp.repository_url, var.image_tag)

  map_environment = {
    "TWITCH_HOST"       = var.ttv_hostname
    "TWITCH_STREAMKEY"  = var.ttv_streamkey
    "YOUTUBE_STREAMKEY" = var.yt_streamkey
  }

  port_mappings = [
    {
      hostPort      = 1935
      containerPort = 1935
      protocol      = "tcp"
    },
    {
      hostPort      = 8080
      containerPort = 8080
      protocol      = "tcp"
    }
  ]

  log_configuration = {
    logDriver = "awslogs"
    options = {
      "awslogs-group"         = "/ecs/nginx-rtmp"
      "awslogs-region"        = data.aws_region.current.name
      "awslogs-stream-prefix" = "ecs"
    }
  }
}

module "service_task" {
  source  = "cloudposse/ecs-alb-service-task/aws"
  version = "0.56.0"

  #   task_definition                = aws_ecs_task_definition.rtmp.arn
  name                           = "nginx-rtmp"
  environment                    = data.aws_region.current.name
  container_definition_json      = module.container_definition.json_map_encoded_list
  ecs_cluster_arn                = module.ecs.ecs_cluster_arn
  security_group_ids             = [module.rtmp_sg.security_group_id]
  subnet_ids                     = data.aws_subnet_ids.private.ids
  network_mode                   = "awsvpc"
  desired_count                  = 1
  task_memory                    = var.task_memory
  task_cpu                       = var.task_cpu
  vpc_id                         = data.aws_vpc.current.id
  ignore_changes_task_definition = true
  ignore_changes_desired_count   = true
  enable_all_egress_rule         = false
  wait_for_steady_state          = true

  capacity_provider_strategies = [
    {
      capacity_provider = "FARGATE_SPOT"
      weight            = 1
      base              = 0
    }
  ]

  ecs_load_balancers = [
    {
      container_name   = "rtmp"
      container_port   = 1935
      elb_name         = null
      target_group_arn = module.alb.target_group_arns[0]
    },
    {
      container_name   = "rtmp"
      container_port   = 8080
      elb_name         = null
      target_group_arn = module.alb.target_group_arns[1]
    }
  ]
}
