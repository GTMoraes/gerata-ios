import Foundation
import Observation

/// Tipos de reunião (os códigos são os mesmos do servidor).
enum Tipos {
    struct Tipo: Identifiable, Hashable {
        let id: String
        let nome: String
    }
    static let todos: [Tipo] = [
        Tipo(id: "auto", nome: "Automático"),
        Tipo(id: "geral", nome: "Geral"),
        Tipo(id: "cliente", nome: "Reunião com cliente"),
        Tipo(id: "equipe", nome: "Reunião de equipe"),
        Tipo(id: "estrategia", nome: "Alinhamento de estratégia"),
        Tipo(id: "daily", nome: "Daily"),
        Tipo(id: "comunicado", nome: "Comunicado ou apresentação"),
        Tipo(id: "pitch", nome: "Pitch de vendas"),
        Tipo(id: "lancamento", nome: "Definição de lançamento"),
    ]
    static func nome(_ id: String) -> String { todos.first { $0.id == id }?.nome ?? id }
}

/// Uma reunião guardada: uma pasta em Arquivos › GerAta › Reuniões, com a transcrição e a ata.
struct Reuniao: Codable, Identifiable, Hashable {
    var id: String                  // nome da pasta
    var titulo: String
    var criada: Date
    var arquivoOrigem: String
    var duracao: Double?
    var duasTrilhas: Bool
    var contexto: String?           // "quem é quem"
    var tipoPedido: String?         // o que você escolheu ("auto" ou um tipo)
    var tipo: String?               // o tipo da ata gerada
    var tipoNome: String?
    var modelo: String?             // modelo que escreveu a ata
    var segundosTranscricao: Double?
    var segundosAta: Double?
    var tokensEntrada: Int?
    var tokensSaida: Int?
    var custo: Double?
    var temAta: Bool?
    var erroAta: String?
    // saldo do plano no momento em que a ata foi gerada (0 a 1) e quando cada janela vira (segundos desde 1970)
    var plano5h: Double?
    var plano5hVira: Double?
    var planoSemana: Double?
    var planoSemanaVira: Double?
}

/// Saldo do plano do Claude, como a nuvem informa junto de cada ata.
struct Plano: Codable, Equatable {
    var cincoHoras: Double?
    var cincoHorasVira: Double?
    var semana: Double?
    var semanaVira: Double?
    var visto: Date = Date()

    init(_ d: [String: Any]) {
        if let j = d["cinco_horas"] as? [String: Any] {
            cincoHoras = (j["uso"] as? NSNumber)?.doubleValue
            cincoHorasVira = (j["vira"] as? NSNumber)?.doubleValue
        }
        if let j = d["semana"] as? [String: Any] {
            semana = (j["uso"] as? NSNumber)?.doubleValue
            semanaVira = (j["vira"] as? NSNumber)?.doubleValue
        }
    }

    /// "53% usado · vira às 03:50"
    static func linha(_ uso: Double?, _ vira: Double?, comDia: Bool) -> String? {
        guard let uso else { return nil }
        var t = "\(Int((uso * 100).rounded()))% usado"
        if let vira, vira > 0 {
            let d = Date(timeIntervalSince1970: vira)
            if comDia {
                let quando: String = d.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute())
                t += " · vira " + quando
            } else {
                let quando: String = d.formatted(.dateTime.hour().minute())
                t += " · vira às " + quando
            }
        }
        return t
    }

    // o último saldo visto fica guardado para o cartão de Ajustes
    static func guardar(_ p: Plano) {
        if let d = try? JSONEncoder().encode(p) { UserDefaults.standard.set(d, forKey: "ultimoPlano") }
    }
    static func ultimo() -> Plano? {
        guard let d = UserDefaults.standard.data(forKey: "ultimoPlano") else { return nil }
        return try? JSONDecoder().decode(Plano.self, from: d)
    }
}

@MainActor
@Observable
final class Reunioes {
    private(set) var lista: [Reuniao] = []

