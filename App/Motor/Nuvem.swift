import Foundation
import Security

/// Cliente da nuvem (whisper.frx9.com): mesmo login do Estúdio, por cookie de sessão.
/// O GerAta usa a nuvem só para pedir a ata ao Claude; a transcrição é feita no iPhone.
final class Nuvem: @unchecked Sendable {
    static let shared = Nuvem()
    static let base = URL(string: "https://whisper.frx9.com")!

    private let sessao: URLSession

    init() {
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = .shared
        c.httpShouldSetCookies = true
        c.httpCookieAcceptPolicy = .always
        c.timeoutIntervalForRequest = 120
        c.timeoutIntervalForResource = 3600
        c.waitsForConnectivity = true
        sessao = URLSession(configuration: c)
    }

    // MARK: - login

    var usuario: String? { Credenciais.ler()?.usuario }

    func entrar(usuario: String, senha: String) async throws {
        var req = URLRequest(url: Self.base.appendingPathComponent("api/login"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["username": usuario, "password": senha])
        let (dados, resp) = try await sessao.data(for: req)
        try Self.conferir(dados, resp)
        Credenciais.salvar(usuario: usuario, senha: senha)
    }

    func sair() async {
        _ = try? await pedir("api/logout", metodo: "POST", json: [:], relogar: false)
        Credenciais.apagar()
        for c in HTTPCookieStorage.shared.cookies(for: Self.base) ?? [] {
            HTTPCookieStorage.shared.deleteCookie(c)
        }
    }

    private func relogar() async throws {
        guard let c = Credenciais.ler() else { throw ErroApp("Entre com seu usuário da nuvem em Ajustes.") }
        try await entrar(usuario: c.usuario, senha: c.senha)
    }

    // MARK: - requisições

    /// Faz a requisição; se a sessão expirou (401), entra de novo e repete uma vez.
    @discardableResult
    func pedir(_ caminho: String, metodo: String = "GET", json: [String: Any]? = nil,
               relogar podeRelogar: Bool = true) async throws -> Data {
        var req = URLRequest(url: Self.base.appendingPathComponent(caminho))
        req.httpMethod = metodo
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (dados, resp) = try await sessao.data(for: req)
        if (resp as? HTTPURLResponse)?.statusCode == 401, podeRelogar {
            try await relogar()
            return try await pedir(caminho, metodo: metodo, json: json, relogar: false)
        }
        try Self.conferir(dados, resp)
        return dados
    }

    func objeto(_ caminho: String, metodo: String = "GET", json: [String: Any]? = nil) async throws -> [String: Any] {
        let d = try await pedir(caminho, metodo: metodo, json: json)
        return (try JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
    }

    static func conferir(_ dados: Data, _ resp: URLResponse) throws {
        guard let h = resp as? HTTPURLResponse else { throw ErroApp("Resposta inválida da nuvem.") }
        guard (200..<300).contains(h.statusCode) else {
            let obj = try? JSONSerialization.jsonObject(with: dados) as? [String: Any]
            if let det = obj?["detail"] as? String { throw ErroApp(det.prefix(1).uppercased() + det.dropFirst()) }
            switch h.statusCode {
            case 401: throw ErroApp("Usuário ou senha da nuvem inválidos.")
            case 404: throw ErroApp("A nuvem ainda não tem a parte das atas (atualize o servidor).")
            case 413: throw ErroApp("A transcrição é grande demais para a nuvem.")
            case 502, 503, 504, 530: throw ErroApp("A nuvem não está respondendo agora (erro \(h.statusCode)).")
            default: throw ErroApp("A nuvem respondeu com erro \(h.statusCode).")
            }
        }
    }

    // MARK: - atas pelo Claude

    struct EstadoClaude {
        var pronto: Bool        // o servidor tem o Claude instalado e com a chave do plano
        var permitido: Bool     // esta conta pode usar
    }

    func estadoClaude() async throws -> EstadoClaude {
        let r = try await objeto("api/claude/status")
        return EstadoClaude(pronto: r["pronto"] as? Bool ?? false, permitido: r["permitido"] as? Bool ?? false)
    }

    struct Ata {
        var texto: String
        var tipo: String
        var tipoNome: String
        var segundos: Double
        var tokensEntrada: Int
        var tokensSaida: Int
        var custo: Double?
        var modelo: String
        var plano: Plano?
    }

    /// Saldo do plano agora (faz uma chamada mínima ao Claude).
    func consultarPlano() async throws -> Plano {
        let r = try await objeto("api/claude/plano", metodo: "POST", json: [:])
        guard let d = r["plano"] as? [String: Any] else { throw ErroApp("A nuvem não informou o saldo do plano.") }
        let p = Plano(d)
        Plano.guardar(p)
        return p
    }

    struct PedidoAta {
        var texto: String
        var tipo: String            // "auto" ou o código do tipo
        var contexto: String
        var glossario: String
        var dono: String
        var duasTrilhas: Bool
        var modelo: String          // "opus" ou "sonnet"
    }

    /// Manda a transcrição e espera a ata (consulta o andamento a cada 3 s).
    func gerarAta(_ p: PedidoAta, avisar: @escaping @Sendable (String) -> Void) async throws -> Ata {
        avisar("Enviando a transcrição para a nuvem")
        let corpo: [String: Any] = ["texto": p.texto, "tipo": p.tipo, "contexto": p.contexto,
                                    "glossario": p.glossario, "dono": p.dono,
                                    "duas_trilhas": p.duasTrilhas, "modelo": p.modelo]
        let inicio = try await objeto("api/claude/ata", metodo: "POST", json: corpo)
        guard let id = inicio["job_id"] as? String else { throw ErroApp("A nuvem não aceitou o pedido de ata.") }
        let comeco = Date()
        var falhasSeguidas = 0
        while true {
            try await Task.sleep(nanoseconds: 3_000_000_000)
            let passou = Int(Date().timeIntervalSince(comeco))
            if passou > 1500 { throw ErroApp("A ata demorou demais (25 min). Tente de novo.") }
            let r: [String: Any]
            do {
                r = try await objeto("api/claude/ata/" + id)
                falhasSeguidas = 0
            } catch {
                // uma consulta que falha por rede não derruba o pedido: a ata continua sendo escrita no servidor
                if error is CancellationError { throw error }
                let msg = (error as? LocalizedError)?.errorDescription ?? ""
                falhasSeguidas += 1
                if msg.contains("não existe mais") || falhasSeguidas >= 10 { throw error }
                continue
            }
            switch r["status"] as? String ?? "" {
            case "queued":
                avisar("Na fila da nuvem (\(passou) s)")
            case "running":
                avisar("O Claude está escrevendo a ata (\(passou) s)")
            case "done":
                guard let texto = r["ata"] as? String, !texto.isEmpty else { throw ErroApp("A nuvem devolveu uma ata vazia.") }
                return Ata(texto: texto, tipo: r["tipo"] as? String ?? "geral",
                           tipoNome: r["tipo_nome"] as? String ?? "Geral",
                           segundos: r["segundos"] as? Double ?? Double(passou),
                           tokensEntrada: r["tokens_entrada"] as? Int ?? 0,
                           tokensSaida: r["tokens_saida"] as? Int ?? 0,
                           custo: (r["custo"] as? NSNumber)?.doubleValue,
                           modelo: r["modelo"] as? String ?? p.modelo,
                           plano: (r["plano"] as? [String: Any]).map { Plano($0) })
            case "error":
                let e = r["erro"] as? String ?? "erro desconhecido"
                throw ErroApp("A ata falhou: " + e)
            default:
                throw ErroApp("Resposta inesperada da nuvem.")
            }
        }
    }
}

/// Usuário e senha da nuvem no Keychain (para renovar a sessão sozinho).
enum Credenciais {
    private static let servico = "com.gtm.gerata.nuvem"

    static func salvar(usuario: String, senha: String) {
        apagar()
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: servico,
                                kSecAttrAccount as String: usuario,
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                                kSecValueData as String: Data(senha.utf8)]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func ler() -> (usuario: String, senha: String)? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: servico,
                                kSecReturnAttributes as String: true,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var r: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess,
              let item = r as? [String: Any],
              let conta = item[kSecAttrAccount as String] as? String,
              let dados = item[kSecValueData as String] as? Data,
              let senha = String(data: dados, encoding: .utf8) else { return nil }
        return (conta, senha)
    }

    static func apagar() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: servico]
        SecItemDelete(q as CFDictionary)
    }
}
