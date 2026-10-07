import Foundation
import Observation
import UIKit

/// O arquivo escolhido na aba Nova.
struct Entrada: Equatable {
    var url: URL
    var nome: String
    var ehTexto: Bool               // .srt ou .txt já transcrito
    var trilhas: [Trilhas.Info]
    var duracao: Double?
}

/// Faz o trabalho de uma reunião: separa as trilhas, transcreve no iPhone, guarda e pede a ata à nuvem.
@MainActor
@Observable
final class Processo {
    struct Opcoes {
        var trilhaEu: Int?          // qual trilha é o seu microfone (só quando o arquivo tem duas ou mais)
        var tipo: String
        var contexto: String
        var modelo: String
        var meuNome: String? = nil      // só em reunião do gravador: como você aparece nela
    }

    private(set) var rodando = false
    private(set) var etapa = ""
    private(set) var fracao: Double?
    /// quando o trabalho atual começou (para mostrar o tempo decorrido)
    private(set) var comecouEm: Date?
    var erro: String?
    /// reunião que acabou de ficar pronta (a tela abre e depois limpa)
    var pronta: Reuniao?

    private var tarefa: Task<Void, Never>?

    private func atualizar(_ texto: String, _ f: Double?) {
        etapa = texto
        fracao = f
    }

