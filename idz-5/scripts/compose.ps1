param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $ComposeArgs
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$env:DOCKER_CONFIG = Join-Path $Root ".docker"

docker compose -f (Join-Path $Root "docker-compose.yml") @ComposeArgs
