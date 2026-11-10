# boopartpay

Sobe o ambiente de teste com **booprecognition** (reconhecimento facial, SQLite) e **boopateway** (API + portal) no Docker, em um só comando.

## Pré-requisitos

- Git
- Docker com Compose v2 (Docker Desktop no Windows/macOS), em execução
- `curl` (Linux/macOS)

## Como rodar

Linux / macOS:

```bash
./setup.sh
```

Windows (duplo clique ou no terminal):

```bat
setup.cmd
```

O script:

1. clona (ou atualiza) `booprecognition` e `boopateway` em `./workspace/`;
2. configura o `config.yaml` do booprecognition com `target: sqlite` e gera o `.env` com as credenciais de teste;
3. sobe o booprecognition (`docker/booprecognition.compose.yml`) na porta **31900**;
4. espera a API responder e emite um token OAuth (`client_credentials`, sem expiração);
5. grava o `.env` do boopateway (`BOOP_TOKEN`, senha do portal e credenciais OAuth) e sobe o compose dele (API e portal);
6. sobe a página de demonstração (`demo/`, `docker/demo.compose.yml`) na porta **31910**.

O primeiro build do booprecognition baixa os modelos InsightFace e leva vários minutos. Rodar o script de novo é seguro: ele atualiza os repositórios e recria os containers.

## Endereços

| Serviço | URL |
|---|---|
| demo de reconhecimento facial (slides + câmera) | http://localhost:31910 |
| booprecognition (Swagger) | http://localhost:31900/docs |
| boopateway API | http://localhost:31800 |
| boopateway portal | http://localhost:31801 (login com a senha `teste123`) |

## Credenciais de teste

booprecognition (`workspace/booprecognition/.env`):

| Variável | Valor padrão |
|---|---|
| `BOOP_JWT_SECRET` | `boopartpay-test-jwt-secret-0123456789abcdefghij` |
| `BOOP_CLIENT_ADMIN_SECRET` (client `boop-admin`) | `boopartpay-test-admin-secret` |

boopateway (`workspace/boopateway/.env`):

| Variável | Valor | Para quê |
|---|---|---|
| `BOOP_TOKEN` | gerado pelo script | token que a API usa no booprecognition |
| `ADMIN_PASSWORD` | `teste123` | senha do login do portal |
| `ADMIN_BOOP_TOKEN` | vazio (usa `BOOP_TOKEN`) | token fixo do portal; não é usado porque há OAuth |
| `BOOP_CLIENT_ID` | `boop-admin` | cada login do portal gera um token novo via OAuth |
| `BOOP_CLIENT_SECRET` | igual a `BOOP_CLIENT_ADMIN_SECRET` | |
| `BOOP_ADMIN_SCOPE` | `identify persons:write persons:delete` | scopes do token do portal |

Para trocar, defina as variáveis antes de rodar o script (ex.: `ADMIN_PASSWORD=outra BOOP_CLIENT_ADMIN_SECRET=outro ./setup.sh`). `BOOP_ADMIN_SCOPE` também pode ser sobrescrita.

## Derrubar

```bash
docker compose -p booprecognition -f docker/booprecognition.compose.yml down
```

```bash
docker compose -f workspace/boopateway/docker-compose.yml down
```

```bash
docker compose -p boopdemo -f docker/demo.compose.yml down
```

## Demo de reconhecimento facial

`demo/index.html` é uma apresentação em slides (← → para navegar). No último slide, **Ligar câmera** desenha em tempo real os contornos do rosto (oval, sobrancelhas, olhos, íris, lábios) de até 10 pessoas. ML Kit não roda no navegador; a página usa o equivalente web do Google, o MediaPipe Face Landmarker, e todo o processamento é local. O detector web é de curto alcance; com **modo grupo** ligado (padrão), a página também procura rostos pequenos em recortes do quadro e rastreia cada um num recorte ampliado. O custo é de ~10 ms por rosto por quadro (RTX 5070: 1 rosto ≈ 30 FPS, 10 rostos ≈ 7 FPS nos pontos; o vídeo continua fluido). O build da imagem baixa a biblioteca e o modelo, então a página não depende de internet depois de construída. Para subir só a demo:

```bash
docker compose -p boopdemo -f docker/demo.compose.yml up -d --build
```

A câmera exige contexto seguro: abra por `localhost` (ou HTTPS).

Adicione `-v` para apagar também os volumes (bancos SQLite e fotos).
