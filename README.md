# boopartpay

Sobe o ambiente de teste com **booprecognition** (reconhecimento facial, SQLite), **boopateway** (API + portal) e **boopateway-web** (POS FacePay web) no Docker, em um só comando.

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

1. clona (ou atualiza) `booprecognition`, `boopateway` e `boopateway-web` em `./workspace/`;
2. configura o `config.yaml` do booprecognition com `target: sqlite` e gera o `.env` com as credenciais de teste;
3. sobe o booprecognition (`docker/booprecognition.compose.yml`) na porta **31900** e, junto, a página de demonstração (`demo/`, `docker/demo.compose.yml`) nas portas **31910** (HTTP) e **31911** (HTTPS, para o celular). A demo não depende dos outros serviços, então fica no ar mesmo se algum passo seguinte falhar;
4. espera a API responder e emite um token OAuth (`client_credentials`, sem expiração);
5. grava o `.env` do boopateway (`BOOP_TOKEN`, senha do portal e credenciais OAuth) e sobe o compose dele (API e portal);
6. sobe o boopateway-web (POS FacePay em React) nas portas **31802** (HTTP) e **31803** (HTTPS, para o celular). O nginx dele repassa `/api/*` para o gateway na porta 31800.

O primeiro build do booprecognition baixa os modelos InsightFace e leva vários minutos. Rodar o script de novo é seguro: ele atualiza os repositórios e recria os containers.

## Endereços

| Serviço | URL |
|---|---|
| demo de reconhecimento facial (slides + câmera) | http://localhost:31910 |
| demo pelo celular (HTTPS, mesma rede) | https://IP-do-computador:31911 |
| booprecognition (Swagger) | http://localhost:31900/docs |
| boopateway API | http://localhost:31800 |
| boopateway portal | http://localhost:31801 (login com a senha `teste123`) |
| boopateway-web (POS FacePay) | http://localhost:31802 |
| POS pelo celular (HTTPS, mesma rede) | https://IP-do-computador:31803 |

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
docker compose -p boopateway-web -f workspace/boopateway-web/docker-compose.yml down
```

```bash
docker compose -p boopdemo -f docker/demo.compose.yml down
```

Adicione `-v` para apagar também os volumes (bancos SQLite, fotos e o certificado da demo).

## Demo de reconhecimento facial

`demo/index.html` é uma apresentação em slides (← → para navegar). No último slide, **Ligar câmera** desenha em tempo real os contornos do rosto (oval, sobrancelhas, olhos, íris, lábios) de até 10 pessoas, com a mesma animação dos cards do slide 3; a imagem da câmera não é exibida, só os pontos. ML Kit não roda no navegador; a página usa o equivalente web do Google, o MediaPipe Face Landmarker, e todo o processamento é local. O detector web é de curto alcance; com **modo grupo** ligado (padrão no computador), a página também procura rostos pequenos em recortes do quadro e rastreia cada um num recorte ampliado. O custo é de ~10 ms por rosto por quadro (RTX 5070: 1 rosto ≈ 30 FPS, 10 rostos ≈ 7 FPS de detecção; a animação continua fluida). O build da imagem baixa a biblioteca e o modelo, então a página não depende de internet depois de construída. Para subir só a demo:

```bash
docker compose -p boopdemo -f docker/demo.compose.yml up -d --build
```

A câmera exige contexto seguro: abra por `localhost` (ou HTTPS).

**Salvar frame** grava um PNG só com os pontos (sem a foto). No celular abre o menu de compartilhar ("Salvar imagem"); no computador, baixa o arquivo.

**GIF 5s** grava 5 segundos da animação (só os pontos, sem a foto), a 10 quadros/s e até 480 px, e salva um `.gif` (~100 KB com 1 rosto). O GIF é gerado no próprio navegador com o [gifenc](https://github.com/mattdesl/gifenc), que vai embutido na imagem Docker junto com o MediaPipe.

### Pelo celular

1. Celular e computador na mesma rede Wi-Fi.
2. Abra `https://<IP-do-computador>:31911` (o setup mostra o endereço no final). Quem abrir `http://<IP>:31910` é redirecionado para o HTTPS, porque fora de `localhost` o navegador bloqueia a câmera em HTTP.
3. O certificado é autoassinado: o navegador avisa uma vez; toque em "Avançado" → "Continuar".

No celular o slide "Ao vivo" ocupa a tela, tem **Trocar câmera** (frontal/traseira) e **Tela cheia** (não disponível no iPhone), e dá para deslizar o dedo para trocar de slide. O **modo grupo** começa desligado em telas de toque, porque pesa bastante; dá para ligar na hora. Se o Windows bloquear o acesso, libere as portas 31910–31911 (e 31802–31803, do POS) no firewall.
