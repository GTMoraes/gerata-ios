import SwiftUI
import UIKit

/// Caixa de altura limitada que rola por dentro; "Ver mais" abre o conteúdo inteiro (como no Estúdio).
struct CaixaExpansivel<Conteudo: View>: View {
    var altura: CGFloat
    @ViewBuilder var conteudo: Conteudo

    @State private var expandido = false
    @State private var total: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if expandido {
                conteudo
            } else {
                ScrollView {
                    conteudo
                        .onGeometryChange(for: CGFloat.self) { g in
                            g.size.height
                        } action: { nova in
                            total = nova
                        }
                }
                .frame(height: total > 0 ? min(total, altura) : altura)
            }
            if expandido || total > altura + 1 {
                BotaoVerMais(expandido: $expandido)
            }
        }
    }
}

struct BotaoVerMais: View {
    @Binding var expandido: Bool

    var body: some View {
        HStack {
            Spacer()
            Button { withAnimation(.snappy) { expandido.toggle() } } label: {
                Label(expandido ? "Ver menos" : "Ver mais", systemImage: expandido ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(.glass)
        }
    }
}

/// Texto da transcrição: caixa de altura limitada (rola por dentro), "Ver mais" abre inteira.
/// Dá para selecionar trechos (UITextView: o Text do SwiftUI só copia o bloco todo).
struct CaixaTexto: View {
    let texto: String
    var altura: CGFloat = 320
    /// nome cujas falas ficam em laranja ("Eu", ou como você aparece na reunião)
    var destaque: String = "Eu"
    @State private var expandido = false
    @State private var alturaTotal: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextoSelecionavel(texto: texto, destaque: destaque, expandido: expandido, alturaMax: altura, alturaTotal: $alturaTotal)
            if alturaTotal > altura + 1 {
                BotaoVerMais(expandido: $expandido)
            }
            Text("Toque e segure para selecionar um trecho.").font(.caption).foregroundStyle(Tema.texto2)
        }
    }
}

struct TextoSelecionavel: UIViewRepresentable {
    let texto: String
    var destaque: String = "Eu"
    let expandido: Bool
    let alturaMax: CGFloat
    @Binding var alturaTotal: CGFloat

    final class Coordinator { var texto = ""; var destaque = "" }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.isEditable = false
        v.isSelectable = true
        v.backgroundColor = .clear
        v.adjustsFontForContentSizeCategory = true
        v.textContainerInset = .zero
        v.textContainer.lineFragmentPadding = 0
        v.dataDetectorTypes = []
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return v
    }

    func updateUIView(_ v: UITextView, context: Context) {
        if context.coordinator.texto != texto || context.coordinator.destaque != destaque {
            context.coordinator.texto = texto
            context.coordinator.destaque = destaque
            v.attributedText = Self.colorido(texto, destaque: destaque)
        }
        v.isScrollEnabled = !expandido
        if !expandido { v.flashScrollIndicators() }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView v: UITextView, context: Context) -> CGSize? {
        let w = proposal.width ?? v.window?.bounds.width ?? 350
        let total = ceil(v.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height)
        if abs(total - alturaTotal) > 0.5 {
            DispatchQueue.main.async { alturaTotal = total }
        }
        return CGSize(width: w, height: expandido ? total : min(total, alturaMax))
    }

    /// As suas falas ("] Eu:" ou "] Seu Nome:") em laranja; o resto na cor normal.
    static func colorido(_ texto: String, destaque: String) -> NSAttributedString {
        let marca = "] " + destaque + ":"
        let fonte = UIFont.preferredFont(forTextStyle: .footnote)
        let paragrafo = NSMutableParagraphStyle()
        paragrafo.paragraphSpacing = 6
        let normal: [NSAttributedString.Key: Any] = [.font: fonte, .foregroundColor: UIColor.label, .paragraphStyle: paragrafo]
        var meu = normal
        meu[.foregroundColor] = UIColor(Tema.acento)
        let saida = NSMutableAttributedString()
        let linhas = texto.components(separatedBy: "\n")
        for (i, linha) in linhas.enumerated() {
            let pedaco = i < linhas.count - 1 ? linha + "\n" : linha
            saida.append(NSAttributedString(string: pedaco, attributes: (!destaque.isEmpty && linha.contains(marca)) ? meu : normal))
        }
        return saida
    }
}
