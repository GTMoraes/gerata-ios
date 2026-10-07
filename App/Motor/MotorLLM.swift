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
    }

    private let fila = DispatchQueue(label: "com.gtm.gerata.llm", qos: .userInitiated)
    private var modelo: OpaquePointer?
    private var aberto: String?            // caminho + modo (GPU ou processador)

    /// O que os retornos do C precisam enxergar durante uma geração.
    private final class Caixa {
        var dados = Data()
        var pico: UInt64 = 0
        var ultimoEnvio = Date.distantPast
        let parar: @Sendable () -> Bool
        let andamento: @Sendable (Double) -> Void
        let texto: @Sendable (String) -> Void
        init(parar: @escaping @Sendable () -> Bool, andamento: @escaping @Sendable (Double) -> Void,
             texto: @escaping @Sendable (String) -> Void) {
            self.parar = parar; self.andamento = andamento; self.texto = texto
        }
        func medir() { pico = max(pico, Medidor.usada()) }
    }

    var motor: String { String(cString: ger_llm_motor()) }

    func fechar() {
        fila.sync {
            if let m = modelo { ger_llm_fechar(m) }
            modelo = nil; aberto = nil
        }
    }

    /// Gera a resposta. `texto` recebe a resposta inteira até o momento, algumas vezes por segundo.
    func gerar(arquivo: URL, sistema: String, usuario: String, contexto: Int, maxSaida: Int,
               temperatura: Float, naGPU: Bool,
               parar: @escaping @Sendable () -> Bool,
               andamento: @escaping @Sendable (Double) -> Void,
               texto: @escaping @Sendable (String) -> Void) async throws -> Resultado {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Resultado, Error>) in
            fila.async {
                do {
                    let r = try self.executar(arquivo, sistema, usuario, contexto, maxSaida, temperatura, naGPU,
                                              parar, andamento, texto)
                    c.resume(returning: r)
                } catch {
                    c.resume(throwing: error)
                }
            }
        }
    }

    private func executar(_ arquivo: URL, _ sistema: String, _ usuario: String, _ contexto: Int, _ maxSaida: Int,
                          _ temperatura: Float, _ naGPU: Bool,
                          _ parar: @escaping @Sendable () -> Bool,
                          _ andamento: @escaping @Sendable (Double) -> Void,
                          _ texto: @escaping @Sendable (String) -> Void) throws -> Resultado {
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
        let depoisDeAbrir = Medidor.usada()

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
                if let s = String(data: cx.dados, encoding: .utf8) { cx.texto(s) }
            }
            return cx.parar() ? 0 : 1
        }

        var estat = GerLLMEstat()
        let r = ger_llm_gerar(m, sistema, usuario, Int32(contexto), Int32(maxSaida), temperatura,
                              aoAndar, aoGerar, ponteiro.toOpaque(), &estat, &motivo, 256)
        caixa.medir()
        if r < 0 { throw ErroApp(String(cString: motivo)) }
        let bruto = String(decoding: caixa.dados, as: UTF8.self)
        return Resultado(texto: Self.semPensamento(bruto), estat: estat, interrompido: r == 1,
                         picoMemoria: caixa.pico, memoriaDepoisDeAbrir: depoisDeAbrir)
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
