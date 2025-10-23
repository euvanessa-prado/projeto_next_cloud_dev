# Configuração do Nextcloud com Amazon RDS

Este guia explica como configurar o Nextcloud para usar um banco de dados PostgreSQL no Amazon RDS ao invés de um banco local.

## Pré-requisitos

1. **Instância RDS PostgreSQL criada** na AWS
2. **Security Group configurado** para permitir conexões na porta 5432
3. **Credenciais do banco** (usuário, senha, nome do banco)

## Persistência de Dados

Com o RDS, você tem **duas camadas de dados** para considerar:

### 1. **Dados do Banco (RDS)** ✅ Já persistente
- Metadados do Nextcloud (usuários, configurações, etc.)
- **Automaticamente persistente** no RDS
- Backups automáticos disponíveis

### 2. **Arquivos dos Usuários** (precisa configurar)
Você tem **3 opções** para persistir os arquivos:

#### **Opção A: Volume Local** (atual)
- ✅ Simples de configurar
- ❌ Dados ficam no container/host
- ❌ Perdidos se o container for removido

#### **Opção B: Amazon EFS** (recomendado para produção)
- ✅ Totalmente gerenciado pela AWS
- ✅ Escalável e durável
- ✅ Pode ser montado em múltiplas instâncias
- ✅ Backups automáticos

#### **Opção C: Amazon S3** (via plugin)
- ✅ Armazenamento ilimitado
- ✅ Muito econômico
- ❌ Requer configuração adicional no Nextcloud

## Configuração do RDS

### 1. Criar a instância RDS
- Engine: PostgreSQL
- Versão: 13 ou superior (compatível com Nextcloud)
- Classe da instância: db.t3.micro (para testes) ou superior
- Armazenamento: 20GB mínimo
- **Importante**: Marque "Publicly accessible" se o Docker estiver fora da VPC

### 2. Configurar Security Group
Adicione uma regra de entrada:
- Tipo: PostgreSQL
- Porta: 5432
- Origem: 0.0.0.0/0 (ou o IP específico do seu servidor)

### 3. Criar o banco de dados (OPCIONAL)

Você tem **2 opções**:

#### **Opção A: Usar banco padrão** (mais simples)
- Use o banco `postgres` que já existe
- Configure no `.env`:
  ```env
  RDS_USERNAME=postgres
  RDS_PASSWORD=sua-senha-master
  RDS_DATABASE=postgres
  ```

#### **Opção B: Criar banco dedicado** (mais organizado)
Conecte-se ao RDS e execute:
```sql
CREATE DATABASE nextcloud;
CREATE USER nextcloud WITH PASSWORD 'sua-senha-segura';
GRANT ALL PRIVILEGES ON DATABASE nextcloud TO nextcloud;
```

Configure no `.env`:
```env
RDS_USERNAME=nextcloud
RDS_PASSWORD=sua-senha-segura
RDS_DATABASE=nextcloud
```

## Configuração com Amazon EFS (Recomendado)

### 1. Criar o EFS
1. No console AWS, vá para **EFS**
2. Clique em **Create file system**
3. Escolha a VPC onde está seu servidor
4. Configure o Security Group para permitir NFS (porta 2049)

### 2. Configurar Security Group do EFS
Adicione uma regra de entrada:
- Tipo: NFS
- Porta: 2049
- Origem: Security Group do seu servidor Docker

### 3. Modificar o Docker Compose
No arquivo `compose.yml`, descomente as linhas do EFS:
```yaml
volumes:
  # Opção 2: Amazon EFS (descomente para usar)
  - type: nfs
    source: ${EFS_DNS_NAME}.efs.${AWS_REGION}.amazonaws.com:/
    target: /var/www/html
    volume:
      nocopy: true
```

### 4. Configurar variáveis de ambiente
No arquivo `.env`, adicione:
```env
EFS_DNS_NAME=fs-xxxxxxxxx
AWS_REGION=us-east-1
```

## Configuração do Docker Compose

### 1. Configurar variáveis de ambiente
Copie o arquivo `.env.example` para `.env`:
```bash
cp .env.example .env
```

Edite o arquivo `.env` com os dados do seu RDS:
```env
RDS_ENDPOINT=seu-rds-endpoint.region.rds.amazonaws.com
RDS_USERNAME=nextcloud
RDS_PASSWORD=sua-senha-segura
RDS_DATABASE=nextcloud
RDS_PORT=5432

# Para EFS (opcional)
EFS_DNS_NAME=fs-xxxxxxxxx
AWS_REGION=us-east-1
```

### 2. Executar o Nextcloud
```bash
docker-compose up -d
```

## Verificação

1. Acesse `http://localhost` no navegador
2. Complete a configuração inicial do Nextcloud
3. Verifique se a conexão com o banco está funcionando
4. Teste upload de arquivos para verificar persistência

## Backup e Recuperação

### RDS (Banco de Dados)
- **Backup automático**: Configurado na criação do RDS
- **Snapshot manual**: Disponível no console AWS
- **Point-in-time recovery**: Até 35 dias

### EFS (Arquivos)
- **AWS Backup**: Configure políticas de backup automático
- **Snapshot manual**: Disponível no console EFS

## Troubleshooting

### Erro de conexão com o banco
- Verifique se o Security Group permite conexões na porta 5432
- Confirme se o endpoint do RDS está correto
- Teste a conectividade: `telnet seu-rds-endpoint.region.rds.amazonaws.com 5432`

### Erro de montagem do EFS
- Verifique se o Security Group permite NFS (porta 2049)
- Confirme se o DNS name do EFS está correto
- Teste: `sudo mount -t nfs4 fs-xxxxxxxxx.efs.region.amazonaws.com:/ /mnt/test`

### Erro de autenticação
- Verifique se as credenciais no arquivo `.env` estão corretas
- Confirme se o usuário tem permissões no banco de dados

### Nextcloud não inicia
- Verifique os logs: `docker-compose logs nc`
- Confirme se todas as variáveis de ambiente estão definidas

## Segurança

- **Nunca** commite o arquivo `.env` no repositório
- Use senhas fortes para o banco de dados
- Configure SSL/TLS para conexões com o RDS em produção
- Restrinja o Security Group apenas aos IPs necessários
- Configure criptografia em trânsito para EFS

## Custos Estimados (us-east-1)

### RDS db.t3.micro
- **Instância**: ~$13/mês
- **Armazenamento**: ~$2.30/mês (20GB)

### EFS
- **Armazenamento Standard**: $0.30/GB/mês
- **Exemplo**: 100GB = ~$30/mês

### Total estimado: ~$45-50/mês para setup básico