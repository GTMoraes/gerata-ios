import Foundation
import Observation

/// O gravador de reuniões da nuvem: um participante que entra no Zoom ou no Meet pelo link, grava e
/// devolve a transcrição com o nome de quem falou. Quem trabalha é o servidor; o app só acompanha,
/// então dá para fechar o GerAta durante a reunião.
@MainActor
@Observable
final class Gravador {
    private(set) var disponivel = false         // o servidor tem o gravador e esta conta pode usar
    private(set) var dias = 7                   // por quantos dias a nuvem guarda gravação e transcrição
    private(set) var lista: [Gravacao] = []     // o que está na nuvem, mais nova primeiro
    private(set) var ocupado = false            // mandando o gravador entrar
    var erro: String?
    /// reunião cuja transcrição acabou de chegar (a aba Nova oferece abrir)
    var chegou: String?

    private var vigia: Task<Void, Never>?

    var vivas: [Gravacao] { lista.filter { $0.viva } }
    var terminadas: [Gravacao] { lista.filter { $0.terminou } }

    private func mensagem(_ e: Error) -> String {
        (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
    }

    /// Confere se o recurso existe e busca a lista. Chamado ao abrir a aba Nova.
    func conferir(reunioes: Reunioes) async {
        guard Nuvem.shared.usuario != nil else { disponivel = false; return }
        do {
            let e = try await Nuvem.shared.estadoGravador()
            disponivel = e.pronto && e.permitido
            dias = e.dias
        } catch {
            disponivel = false          // servidor antigo ou fora do ar: o cartão simplesmente não aparece
            return
        }
        if disponivel {
            await atualizar(reunioes: reunioes)
            vigiar(reunioes: reunioes)
        }
    }

    /// Relê a lista e guarda no iPhone as transcrições que ficaram prontas.
    func atualizar(reunioes: Reunioes) async {
        do {
            lista = try await Nuvem.shared.gravacoes()
        } catch {
            return                      // falha de rede numa consulta não é erro para a tela
        }
        for g in lista where g.fase == "pronta" && !jaGuardada(g.id) {
            await guardar(g.id, reunioes: reunioes)
        }
    }

    /// Enquanto houver reunião em andamento, consulta a cada 5 segundos.
    func vigiar(reunioes: Reunioes) {
        guard vigia == nil, !vivas.isEmpty else { return }
        vigia = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self.atualizar(reunioes: reunioes)
                if self.vivas.isEmpty { break }
            }
            self.vigia = nil
        }
    }

    func entrar(link: String, reunioes: Reunioes) async {
        ocupado = true
        defer { ocupado = false }
        do {
            let g = try await Nuvem.shared.mandarGravador(link: link)
            lista.removeAll { $0.id == g.id }
            lista.insert(g, at: 0)
            vigiar(reunioes: reunioes)
        } catch {
            erro = mensagem(error)
        }
    }

    func sair(_ g: Gravacao, reunioes: Reunioes) async {
        do {
            let n = try await Nuvem.shared.sairDaReuniao(g.id)
            trocar(n)
            vigiar(reunioes: reunioes)
        } catch {
            erro = mensagem(error)
        }
    }

    /// Transcreve a gravação de novo (quando a primeira saiu "ao vivo", com trechos perdidos).
    func refazer(_ g: Gravacao, reunioes: Reunioes) async {
        do {
            let n = try await Nuvem.shared.refazerGravacao(g.id)
            esquecer(g.id)              // quando ficar pronta de novo, a transcrição nova substitui a guardada
            trocar(n)
            vigiar(reunioes: reunioes)
        } catch {
            erro = mensagem(error)
        }
    }

    /// Apaga da nuvem a gravação e a transcrição. A cópia guardada no iPhone (em Resultados) continua.
    func apagar(_ g: Gravacao) async {
        do {
            try await Nuvem.shared.apagarGravacao(g.id)
            lista.removeAll { $0.id == g.id }
        } catch {
            erro = mensagem(error)
        }
    }

    private func trocar(_ g: Gravacao) {
        if let i = lista.firstIndex(where: { $0.id == g.id }) { lista[i] = g } else { lista.insert(g, at: 0) }
    }

    // MARK: guardar no iPhone

    private var guardadas: [Int] {
        get { UserDefaults.standard.array(forKey: "gravacoesGuardadas") as? [Int] ?? [] }
        set { UserDefaults.standard.set(Array(newValue.suffix(300)), forKey: "gravacoesGuardadas") }
    }

    func jaGuardada(_ id: Int) -> Bool { guardadas.contains(id) }
    private func esquecer(_ id: Int) { guardadas = guardadas.filter { $0 != id } }

    /// Busca o texto da reunião pronta e cria (ou atualiza) a reunião em Resultados, ainda sem ata.
    private func guardar(_ id: Int, reunioes: Reunioes) async {
        guard let g = try? await Nuvem.shared.gravacao(id), g.fase == "pronta",
              g.texto.trimmingCharacters(in: .whitespacesAndNewlines).count > 10 else { return }
        do {
            if var existente = reunioes.lista.first(where: { $0.gravacaoID == id }) {
                try reunioes.regravarTranscricao(g.texto, em: existente)
                existente.qualidade = g.qualidade
                existente.duracao = g.duracao ?? existente.duracao
                try reunioes.gravar(existente)
                chegou = existente.id
            } else {
                let titulo = "Reunião no " + g.nomePlataforma
                var r = try reunioes.criar(titulo: titulo, arquivoOrigem: g.nomePlataforma + " " + g.codigo,
                                           duracao: g.duracao, duasTrilhas: false,
                                           transcricao: g.texto, segundosTranscricao: nil)
                r.comNomes = true
                r.gravacaoID = id
                r.qualidade = g.qualidade
                try reunioes.gravar(r)
                chegou = r.id
            }
            guardadas = guardadas + [id]
        } catch {
            erro = "A transcrição da reunião chegou, mas não consegui guardar no iPhone: " + mensagem(error)
        }
    }
}
