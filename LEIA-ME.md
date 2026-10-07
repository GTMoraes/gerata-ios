# GerAta

App de iPhone que transforma a gravação de uma reunião em ata, com o modelo de linguagem rodando no
próprio aparelho. Projeto separado do Estúdio; reaproveita o tema e o molde de build dele.

SwiftUI · iOS 26 · compila sem Mac, pelo GitHub Actions · instalado pelo LiveContainer.

## Estado: etapa 1 (fundação e medição) — versão 0.1.0

Ainda não gera ata de verdade. Esta versão existe para responder, com medida real, qual é o melhor
modelo que o iPhone aguenta:

- baixa modelos `.gguf` direto do Hugging Face (três candidatos na lista, e um campo para colar o
  endereço de qualquer outro);
- lê uma transcrição (`.txt`, `.srt`, texto colado ou o exemplo embutido) e pede um resumo simples;
- mostra o tempo de abrir o modelo, de ler o texto e de escrever a resposta, e a memória usada;
- se o iOS encerrar o app por falta de memória, avisa na próxima abertura o que estava rodando;
- "Copiar relatório" junta as medições em texto, para colar na conversa.

## Plano

1. **Fundação e medição** (esta versão).
2. Da gravação à transcrição: seletor de arquivos (inclusive vídeo grande do OBS, lido sem copiar),
   gravação presencial, duas trilhas rotuladas ("Eu" e "Participantes"), glossário.
3. A ata local: moldes por tipo de reunião (pitch, lançamento, estratégia, cliente, equipe, geral),
   tipo sugerido pelo modelo e confirmado pelo usuário, geração seção por seção, um arquivo só com
   topo geral e blocos por assunto.
4. "Gerar com Claude": pelo Claude Code no GT-SRV (plano Pro), só quando o usuário pedir.
5. Depois, se fizer falta: separar participantes em gravação presencial, modelo maior na nuvem,
   busca entre atas.

## Como compila

- `scripts/baixar-llama.sh` baixa o `llama.xcframework` oficial das Releases do llama.cpp (versão
  fixada no script) para `vendor-llm/`, com cache no Actions. Se a versão fixada sumir, usa a mais
  nova e confere se as funções que a ponte usa existem.
- `project.yml` (XcodeGen) liga e embute o framework.
- `.github/workflows/build-ipa.yml` gera o `GerAta.ipa` e publica em Releases.

## Estrutura

```
project.yml
scripts/baixar-llama.sh
App/GerAtaApp.swift
App/Motor/MotorLLM.h, MotorLLM.c    ponte em C para o llama.cpp (abrir, gerar, fechar)
App/Motor/MotorLLM.swift            o motor visto pelo Swift (fila própria, texto aos poucos)
App/Motor/Modelos.swift             catálogo e download do Hugging Face (retoma de onde parou)
App/Motor/Medidor.swift             memória do app
App/Motor/Transcricao.swift         leitura de .txt/.srt e o texto de exemplo
App/Telas/TesteView.swift           a tela da etapa 1
App/Telas/Tema.swift                tema e confirmações (vindos do Estúdio)
```

## Notas técnicas

- A ponte em C cria um contexto novo a cada geração (não reaproveita o anterior): mais simples e
  evita depender de funções do llama.cpp que mudam de nome entre versões.
- O pedido é montado no formato de conversa do próprio modelo (`llama_chat_apply_template`); se o
  formato não for reconhecido, cai em ChatML.
- Texto que não cabe no contexto é cortado no fim e a medição marca "TEXTO CORTADO". Na etapa 3 a
  reunião longa será resumida em blocos de tempo e consolidada.
- Ícone próprio desde a 0.1.1 (uma ata com itens marcados), desenhado por `icone.py` fora do repositório.
- Dentro do LiveContainer o limite de memória é o do próprio LiveContainer, não o de um app
  instalado direto. É uma das coisas que esta etapa mede.

## 0.1.2

O teste com a reunião de 2 h na 0.1.0 mostrou o modelo copiando a transcrição e entrando em repetição. Causa: o texto não cabia no contexto, era cortado no fim e a instrução ficava lá no começo. Mudou:

- A instrução vai **depois** da transcrição; quando não cabe, corta-se a transcrição (a medição diz quanto coube), nunca a instrução.
- Penalidade de repetição leve (1,1) e detector de repetição, que para sozinho.
- **Transcrição enxuta** (ligada por padrão): tira falas que o Whisper inventa no silêncio (outro alfabeto, créditos de legenda), tira repetidas em seguida e deixa um horário por minuto.
- Dois modos: **Tudo de uma vez** e **Por blocos** (anota trecho a trecho, depois escreve a ata das anotações).
- Contexto de 24 mil, **contexto comprimido** (8 bits, metade da memória), opção de usar só os núcleos fortes, resposta de até 2500.
- Antes de rodar, o app faz a conta de memória e pergunta se não fechar ("Rodar mesmo assim").
- Barra fixa embaixo com o andamento, a memória ao vivo e o botão **Parar**.
- Medição mostra a menor folga de memória vista. O arquivo do modelo não entra em "em uso" (o iOS o conta à parte); ele aparece como queda nos livres.
- Aviso de app encerrado não culpa mais a memória sem evidência.
- Ícone novo (era da 0.1.1).

Arquivos: `project.yml`, `LEIA-ME.md`, `App/Motor/MotorLLM.h`, `MotorLLM.c`, `MotorLLM.swift`, `Transcricao.swift`, `App/Telas/TesteView.swift`, `App/Assets.xcassets/AppIcon.appiconset/icone.png`.
