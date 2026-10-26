$txtPath = Join-Path $PSScriptRoot "usuario.txt"
$logPath = Join-Path $PSScriptRoot "log_execucao_filial.txt"

Set-Content -Path $logPath -Value "==================================================" -Encoding utf8
Add-Content -Path $logPath -Value "Inicio da Execucao (Filial): $(Get-Date)" -Encoding utf8
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

# --- MAPEAMENTO DE SIGLAS DAS FILIAIS PARA A OU DO AD ---
$filialRef = if ($local) { $local } else { $cidade }
switch -Wildcard ($filialRef.ToUpper()) {
    "*BAU*"     { $siglaFilial = "BAU" }
    "*BAURU*"   { $siglaFilial = "BAU" }
    "*BC*"      { $siglaFilial = "BC" }
    "*CAMBORI*" { $siglaFilial = "BC" }
    "*BH*"      { $siglaFilial = "BH" }
    "*HORIZONTE*" { $siglaFilial = "BH" }
    "*RJ*"      { $siglaFilial = "RJ" }
    "*JANEIRO*" { $siglaFilial = "RJ" }
    default     { $siglaFilial = "BAU" }
}

# Tratamento padronizado para nomes de Departamento
switch -Wildcard ($departamento.ToUpper()) {
    "*TI*"        { $deptOU = "TI" }
    "*CRC*"       { $deptOU = "CRC" }
    "*OPERA*"     { $deptOU = "Operacao" }
    "*FINAN*"     { $deptOU = "Financas" }
    default       { $deptOU = $departamento }
}

$pathOU = "OU=" + $deptOU + ",OU=" + $siglaFilial + ",DC=suaempresa,DC=local"

$senha = ConvertTo-SecureString "SenhaPadrao@123" -AsPlainText -Force

# Configurações de Rede da Filial (Substituir pelos seus IPs em Produção)
$jumperIP     = "[IP_SERVIDOR_JUMPER]"  # Exemplo: 10.0.0.50
$targetIP     = "[IP_DC_FILIAL]"        # Exemplo: 10.1.0.10
$domainSuffix = "[SEU_DOMINIO.LOCAL]"

# --- GESTÃO DE CREDENCIAIS SEPARADAS VIA DPAPI ---
$credJumperPath = Join-Path $PSScriptRoot "cred_jumper.xml"
if (Test-Path $credJumperPath) {
    $credJumper = Import-Clixml -Path $credJumperPath
} else {
    Write-Host ">>> Insira as credenciais de acesso ao JUMPER (ex: Bot):" -ForegroundColor Yellow
    $credJumper = Get-Credential
    $credJumper | Export-Clixml -Path $credJumperPath
}

$credFilialPath = Join-Path $PSScriptRoot "cred_filial.xml"
if (Test-Path $credFilialPath) {
    $credFilial = Import-Clixml -Path $credFilialPath
} else {
    Write-Host ">>> Insira as credenciais de Administrador do AD da FILIAL:" -ForegroundColor Yellow
    $credFilial = Get-Credential
    $credFilial | Export-Clixml -Path $credFilialPath
}

Write-Host "A ligar ao Jumper ($jumperIP) com CredSSP para saltar para a Filial ($targetIP)..." -ForegroundColor Cyan

# Primeiro Salto (Double-Hop): Cliente -> Jumper
$resultadoLog = Invoke-Command -ComputerName $jumperIP -Credential $credJumper -Authentication Credssp -ScriptBlock {
    param($targetIP, $nomeCompleto, $departamento, $cargo, $pathOU, $domainSuffix, $senhaRemota, $credFilialRemoto)

    # Segundo Salto: Jumper -> DC da Filial
    $resultadoFilial = Invoke-Command -ComputerName $targetIP -Credential $credFilialRemoto -ScriptBlock {
        param($nomeCompleto, $departamento, $cargo, $pathOU, $domainSuffix, $senhaRemota)

        $partes = $nomeCompleto.Trim().Split(" ")
        $primeiroNome = $partes[0].ToLower() -replace "[^a-z]", ""

        $sobrenomeCompleto = ""
        if ($partes.Length -gt 1) {
            $sobrenomeCompleto = ($partes[1..($partes.Length-1)] -join "").ToLower() -replace "[^a-z]", ""
        }

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

        # Geração de e-mail corporativo padrão
        $primeiroNomeLimpo = $partes[0].ToLower() -replace "[^a-z]", ""
        $sobrenomeLimpo = if ($partes.Length -gt 1) { $partes[-1].ToLower() -replace "[^a-z]", "" } else { "" }
        $emailCorporativo = "$primeiroNomeLimpo.$sobrenomeLimpo@empresa.com.br"

        $existe = Get-ADUser -Filter ("SamAccountName -eq '" + $samAccountName + "'") -ErrorAction SilentlyContinue

        if (-not $existe) {
            try {
                New-ADUser -Name $nomeCompleto `
                           -GivenName $partes[0] `
                           -Surname $sobrenomeReal `
                           -SamAccountName $samAccountName `
                           -UserPrincipalName $upn `
                           -EmailAddress $emailCorporativo `
                           -Title $cargo `
                           -Department $departamento `
                           -Path $pathOU `
                           -AccountPassword $senhaRemota `
                           -Enabled $true `
                           -ChangePasswordAtLogon $false

                return "[SUCESSO] Utilizador '$nomeCompleto' criado com login '$samAccountName' e e-mail '$emailCorporativo' na OU '$pathOU'."
            } catch {
                return "[ERRO] Falha ao criar o utilizador '$nomeCompleto': $_"
            }
        } else {
            return "[AVISO] O utilizador '$samAccountName' ($nomeCompleto) ja existe na Filial. Ignorado."
        }
    } -ArgumentList $nomeCompleto, $departamento, $cargo, $pathOU, $domainSuffix, $senhaRemota

    return $resultadoFilial

} -ArgumentList $targetIP, $nomeCompleto, $departamento, $cargo, $pathOU, $domainSuffix, $senha, $credFilial

Write-Host $resultadoLog -ForegroundColor Green
Add-Content -Path $logPath -Value $resultadoLog -Encoding utf8

Add-Content -Path $logPath -Value "==================================================" -Encoding utf8
Add-Content -Path $logPath -Value "Fim da Execucao (Filial): $(Get-Date)" -Encoding utf8
Add-Content -Path $logPath -Value "==================================================" -Encoding utf8

Remove-Item -Path $txtPath -Force -ErrorAction SilentlyContinue
Write-Host "Processo da Filial concluido. Verifique o ficheiro 'log_execucao_filial.txt'." -ForegroundColor Magenta