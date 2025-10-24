# Deploy Nextcloud no Amazon ECS

Este guia detalha como fazer o deploy do Nextcloud otimizado no Amazon ECS (Elastic Container Service).

## 📋 Pré-requisitos

- AWS CLI configurado
- Docker instalado
- Amazon ECR (Elastic Container Registry) configurado
- RDS PostgreSQL configurado (veja `RDS_SETUP.md`)
- VPC e subnets configuradas
- Security Groups configurados

## 🏗️ Arquitetura ECS

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Application   │    │   Load Balancer │    │      ECS        │
│   Load Balancer │◄───┤      (ALB)      │◄───┤    Service      │
│                 │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        │
                       ┌─────────────────┐             │
                       │      EFS        │◄────────────┤
                       │   (Storage)     │             │
                       └─────────────────┘             │
                                                        │
                       ┌─────────────────┐             │
                       │      RDS        │◄────────────┘
                       │  (PostgreSQL)   │
                       └─────────────────┘
```

## 🚀 Passo 1: Build e Push da Imagem

### 1.1 Criar repositório no ECR

```bash
# Criar repositório
aws ecr create-repository --repository-name nextcloud-ecs --region us-east-1

# Obter URI do repositório
aws ecr describe-repositories --repository-names nextcloud-ecs --region us-east-1
```

### 1.2 Build e push da imagem

```bash
# Fazer login no ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com

# Build da imagem
docker build -t nextcloud-ecs .

# Tag da imagem
docker tag nextcloud-ecs:latest <account-id>.dkr.ecr.us-east-1.amazonaws.com/nextcloud-ecs:latest

