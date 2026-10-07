# GerAta

App de iPhone que transforma a gravação de uma reunião em ata.

- A **transcrição** é feita no iPhone (Whisper, o mesmo motor do Estúdio).
- A **ata** é escrita pelo Claude, na sua nuvem (GT-SRV), usando o seu plano. Só o texto da transcrição sai do iPhone; o servidor não grava nada em disco.
- Cada reunião vira uma pasta em Arquivos › No Meu iPhone › GerAta › Reuniões, com `ata.md` e `transcricao.txt`.

## Como usar

1. **Ajustes:** entre na nuvem (mesmo usuário do Estúdio), ponha o seu nome e, se quiser, o glossário.
2. **Nova:** escolha o vídeo ou áudio da reunião (ou um `.srt`/`.txt` já transcrito).
   - Arquivo do OBS com duas trilhas: marque qual é o seu microfone (botão Ouvir para conferir). A escolha fica guardada.
   - Tipo de reunião: Automático (o Claude decide) ou um tipo fixo.
   - "Quem é quem": uma linha de contexto, opcional.
3. **Gerar ata.** Deixe o app aberto. Para 2 h com duas trilhas: cerca de 16 min de transcrição e 1 min de ata.
4. **Resultados:** abre a ata (Markdown) e a transcrição. No menu: copiar, compartilhar, gerar de novo (outro tipo, contexto ou modelo, sem retranscrever) e apagar.

## Estrutura

- `App/Motor/TranscritorLocal.swift`: transcrição (cópia do Estúdio).
- `App/Motor/Trilhas.swift`: lista as trilhas de áudio, separa uma trilha em `.wav` de 16 kHz, toca uma amostra.
- `App/Motor/Processo.swift`: o passo a passo de uma reunião.
- `App/Motor/Reunioes.swift`: as reuniões guardadas, os tipos e a montagem do texto ("[HH:MM:SS] Eu: ...").
- `App/Motor/Nuvem.swift`: login e pedido de ata (`/api/claude/ata`).
- `App/Telas/`: Nova, Resultados, Reunião (com o leitor de Markdown) e Ajustes.

## Servidor

Em `Transcreve/webapp`: o `app.py` ganhou `/api/claude/status`, `/api/claude/ata` e `/api/claude/ata/{id}`; o `Dockerfile` instala o Claude Code; o `.env.webapp` precisa de `CLAUDE_CODE_OAUTH_TOKEN` (gerado com `claude setup-token`). Os formatos de ata por tipo de reunião ficam no `app.py` (`_CLAUDE_TIPOS`): dá para ajustar sem recompilar o app.

## Build

GitHub Actions (`.github/workflows/build-ipa.yml`, runner `macos-26`), XcodeGen, IPA sem assinatura para o LiveContainer.

## Histórico

- **0.3.0:** reunião por link. Cartão na aba Nova para colar o link do Zoom ou do Google Meet; o gravador da nuvem entra na sala, grava e devolve a transcrição com o nome de quem falou (rotas `/api/reuniao*`, feitas em outra conversa: ver `random\Participante-Reuniao\ROTAS-para-o-GerAta.md`). O app acompanha a fase a cada 5 s, tem "Sair da conversa", guarda a transcrição em Resultados quando fica pronta (sem ata) e lista o que está na nuvem, com Refazer e Apagar. Ao gerar a ata dessas reuniões, você marca qual dos nomes é você. Servidor: o pedido ao Claude ganhou a variante para nomes reais (campo `nomes`).

- **0.2.1:** custo da ata e saldo do plano (janela de 5 h e semana, com a hora da virada) no cabeçalho da reunião; cartão "Plano do Claude" em Ajustes. Transcrição só refaz a passada em português se a maior parte da trilha saiu em outro idioma (antes bastava o primeiro trecho, o que dobrava o tempo). Filtro de créditos de legenda inventados ("Legenda Adriana Zanotto"). Tempo decorrido na tela. Resultados virou lista: deslizar para a esquerda apaga, para a direita copia a ata, segurar abre o menu. Ata e Transcrição em caixa com "Ver mais"; na transcrição dá para selecionar trechos. Servidor: `/api/claude/plano` e saída em `stream-json` para ler o `rate_limit_event`.

- **0.2.0:** app refeito. Saiu o modelo de linguagem local (testado até a 0.1.3: um modelo de 4B no iPhone não entende reunião longa e a reunião de 2 h não cabe num contexto só). Entraram a transcrição com duas trilhas, a ata pelo Claude, Resultados, Ajustes e o leitor de Markdown.
- **0.1.0 a 0.1.3:** tela de medição com modelo local (llama.cpp).

Medição que definiu o modelo (reunião de 2 h, 7/10/2026): Opus 65 s e cerca de 3 pontos da sessão de 5 h do plano Pro; Sonnet 28 s e cerca de 1,3 ponto, mas trocou quem disse o quê numa das duas rodadas; Haiku errou nas duas.
