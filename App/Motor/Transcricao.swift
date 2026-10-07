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

    /// Falas que o Whisper inventa no silêncio (outro alfabeto, créditos de legenda).
    static func inventada(_ fala: String) -> Bool {
        for u in fala.unicodeScalars {
            let v = u.value
            if (0x0400...0x052F).contains(v) || (0x0590...0x06FF).contains(v) || (0x3040...0x9FFF).contains(v)
                || (0xAC00...0xD7AF).contains(v) { return true }
        }
        let b = fala.lowercased()
        return b.contains("amara.org") || b.contains("legendas pela comunidade")
    }

    /// Versão enxuta para o modelo: sem falas inventadas nem repetidas em seguida, e um horário por minuto.
    static func enxugar(_ texto: String) -> String {
        var saida: [String] = []
        var minuto = ""
        var anterior = ""
        for bruta in texto.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n") {
            let l = bruta.trimmingCharacters(in: .whitespaces)
            if l.isEmpty { continue }
            var hora = ""
            var fala = l
            let c = Array(l)
            if c.count > 10 && c[0] == "[" && c[3] == ":" && c[6] == ":" && c[9] == "]" {
                hora = String(c[1...5])
                fala = String(c[10...]).trimmingCharacters(in: .whitespaces)
            }
            if fala.isEmpty || inventada(fala) || fala == anterior { continue }
            anterior = fala
            if hora.isEmpty {
                saida.append(fala)
            } else if hora != minuto || saida.isEmpty {
                minuto = hora
                saida.append("[\(hora)] \(fala)")
            } else {
                saida[saida.count - 1] += " " + fala
            }
        }
        return saida.joined(separator: "\n")
    }

    /// Uma daily inventada, com combinados e pendências claros, para conferir a ata contra o que se sabe.
    static let daily = """
    [00:00:03] Eu: Bom dia. Daily rápida. Carla, começa você.
    [00:00:08] Participantes: Bom dia. Ontem terminei os criativos da campanha de remarketing, são quatro imagens e um vídeo. Hoje subo tudo no gerenciador. Meu impedimento é que ainda não tenho acesso à conta de anúncios nova.
    [00:00:27] Eu: Eu libero o acesso para você hoje até o meio-dia. Bruno?
    [00:00:33] Participantes: Ontem a página de captura ficou pronta, mas o formulário não está mandando o lead para a planilha. Hoje eu vejo isso. Acho que é o webhook.
    [00:00:47] Eu: Isso é prioridade, porque a campanha entra no ar na quinta. Consegue resolver até amanhã?
    [00:00:55] Participantes: Consigo. Amanhã de manhã eu aviso no grupo se ficou pronto.
    [00:01:02] Eu: Fechado. Se eu fosse chutar, diria que é a URL antiga do webhook, mas confere. Mais alguma coisa?
    [00:01:11] Participantes: Só uma dúvida: a verba de teste continua em cinquenta reais por dia?
    [00:01:17] Eu: Continua em cinquenta por dia até sexta. Na sexta a gente olha os números e decide se aumenta.
    [00:01:26] Participantes: Ah, e o cliente perguntou se dá para adiantar o relatório mensal.
    [00:01:32] Eu: Não dá, o relatório sai no dia cinco como sempre. Eu mesmo respondo para ele hoje.
    [00:01:40] Participantes: Beleza. Vocês viram o jogo ontem? Que vergonha.
    [00:01:45] Eu: Nem me fala. Então é isso: Carla sobe os criativos hoje, Bruno resolve o formulário até amanhã, e eu libero o acesso e respondo o cliente. Valeu.
    """

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