    static var raiz: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("Reuniões", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func pasta(_ r: Reuniao) -> URL { raiz.appendingPathComponent(r.id, isDirectory: true) }
    static func arquivoAta(_ r: Reuniao) -> URL { pasta(r).appendingPathComponent("ata.md") }
    static func arquivoTranscricao(_ r: Reuniao) -> URL { pasta(r).appendingPathComponent("transcricao.txt") }
    private static func arquivoDados(_ id: String) -> URL {
        raiz.appendingPathComponent(id, isDirectory: true).appendingPathComponent("reuniao.json")
    }

    init() { recarregar() }

    /// Relê as pastas (você pode ter apagado alguma pelo app Arquivos).
    func recarregar() {
        var achadas: [Reuniao] = []
        let nomes = (try? FileManager.default.contentsOfDirectory(atPath: Self.raiz.path)) ?? []
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        for nome in nomes {
            guard let d = try? Data(contentsOf: Self.arquivoDados(nome)),
                  var r = try? dec.decode(Reuniao.self, from: d) else { continue }
            r.id = nome
            achadas.append(r)
        }
        lista = achadas.sorted { $0.criada > $1.criada }
    }

    func reuniao(_ id: String) -> Reuniao? { lista.first { $0.id == id } }

    func ata(_ r: Reuniao) -> String? { try? String(contentsOf: Self.arquivoAta(r), encoding: .utf8) }
    func transcricao(_ r: Reuniao) -> String? { try? String(contentsOf: Self.arquivoTranscricao(r), encoding: .utf8) }

    /// Cria a pasta da reunião com a transcrição. O nome começa pela data, para ordenar em Arquivos.
    func criar(titulo: String, arquivoOrigem: String, duracao: Double?, duasTrilhas: Bool,
               transcricao: String, segundosTranscricao: Double?) throws -> Reuniao {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH-mm"
        let limpo = Self.nomeLimpo(titulo)
        let base = f.string(from: Date()) + (limpo.isEmpty ? "" : " " + limpo)
        var id = base
        var n = 2
        while FileManager.default.fileExists(atPath: Self.raiz.appendingPathComponent(id).path) {
            id = "\(base) (\(n))"; n += 1
        }
        var r = Reuniao(id: id, titulo: titulo.isEmpty ? "Reunião" : titulo, criada: Date(), arquivoOrigem: arquivoOrigem,
                        duracao: duracao, duasTrilhas: duasTrilhas)
        r.segundosTranscricao = segundosTranscricao
        r.temAta = false
        try FileManager.default.createDirectory(at: Self.pasta(r), withIntermediateDirectories: true)
        try transcricao.write(to: Self.arquivoTranscricao(r), atomically: true, encoding: .utf8)
        try gravar(r)
        return r
    }

    func gravar(_ r: Reuniao) throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(r).write(to: Self.arquivoDados(r.id), options: .atomic)
        if let i = lista.firstIndex(where: { $0.id == r.id }) { lista[i] = r } else { lista.insert(r, at: 0) }
        lista.sort { $0.criada > $1.criada }
    }

    func gravarAta(_ texto: String, em r: Reuniao) throws {
        try texto.write(to: Self.arquivoAta(r), atomically: true, encoding: .utf8)
    }

    func apagar(_ r: Reuniao) {
        try? FileManager.default.removeItem(at: Self.pasta(r))
        lista.removeAll { $0.id == r.id }
    }