    private func comecar() {
        rodando = true; erro = nil; pronta = nil; etapa = "Preparando"; fracao = nil; comecouEm = Date()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func terminar() {
        rodando = false; tarefa = nil; etapa = ""; fracao = nil; comecouEm = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func parar() {
        tarefa?.cancel()
        etapa = "Parando (termina o passo atual)"
    }

    /// Arquivo novo: transcreve (ou lê o texto pronto), guarda e gera a ata.
    func iniciar(_ e: Entrada, _ o: Opcoes, reunioes: Reunioes) {
        guard tarefa == nil else { return }
        comecar()
        tarefa = Task {
            do {
                let r = try await self.executar(e, o, reunioes)
                self.pronta = r
            } catch is CancellationError {
                self.erro = nil
            } catch {
                self.erro = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            self.terminar()
        }
    }

    /// Reunião já transcrita: só pede a ata de novo (outro tipo, outro contexto, outro modelo).
    func gerarDeNovo(_ r: Reuniao, _ o: Opcoes, reunioes: Reunioes) {
        guard tarefa == nil else { return }
        comecar()
        tarefa = Task {
            do {
                _ = try await self.pedirAta(r, o, reunioes)
            } catch is CancellationError {
                self.erro = nil
            } catch {
                self.erro = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            self.terminar()
        }
    }

    private func executar(_ e: Entrada, _ o: Opcoes, _ reunioes: Reunioes) async throws -> Reuniao {
        let acesso = e.url.startAccessingSecurityScopedResource()
        defer { if acesso { e.url.stopAccessingSecurityScopedResource() } }
        let inicio = Date()
        let modelo = TranscritorLocal.modeloPadrao
        var texto = ""
        var duas = false

        if e.ehTexto {
            atualizar("Lendo a transcrição", nil)
            texto = try Roteiro.deArquivo(e.url)
        } else if let eu = o.trilhaEu, e.trilhas.count >= 2, let outra = e.trilhas.first(where: { $0.indice != eu }) {
            let wavEu = try await Trilhas.extrair(e.url, indice: eu) { p in
                Task { @MainActor in self.atualizar("Separando a sua trilha", p) }
            }
            defer { try? FileManager.default.removeItem(at: wavEu) }
            try Task.checkCancellation()
            let wavOutra = try await Trilhas.extrair(e.url, indice: outra.indice) { p in
                Task { @MainActor in self.atualizar("Separando a trilha dos participantes", p) }
            }
            defer { try? FileManager.default.removeItem(at: wavOutra) }
            try Task.checkCancellation()
            let segEu = try await TranscritorLocal.shared.transcrever(wavEu, modelo: modelo, idioma: "pt") { m, f in
                Task { @MainActor in self.atualizar("Sua trilha (1 de 2): " + m, f) }
            }
            try Task.checkCancellation()
            let segOutra = try await TranscritorLocal.shared.transcrever(wavOutra, modelo: modelo, idioma: "pt") { m, f in
                Task { @MainActor in self.atualizar("Participantes (2 de 2): " + m, f) }
            }
            texto = Roteiro.texto(Roteiro.intercalar(Roteiro.falas(segEu, quem: "Eu"),
                                                     Roteiro.falas(segOutra, quem: "Participantes")))
            duas = true
        } else if !e.trilhas.isEmpty {
            let wav = try await Trilhas.extrair(e.url, indice: e.trilhas[0].indice) { p in
                Task { @MainActor in self.atualizar("Lendo o áudio", p) }
            }
            defer { try? FileManager.default.removeItem(at: wav) }
            try Task.checkCancellation()
            let seg = try await TranscritorLocal.shared.transcrever(wav, modelo: modelo, idioma: "pt") { m, f in
                Task { @MainActor in self.atualizar(m, f) }
            }
            texto = Roteiro.texto(Roteiro.falas(seg, quem: ""))
        } else {
            let seg = try await TranscritorLocal.shared.transcrever(e.url, modelo: modelo, idioma: "pt") { m, f in
                Task { @MainActor in self.atualizar(m, f) }
            }
            texto = Roteiro.texto(Roteiro.falas(seg, quem: ""))
        }
        try Task.checkCancellation()
        if texto.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 {
            throw ErroApp("Não saiu texto dessa gravação (áudio mudo ou curto demais).")
        }

        let base = (e.nome as NSString).deletingPathExtension
        let r = try reunioes.criar(titulo: base, arquivoOrigem: e.nome, duracao: e.duracao, duasTrilhas: duas,
                                   transcricao: texto,
                                   segundosTranscricao: e.ehTexto ? nil : Date().timeIntervalSince(inicio))
        do {
            return try await pedirAta(r, o, reunioes)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // a transcrição não se perde: a reunião fica em Resultados, sem ata, e dá para pedir de novo
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            var n = r
            n.erroAta = msg
            n.tipoPedido = o.tipo
            n.contexto = o.contexto
            try? reunioes.gravar(n)
            throw ErroApp("A transcrição ficou guardada em Resultados, mas a ata falhou. " + msg)
        }
    }

    private func pedirAta(_ r: Reuniao, _ o: Opcoes, _ reunioes: Reunioes) async throws -> Reuniao {
        guard let texto = reunioes.transcricao(r), !texto.isEmpty else {
            throw ErroApp("Não achei a transcrição dessa reunião.")
        }
        let d = UserDefaults.standard
        let comNomes = r.comNomes == true
        let dono: String = comNomes ? (o.meuNome ?? "") : (d.string(forKey: "seuNome") ?? "")
        let pedido = Nuvem.PedidoAta(texto: texto, tipo: o.tipo, contexto: o.contexto,
                                     glossario: d.string(forKey: "glossario") ?? "",
                                     dono: dono,
                                     duasTrilhas: comNomes ? false : r.duasTrilhas,
                                     nomes: comNomes, modelo: o.modelo)
        let ata = try await Nuvem.shared.gerarAta(pedido) { m in
            Task { @MainActor in self.atualizar(m, nil) }
        }
        var n = r
        n.tipoPedido = o.tipo
        n.contexto = o.contexto
        if comNomes {
            n.meuNome = o.meuNome
            if let nome = o.meuNome, !nome.isEmpty { d.set(nome, forKey: "ultimoNomeReuniao") }
        }
        n.tipo = ata.tipo
        n.tipoNome = ata.tipoNome
        n.modelo = ata.modelo
        n.segundosAta = ata.segundos
        n.tokensEntrada = ata.tokensEntrada
        n.tokensSaida = ata.tokensSaida
        n.custo = ata.custo
        if let p = ata.plano {
            n.plano5h = p.cincoHoras; n.plano5hVira = p.cincoHorasVira
            n.planoSemana = p.semana; n.planoSemanaVira = p.semanaVira
            Plano.guardar(p)
        }
        n.temAta = true
        n.erroAta = nil
        if let t = Roteiro.titulo(daAta: ata.texto) { n.titulo = t }
        try reunioes.gravarAta(ata.texto, em: n)
        try reunioes.gravar(n)
        return n
    }
}
