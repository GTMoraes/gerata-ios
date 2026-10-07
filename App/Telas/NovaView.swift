import SwiftUI
import UniformTypeIdentifiers

/// Aba Nova: escolher a gravação (ou a transcrição pronta), conferir as trilhas e gerar a ata.
struct NovaView: View {
    @Environment(Reunioes.self) private var reunioes
    @Environment(Processo.self) private var processo

    @AppStorage("trilhaEu") private var trilhaEu = -1          // -1 = ainda não escolhida
    @AppStorage("ultimoTipo") private var tipo = "auto"
    @AppStorage("modeloPadrao") private var modeloPadrao = "opus"

    @State private var entrada: Entrada?
    @State private var acessoAberto = false
    @State private var analisando = false
    @State private var contexto = ""
    @State private var modelo = "opus"
    @State private var escolhendo = false
    @State private var aviso: String?
    @State private var abrir: Reuniao?
    @State private var logado = Nuvem.shared.usuario != nil

    private var tipos: [UTType] {
        var t: [UTType] = [.movie, .audio, .plainText, .text]
        if let srt = UTType(filenameExtension: "srt") { t.append(srt) }
        t.append(.data)
        return t
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !logado {
                        Cartao {
                            Label("Entre na nuvem primeiro", systemImage: "person.crop.circle.badge.exclamationmark")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.yellow)
                            Text("A ata é escrita pelo Claude, na sua nuvem. Entre com o seu usuário na aba Ajustes.")
                                .font(.footnote).foregroundStyle(Tema.texto2)
                        }
                    }
                    cartaoArquivo
                    if let e = entrada, e.trilhas.count >= 2 { cartaoTrilhas(e) }
                    if entrada != nil {
                        Cartao(titulo: "Ata", icone: "doc.text") {
                            OpcoesAta(tipo: $tipo, contexto: $contexto, modelo: $modelo)
                            Text("No automático, o Claude identifica o tipo da reunião e escolhe o formato da ata. O tipo usado aparece no resultado.")
                                .font(.caption).foregroundStyle(Tema.texto2)
                        }
                    }
                    cartaoGerar
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .telaEscura()
            .navigationTitle("GerAta")
            .navigationDestination(item: $abrir) { r in
                ReuniaoView(id: r.id)
            }
            .alert("Aviso", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(aviso ?? "") }
            .fileImporter(isPresented: $escolhendo, allowedContentTypes: tipos) { r in
                switch r {
                case .success(let u): escolher(u)
                case .failure(let e): aviso = "Não consegui abrir o arquivo: \(e.localizedDescription)"
                }
            }
            .onAppear {
                logado = Nuvem.shared.usuario != nil
                modelo = modeloPadrao
            }
            .onChange(of: processo.erro) { _, novo in
                if let novo { aviso = novo; processo.erro = nil }
            }
            .onChange(of: processo.pronta) { _, nova in
                if let nova {
                    abrir = nova
                    processo.pronta = nil
                    limpar()
                }
            }
        }
    }

    // MARK: cartões

    private var cartaoArquivo: some View {
        Cartao(titulo: "Gravação", icone: "waveform") {
            if let e = entrada {
                Text(e.nome).font(.subheadline.weight(.semibold))
                Text(descricao(e)).font(.caption).foregroundStyle(Tema.texto2)
            } else if analisando {
                ProgressView("Lendo o arquivo")
            } else {
                Text("Escolha o vídeo ou o áudio da reunião. O arquivo é lido onde está, sem cópia. Também aceita uma transcrição pronta (.srt ou .txt).")
                    .font(.footnote).foregroundStyle(Tema.texto2)
            }
            Button { escolhendo = true } label: {
                Label(entrada == nil ? "Escolher arquivo" : "Trocar arquivo", systemImage: "folder.fill")
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.glass)
            .disabled(processo.rodando || analisando)
        }
    }

    @ViewBuilder
    private func cartaoTrilhas(_ e: Entrada) -> some View {
        Cartao(titulo: "Trilhas de áudio", icone: "person.2.wave.2") {
            Text("Este arquivo tem \(e.trilhas.count) trilhas. Marque qual é o seu microfone; a outra entra como “Participantes”. A escolha fica guardada para os próximos arquivos.")
                .font(.footnote).foregroundStyle(Tema.texto2)
            ForEach(e.trilhas) { t in
                HStack(spacing: 10) {
                    Button {
                        trilhaEu = t.indice
                    } label: {
                        Image(systemName: trilhaEu == t.indice ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(Tema.acento)
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nomeTrilha(t)).font(.subheadline.weight(.semibold))
                        Text(papelTrilha(t, total: e.trilhas.count))
                            .font(.caption).foregroundStyle(Tema.texto2)
                    }
                    Spacer(minLength: 0)
                    Button {
                        Task { await Amostra.shared.tocar(e.url, indice: t.indice) }
                    } label: {
                        Label("Ouvir", systemImage: "play.fill").lineLimit(1)
                    }
                    .buttonStyle(.glass)
                    .disabled(processo.rodando)
                }
                .padding(.vertical, 2)
            }
            Text("“Ouvir” toca 12 segundos. Se cair num silêncio, toque de novo: cada toque pega outro ponto da gravação.")
                .font(.caption).foregroundStyle(Tema.texto2)
            if e.trilhas.count > 2 {
                Text("Com mais de duas trilhas, uso a sua e a primeira das outras.")
                    .font(.caption).foregroundStyle(Tema.texto2)
            }
        }
    }

    private var cartaoGerar: some View {
        Cartao {
            if processo.rodando {
                if let f = processo.fracao { ProgressView(value: min(1, max(0, f))).tint(Tema.acento) }
                else { ProgressView().progressViewStyle(.linear).tint(Tema.acento) }
                Text(processo.etapa).font(.subheadline)
                if let inicio = processo.comecouEm {
                    TimelineView(.periodic(from: inicio, by: 1)) { c in
                        Text("Tempo decorrido: " + relogio(c.date.timeIntervalSince(inicio)))
                            .font(.caption.monospacedDigit()).foregroundStyle(Tema.texto2)
                    }
                }
                Text("Deixe o GerAta aberto na tela até terminar. A barra recomeça a cada passada e a cada trecho conferido.")
                    .font(.caption).foregroundStyle(Tema.texto2)
                Button { processo.parar() } label: {
                    Label("Parar", systemImage: "stop.fill").frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent).tint(.red)
            } else {
                BotaoPrincipal(titulo: "Gerar ata", icone: "sparkles", desativado: !podeGerar) { gerar() }
                if let m = motivo { Text(m).font(.caption).foregroundStyle(Tema.texto2) }
            }
        }
    }

    // MARK: lógica

    private var precisaTrilha: Bool {
        guard let e = entrada, e.trilhas.count >= 2 else { return false }
        return trilhaEu < 0 || trilhaEu >= e.trilhas.count
    }

    private func nomeTrilha(_ t: Trilhas.Info) -> String {
        let base = "Trilha \(t.indice + 1)"
        return t.nome.isEmpty ? base : base + " · " + t.nome
    }

    private func papelTrilha(_ t: Trilhas.Info, total: Int) -> String {
        if trilhaEu == t.indice { return "Eu (meu microfone)" }
        if trilhaEu >= 0 && trilhaEu < total { return "Participantes" }
        return "toque no círculo se esta for a sua"
    }

    private var podeGerar: Bool { entrada != nil && logado && !precisaTrilha && !analisando }

    private var motivo: String? {
        if entrada == nil { return "Escolha um arquivo para começar." }
        if !logado { return "Entre na nuvem em Ajustes." }
        if precisaTrilha { return "Marque qual trilha é o seu microfone." }
        return nil
    }

    private func descricao(_ e: Entrada) -> String {
        if e.ehTexto { return "Transcrição pronta: vai direto para a ata." }
        var p: [String] = []
        if let d = formatarDuracao(e.duracao) { p.append(d) }
        switch e.trilhas.count {
        case 0: p.append("não consegui ler as trilhas; tento transcrever assim mesmo")
        case 1: p.append("uma trilha de áudio (sem separar quem fala)")
        default: p.append("\(e.trilhas.count) trilhas de áudio")
        }
        if let d = e.duracao, d > 0 {
            // medido no GerAta 0.2.0: 2 h com duas trilhas em 28m46s (cerca de 14 min por trilha de 2 h)
            let minutos = max(1, Int((d / 8.3 * Double(max(1, min(2, e.trilhas.count))) / 60).rounded()))
            p.append("transcrição: até uns \(minutos) min")
        }
        return p.joined(separator: " · ")
    }

    private func relogio(_ s: TimeInterval) -> String {
        let t = Int(max(0, s))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t % 3600 / 60, t % 60)
                         : String(format: "%d:%02d", t / 60, t % 60)
    }

    private func limpar() {
        Amostra.shared.parar()
        if acessoAberto, let e = entrada { e.url.stopAccessingSecurityScopedResource() }
        acessoAberto = false
        entrada = nil
        contexto = ""
    }

    private func escolher(_ url: URL) {
        limpar()
        acessoAberto = url.startAccessingSecurityScopedResource()
        let nome = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        if ["srt", "txt", "md", "text"].contains(ext) {
            entrada = Entrada(url: url, nome: nome, ehTexto: true, trilhas: [], duracao: nil)
            return
        }
        analisando = true
        Task {
            let trilhas = await Trilhas.listar(url)
            let duracao = await Trilhas.duracao(url)
            entrada = Entrada(url: url, nome: nome, ehTexto: false, trilhas: trilhas, duracao: duracao)
            analisando = false
        }
    }

    private func gerar() {
        guard let e = entrada else { return }
        Amostra.shared.parar()
        let eu: Int? = (e.trilhas.count >= 2 && trilhaEu >= 0 && trilhaEu < e.trilhas.count) ? trilhaEu : nil
        processo.iniciar(e, Processo.Opcoes(trilhaEu: eu, tipo: tipo, contexto: contexto, modelo: modelo), reunioes: reunioes)
    }
}
