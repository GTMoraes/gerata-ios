import Foundation

/// Trecho transcrito (mesmo formato do Estúdio).
struct Segmento: Codable, Equatable {
    var inicio: Double
    var fim: Double
    var texto: String
    var palavras: [Palavra]

    struct Palavra: Codable, Equatable {
        var inicio: Double
        var fim: Double
        var texto: String      // com o espaço inicial, como o Whisper devolve
    }
}

/// Chave do cache de compilação do iOS: muda quando o cache deixa de valer
/// (app instalado/atualizado — a pasta do app muda a cada instalação — ou outra versão do iOS).
enum CacheCompilacao {
    static func chave(_ nome: String) -> String {
        [nome, Bundle.main.bundleURL.path, ProcessInfo.processInfo.operatingSystemVersionString].joined(separator: "|")
    }
    static func feito(_ nome: String) -> Bool {
        UserDefaults.standard.string(forKey: "compilado." + nome) == chave(nome)
    }
    static func marcar(_ nome: String) {
        UserDefaults.standard.set(chave(nome), forKey: "compilado." + nome)
    }
}

func hms(_ t: Double) -> String {
    let s = Int(max(0, t))
    return String(format: "%02d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
}
