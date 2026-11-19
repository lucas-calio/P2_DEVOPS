# Avaliação Prática de DevOps — Prova C — Cadastro de Cursos

## Integrantes do grupo

| Nome completo                  | RA        |
|--------------------------------|-----------|
| Calebe Matheus Moreira Moraes  | 24000974  |
| Lucas Vigo Calió               | 24000092  |
| Leandro José de Carvalho       | 24001964  |

## Endereço da aplicação

- **Aplicação web (VM1):** http://18.220.154.135
- **API REST (VM2):** http://18.191.175.134:3000/cursos

| Item              | Valor                                   |
|-------------------|-----------------------------------------|
| Região AWS        | `us-east-2` (Ohio)                      |
| Tipo de instância | `t3.micro`                              |
| Sistema           | Ubuntu 22.04 LTS (AMI oficial Canonical) |
| Implantação       | 18/11/2026, via OpenTofu + Ansible      |

## Arquitetura

```
 Máquina de controle (EC2 Ubuntu em us-east-2)
 OpenTofu + Ansible + AWS CLI
        │  tofu apply (cria as VMs)   ansible-playbook (SSH)
        ▼
 VM1 - aplicação web                      VM2 - API e banco
 ┌──────────────────────────┐   HTTP     ┌───────────────────────────────┐
 │ Docker: nginx + HTML     │ ─────────▶ │ Docker: API Node.js (:3000)   │
 │ Formulário de cadastro   │  GET/POST  │ Docker: MySQL 8 (rede interna)│
 │ Link "Listar todos"      │            │ POST /curso   GET /cursos     │
 └──────────────────────────┘            └───────────────────────────────┘

 OpenTofu provisiona as VMs | cloud-init prepara o Docker | Ansible implanta os serviços
```

- **OpenTofu** (`iac/main.tf`): cria, em `us-east-2`, as duas instâncias EC2 `t3.micro`
  (Ubuntu 22.04), os security groups (VM1: 22/80 — VM2: 22/3000) e o par de chaves SSH, e gera
  automaticamente o `ansible/inventory` com os IPs. A AMI do Ubuntu é obtida pelo parâmetro
  público da Canonical no SSM
  (`/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id`),
  que sempre aponta para a imagem estável mais recente da região.
- **cloud-init** (`iac/cloud_init.yaml`): instala Docker Engine + Docker Compose e cria swap de 1 GB.
- **Ansible** (`ansible/playbook.yml`): garante o Docker, sobe MySQL + API na VM2 com
  `docker compose` e sobe o nginx com a aplicação HTML na VM1, já apontando para o IP da VM2.
- **CORS**: a API só aceita requisições de navegador vindas da origem da aplicação web
  (`http://18.220.154.135`), com métodos `GET`, `POST` e `OPTIONS` (preflight). A origem é
  configurada pelo Ansible na variável `CORS_ORIGIN`.
- O MySQL **não** é exposto para fora da VM2 — só a API acessa, pela rede interna do Docker.
  Os dados ficam no volume `mysql_data`.

## Dados do curso

| Campo                 | Coluna      | Tipo            |
|-----------------------|-------------|-----------------|
| Nome do curso         | `nome`      | Texto (VARCHAR) |
| Instrutor responsável | `instrutor` | Texto (VARCHAR) |
| Preço                 | `preco`     | Decimal (10,2)  |
| Quantidade de vagas   | `vagas`     | Inteiro         |

## Rotas da API

| Método | Rota      | Descrição                                       |
|--------|-----------|-------------------------------------------------|
| POST   | `/curso`  | Recebe os quatro campos e cadastra no MySQL     |
| GET    | `/cursos` | Retorna todos os cursos cadastrados em JSON     |
| GET    | `/health` | Verificação de saúde (usado pelo Ansible)       |

Exemplo de corpo do `POST /curso`:

```json
{ "nome": "Docker na Prática", "instrutor": "Maria Silva", "preco": 199.90, "vagas": 30 }
```

## Pré-requisitos (máquina de controle)

A implantação foi feita a partir de uma EC2 Ubuntu já existente em `us-east-2`, usada só como
máquina de controle (qualquer Linux ou WSL também serve).

1. **Ferramentas** — OpenTofu ≥ 1.6, Ansible, git e AWS CLI:

   ```bash
   sudo apt update && sudo apt install -y ansible git curl unzip
   curl -fsSL https://get.opentofu.org/install-opentofu.sh -o install-opentofu.sh
   chmod +x install-opentofu.sh && sudo ./install-opentofu.sh --install-method deb
   sudo snap install aws-cli --classic
   ```

