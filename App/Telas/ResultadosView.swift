import SwiftUI

/// Lista das reuniões guardadas. Deslizar para a esquerda apaga (pergunta antes); para a direita copia a ata;
/// tocar e segurar abre o menu.
struct ResultadosView: View {
    @Environment(Reunioes.self) private var reunioes
    @Environment(Processo.self) private var processo

    @State private var saindo: Set<String> = []
    @State private var confirmar: Confirmacao?
    @State private var aviso: String?
    @State private var deNovo: Reuniao?

    var body: some View {
        NavigationStack {
            Group {
                if reunioes.lista.isEmpty {
                    ContentUnavailableView("Nenhuma reunião ainda", systemImage: "tray",
                                           description: Text("As atas que você gerar na aba Nova aparecem aqui e ficam também no app Arquivos, em “No Meu iPhone › GerAta › Reuniões”."))
                } else {
                    List {
                        ForEach(reunioes.lista) { r in
                            NavigationLink(value: r.id) { LinhaReuniao(reuniao: r) }
                                .offset(x: saindo.contains(r.id) ? -700 : 0)
                                .opacity(saindo.contains(r.id) ? 0 : 1)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    // sem "role: .destructive": a lista só fecha a linha quando o item sai de verdade
                                    Button { pedirApagar(r) } label: { Label("Apagar", systemImage: "trash") }
                                        .tint(.red)
                                }
                                .swipeActions(edge: .leading) {
                                    if r.temAta == true {
                                        Button { copiarAta(r) } label: { Label("Copiar ata", systemImage: "doc.on.doc") }
                                            .tint(Tema.acento)
                                    }
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .contextMenu {
                                    if r.temAta == true {
                                        Button("Copiar a ata", systemImage: "doc.on.doc") { copiarAta(r) }
                                        ShareLink(item: Reunioes.arquivoAta(r)) {
                                            Label("Compartilhar a ata (.md)", systemImage: "square.and.arrow.up")
                                        }
                                    }
                                    Button("Gerar a ata de novo", systemImage: "arrow.clockwise") { deNovo = r }
                                        .disabled(processo.rodando)
                                    Button("Apagar", systemImage: "trash", role: .destructive) { pedirApagar(r) }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .telaEscura()
            .navigationTitle("Resultados")
            .confirmar($confirmar)
            .alert("Aviso", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(aviso ?? "") }
            .sheet(item: $deNovo) { r in
                GerarDeNovoView(reuniao: r)
            }
            .navigationDestination(for: String.self) { id in
                ReuniaoView(id: id)
            }
            .onAppear { reunioes.recarregar() }
        }
    }

    private func pedirApagar(_ r: Reuniao) {
        let id = r.id
        withAnimation(.snappy) { _ = saindo.insert(id) }
        var c = Confirmacao(titulo: "Apagar “\(r.titulo)”?",
                            mensagem: "A ata e a transcrição saem do iPhone. Isso não pode ser desfeito.") {
            withAnimation(.snappy) { reunioes.apagar(r) }       // a linha de baixo sobe
            saindo.remove(id)
        }
        c.aoCancelar = { withAnimation(.snappy) { _ = saindo.remove(id) } }   // volta para o lugar
        confirmar = c
    }

    private func copiarAta(_ r: Reuniao) {
        guard let texto = reunioes.ata(r), !texto.isEmpty else { aviso = "Essa reunião ainda não tem ata."; return }
        UIPasteboard.general.string = texto
        aviso = "Ata copiada."
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
