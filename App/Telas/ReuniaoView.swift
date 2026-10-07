import SwiftUI

/// Uma reunião aberta: a ata (lida como Markdown) e a transcrição.
struct ReuniaoView: View {
    let id: String
    @Environment(Reunioes.self) private var reunioes
    @Environment(Processo.self) private var processo
    @Environment(Gravador.self) private var gravador
    @Environment(\.dismiss) private var fechar

    @State private var aba = 0
    @State private var ata = ""
    @State private var transcricao = ""
    @State private var confirmar: Confirmacao?
    @State private var aviso: String?
    @State private var pedindoDeNovo = false

    private var reuniao: Reuniao? { reunioes.reuniao(id) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let r = reuniao {
                    cabecalho(r)
                    if r.qualidade == "ao_vivo" { avisoQualidade(r) }
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
        .task { if reuniao?.gravacaoID != nil { await gravador.atualizar(reunioes: reunioes) } }
        .onChange(of: reuniao) { _, _ in ler() }
        .onChange(of: gravador.erro) { _, novo in
            if let novo { aviso = novo; gravador.erro = nil }
        }
        .onChange(of: processo.erro) { _, novo in
            if let novo { aviso = novo; processo.erro = nil }
        }
    }

    private func ler() {
        guard let r = reuniao else { return }
        ata = reunioes.ata(r) ?? ""
        transcricao = reunioes.transcricao(r) ?? ""
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
            if let c = linhaCusto(r) {
                Text(c).font(.caption2.monospacedDigit()).foregroundStyle(Tema.texto2)
            }
            if let p = Plano.linha(r.plano5h, r.plano5hVira, comDia: false) {
                Text("Plano, janela de 5 h: " + p).font(.caption2.monospacedDigit()).foregroundStyle(Tema.texto2)
            }
            if let p = Plano.linha(r.planoSemana, r.planoSemanaVira, comDia: true) {
                Text("Plano, semana: " + p).font(.caption2.monospacedDigit()).foregroundStyle(Tema.texto2)
            }
            if r.plano5h != nil || r.planoSemana != nil {
                Text("Saldo do plano no momento em que esta ata foi gerada.").font(.caption2).foregroundStyle(Tema.texto2)
            }
        }
    }

    private func linhaDados(_ r: Reuniao) -> String {
        var p = [r.criada.formatted(.dateTime.day().month().year().hour().minute())]
        if let d = formatarDuracao(r.duracao) { p.append(d) }
        p.append(r.comNomes == true ? "gravador, com nomes" : (r.duasTrilhas ? "duas trilhas" : "uma trilha"))
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

    /// Nas reuniões do gravador, o destaque é o nome que você marcou; nas outras, "Eu".
    private var destaque: String {
        guard let r = reuniao else { return "Eu" }
        return r.comNomes == true ? (r.meuNome ?? "") : "Eu"
    }

    @ViewBuilder
    private func avisoQualidade(_ r: Reuniao) -> some View {
        let g = gravador.lista.first { $0.id == r.gravacaoID }
        Cartao {
            Label("Transcrição de reserva", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.yellow)
            Text(g?.detalhe ?? "A nuvem falhou ao transcrever a gravação inteira. Este texto é o do ao vivo e perde trechos.")
                .font(.footnote).foregroundStyle(Tema.texto2)
            if let g, g.terminou {
                Button {
                    Task { await gravador.refazer(g, reunioes: reunioes) }
                } label: {
                    Label("Refazer a transcrição", systemImage: "arrow.clockwise").frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.glass)
            } else if g != nil {
                Text("Refazendo: " + (g?.textoDaFase ?? "")).font(.caption).foregroundStyle(Tema.texto2)
            } else {
                Text("A gravação não está mais na nuvem, então não dá para refazer.").font(.caption).foregroundStyle(Tema.texto2)
            }
        }
    }

    private func linhaCusto(_ r: Reuniao) -> String? {
        guard let c = r.custo, c > 0 else { return nil }
        return String(format: "Custo desta ata: US$ %.2f (equivalente; no plano não é cobrado à parte)", c)
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
                CaixaExpansivel(altura: alturaAta) {
                    MarkdownView(texto: ata)
                }
            }
        }
    }

    /// A ata ocupa cerca de metade da tela; "Ver mais" abre inteira.
    private var alturaAta: CGFloat { max(320, UIScreen.main.bounds.height * 0.5) }

    private var cartaoTranscricao: some View {
        Cartao {
            if transcricao.isEmpty {
                Text("Sem transcrição.").font(.subheadline).foregroundStyle(Tema.texto2)
            } else {
                CaixaTexto(texto: transcricao, altura: 320, destaque: destaque)
            }
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
    @State private var nomes: [String] = []
    @State private var meuNome = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Cartao(titulo: reuniao.temAta == true ? "Gerar a ata de novo" : "Gerar a ata", icone: "sparkles") {
                        Text(reuniao.temAta == true ? "A transcrição já está guardada, então isso leva cerca de 1 minuto. A ata nova substitui a atual."
                                                    : "A transcrição já está guardada. A ata leva cerca de 1 minuto e usa o seu plano do Claude.")
                            .font(.footnote).foregroundStyle(Tema.texto2)
                        OpcoesAta(tipo: $tipo, contexto: $contexto, modelo: $modelo)
                    }
                    if reuniao.comNomes == true {
                        Cartao(titulo: "Qual destes é você?", icone: "person.crop.circle") {
                            if nomes.isEmpty {
                                Text("O gravador não identificou ninguém pelo nome nesta reunião.")
                                    .font(.footnote).foregroundStyle(Tema.texto2)
                            }
                            ForEach(nomes, id: \.self) { n in
                                Button { meuNome = n } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: meuNome == n ? "largecircle.fill.circle" : "circle")
                                            .foregroundStyle(Tema.acento)
                                        Text(n).font(.subheadline).foregroundStyle(.primary)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 3)
                                }
                                .buttonStyle(.plain)
                            }
                            Button { meuNome = "" } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: meuNome.isEmpty ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(Tema.acento)
                                    Text("Nenhum (não participei ou não apareço)").font(.subheadline).foregroundStyle(Tema.texto2)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 3)
                            }
                            .buttonStyle(.plain)
                            Text("Serve para a ata saber quais pendências e combinados são seus.")
                                .font(.caption).foregroundStyle(Tema.texto2)
                        }
                    }
                    BotaoPrincipal(titulo: "Gerar", icone: "sparkles") {
                        var o = Processo.Opcoes(trilhaEu: nil, tipo: tipo, contexto: contexto, modelo: modelo)
                        if reuniao.comNomes == true { o.meuNome = meuNome }
                        processo.gerarDeNovo(reuniao, o, reunioes: reunioes)
                        fechar()
                    }
                }
                .padding()
            }
            .telaEscura()
            .navigationTitle(reuniao.temAta == true ? "Nova versão" : "Ata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { fechar() } }
            }
            .onAppear {
                tipo = reuniao.tipoPedido ?? "auto"
                contexto = reuniao.contexto ?? ""
                modelo = modeloPadrao
                if reuniao.comNomes == true {
                    nomes = Roteiro.nomes(reunioes.transcricao(reuniao) ?? "")
                    let ultimo = UserDefaults.standard.string(forKey: "ultimoNomeReuniao") ?? ""
                    if let m = reuniao.meuNome, nomes.contains(m) { meuNome = m }
                    else if nomes.contains(ultimo) { meuNome = ultimo }
                }
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
