#include "MotorLLM.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#if __has_include(<llama/llama.h>)
#include <llama/llama.h>
#else
#include "llama.h"
#endif

struct GerLLM {
    struct llama_model *modelo;
    const struct llama_vocab *vocab;
    double segCarregar;
    int carregarContado;
};

static void anotar(char *erro, int tam, const char *texto) {
    if (erro && tam > 0) snprintf(erro, (size_t)tam, "%s", texto);
}

static void semLog(enum ggml_log_level nivel, const char *texto, void *u) {
    (void)nivel; (void)texto; (void)u;
}

const char *ger_llm_motor(void) {
    return llama_print_system_info();
}

GerLLM *ger_llm_abrir(const char *caminho, int camadasGPU, char *erro, int tamErro) {
    static int iniciado = 0;
    if (!iniciado) { llama_log_set(semLog, NULL); llama_backend_init(); iniciado = 1; }
    GerLLM *m = calloc(1, sizeof *m);
    if (!m) { anotar(erro, tamErro, "sem memória"); return NULL; }
    int64_t t0 = llama_time_us();
    struct llama_model_params mp = llama_model_default_params();
    mp.n_gpu_layers = camadasGPU < 0 ? 999 : camadasGPU;
    m->modelo = llama_model_load_from_file(caminho, mp);
    if (!m->modelo) {
        anotar(erro, tamErro, "não consegui abrir o modelo (arquivo incompleto, formato não suportado ou falta de memória)");
        free(m); return NULL;
    }
    m->vocab = llama_model_get_vocab(m->modelo);
    m->segCarregar = (llama_time_us() - t0) / 1e6;
    return m;
}

void ger_llm_info(GerLLM *m, char *descricao, int tam, int *contextoTreino, uint64_t *bytes) {
    if (!m) return;
    if (descricao && tam > 0) { descricao[0] = 0; llama_model_desc(m->modelo, descricao, (size_t)tam); }
    if (contextoTreino) *contextoTreino = llama_model_n_ctx_train(m->modelo);
    if (bytes) *bytes = llama_model_size(m->modelo);
}

/// Monta o pedido no formato de conversa do próprio modelo; sem formato conhecido, usa ChatML.
static char *montarPedido(GerLLM *m, const char *sistema, const char *usuario) {
    const char *molde = llama_model_chat_template(m->modelo, NULL);
    struct llama_chat_message msgs[2];
    size_t n = 0;
    if (sistema && sistema[0]) { msgs[n].role = "system"; msgs[n].content = sistema; n++; }
    msgs[n].role = "user"; msgs[n].content = usuario; n++;
    size_t cap = 2 * (strlen(usuario) + (sistema ? strlen(sistema) : 0)) + 1024;
    char *buf = malloc(cap);
    if (!buf) return NULL;
    int r = molde ? llama_chat_apply_template(molde, msgs, n, true, buf, (int32_t)cap) : -1;
    if (r > (int)cap) {
        char *maior = realloc(buf, (size_t)r + 1);
        if (!maior) { free(buf); return NULL; }
        buf = maior; cap = (size_t)r + 1;
        r = llama_chat_apply_template(molde, msgs, n, true, buf, (int32_t)cap);
    }
    if (r < 0) {
        // o formato do modelo não está na lista do llama.cpp: ChatML, que a maioria entende
        int k = snprintf(buf, cap, "%s%s%s<|im_start|>user\n%s<|im_end|>\n<|im_start|>assistant\n",
                         (sistema && sistema[0]) ? "<|im_start|>system\n" : "",
                         (sistema && sistema[0]) ? sistema : "",
                         (sistema && sistema[0]) ? "<|im_end|>\n" : "", usuario);
        if (k < 0) { free(buf); return NULL; }
        r = k;
    }
    if ((size_t)r >= cap) r = (int)cap - 1;
    buf[r] = 0;
    return buf;
}

