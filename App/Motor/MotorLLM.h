#ifndef GERATA_MOTOR_LLM_H
#define GERATA_MOTOR_LLM_H

#include <stdint.h>

// Ponte para o llama.cpp embutido (vendor-llm/llama.xcframework, baixado por scripts/baixar-llama.sh).
// Um modelo aberto por vez. Cada geração começa de um contexto limpo.

typedef struct GerLLM GerLLM;

typedef struct {
    int tokensEntrada;          // tokens do pedido (depois do corte, se houve)
    int tokensSaida;            // tokens gerados
    int cortado;                // 1 = o pedido não coube no contexto e foi cortado no fim (não deveria acontecer: o app ajusta antes)
    int contexto;               // tamanho do contexto usado
    double segCarregar;         // abrir o modelo (só na primeira geração depois de abrir)
    double segEntrada;          // ler o pedido
    double segSaida;            // escrever a resposta
} GerLLMEstat;

/// Pedaço de texto gerado (bytes UTF-8, pode cortar um caractere no meio). Devolver 0 interrompe.
typedef int (*GerLLMPedaco)(const char *bytes, int n, void *usuario);
/// Andamento da leitura do pedido, de 0 a 1. Devolver 0 interrompe.
typedef int (*GerLLMAndamento)(double fracao, void *usuario);

/// Versão/descrição do motor (para a tela de teste).
const char *ger_llm_motor(void);

/// Abre o arquivo .gguf. camadasGPU: -1 = todas na GPU, 0 = só processador. NULL se falhar.
GerLLM *ger_llm_abrir(const char *caminho, int camadasGPU, char *erro, int tamErro);

/// Nome/descrição e tamanho do contexto com que o modelo foi treinado.
void ger_llm_info(GerLLM *m, char *descricao, int tam, int *contextoTreino, uint64_t *bytes);

typedef struct {
    int contexto;               // tamanho do contexto
    int maxSaida;               // máximo de tokens da resposta
    float temperatura;          // <= 0.01 = sempre a palavra mais provável
    float penalidade;           // penalidade de repetição (1.0 = desligada; 1.1 = leve)
    int kvComprimido;           // 1 = guarda o contexto em 8 bits (metade da memória, perda mínima)
    int threads;                // 0 = padrão do motor
} GerLLMOpcoes;

/// Quantos tokens o texto ocupa neste modelo (sem os marcadores de conversa). <0 = erro.
int ger_llm_tokens(GerLLM *m, const char *texto);

/// Memória estimada, em bytes, só para guardar um contexto desse tamanho.
uint64_t ger_llm_memoria_contexto(GerLLM *m, int contexto, int kvComprimido);

/// Núcleos fortes do aparelho (0 se não der para saber).
int ger_llm_nucleos_fortes(void);

/// Gera a resposta para (sistema, usuario). 0 = terminou; 1 = interrompido; <0 = erro.
int ger_llm_gerar(GerLLM *m, const char *sistema, const char *usuario, GerLLMOpcoes op,
                  GerLLMAndamento andamento, GerLLMPedaco pedaco, void *usuarioCb,
                  GerLLMEstat *estat, char *erro, int tamErro);

void ger_llm_fechar(GerLLM *m);

#endif
