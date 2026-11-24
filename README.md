# Server Monitor

Dashboard web **100% local** (sem nuvem, sem Node.js e sem Python) para monitorar servidores Windows em tempo real pela rede local ou VPN.

## Recursos

- **Status Online / Offline automático**: alerta visual caso o servidor fique mais de 20 segundos sem responder.
- **CPU e Memória RAM**: leitura nativa via `kernel32.dll`, medidores radiais e gráficos históricos.
- **Armazenamento**: todos os discos fixos (`C:`, `D:`, etc.) com espaço livre/usado e alertas visuais.
- **Rede**: Download (RX) e Upload (TX) em tempo real, tráfego acumulado e adaptadores ativos.
- **Monitoramento de Backup**: histórico via `POST /api/backup` (persistido em disco), autodescoberta do **FreeFileSync / OneDrive** e alertas de atraso (> 24h / > 48h).
- **Pastas Compartilhadas (SMB)**: caminho local, acessos ativos, filtro de pastas `$` e cópia rápida do caminho UNC.
- **Usuários & Sessões**: contas locais, sessões interativas/RDP e conexões SMB ativas.
- **Serviços & Processos**: status de serviços Windows, ping no gateway e Top 6 processos por RAM.
- **PWA e Modo Demo**: instalável na tela inicial do celular, tema claro/escuro e modo de demonstração integrado.

## Instalação rápida

1. Copie a pasta do projeto para um diretório fixo no servidor (ex.: `C:\ServerMonitor`).
2. Dê dois cliques em **`Gerenciador.bat`**, aceite o pedido de Administrador e escolha **`[1] Iniciar dashboard`**.
3. Acesse de qualquer PC ou celular da rede por **`http://<nome-do-servidor>`** ou **`http://<ip-do-servidor>`**.

> O instalador escolhe automaticamente a porta `80` (ou `3000` se a `80` estiver ocupada), libera o firewall para a rede local e cria duas tarefas em segundo plano (`ServerMonitorDashboard` e `ServerMonitorAgente`) que iniciam com o Windows.

## Estrutura do projeto

```text
Monitor-Servidor/
├── agent/              # Agente PowerShell/C# de coleta e configuração (config.json)
├── public/             # Interface web estática (HTML, CSS, JS e PWA)
├── scripts/            # Instalador (instalar.ps1) e desinstalador (desinstalar.ps1)
├── server/             # Servidor HTTP C# embarcado em PowerShell (local-server.ps1)
├── Gerenciador.bat     # Painel interativo (Iniciar / Reiniciar / Encerrar / Status)
├── DOCUMENTACAO.md     # Documentação técnica (arquitetura, configuração e API)
└── README.md
```

## Operação e desinstalação

- **Iniciar, reiniciar ou encerrar**: execute **`Gerenciador.bat`** no servidor.
- **Desinstalar serviços e firewall**: execute no PowerShell como Administrador:
  ```powershell
  powershell -ExecutionPolicy Bypass -File "C:\ServerMonitor\scripts\desinstalar.ps1"
  ```

## Documentação

Para detalhes de arquitetura, configuração de `agent/config.json`, endpoints da API (`/api/metrics`, `/api/backup`, `/api/health`) e solução de problemas, consulte [DOCUMENTACAO.md](DOCUMENTACAO.md).
