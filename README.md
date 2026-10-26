# Automação de Provisionamento no Active Directory via Outlook MAPI & WinRM

Sistema de automação em **PowerShell** e **Batch** projetado para ler solicitações de novos colaboradores recebidas via **Microsoft Outlook Desktop (MAPI)**, extrair e validar dados cadastrais, e realizar o provisionamento automatizado de usuários no **Active Directory (AD)** para ambientes de **Matriz** e **Filiais Remotas**.

---

## Arquitetura do Sistema

O projeto é estruturado de forma desacoplada em duas camadas principais:

1. **Orquestrador de E-mail (`processar_email.ps1`):**
   * Conecta-se à API COM do Outlook em tempo de execução.
   * Filtra e-mails de solicitação com a sintaxe `Novo Utilizador`.
   * Identifica o destino (**Matriz vs. Filial**) com base em *Regex* e geolocalização.
   * Gera o arquivo padronizado de carga (`usuario.txt`).

2. **Módulos de Execução AD (`processar_usuario.ps1` & `processar_filial.ps1`):**
   * **Matriz (Conexão Direta):** Executa comandos `WinRM` / `PSRemoting` de salto único diretamente no Domain Controller principal.
   * **Filiais (Duplo Salto / CredSSP):** Trafega com autenticação delegada de **duplo salto (Double-Hop)** passando por um servidor **Jumper** até o controlador de domínio da filial.

              ┌──────────────────────────────┐
              │   Outlook Desktop (MAPI)     │
              └──────────────┬───────────────┘
                             │
               [processar_email.ps1]
                             │
             ┌───────────────┴───────────────┐
             ▼                               ▼
   ┌──────────────────┐            ┌──────────────────┐
   │   Pasta /Teste   │            │  Pasta /FTeste   │
   │    (Matriz)      │            │    (Filiais)     │
   └────────┬─────────┘            └────────┬─────────┘
            │                               │
    WinRM (1 Salto)                 CredSSP (Double-Hop)
            │                               │
            ▼                               ▼
┌──────────────────────┐        ┌──────────────────────┐
│  DC Matriz (Primary) │        │   Servidor Jumper    │
└──────────────────────┘        └──────────┬───────────┘
                                           │
                                           ▼
                                ┌──────────────────────┐
                                │      DC Filial       │
                                └──────────────────────┘

---

## Destaques de Segurança e Funcionalidades

* **Higienização de Logins (Filtro Anti-Ofensivo):** Algoritmo nativo em PowerShell que sanitiza entradas, gera combinações dinâmicas de `SamAccountName` e valida o candidato contra uma lista de termos impróprios antes da criação.
* **Criptografia DPAPI:** Proteção de credenciais de acesso remotos utilizando `Export-Clixml` / `Import-Clixml`, vinculando as chaves ao contexto do usuário local e impedindo vazamento de senhas em texto plano.
* **Mapeamento Dinâmico de OUs:** Identificação automática da Unidade Organizacional (OU) de destino com base nas siglas de departamento e cidade.
* **Auditoria Local:** Geração automática de logs estruturados de execução (`log_execucao.txt` e `log_execucao_filial.txt`).

---

## Estrutura do Repositório

```text
automacao-ad-outlook/
├── README.md                    <-- Documentação do Projeto
├── .gitignore                   <-- Bloqueio de arquivos sensíveis
├── rodar_automacao.bat          <-- Disparador principal (Task Scheduler)
├── processar_email.ps1          <-- Leitor MAPI e direcionador de fluxo
├── Teste/
│   ├── rodar_matriz.bat         <-- Disparador local da Matriz
│   └── processar_usuario.ps1    <-- Script de criação no AD da Matriz
└── FTeste/
    ├── rodar_filial.bat         <-- Disparador local das Filiais
    └── processar_filial.ps1     <-- Script de criação no AD via CredSSP

 Configuração e Pré-requisitos
1. Pré-requisitos de Ambiente
Windows Server ou Windows 10/11 Pro.

Microsoft Outlook Desktop instalado e perfil MAPI ativo.

Módulo ActiveDirectory habilitado via RSAT.

2. Habilitação de Remoting (Servidores e Jumper)
Nos servidores remotos e Jumper, execute no PowerShell como Administrador:

PowerShell
Enable-PSRemoting -Force
Enable-WSManCredSSP -Role Server -Force
3. Habilitação do CredSSP no Cliente (Orquestrador)
PowerShell
Enable-WSManCredSSP -Role Client -DelegateComputer "[IP_OU_HOST_DO_JUMPER]" -Force

 Próximos Passos (Roadmap)
[ ] Substituição do gatilho MAPI do Outlook por chamadas à API REST do GLPI.

[ ] Implementação de Webhooks para inicialização orientada a eventos (Event-Driven).

[ ] Integração com Cofre de Senhas Corporativo (PAM / Vault).