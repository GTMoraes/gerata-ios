import SwiftUI

/// Leitor simples de Markdown para as atas: títulos, listas, citações, linha divisória e
/// negrito/itálico/código dentro do texto. Sem biblioteca externa.
struct MarkdownView: View {
    let texto: String

    private struct Bloco: Identifiable {
        enum Tipo { case titulo1, titulo2, titulo3, item, numerado, citacao, regua, paragrafo }
        let id: Int
        var tipo: Tipo
        var texto: String
        var marca: String = ""      // "1." nas listas numeradas
        var recuo: Int = 0
    }

    private var blocos: [Bloco] {
        var saida: [Bloco] = []
        var n = 0
        for bruta in texto.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let espacos = bruta.prefix { $0 == " " || $0 == "\t" }.count
            let l = bruta.trimmingCharacters(in: .whitespaces)
            if l.isEmpty { continue }
            n += 1
            if l.hasPrefix("### ") { saida.append(Bloco(id: n, tipo: .titulo3, texto: String(l.dropFirst(4)))) }
            else if l.hasPrefix("## ") { saida.append(Bloco(id: n, tipo: .titulo2, texto: String(l.dropFirst(3)))) }
            else if l.hasPrefix("# ") { saida.append(Bloco(id: n, tipo: .titulo1, texto: String(l.dropFirst(2)))) }
            else if l == "---" || l == "***" || l == "___" { saida.append(Bloco(id: n, tipo: .regua, texto: "")) }
            else if l.hasPrefix("- ") || l.hasPrefix("* ") || l.hasPrefix("• ") {
                saida.append(Bloco(id: n, tipo: .item, texto: String(l.dropFirst(2)), recuo: espacos >= 2 ? 1 : 0))
            }
            else if l.hasPrefix("> ") { saida.append(Bloco(id: n, tipo: .citacao, texto: String(l.dropFirst(2)))) }
            else if let ponto = l.firstIndex(of: "."), l.distance(from: l.startIndex, to: ponto) <= 3,
                    l[l.startIndex..<ponto].allSatisfy({ $0.isNumber }), l.index(after: ponto) < l.endIndex,
                    l[l.index(after: ponto)] == " " {
                saida.append(Bloco(id: n, tipo: .numerado, texto: String(l[l.index(ponto, offsetBy: 2)...]),
                                   marca: String(l[l.startIndex...ponto]), recuo: espacos >= 2 ? 1 : 0))
            }
            else { saida.append(Bloco(id: n, tipo: .paragrafo, texto: l)) }
        }
        return saida
    }

    /// Negrito, itálico e `código` dentro da linha.
    private func rico(_ s: String) -> AttributedString {
        let opcoes = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let a = try? AttributedString(markdown: s, options: opcoes) { return a }
        return AttributedString(s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocos) { b in
                linha(b)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func linha(_ b: Bloco) -> some View {
        switch b.tipo {
        case .titulo1:
            Text(rico(b.texto)).font(.title2.weight(.bold)).padding(.top, 4)
        case .titulo2:
            Text(rico(b.texto)).font(.title3.weight(.semibold)).foregroundStyle(Tema.acento).padding(.top, 12)
        case .titulo3:
            Text(rico(b.texto)).font(.headline).padding(.top, 8)
        case .item:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(Tema.acento)
                Text(rico(b.texto)).font(.callout)
            }
            .padding(.leading, b.recuo == 0 ? 0 : 18)
        case .numerado:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(b.marca).font(.callout.monospacedDigit()).foregroundStyle(Tema.acento)
                Text(rico(b.texto)).font(.callout)
            }
            .padding(.leading, b.recuo == 0 ? 0 : 18)
        case .citacao:
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Tema.acento.opacity(0.7)).frame(width: 3)
                Text(rico(b.texto)).font(.callout).italic().foregroundStyle(Tema.texto2)
            }
        case .regua:
            Divider().padding(.vertical, 4)
        case .paragrafo:
            Text(rico(b.texto)).font(.callout)
        }
    }
}