# Push da imagem
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/nextcloud-ecs:latest
```

## 🔧 Passo 2: Configurar ECS

### 2.1 Criar Cluster ECS

```bash
# Criar cluster Fargate
aws ecs create-cluster --cluster-name nextcloud-cluster --capacity-providers FARGATE --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1
```

### 2.2 Criar Task Definition

Crie o arquivo `task-definition.json`:

```json
{
  "family": "nextcloud-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::<account-id>:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::<account-id>:role/ecsTaskRole",
  "containerDefinitions": [
    {
      "name": "nextcloud",
      "image": "<account-id>.dkr.ecr.us-east-1.amazonaws.com/nextcloud-ecs:latest",
      "portMappings": [
        {
          "containerPort": 80,
          "protocol": "tcp"
        }
      ],
      "essential": true,
      "environment": [
        {
          "name": "POSTGRES_HOST",
          "value": "nextcloud.c29gca8kizzb.us-east-1.rds.amazonaws.com"
        },
        {
          "name": "POSTGRES_DB",
          "value": "postgres"
        },
        {
          "name": "POSTGRES_USER",
          "value": "postgres"
        },
        {
          "name": "POSTGRES_PORT",
          "value": "5432"
        },
        {
          "name": "NEXTCLOUD_ADMIN_USER",
          "value": "admin"
        },
        {
          "name": "NEXTCLOUD_TRUSTED_DOMAINS",
          "value": "seu-dominio.com"
        }
      ],
      "secrets": [
        {
          "name": "POSTGRES_PASSWORD",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:<account-id>:secret:nextcloud/rds-password"
        },
        {
          "name": "NEXTCLOUD_ADMIN_PASSWORD",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:<account-id>:secret:nextcloud/admin-password"
        }
      ],
      "mountPoints": [
        {
          "sourceVolume": "nextcloud-efs",
          "containerPath": "/var/www/html"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/nextcloud",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": [
          "CMD-SHELL",
          "/usr/local/bin/healthcheck.sh"
        ],
        "interval": 30,
        "timeout": 10,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ],
  "volumes": [
    {
      "name": "nextcloud-efs",
      "efsVolumeConfiguration": {
        "fileSystemId": "fs-xxxxxxxxx",
        "transitEncryption": "ENABLED",
        "authorizationConfig": {
          "accessPointId": "fsap-xxxxxxxxx"
        }
      }
    }
  ]
}
```

### 2.3 Registrar Task Definition

```bash
aws ecs register-task-definition --cli-input-json file://task-definition.json
```

## 🔐 Passo 3: Configurar Secrets Manager

### 3.1 Criar secrets para senhas

```bash
# Senha do RDS
aws secretsmanager create-secret \
  --name "nextcloud/rds-password" \
  --description "Senha do banco RDS para Nextcloud" \
  --secret-string "SuaSenhaSeguraDoRDS"

# Senha do admin do Nextcloud
aws secretsmanager create-secret \
  --name "nextcloud/admin-password" \
  --description "Senha do admin do Nextcloud" \
  --secret-string "SuaSenhaSeguraDoAdmin"
```

## 🌐 Passo 4: Configurar Application Load Balancer

### 4.1 Criar ALB

```bash
# Criar ALB
aws elbv2 create-load-balancer \
  --name nextcloud-alb \
  --subnets subnet-xxxxxxxx subnet-yyyyyyyy \
  --security-groups sg-xxxxxxxxx \
  --scheme internet-facing \
  --type application \
  --ip-address-type ipv4
```

### 4.2 Criar Target Group

```bash
# Criar target group
aws elbv2 create-target-group \
  --name nextcloud-targets \
  --protocol HTTP \
  --port 80 \
  --vpc-id vpc-xxxxxxxxx \
  --target-type ip \
  --health-check-path /status.php \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 10 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3
```

### 4.3 Criar Listener

```bash
# Criar listener HTTP
aws elbv2 create-listener \
  --load-balancer-arn arn:aws:elasticloadbalancing:us-east-1:<account-id>:loadbalancer/app/nextcloud-alb/xxxxxxxxx \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=arn:aws:elasticloadbalancing:us-east-1:<account-id>:targetgroup/nextcloud-targets/xxxxxxxxx
```

## 🚀 Passo 5: Criar ECS Service

### 5.1 Criar service

```bash
aws ecs create-service \
  --cluster nextcloud-cluster \
  --service-name nextcloud-service \
  --task-definition nextcloud-task:1 \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxxxxxxx,subnet-yyyyyyyy],securityGroups=[sg-xxxxxxxxx],assignPublicIp=ENABLED}" \
  --load-balancers targetGroupArn=arn:aws:elasticloadbalancing:us-east-1:<account-id>:targetgroup/nextcloud-targets/xxxxxxxxx,containerName=nextcloud,containerPort=80 \
  --health-check-grace-period-seconds 300
```

## 📊 Passo 6: Monitoramento e Logs

### 6.1 Criar CloudWatch Log Group

```bash
aws logs create-log-group --log-group-name /ecs/nextcloud
```

### 6.2 Configurar Auto Scaling

```bash
# Registrar target escalável
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id service/nextcloud-cluster/nextcloud-service \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 1 \
  --max-capacity 10

# Criar política de scaling
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id service/nextcloud-cluster/nextcloud-service \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name nextcloud-cpu-scaling \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration file://scaling-policy.json
```

Arquivo `scaling-policy.json`:
```json
{
  "TargetValue": 70.0,
  "PredefinedMetricSpecification": {
    "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
  },
  "ScaleOutCooldown": 300,
  "ScaleInCooldown": 300
}
```

## 🔍 Verificação e Troubleshooting

### Verificar status do service
```bash
aws ecs describe-services --cluster nextcloud-cluster --services nextcloud-service
```

### Verificar logs
```bash
aws logs tail /ecs/nextcloud --follow
```

### Verificar health checks
```bash
aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:us-east-1:<account-id>:targetgroup/nextcloud-targets/xxxxxxxxx
```

## 💰 Estimativa de Custos (us-east-1)

### ECS Fargate
- **2 tasks (0.5 vCPU, 1GB RAM cada)**: ~$35/mês
- **Application Load Balancer**: ~$16/mês
- **Data Transfer**: ~$9/GB

### Armazenamento
- **EFS Standard**: ~$0.30/GB/mês
- **EFS Infrequent Access**: ~$0.025/GB/mês

### Monitoramento
- **CloudWatch Logs**: ~$0.50/GB
- **CloudWatch Metrics**: Incluído

**Total estimado**: ~$60-80/mês (sem contar RDS e data transfer)

## 🔒 Considerações de Segurança

1. **Secrets Manager**: Nunca coloque senhas em variáveis de ambiente
2. **Security Groups**: Configure apenas as portas necessárias
3. **EFS**: Use criptografia em trânsito e em repouso
4. **ALB**: Configure HTTPS com certificado SSL/TLS
5. **IAM**: Use princípio do menor privilégio
6. **VPC**: Use subnets privadas para tasks ECS

## 🚀 Próximos Passos

1. Configure um domínio personalizado
2. Implemente HTTPS com ACM (AWS Certificate Manager)
3. Configure backup automático do EFS
4. Implemente CI/CD com CodePipeline
5. Configure monitoramento avançado com CloudWatch Insights

## 📞 Suporte

Para problemas específicos do ECS:
- Verifique os logs do CloudWatch
- Confirme as configurações de rede (VPC, subnets, security groups)
- Valide as permissões IAM
- Teste a conectividade com RDS e EFS