2. **Credenciais da AWS** — criar um usuário IAM (ex.: `devops-prova`, política
   `AdministratorAccess`) com uma *access key* do tipo CLI e configurar:

   ```bash
   aws configure          # Access Key, Secret Key, região us-east-2, formato: Enter
   aws sts get-caller-identity   # deve mostrar o ARN do usuário
   ```

3. **Chave SSH** — não é preciso nenhum `.pem`: o OpenTofu gera o par de chaves, cadastra na AWS
   e grava a chave privada em `ansible/avaliacao_key.pem` (ignorada pelo git), já referenciada
   no inventário.

## Instruções de execução

```bash
# 0) Obter o código
git clone https://github.com/lucas-calio/P2_DEVOPS.git && cd P2_DEVOPS

# 1) Provisionar as VMs em us-east-2 (também gera ansible/inventory e a chave SSH) — ~2 min
cd iac
tofu init
tofu apply -auto-approve
cd ..

# 2) Configurar e implantar os serviços — ~5 a 8 min
ansible-playbook -i ansible/inventory ansible/playbook.yml

# 3) Acessar a aplicação
#    http://<vm1_ip_publico>   (exibido no "tofu output" e no fim do playbook)
```

Saída esperada ao final:

```
tofu apply  -> Apply complete! Resources: 8 added, 0 changed, 0 destroyed.
playbook    -> PLAY RECAP: vm1 failed=0, vm2 failed=0
```

## Testes

Teste rápido da API pelo terminal:

```bash
curl http://18.191.175.134:3000/health
curl -X POST http://18.191.175.134:3000/curso -H "Content-Type: application/json" \
     -d '{"nome":"Ansible para Iniciantes","instrutor":"João Pereira","preco":150.5,"vagas":20}'
curl http://18.191.175.134:3000/cursos
```

Teste do CORS (preflight vindo da VM1 deve retornar `204` com `Access-Control-Allow-Origin`):

```bash
curl -i -X OPTIONS http://18.191.175.134:3000/curso \
     -H "Origin: http://18.220.154.135" -H "Access-Control-Request-Method: POST"
```

Conferir os registros persistidos no MySQL da VM2 (a partir da máquina de controle):

```bash
ssh -i ansible/avaliacao_key.pem ubuntu@18.191.175.134 \
  "sudo docker exec cursos-mysql mysql -ucursos -pcursos123 cursosdb -e 'SELECT * FROM cursos;'"
```

Pelo navegador: abrir http://18.220.154.135, preencher o formulário, clicar em
**Cadastrar curso** e depois em **Listar todos os cursos**.

### Teste local (opcional, sem AWS)

```bash
cd api && docker compose up -d --build          # API em http://localhost:3000
cd ../app && docker build -t cursos-web . && docker run -d -p 8080:80 cursos-web
# abrir http://localhost:8080
```

## Problemas encontrados e soluções

| Problema | Solução |
|----------|---------|
| `tofu apply` falhou com *"Your query returned no results"* no `data "aws_ami"` | A busca de AMIs por dono não retornava resultados na conta. A AMI passou a ser obtida pelo parâmetro público da Canonical no SSM (`data "aws_ssm_parameter"`). |
| Contas novas da AWS podem não aceitar `t2.micro` no nível gratuito | Tipo padrão alterado para `t3.micro`. |
| SSH pelo Windows: *"UNPROTECTED PRIVATE KEY FILE"* | Remover herança e dar leitura só ao usuário: `icacls chave.pem /inheritance:r` e `icacls chave.pem /grant:r "%USERNAME%:(R)"`. |

## Destruir a infraestrutura

```bash
cd iac && tofu destroy -auto-approve
```

## Estrutura do repositório

```
P2_DEVOPS/
├── ansible/
│   ├── inventory       (gerado pelo tofu apply)
│   └── playbook.yml
├── iac/
│   ├── cloud_init.yaml
│   └── main.tf
├── app/
│   ├── Dockerfile
│   ├── index.html      (formulário + link "Listar todos os cursos")
│   ├── cursos.html     (listagem)
│   ├── app.js, config.js, style.css
├── api/
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── package.json, package-lock.json
│   └── server.js
├── .gitignore
└── README.md
```
