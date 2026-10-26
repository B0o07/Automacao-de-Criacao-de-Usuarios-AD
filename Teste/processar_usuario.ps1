$txtPath = Join-Path $PSScriptRoot "usuario.txt"
$logPath = Join-Path $PSScriptRoot "log_execucao.txt"

Set-Content -Path $logPath -Value "==================================================" -Encoding utf8
Add-Content -Path $logPath -Value "Inicio da Execucao: $(Get-Date)" -Encoding utf8
Add-Content -Path $logPath -Value "==================================================" -Encoding utf8

if (-not (Test-Path $txtPath)) {
    $msgErro = "[ERRO] O ficheiro 'usuario.txt' nao foi encontrado!"
    Write-Host $msgErro -ForegroundColor Red
    Add-Content -Path $logPath -Value $msgErro -Encoding utf8
    exit
}

$linhas = Get-Content -Path $txtPath -Encoding utf8
$dados = @{}

for ($i = 0; $i -lt $linhas.Count; $i++) {
    $linhaAtual = $linhas[$i]
    if ($linhaAtual -match "^\s*([^:]+)\s*:\s*(.+)\s*$") {
        $chave = $Matches[1].Trim()
        $valor = $Matches[2].Trim()
        $dados[$chave] = $valor
    }
}

$nomeCompleto = $dados["Nome"]
$departamento = $dados["Departamento"]
$local        = $dados["Local"]
$cargo        = $dados["Cargo"]
$cidade       = $dados["Cidade"]

if (-not $nomeCompleto -or -not $departamento -or -not $local) {
    $msgErro = "[ERRO] Faltam campos obrigatorios no ficheiro (Nome, Departamento, Local)."
    Write-Host $msgErro -ForegroundColor Red
    Add-Content -Path $logPath -Value $msgErro -Encoding utf8
    exit
}

$senha = ConvertTo-SecureString "SenhaPadrao@123" -AsPlainText -Force

if ($local -eq "Matriz") {
    $targetIP     = "[IP_DC_MATRIZ]"        # Exemplo: 192.168.10.10
    $domainSuffix = "[SEU_DOMINIO.LOCAL]"   # Exemplo: empresa.local
    $pathOU       = "OU=" + $departamento + ",DC=suaempresa,DC=local"
} else {
    $targetIP     = "[IP_DC_FILIAL]"        # Exemplo: 192.168.20.10
    $domainSuffix = "[SEU_DOMINIO_FILIAL.LOCAL]"
    if ($cidade) {
        $pathOU = "OU=" + $departamento + ",OU=" + $cidade + ",DC=suaempresa,DC=local"
    } else {
        $pathOU = "OU=" + $departamento + ",DC=suaempresa,DC=local"
    }
}

$credPath = Join-Path $PSScriptRoot "cred.xml"

if (Test-Path $credPath) {
    $cred = Import-Clixml -Path $credPath
} else {
    Write-Host "Primeira execucao: Por favor, insira as credenciais de administrador uma unica vez." -ForegroundColor Yellow
    $cred = Get-Credential
    $cred | Export-Clixml -Path $credPath
}

Write-Host "A estabelecer ligacao remota com o destino $local ($targetIP)..." -ForegroundColor Cyan

$resultadoLog = Invoke-Command -ComputerName $targetIP -Credential $cred -Authentication Basic -ScriptBlock {
    param($nomeCompleto, $departamento, $cargo, $pathOU, $domainSuffix, $senhaRemota)

    $partes = $nomeCompleto.Trim().Split(" ")
    $primeiroNome = $partes[0].ToLower() -replace "[^a-z]", ""

    $sobrenomeCompleto = ""
    if ($partes.Length -gt 1) {
        $sobrenomeCompleto = ($partes[1..($partes.Length-1)] -join "").ToLower() -replace "[^a-z]", ""
    }

    # Lista defensiva para evitar geracao acidental de logins ofensivos
    $palavrasProibidas = @("anal", "anus", "anau", "cucab", "jacintop", "merda", "bosta", "puta", "caralho", "porra", "cu", "cacete", "pinto", "sex", "bicha", "boiola", "kct", "krl")
    $letras = $sobrenomeCompleto.ToCharArray()
    $idx = 0
    $samAccountName = ""
    $encontrouSeguro = $false

    while (-not $encontrouSeguro) {
        if ($idx -lt $letras.Length) {
            $candidato = $primeiroNome + $letras[$idx]
        } else {
            $candidato = $primeiroNome + ($idx - $letras.Length + 1)
        }

        $ofensivo = $false
        for ($j = 0; $j -lt $palavrasProibidas.Count; $j++) {
            $palavraProibida = $palavrasProibidas[$j]
            if ($candidato.ToLower() -like ("*" + $palavraProibida + "*")) {
                $ofensivo = $true
                break
            }
        }

        if (-not $ofensivo) {
            $encontrouSeguro = $true
            $samAccountName = $candidato
        } else {
            $idx++
        }
    }

    $upn = $samAccountName + "@" + $domainSuffix
    $sobrenomeReal = ""
    if ($partes.Length -gt 1) {
        $sobrenomeReal = $partes[-1]
    }

    $existe = Get-ADUser -Filter ("SamAccountName -eq '" + $samAccountName + "'") -ErrorAction SilentlyContinue

    if (-not $existe) {
        try {
            New-ADUser -Name $nomeCompleto `
                       -GivenName $partes[0] `
                       -Surname $sobrenomeReal `
                       -SamAccountName $samAccountName `
                       -UserPrincipalName $upn `
                       -Title $cargo `
                       -Department $departamento `
                       -Path $pathOU `
                       -AccountPassword $senhaRemota `
                       -Enabled $true `
                       -ChangePasswordAtLogon $false

            return "[SUCESSO] Utilizador '$nomeCompleto' criado com o login seguro '$samAccountName' na OU '$pathOU'."
        } catch {
            return "[ERRO] Falha ao criar o utilizador '$nomeCompleto': $_"
        }
    } else {
        return "[AVISO] O utilizador '$samAccountName' ($nomeCompleto) ja existe. Ignorado."
    }
} -ArgumentList $nomeCompleto, $departamento, $cargo, $pathOU, $domainSuffix, $senha

Write-Host $resultadoLog -ForegroundColor Green
Add-Content -Path $logPath -Value $resultadoLog -Encoding utf8

Add-Content -Path $logPath -Value "==================================================" -Encoding utf8
Add-Content -Path $logPath -Value "Fim da Execucao: $(Get-Date)" -Encoding utf8
Add-Content -Path $logPath -Value "==================================================" -Encoding utf8

Write-Host "Processo concluido. Verifique o ficheiro 'log_execucao.txt' para detalhes." -ForegroundColor Magenta