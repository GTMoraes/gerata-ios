import Foundation

/// O modelo de linguagem rodando no iPhone (llama.cpp). Um modelo aberto por vez, numa fila própria.
final class MotorLLM: @unchecked Sendable {
    static let shared = MotorLLM()

    struct Resultado {
        var texto: String
        var estat: GerLLMEstat
        var interrompido: Bool
        var picoMemoria: UInt64
        var memoriaDepoisDeAbrir: UInt64
        var menorLivre: UInt64
        var loop: Bool
    }

    struct Opcoes: Sendable {
        var contexto = 8192
        var maxSaida = 800
        var temperatura: Float = 0.2
        var penalidade: Float = 1.1
        var naGPU = true
        var kvComprimido = false
        var nucleosFortes = false
        var forcar = false          // roda mesmo com a conta de memória não fechando
    }

    /// A conta de memória não fecha: a tela pergunta se roda mesmo assim.
    struct ErroMemoria: LocalizedError {
        var texto: String
        var errorDescription: String? { texto }
    }

    static var nucleosFortes: Int { Int(ger_llm_nucleos_fortes()) }

    private let fila = DispatchQueue(label: "com.gtm.gerata.llm", qos: .userInitiated)
    private var modelo: OpaquePointer?
    private var aberto: String?            // caminho + modo (GPU ou processador)

    /// O que os retornos do C precisam enxergar durante uma geração.
    private final class Caixa {
        var dados = Data()
        var pico: UInt64 = 0
        var menorLivre: UInt64 = .max
        var loop = false
        var ultimoEnvio = Date.distantPast
        let parar: @Sendable () -> Bool
        let andamento: @Sendable (Double) -> Void
        let texto: @Sendable (String) -> Void
        init(parar: @escaping @Sendable () -> Bool, andamento: @escaping @Sendable (Double) -> Void,
             texto: @escaping @Sendable (String) -> Void) {
            self.parar = parar; self.andamento = andamento; self.texto = texto
        }
        func medir() { pico = max(pico, Medidor.usada()); menorLivre = min(menorLivre, Medidor.livre()) }
    }

    /// O modelo ficou repetindo a mesma linha (ou o mesmo trecho)?
    static func emLoop(_ s: String) -> Bool {
        var linhas: [String] = []
        for bruta in s.split(separator: "\n").suffix(6) {
            var l = bruta.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("["), let f = l.firstIndex(of: "]") { l = String(l[l.index(after: f)...]).trimmingCharacters(in: .whitespaces) }
            if !l.isEmpty { linhas.append(l) }
        }
        if !s.hasSuffix("\n") && !linhas.isEmpty { linhas.removeLast() }     // a última pode estar pela metade
        if linhas.count >= 3 {
            let u = linhas[linhas.count - 1]
            if u.count >= 12 && linhas[linhas.count - 2] == u && linhas[linhas.count - 3] == u { return true }
        }
        if s.count >= 900 {
            let fim = String(s.suffix(70))
            let janela = String(s.suffix(900))
            if janela.components(separatedBy: fim).count - 1 >= 5 { return true }
        }
        return false
    }

    var motor: String { String(cString: ger_llm_motor()) }

    func fechar() {
        fila.sync {
            if let m = modelo { ger_llm_fechar(m) }
            modelo = nil; aberto = nil
        }
    }

