import Foundation

/// Leitura dos textos de teste: .txt puro ou legenda .srt (vira linhas "[HH:MM:SS] fala", que gasta menos).
enum Transcricao {
    static func ler(_ url: URL) throws -> String {
        let acesso = url.startAccessingSecurityScopedResource()
        defer { if acesso { url.stopAccessingSecurityScopedResource() } }
        let dados = try Data(contentsOf: url)
        let texto = String(data: dados, encoding: .utf8) ?? String(decoding: dados, as: UTF8.self)
        return url.pathExtension.lowercased() == "srt" ? deSRT(texto) : texto
    }

    static func deSRT(_ srt: String) -> String {
        var linhas: [String] = []
        let blocos = srt.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        for b in blocos {
            let l = b.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let k = l.firstIndex(where: { $0.contains("-->") }) else { continue }
            let inicio = l[k].components(separatedBy: "-->")[0].trimmingCharacters(in: .whitespaces)
            let hora = String(inicio.prefix(8))
            let fala = l[(k + 1)...].joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !fala.isEmpty { linhas.append("[\(hora)] \(fala)") }
        }
        return linhas.joined(separator: "\n")
    }

    /// Uma conversa curta inventada, para o primeiro teste sem precisar de arquivo.
    static let exemplo = """
    [00:00:05] Eu: Bom, vamos começar. A ideia de hoje é fechar o calendário do lançamento de novembro.
    [00:00:14] Participantes: Perfeito. Antes disso eu queria entender como ficou o resultado da última campanha, porque o custo por lead subiu bastante na segunda semana.
    [00:00:29] Eu: Subiu. Fechamos a primeira semana em sete reais e a segunda em onze. O que puxou foi o público frio; o remarketing ficou estável.
    [00:00:44] Participantes: E dá para segurar isso no próximo? Porque a verba é a mesma, trinta mil.
    [00:00:53] Eu: Dá, se a gente antecipar a captação em uma semana e trocar os criativos na metade. Eu preciso de três vídeos novos até o dia vinte.
    [00:01:08] Participantes: Três vídeos até o dia vinte eu consigo. A Marina grava na quinta. Agora, sobre a data: eu pensei em abrir o carrinho no dia dez de novembro.
    [00:01:22] Eu: Dia dez cai numa segunda. Eu prefiro abrir no domingo, dia nove, com a aula ao vivo às oito da noite.
    [00:01:33] Participantes: Fechado, domingo dia nove. Mudando de assunto, você viu que a página está lenta no celular? Meu sobrinho comentou.
    [00:01:45] Eu: Vi. Isso é da hospedagem. Eu posso migrar, mas preciso do acesso ao domínio.
    [00:01:54] Participantes: Te mando o acesso hoje ainda. Ah, e sobre o preço: mantemos novecentos e noventa e sete?
    [00:02:03] Eu: Mantemos, com o bônus para quem comprar nas primeiras quarenta e oito horas. Só falta decidir qual bônus.
    [00:02:12] Participantes: Isso eu ainda não sei. Deixa eu pensar e te falo até sexta.
    [00:02:19] Eu: Combinado. Então fica: captação começa uma semana antes, três vídeos até o dia vinte, carrinho no domingo dia nove e o bônus você define até sexta.
    """
}
