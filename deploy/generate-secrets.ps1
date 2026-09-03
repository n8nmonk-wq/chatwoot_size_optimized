# Powershell script to generate Chatwoot secrets
$secretKeyBase = -join ((1..64) | ForEach-Object { '{0:x}' -f (Get-Random -Max 16) })
$encPrimary = -join ((1..32) | ForEach-Object { '{0:x}' -f (Get-Random -Max 16) })
$encDeterministic = -join ((1..32) | ForEach-Object { '{0:x}' -f (Get-Random -Max 16) })
$encSalt = -join ((1..32) | ForEach-Object { '{0:x}' -f (Get-Random -Max 16) })
$postgresPass = -join ((1..24) | ForEach-Object { [char](Get-Random -Min 97 -Max 122) })
$redisPass = -join ((1..24) | ForEach-Object { [char](Get-Random -Min 97 -Max 122) })

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "  GENERATED CHATWOOT PRODUCTION SECRETS" -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "SECRET_KEY_BASE=$secretKeyBase"
Write-Host "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$encPrimary"
Write-Host "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$encDeterministic"
Write-Host "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$encSalt"
Write-Host "POSTGRES_PASSWORD=$postgresPass"
Write-Host "REDIS_PASSWORD=$redisPass"
Write-Host "=================================================" -ForegroundColor Cyan