    /// Quantos tokens cada linha ocupa no modelo (abre o modelo se precisar).
    func contar(arquivo: URL, naGPU: Bool, linhas: [String]) async throws -> [Int] {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<[Int], Error>) in
            fila.async {
                do {
                    let m = try self.abrir(arquivo, naGPU)
                    c.resume(returning: linhas.map { max(0, Int(ger_llm_tokens(m, $0))) })
                } catch {
                    c.resume(throwing: error)
                }
            }
        }
    }

    private func abrir(_ arquivo: URL, _ naGPU: Bool) throws -> OpaquePointer {
        var motivo = [CChar](repeating: 0, count: 256)
        let chave = arquivo.path + (naGPU ? "|gpu" : "|cpu")
        if aberto != chave {
            if let m = modelo { ger_llm_fechar(m) }
            modelo = nil; aberto = nil
            guard let m = ger_llm_abrir(arquivo.path, naGPU ? -1 : 0, &motivo, 256) else {
                throw ErroApp(String(cString: motivo))
            }
            modelo = m; aberto = chave
        }
        guard let m = modelo else { throw ErroApp("O modelo não está aberto.") }
        return m
    }

    /// Gera a resposta. `texto` recebe a resposta inteira até o momento, algumas vezes por segundo.
    func gerar(arquivo: URL, sistema: String, usuario: String, opcoes: Opcoes,
               parar: @escaping @Sendable () -> Bool,
               andamento: @escaping @Sendable (Double) -> Void,
               texto: @escaping @Sendable (String) -> Void) async throws -> Resultado {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Resultado, Error>) in
            fila.async {
                do {
                    let r = try self.executar(arquivo, sistema, usuario, opcoes, parar, andamento, texto)
                    c.resume(returning: r)
                } catch {
                    c.resume(throwing: error)
                }
            }
        }
    }

    private func executar(_ arquivo: URL, _ sistema: String, _ usuario: String, _ op: Opcoes,
                          _ parar: @escaping @Sendable () -> Bool,
                          _ andamento: @escaping @Sendable (Double) -> Void,
                          _ texto: @escaping @Sendable (String) -> Void) throws -> Resultado {
        var motivo = [CChar](repeating: 0, count: 256)
        let m = try abrir(arquivo, op.naGPU)
        let depoisDeAbrir = Medidor.usada()

        // a conta de memória fecha? (o contexto pesa na cota do app; o modelo pesa na memória do aparelho)
        if !op.forcar {
            let doContexto = ger_llm_memoria_contexto(m, Int32(op.contexto), op.kvComprimido ? 1 : 0)
            let folga: UInt64 = 500_000_000
            let livre = Medidor.livre()
            var tamanho: UInt64 = 0
            if let atributos = try? FileManager.default.attributesOfItem(atPath: arquivo.path),
               let n = atributos[.size] as? NSNumber { tamanho = n.uint64Value }
            let total = Medidor.totalDoAparelho
            if doContexto + folga > livre {
                throw ErroMemoria(texto: "Este contexto pede cerca de \(Medidor.texto(doContexto)) e o app só tem \(Medidor.texto(livre)) livres. O iOS pode encerrar o GerAta.")
            }
            if tamanho + doContexto + folga > total - total / 5 {
                throw ErroMemoria(texto: "Modelo (\(Medidor.texto(tamanho))) mais contexto (\(Medidor.texto(doContexto))) passam de 80% da memória do aparelho (\(Medidor.texto(total))). O iOS pode encerrar o GerAta.")
            }
        }

        let caixa = Caixa(parar: parar, andamento: andamento, texto: texto)
        caixa.pico = depoisDeAbrir
        let ponteiro = Unmanaged.passRetained(caixa)
        defer { ponteiro.release() }

        let aoAndar: GerLLMAndamento = { fracao, u in
            guard let u else { return 1 }
            let cx = Unmanaged<Caixa>.fromOpaque(u).takeUnretainedValue()
            cx.medir()
            cx.andamento(fracao)
            return cx.parar() ? 0 : 1
        }
        let aoGerar: GerLLMPedaco = { bytes, n, u in
            guard let bytes, let u, n > 0 else { return 1 }
            let cx = Unmanaged<Caixa>.fromOpaque(u).takeUnretainedValue()
            bytes.withMemoryRebound(to: UInt8.self, capacity: Int(n)) { p in
                cx.dados.append(p, count: Int(n))
            }
            let agora = Date()
            if agora.timeIntervalSince(cx.ultimoEnvio) > 0.15 {
                cx.ultimoEnvio = agora
                cx.medir()
                // um caractere pode estar pela metade no fim: só mostra quando o texto fecha em UTF-8
                if let s = String(data: cx.dados, encoding: .utf8) {
                    cx.texto(s)
                    if MotorLLM.emLoop(s) { cx.loop = true; return 0 }
                }
            }
            return cx.parar() ? 0 : 1
        }

        var estat = GerLLMEstat()
        let opC = GerLLMOpcoes(contexto: Int32(op.contexto), maxSaida: Int32(op.maxSaida), temperatura: op.temperatura,
                               penalidade: op.penalidade, kvComprimido: op.kvComprimido ? 1 : 0,
                               threads: op.nucleosFortes ? Int32(max(2, Self.nucleosFortes)) : 0)
        let r = ger_llm_gerar(m, sistema, usuario, opC,
                              aoAndar, aoGerar, ponteiro.toOpaque(), &estat, &motivo, 256)
        caixa.medir()
        if r < 0 { throw ErroApp(String(cString: motivo)) }
        let bruto = String(decoding: caixa.dados, as: UTF8.self)
        return Resultado(texto: Self.semPensamento(bruto), estat: estat, interrompido: r == 1 && !caixa.loop,
                         picoMemoria: caixa.pico, memoriaDepoisDeAbrir: depoisDeAbrir,
                         menorLivre: caixa.menorLivre, loop: caixa.loop)
    }

    /// Alguns modelos escrevem o raciocínio entre <think> e </think> antes da resposta: fica de fora.
    static func semPensamento(_ s: String) -> String {
        var t = s
        while let a = t.range(of: "<think>") {
            if let b = t.range(of: "</think>", range: a.upperBound..<t.endIndex) {
                t.removeSubrange(a.lowerBound..<b.upperBound)
            } else {
                t.removeSubrange(a.lowerBound..<t.endIndex)
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
