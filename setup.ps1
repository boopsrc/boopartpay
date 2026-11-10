# Setup do ambiente de teste boopartpay (Windows / PowerShell 5.1+).
# Clona booprecognition e boopateway, configura e sobe tudo no Docker.
# Uso: .\setup.cmd   (ou: powershell -ExecutionPolicy Bypass -File setup.ps1)
# Arquivo mantido em ASCII: o PowerShell 5.1 le scripts sem BOM como ANSI.

$ErrorActionPreference = 'Continue'   # stderr de git/docker nao deve abortar o script
Set-StrictMode -Version 2.0

# ---------------------------------------------------------------- config de teste
$JwtSecret   = if ($env:BOOP_JWT_SECRET)          { $env:BOOP_JWT_SECRET }          else { 'boopartpay-test-jwt-secret-0123456789abcdefghij' }
$ClientId    = 'boop-admin'
$ClientSecret = if ($env:BOOP_CLIENT_ADMIN_SECRET) { $env:BOOP_CLIENT_ADMIN_SECRET } else { 'boopartpay-test-admin-secret' }
$AdminScope   = if ($env:BOOP_ADMIN_SCOPE)         { $env:BOOP_ADMIN_SCOPE }         else { 'identify persons:write persons:delete' }
$AdminPassword = if ($env:ADMIN_PASSWORD)          { $env:ADMIN_PASSWORD }           else { 'teste123' }
$RecognitionUrl = 'http://localhost:31900'
$WaitSeconds = 600

$Root      = Split-Path -Parent $MyInvocation.MyCommand.Path
$Workspace = Join-Path $Root 'workspace'
$Repos = [ordered]@{
    'booprecognition' = 'https://github.com/boopsrc/booprecognition.git'
    'boopateway'      = 'https://github.com/boopsrc/boopateway.git'
}
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Step($msg) { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "ERRO: $msg" -ForegroundColor Red; exit 1 }
function Run {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { Fail "falhou: $Exe $($Arguments -join ' ')" }
}
function Write-TextFile($path, $content) { [IO.File]::WriteAllText($path, $content, $Utf8NoBom) }

# ---------------------------------------------------------------- 1. pre-requisitos
Step 'Verificando pre-requisitos'
foreach ($cmd in 'git', 'docker') {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { Fail "'$cmd' nao encontrado no PATH" }
}
docker compose version | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "'docker compose' (v2) nao disponivel" }
docker info --format '{{.ServerVersion}}' | Out-Null
if ($LASTEXITCODE -ne 0) { Fail 'o Docker nao esta rodando (abra o Docker Desktop e tente de novo)' }

# ---------------------------------------------------------------- 2. clonar / atualizar
Step 'Clonando/atualizando repositorios'
New-Item -ItemType Directory -Force $Workspace | Out-Null
foreach ($name in $Repos.Keys) {
    $dir = Join-Path $Workspace $name
    if (Test-Path (Join-Path $dir '.git')) {
        Write-Host "$name ja existe, atualizando"
        Run git @('-C', $dir, 'checkout', '--', '.')   # desfaz o patch do config.yaml antes do pull
        Run git @('-C', $dir, 'pull', '--ff-only')
    } else {
        Run git @('clone', $Repos[$name], $dir)
    }
}
$RecDir  = Join-Path $Workspace 'booprecognition'
$GateDir = Join-Path $Workspace 'boopateway'

# ---------------------------------------------------------------- 3. config.yaml -> sqlite
Step 'Configurando booprecognition para SQLite'
$cfgPath = Join-Path $RecDir 'config.yaml'
$cfg = [IO.File]::ReadAllText($cfgPath)
$cfg = [regex]::Replace($cfg, '(?m)^target:[^\r\n]*', 'target: sqlite')
Write-TextFile $cfgPath $cfg

