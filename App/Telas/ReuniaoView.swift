import SwiftUI

/// Uma reunião aberta: a ata (lida como Markdown) e a transcrição.
struct ReuniaoView: View {
    let id: String
    @Environment(Reunioes.self) private var reunioes
    @Environment(Processo.self) private var processo
    @Environment(\.dismiss) private var fechar

    @State private var aba = 0
    @State private var ata = ""
    @State private var transcricao: [String] = []
    @State private var confirmar: Confirmacao?
    @State private var aviso: String?
    @State private var pedindoDeNovo = false

    private var reuniao: Reuniao? { reunioes.reuniao(id) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let r = reuniao {
                    cabecalho(r)
                    if processo.rodando {
                        Cartao {
                            ProgressView().progressViewStyle(.linear).tint(Tema.acento)
                            Text(processo.etapa).font(.subheadline)
                        }
                    }
                    Picker("Ver", selection: $aba) {
                        Text("Ata").tag(0)
                        Text("Transcrição").tag(1)
                    }
                    .pickerStyle(.segmented)
                    if aba == 0 { cartaoAta(r) } else { cartaoTranscricao }
                } else {
                    Cartao { Text("Essa reunião não existe mais.").font(.subheadline) }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .telaEscura()
        .navigationTitle("Reunião")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let r = reuniao {
                    Menu {
                        Button { copiar() } label: { Label("Copiar a ata", systemImage: "doc.on.doc") }
                            .disabled(ata.isEmpty)
                        if r.temAta == true {
                            ShareLink(item: Reunioes.arquivoAta(r)) { Label("Compartilhar a ata (.md)", systemImage: "square.and.arrow.up") }
                        }
                        ShareLink(item: Reunioes.arquivoTranscricao(r)) { Label("Compartilhar a transcrição", systemImage: "text.quote") }
                        Button { pedindoDeNovo = true } label: { Label("Gerar a ata de novo", systemImage: "arrow.clockwise") }
                            .disabled(processo.rodando)
                        Button(role: .destructive) {
                            confirmar = Confirmacao(titulo: "Apagar esta reunião?",
                                                    mensagem: "A ata e a transcrição saem do iPhone. Isso não pode ser desfeito.") {
                                reunioes.apagar(r)
                                fechar()
                            }
                        } label: { Label("Apagar", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmar($confirmar)
        .alert("Aviso", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(aviso ?? "") }
        .sheet(isPresented: $pedindoDeNovo) {
            if let r = reuniao { GerarDeNovoView(reuniao: r) }
        }
        .onAppear { ler() }
        .onChange(of: reuniao) { _, _ in ler() }
        .onChange(of: processo.erro) { _, novo in
            if let novo { aviso = novo; processo.erro = nil }
        }
    }

    private func ler() {
        guard let r = reuniao else { return }
        ata = reunioes.ata(r) ?? ""
        transcricao = (reunioes.transcricao(r) ?? "").split(separator: "\n").map(String.init)
    }

    private func copiar() {
        UIPasteboard.general.string = ata
        aviso = "Ata copiada."
    }

    @ViewBuilder
    private func cabecalho(_ r: Reuniao) -> some View {
        Cartao {
            Text(r.titulo).font(.title3.weight(.semibold))
            Text(linhaDados(r)).font(.caption).foregroundStyle(Tema.texto2)
            if let c = r.contexto, !c.isEmpty {
                Text("Contexto: " + c).font(.caption).foregroundStyle(Tema.texto2)
            }
            if let m = linhaMedidas(r) {
                Text(m).font(.caption2.monospacedDigit()).foregroundStyle(Tema.texto2)
            }
        }
    }

    private func linhaDados(_ r: Reuniao) -> String {
        var p = [r.criada.formatted(.dateTime.day().month().year().hour().minute())]
        if let d = formatarDuracao(r.duracao) { p.append(d) }
        p.append(r.duasTrilhas ? "duas trilhas" : "uma trilha")
        if let t = r.tipoNome { p.append(t) }
        return p.joined(separator: " · ")
    }

    private func linhaMedidas(_ r: Reuniao) -> String? {
        var p: [String] = []
        if let s = formatarDuracao(r.segundosTranscricao) { p.append("transcrição em " + s) }
        if let s = formatarDuracao(r.segundosAta) { p.append("ata em " + s) }
        if let m = r.modelo { p.append(m) }
        if let e = r.tokensEntrada, let s = r.tokensSaida, e + s > 0 { p.append("\(e) + \(s) tokens") }
        return p.isEmpty ? nil : p.joined(separator: " · ")
    }

    @ViewBuilder
    private func cartaoAta(_ r: Reuniao) -> some View {
        Cartao {
            if ata.isEmpty {
                Label(r.erroAta == nil ? "Esta reunião ainda não tem ata" : "A ata falhou",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.yellow)
                if let e = r.erroAta {
                    Text(e).font(.footnote).foregroundStyle(Tema.texto2)
                }
                BotaoPrincipal(titulo: "Gerar a ata", icone: "sparkles", desativado: processo.rodando) {
                    pedindoDeNovo = true
                }
            } else {
                MarkdownView(texto: ata)
            }
        }
    }

    private var cartaoTranscricao: some View {
        Cartao {
            if transcricao.isEmpty {
                Text("Sem transcrição.").font(.subheadline).foregroundStyle(Tema.texto2)
            }
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(Array(transcricao.enumerated()), id: \.offset) { _, linha in
                    Text(linha).font(.footnote)
                        .foregroundStyle(linha.contains("] Eu:") ? Tema.acento : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .textSelection(.enabled)
        }
    }
}

/// Folha para pedir a ata de novo, com outro tipo, outro contexto ou outro modelo.
struct GerarDeNovoView: View {
    let reuniao: Reuniao
    @Environment(Reunioes.self) private var reunioes
    @Environment(Processo.self) private var processo
    @Environment(\.dismiss) private var fechar
    @AppStorage("modeloPadrao") private var modeloPadrao = "opus"

    @State private var tipo = "auto"
    @State private var contexto = ""
    @State private var modelo = "opus"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Cartao(titulo: "Gerar a ata de novo", icone: "arrow.clockwise") {
                        Text("A transcrição já está guardada, então isso leva cerca de 1 minuto. A ata nova substitui a atual.")
                            .font(.footnote).foregroundStyle(Tema.texto2)
                        OpcoesAta(tipo: $tipo, contexto: $contexto, modelo: $modelo)
                    }
                    BotaoPrincipal(titulo: "Gerar", icone: "sparkles") {
                        processo.gerarDeNovo(reuniao, Processo.Opcoes(trilhaEu: nil, tipo: tipo, contexto: contexto, modelo: modelo),
                                             reunioes: reunioes)
                        fechar()
                    }
                }
                .padding()
            }
            .telaEscura()
            .navigationTitle("Nova versão")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { fechar() } }
            }
            .onAppear {
                tipo = reuniao.tipoPedido ?? "auto"
                contexto = reuniao.contexto ?? ""
                modelo = modeloPadrao
            }
        }
    }
}

/// Tipo de reunião, "quem é quem" e modelo: os mesmos campos na aba Nova e no "gerar de novo".
struct OpcoesAta: View {
    @Binding var tipo: String
    @Binding var contexto: String
    @Binding var modelo: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tipo de reunião").font(.subheadline)
                Spacer(minLength: 8)
                Picker("Tipo de reunião", selection: $tipo) {
                    ForEach(Tipos.todos) { t in
                        Text(t.nome).tag(t.id)
                    }
                }
                .labelsHidden()
            }
            TextField("Quem é quem e do que se trata (opcional)", text: $contexto, axis: .vertical)
                .lineLimit(1...4)
                .padding(10).background(.white.opacity(0.06), in: .rect(cornerRadius: 12))
            Picker("Modelo", selection: $modelo) {
                Text("Opus (melhor)").tag("opus")
                Text("Sonnet (mais rápido)").tag("sonnet")
            }
            .pickerStyle(.segmented)
        }
    }
}
