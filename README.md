# Avaliação Prática de DevOps — Prova C — Cadastro de Cursos

## Integrantes do grupo

| Nome completo                  | RA        |
|--------------------------------|-----------|
| Calebe Matheus Moreira Moraes  | 24000974  |
| Lucas Vigo Calió               | 24000092  |
| Leandro José de Carvalho       | 240001964 |

## Endereço da aplicação

- **Aplicação web (VM1):** http://IP_PUBLICO_VM1
- **API REST (VM2):** http://IP_PUBLICO_VM2:3000/cursos

## Arquitetura

```
 VM1 - aplicação web                      VM2 - API e banco
 ┌──────────────────────────┐   HTTP     ┌──────────────────────────────┐
 │ Docker: nginx + HTML     │ ─────────▶ │ Docker: API Node.js (:3000)  │
 │ Formulário de cadastro   │  GET/POST  │ Docker: MySQL 8 (rede interna)│
 │ Link "Listar todos"      │            │ POST /curso   GET /cursos    │
 └──────────────────────────┘            └──────────────────────────────┘

 OpenTofu provisiona as VMs | cloud-init prepara o Docker | Ansible implanta os serviços
```

- **OpenTofu** (`iac/main.tf`): cria as duas instâncias EC2 (Ubuntu 22.04), os security groups
  (VM1: 22/80 — VM2: 22/3000) e gera automaticamente o `ansible/inventory` com os IPs.
- **cloud-init** (`iac/cloud_init.yaml`): instala Docker Engine + Docker Compose e cria swap.
- **Ansible** (`ansible/playbook.yml`): garante o Docker, sobe MySQL + API na VM2 com
  `docker compose` e sobe o nginx com a aplicação HTML na VM1, já apontando para o IP da VM2.
- **CORS**: a API só aceita requisições de navegador vindas da origem da aplicação web
  (`http://IP_DA_VM1`), com métodos `GET`, `POST` e `OPTIONS` (preflight). A origem é
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

## Pré-requisitos (máquina de controle — Linux, WSL ou EC2)

- OpenTofu ≥ 1.6, Ansible, credenciais da AWS configuradas (`~/.aws/credentials`)
- Um key pair existente na AWS (no AWS Academy: `vockey`) e a chave privada `.pem`
  correspondente com permissão `chmod 400`

## Instruções de execução

```bash
# 1) Provisionar as VMs (também gera ansible/inventory)
cd iac
tofu init
tofu apply -auto-approve \
  -var="key_name=vockey" \
  -var="ssh_private_key_path=~/.ssh/labsuser.pem"
cd ..

# 2) Configurar e implantar os serviços
ansible-playbook -i ansible/inventory ansible/playbook.yml

# 3) Acessar a aplicação
#    http://<vm1_ip_publico>   (exibido no "tofu output" e no fim do playbook)
```

Teste rápido da API pelo terminal:

```bash
curl -X POST http://IP_VM2:3000/curso -H "Content-Type: application/json" \
     -d '{"nome":"Ansible","instrutor":"João","preco":150.5,"vagas":20}'
curl http://IP_VM2:3000/cursos
```

Conferir os registros persistidos no MySQL da VM2:

```bash
ssh -i ~/.ssh/labsuser.pem ubuntu@IP_VM2 \
  "sudo docker exec cursos-mysql mysql -ucursos -pcursos123 cursosdb -e 'SELECT * FROM cursos;'"
```

### Teste local (opcional, sem AWS)

```bash
cd api && docker compose up -d --build          # API em http://localhost:3000
cd ../app && docker build -t cursos-web . && docker run -d -p 8080:80 cursos-web
# abrir http://localhost:8080
```

### Destruir a infraestrutura

```bash
cd iac && tofu destroy -auto-approve
```

## Estrutura do repositório

```
avaliacao/
├── ansible/
│   ├── inventory
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
│   ├── package.json
│   └── server.js
└── README.md
```
