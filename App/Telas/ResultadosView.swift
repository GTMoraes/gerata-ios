import SwiftUI

/// Lista das reuniões guardadas.
struct ResultadosView: View {
    @Environment(Reunioes.self) private var reunioes

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if reunioes.lista.isEmpty {
                        Cartao {
                            Label("Nenhuma reunião ainda", systemImage: "tray")
                                .font(.headline)
                            Text("As atas que você gerar na aba Nova aparecem aqui. Elas também ficam no app Arquivos, em No Meu iPhone › GerAta › Reuniões.")
                                .font(.footnote).foregroundStyle(Tema.texto2)
                        }
                    }
                    ForEach(reunioes.lista) { r in
                        NavigationLink(value: r.id) {
                            LinhaReuniao(reuniao: r)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .telaEscura()
            .navigationTitle("Resultados")
            .navigationDestination(for: String.self) { id in
                ReuniaoView(id: id)
            }
            .onAppear { reunioes.recarregar() }
        }
    }
}

struct LinhaReuniao: View {
    let reuniao: Reuniao

    var body: some View {
        Cartao {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: reuniao.temAta == true ? "doc.text.fill" : "doc.badge.ellipsis")
                    .font(.title3)
                    .foregroundStyle(reuniao.temAta == true ? Tema.acento : Tema.texto2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(reuniao.titulo).font(.headline).multilineTextAlignment(.leading)
                    Text(detalhe).font(.caption).foregroundStyle(Tema.texto2)
                    if reuniao.temAta != true {
                        Text(reuniao.erroAta == nil ? "Sem ata ainda" : "A ata falhou: toque para tentar de novo")
                            .font(.caption).foregroundStyle(.yellow)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Tema.texto2)
            }
        }
    }

    private var detalhe: String {
        var partes = [reuniao.criada.formatted(.dateTime.day().month().year().hour().minute())]
        if let d = formatarDuracao(reuniao.duracao) { partes.append(d) }
        if let t = reuniao.tipoNome { partes.append(t) }
        return partes.joined(separator: " · ")
    }
}