    func tamanhoEmDisco() -> Int64 {
        guard let e = FileManager.default.enumerator(at: Self.raiz, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let u as URL in e {
            total += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    /// Só o que pode entrar em nome de pasta, até 60 caracteres.
    static func nomeLimpo(_ s: String) -> String {
        let proibidos = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let partes = s.components(separatedBy: proibidos).joined(separator: " ")
        let junto = partes.split(separator: " ").joined(separator: " ")
        return String(junto.prefix(60)).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
    }
}

/// Monta o texto da transcrição no formato que vai para o Claude e fica guardado:
/// uma fala por linha, "[HH:MM:SS] Eu: ..." (duas trilhas) ou "[HH:MM:SS] ..." (uma).
enum Roteiro {
    struct Fala {
        var inicio: Double
        var fim: Double
        var quem: String        // "Eu", "Participantes" ou ""
        var texto: String
    }

    /// Junta os trechos seguidos da mesma pessoa numa fala só (até ~350 caracteres ou uma pausa de 2 s).
    static func falas(_ segmentos: [Segmento], quem: String) -> [Fala] {
        var saida: [Fala] = []
        for s in segmentos {
            let t = semCreditos(s.texto)
            if t.isEmpty || inventada(t) { continue }
            if var u = saida.last, s.inicio - u.fim < 2.0, u.texto.count + t.count < 350 {
                u.texto += " " + t
                u.fim = max(u.fim, s.fim)
                saida[saida.count - 1] = u
            } else {
                saida.append(Fala(inicio: s.inicio, fim: s.fim, quem: quem, texto: t))
            }
        }
        return saida
    }

    /// Intercala as falas das duas trilhas pelo horário de início.
    static func intercalar(_ a: [Fala], _ b: [Fala]) -> [Fala] {
        (a + b).sorted { $0.inicio < $1.inicio }
    }

    static func texto(_ falas: [Fala]) -> String {
        falas.map { f in
            f.quem.isEmpty ? "[\(hms(f.inicio))] \(f.texto)" : "[\(hms(f.inicio))] \(f.quem): \(f.texto)"
        }.joined(separator: "\n")
    }

    /// Lê um arquivo de texto ou legenda .srt já pronto.
    static func deArquivo(_ url: URL) throws -> String {
        let dados = try Data(contentsOf: url)
        let bruto = String(data: dados, encoding: .utf8) ?? String(decoding: dados, as: UTF8.self)
        return url.pathExtension.lowercased() == "srt" ? deSRT(bruto) : bruto
    }

    static func deSRT(_ srt: String) -> String {
        var segmentos: [Segmento] = []
        let blocos = srt.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        for b in blocos {
            let l = b.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let k = l.firstIndex(where: { $0.contains("-->") }) else { continue }
            let tempos = l[k].components(separatedBy: "-->")
            let fala = l[(k + 1)...].joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if fala.isEmpty || inventada(fala) { continue }
            let ini = segundos(tempos[0])
            let fim = tempos.count > 1 ? segundos(tempos[1]) : ini
            segmentos.append(Segmento(inicio: ini, fim: max(fim, ini), texto: fala, palavras: []))
        }
        return texto(falas(segmentos, quem: ""))
    }

    /// "00:01:02,500" → 62.5
    static func segundos(_ s: String) -> Double {
        let limpo = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let p = limpo.split(separator: ":").map { Double($0) ?? 0 }
        if p.count == 3 { return p[0] * 3600 + p[1] * 60 + p[2] }
        if p.count == 2 { return p[0] * 60 + p[1] }
        return p.first ?? 0
    }

    /// Falas que o Whisper inventa no silêncio (outro alfabeto, créditos de legenda).
    static func inventada(_ fala: String) -> Bool {
        var letras = 0
        var deFora = 0
        for u in fala.unicodeScalars where u.properties.isAlphabetic {
            letras += 1
            let v = u.value
            if (0x0370...0x052F).contains(v) || (0x0590...0x08FF).contains(v) || (0x3040...0x30FF).contains(v)
                || (0x3400...0x9FFF).contains(v) || (0xAC00...0xD7AF).contains(v) { deFora += 1 }
        }
        if letras > 0 && deFora * 2 > letras { return true }
        let b = fala.lowercased()
        return b.contains("amara.org") || b.contains("legendas pela comunidade")
    }

    /// Créditos de legenda que o Whisper solta no silêncio ("Legenda Adriana Zanotto", "Legendas pela
    /// comunidade Amara.org"), sozinhos ou grudados numa fala de verdade. Só frases que são crédito com certeza.
    static let creditos = [
        "legendas? (por |de |da |pela comunidade )?adriana zanotto",
        "legendas? pela comunidade( d[aeo])? amara\\.org",
        "legendas? pela comunidade",
        "amara\\.org",
    ]

    static func semCreditos(_ texto: String) -> String {
        var t = texto
        for padrao in creditos {
            t = t.replacingOccurrences(of: padrao, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        return t.split(separator: " ").joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Título da ata: a primeira linha "# ...", se houver.
    static func titulo(daAta ata: String) -> String? {
        for linha in ata.split(separator: "\n").prefix(5) {
            let l = linha.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("# ") {
                let t = String(l.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                return t.isEmpty ? nil : t
            }
        }
        return nil
    }
}