int ger_llm_gerar(GerLLM *m, const char *sistema, const char *usuario,
                  int contexto, int maxSaida, float temperatura,
                  GerLLMAndamento andamento, GerLLMPedaco pedaco, void *usuarioCb,
                  GerLLMEstat *estat, char *erro, int tamErro) {
    if (estat) memset(estat, 0, sizeof *estat);
    if (!m || !usuario) { anotar(erro, tamErro, "pedido vazio"); return -1; }
    if (contexto < 1024) contexto = 1024;
    if (maxSaida < 16) maxSaida = 16;
    if (maxSaida > contexto / 2) maxSaida = contexto / 2;

    char *pedido = montarPedido(m, sistema, usuario);
    if (!pedido) { anotar(erro, tamErro, "sem memória para montar o pedido"); return -1; }

    // tokens do pedido
    int32_t cap = (int32_t)strlen(pedido) + 16;
    llama_token *tokens = malloc(sizeof(llama_token) * (size_t)cap);
    if (!tokens) { free(pedido); anotar(erro, tamErro, "sem memória"); return -1; }
    int32_t n = llama_tokenize(m->vocab, pedido, (int32_t)strlen(pedido), tokens, cap, true, true);
    if (n < 0) {
        cap = -n + 16;
        llama_token *maior = realloc(tokens, sizeof(llama_token) * (size_t)cap);
        if (!maior) { free(tokens); free(pedido); anotar(erro, tamErro, "sem memória"); return -1; }
        tokens = maior;
        n = llama_tokenize(m->vocab, pedido, (int32_t)strlen(pedido), tokens, cap, true, true);
    }
    free(pedido);
    if (n <= 0) { free(tokens); anotar(erro, tamErro, "não consegui ler o texto do pedido"); return -1; }

    // o pedido precisa caber no contexto junto com a resposta
    int limite = contexto - maxSaida - 8;
    int cortado = 0;
    if (n > limite) { n = limite; cortado = 1; }

    struct llama_context_params cp = llama_context_default_params();
    cp.n_ctx = (uint32_t)contexto;
    cp.n_batch = 512;
    cp.no_perf = true;
    struct llama_context *ctx = llama_init_from_model(m->modelo, cp);
    if (!ctx) { free(tokens); anotar(erro, tamErro, "faltou memória para um contexto desse tamanho: tente um contexto menor"); return -2; }

    struct llama_sampler *amostra = llama_sampler_chain_init(llama_sampler_chain_default_params());
    if (temperatura <= 0.01f) {
        llama_sampler_chain_add(amostra, llama_sampler_init_greedy());
    } else {
        llama_sampler_chain_add(amostra, llama_sampler_init_top_k(40));
        llama_sampler_chain_add(amostra, llama_sampler_init_top_p(0.9f, 1));
        llama_sampler_chain_add(amostra, llama_sampler_init_temp(temperatura));
        llama_sampler_chain_add(amostra, llama_sampler_init_dist(1234));
    }

    int resultado = 0;
    int64_t t0 = llama_time_us();
    // lê o pedido em lotes, avisando o andamento
    for (int32_t i = 0; i < n && resultado == 0; i += 512) {
        int32_t lote = n - i < 512 ? n - i : 512;
        if (llama_decode(ctx, llama_batch_get_one(tokens + i, lote)) != 0) {
            anotar(erro, tamErro, "o modelo falhou ao ler o texto (provável falta de memória)");
            resultado = -3; break;
        }
        if (andamento && !andamento((double)(i + lote) / (double)n, usuarioCb)) resultado = 1;
    }
    int64_t t1 = llama_time_us();

    int gerados = 0;
    while (resultado == 0 && gerados < maxSaida) {
        llama_token t = llama_sampler_sample(amostra, ctx, -1);
        if (llama_vocab_is_eog(m->vocab, t)) break;
        char peca[256];
        int32_t k = llama_token_to_piece(m->vocab, t, peca, (int32_t)sizeof peca, 0, false);
        gerados++;
        if (k > 0 && pedaco && !pedaco(peca, k, usuarioCb)) { resultado = 1; break; }
        if (llama_decode(ctx, llama_batch_get_one(&t, 1)) != 0) {
            anotar(erro, tamErro, "o modelo falhou ao gerar (provável falta de memória)");
            resultado = -3; break;
        }
    }
    int64_t t2 = llama_time_us();

    if (estat) {
        estat->tokensEntrada = n; estat->tokensSaida = gerados; estat->cortado = cortado;
        estat->contexto = contexto;
        estat->segCarregar = m->carregarContado ? 0 : m->segCarregar;
        estat->segEntrada = (t1 - t0) / 1e6; estat->segSaida = (t2 - t1) / 1e6;
    }
    m->carregarContado = 1;
    llama_sampler_free(amostra);
    llama_free(ctx);
    free(tokens);
    return resultado;
}

void ger_llm_fechar(GerLLM *m) {
    if (!m) return;
    if (m->modelo) llama_model_free(m->modelo);
    free(m);
}