# ---------------------------------------------------------------- 4. .env do booprecognition
$recEnv = "BOOP_JWT_SECRET=$JwtSecret`nBOOP_CLIENT_ADMIN_SECRET=$ClientSecret`n"
Write-TextFile (Join-Path $RecDir '.env') $recEnv

# ---------------------------------------------------------------- 5. subir booprecognition + demo
#    a demo nao depende de nada: sobe ja, junto, e fica no ar mesmo se o resto falhar
Step 'Subindo booprecognition (o primeiro build baixa os modelos e demora)'
Run docker @('compose', '-p', 'booprecognition', '-f', (Join-Path $Root 'docker\booprecognition.compose.yml'), 'up', '-d', '--build')
Step 'Subindo demo de reconhecimento facial'
Run docker @('compose', '-p', 'boopdemo', '-f', (Join-Path $Root 'docker\demo.compose.yml'), 'up', '-d', '--build')

# ---------------------------------------------------------------- 6. aguardar e pegar token
Step "Aguardando booprecognition em $RecognitionUrl e emitindo token"
$basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${ClientId}:${ClientSecret}"))
$token = $null
$deadline = (Get-Date).AddSeconds($WaitSeconds)
while ((Get-Date) -lt $deadline) {
    try {
        $resp = Invoke-RestMethod -Method Post -Uri "$RecognitionUrl/oauth/token" `
            -Headers @{ Authorization = "Basic $basic" } `
            -Body @{ grant_type = 'client_credentials' } -TimeoutSec 10
        if ($resp.access_token) { $token = $resp.access_token; break }
    } catch { }
    Write-Host '.' -NoNewline
    Start-Sleep -Seconds 5
}
Write-Host ''
if (-not $token) {
    docker logs booprecognition --tail 50
    Fail "booprecognition nao respondeu em $WaitSeconds s"
}
Write-Host 'Token obtido.'

# ---------------------------------------------------------------- 7. .env do boopateway
#    BOOP_TOKEN: token fixo usado pela API; ADMIN_PASSWORD: login do portal;
#    BOOP_CLIENT_*: a cada login do portal a API gera um token novo via OAuth.
$gateEnv = @(
    "BOOP_TOKEN=$token"
    "ADMIN_PASSWORD=$AdminPassword"
    "ADMIN_BOOP_TOKEN="
    "BOOP_CLIENT_ID=$ClientId"
    "BOOP_CLIENT_SECRET=$ClientSecret"
    "BOOP_ADMIN_SCOPE=`"$AdminScope`""
) -join "`n"
Write-TextFile (Join-Path $GateDir '.env') "$gateEnv`n"

# ---------------------------------------------------------------- 8. subir boopateway
Step 'Subindo boopateway (API + portal)'
Push-Location $GateDir
try { Run docker @('compose', 'up', '-d', '--build') } finally { Pop-Location }

# ---------------------------------------------------------------- 9. resumo
Step 'Ambiente pronto'
$LanIp = $null
try {
    # IP da rede local: o adaptador com gateway padrao (ignora VirtualBox, WSL, Hyper-V, Docker)
    $LanIp = Get-NetIPConfiguration -ErrorAction Stop |
        Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
        ForEach-Object { $_.IPv4Address.IPAddress } | Select-Object -First 1
} catch { }
if (-not $LanIp) { $LanIp = '<IP-do-computador>' }
Write-Host 'demo (reconhecimento):     http://localhost:31910'
Write-Host "demo no celular (HTTPS):   https://${LanIp}:31911  (certificado autoassinado: aceite o aviso)"
Write-Host "booprecognition (Swagger): $RecognitionUrl/docs"
Write-Host 'boopateway API:            http://localhost:31800'
Write-Host 'boopateway portal:         http://localhost:31801'
Write-Host "senha do portal:           $AdminPassword"
Write-Host "client_id / secret:        $ClientId / $ClientSecret"
Write-Host "scopes do portal:          $AdminScope"
Write-Host "BOOP_TOKEN:                $token"
