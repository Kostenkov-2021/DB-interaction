@echo off
setlocal
set "ROOT=%~dp0.."
set "DOCKER_CONFIG=%ROOT%\.docker"
docker compose -f "%ROOT%\docker-compose.yml" %*
