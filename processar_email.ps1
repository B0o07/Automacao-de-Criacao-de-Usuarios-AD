# Ligar ao Outlook Desktop via COM
$outlook = New-Object -ComObject Outlook.Application
$namespace = $outlook.GetNamespace("MAPI")
$inbox = $namespace.GetDefaultFolder(6) # Caixa de Entrada

# Procurar e-mails com "Novo Utilizador" no assunto
$mensagens = $inbox.Items | Where-Object { $_.Subject -like "*Novo Utilizador*" }

if (-not $mensagens) {
    Write-Host "Nenhum e-mail novo encontrado. A fechar ciclo..." -ForegroundColor Yellow
    exit
}

foreach ($msg in $mensagens) {
    Write-Host "A processar e-mail de: $($msg.SenderName) - Assunto: $($msg.Subject)" -ForegroundColor Cyan
    $corpo = $msg.Body

    # Expressao regular cobrindo as palavras-chave para identificar Filiais
    $patternFilial = "BAU|Bauru|BC|Balneario|BH|Belo Horizonte|RJ|Rio de Janeiro|Filial"

    if ($corpo -match $patternFilial) {
        Write-Host ">>> Destino detetado: FILIAL. A gravar usuario.txt na pasta FTeste..." -ForegroundColor Yellow
        
        $pastaFilial = Join-Path $PSScriptRoot "FTeste"
        if (-not (Test-Path $pastaFilial)) { New-Item -Path $pastaFilial -ItemType Directory | Out-Null }

        $txtPath = Join-Path $pastaFilial "usuario.txt"
        $corpo | Out-File -FilePath $txtPath -Encoding UTF8

        $batPath = Join-Path $pastaFilial "rodar_filial.bat"
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$batPath`"" -Wait

    } else {
        Write-Host ">>> Destino detetado: MATRIZ. A gravar usuario.txt na pasta Teste..." -ForegroundColor Yellow
        
        $pastaMatriz = Join-Path $PSScriptRoot "Teste"
        if (-not (Test-Path $pastaMatriz)) { New-Item -Path $pastaMatriz -ItemType Directory | Out-Null }

        $txtPath = Join-Path $pastaMatriz "usuario.txt"
        $corpo | Out-File -FilePath $txtPath -Encoding UTF8

        $batPath = Join-Path $pastaMatriz "rodar_matriz.bat"
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$batPath`"" -Wait
    }

    # Marcar e-mail como lido
    $msg.UnRead = $false
    $msg.Save()
    Write-Host "E-mail processado com sucesso e marcado como lido.`n" -ForegroundColor Green
}