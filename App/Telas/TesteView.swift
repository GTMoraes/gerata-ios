import SwiftUI
import UniformTypeIdentifiers

/// Etapa 1: medir o que o iPhone aguenta. Escolhe um modelo, um texto, e mostra tempo e memória.
struct TesteView: View {
    @Environment(Modelos.self) private var modelos

    struct Medicao: Codable, Identifiable {
        var id = UUID()
        var quando = Date()
        var modelo: String
        var naGPU: Bool
        var contexto: Int
        var caracteres: Int
        var tokensEntrada: Int
        var tokensSaida: Int
        var cortado: Bool
        var segCarregar: Double
        var segEntrada: Double
        var segSaida: Double
        var memoriaModelo: UInt64
        var memoriaPico: UInt64
        var resultado: String        // "ok", "interrompido" ou o erro
    }

    @AppStorage("modeloEscolhido") private var escolhido = ""
    @AppStorage("contexto") private var contexto = 8192
    @AppStorage("maxSaida") private var maxSaida = 800
    @AppStorage("naGPU") private var naGPU = true
    @AppStorage("emAndamento") private var emAndamento = ""

    @State private var texto = Transcricao.exemplo
    @State private var origem = "texto de exemplo"
    @State private var resposta = ""
    @State private var etapa = ""
    @State private var andamento: Double?
    @State private var rodando = false
    @State private var parar = Sinal()
    @State private var medicoes: [Medicao] = []
    @State private var memoria = ""
    @State private var aviso: String?
    @State private var caiu: String?
    @State private var escolhendoArquivo = false
    @State private var novoEndereco = ""
    @State private var confirmar: Confirmacao?

    private let relogio = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    final class Sinal: @unchecked Sendable { var ligado = false }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let caiu {
                        Cartao {
                            Label("Na última tentativa o app foi encerrado", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.yellow)
                            Text("Estava fazendo: \(caiu). O mais provável é falta de memória. Tente um contexto menor ou um modelo menor.")
                                .font(.footnote).foregroundStyle(Tema.texto2)
                            Button("Entendi") { self.caiu = nil }.buttonStyle(.glass)
                        }
                    }
                    cartaoModelos
                    cartaoTexto
                    cartaoAjustes
                    cartaoRodar
                    if !resposta.isEmpty { cartaoResposta }
                    if !medicoes.isEmpty { cartaoMedicoes }
                    Cartao(titulo: "Aparelho", icone: "iphone") {
                        Text(memoria).font(.footnote.monospacedDigit()).foregroundStyle(Tema.texto2)
                        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
                        Text("GerAta \(v) · etapa 1 (medição)").font(.caption).foregroundStyle(Tema.texto2)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .telaEscura()
            .navigationTitle("GerAta")
            .confirmar($confirmar)
            .alert("Aviso", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(aviso ?? "") }
            .fileImporter(isPresented: $escolhendoArquivo, allowedContentTypes: [.plainText, .text, .data]) { r in
                switch r {
                case .success(let u):
                    do { texto = try Transcricao.ler(u); origem = u.lastPathComponent }
                    catch { aviso = "Não consegui ler o arquivo: \(error.localizedDescription)" }
                case .failure(let e): aviso = "Não consegui abrir o arquivo: \(e.localizedDescription)"
                }
            }
            .onAppear {
                if !emAndamento.isEmpty { caiu = emAndamento; emAndamento = "" }
                if let d = UserDefaults.standard.data(forKey: "medicoes"),
                   let l = try? JSONDecoder().decode([Medicao].self, from: d) { medicoes = l }
                atualizarMemoria()
            }
            .onReceive(relogio) { _ in atualizarMemoria() }
            .onChange(of: modelos.erro) { _, novo in
                if let novo { aviso = novo; modelos.erro = nil }
            }
        }
    }

    // MARK: cartões

    private var cartaoModelos: some View {
        Cartao(titulo: "Modelo", icone: "cpu") {
            ForEach(modelos.todos) { m in
                linhaModelo(m)
            }
            .id(modelos.versao)
            HStack(spacing: 8) {
                TextField("Endereço de outro .gguf no Hugging Face", text: $novoEndereco)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .padding(10).background(.white.opacity(0.06), in: .rect(cornerRadius: 12))
                Button("Adicionar") {
                    if let e = modelos.adicionar(novoEndereco) { aviso = e } else { novoEndereco = "" }
                }
                .buttonStyle(.glass)
                .disabled(novoEndereco.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Os modelos ficam guardados no iPhone. Baixe pelo Wi-Fi: são arquivos de alguns GB.")
                .font(.caption).foregroundStyle(Tema.texto2)
        }
    }

    @ViewBuilder
    private func linhaModelo(_ m: Modelos.Modelo) -> some View {
        let tem = modelos.baixado(m)
        let baixandoEste = modelos.baixando == m.arquivo
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    if tem { escolhido = m.arquivo }
                } label: {
                    Image(systemName: escolhido == m.arquivo && tem ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(tem ? Tema.acento : Tema.texto2)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.nome).font(.subheadline.weight(.semibold))
                    Text(tem ? "\(m.nota) · no iPhone: \(formatarBytes(modelos.tamanho(m)))" : m.nota)
                        .font(.caption).foregroundStyle(Tema.texto2)
                }
                Spacer(minLength: 0)
                if baixandoEste {
                    Button("Parar") { modelos.cancelar() }.buttonStyle(.glass)
                } else if tem {
                    Button(role: .destructive) {
                        confirmar = Confirmacao(titulo: "Apagar “\(m.nome)”?",
                                                mensagem: "O arquivo do modelo sai do iPhone. Dá para baixar de novo depois.") {
                            if escolhido == m.arquivo { MotorLLM.shared.fechar(); escolhido = "" }
                            modelos.apagar(m)
                            if !Modelos.sugeridos.contains(m) { modelos.tirarDaLista(m) }
                        }
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.glass)
                } else {
                    Button("Baixar") { modelos.baixar(m) }
                        .buttonStyle(.glass)
                        .disabled(modelos.baixando != nil)
                }
            }
            if baixandoEste {
                if modelos.total > 0 {
                    ProgressView(value: Double(modelos.recebido), total: Double(modelos.total)).tint(Tema.acento)
                    Text("\(formatarBytes(modelos.recebido)) de \(formatarBytes(modelos.total))")
                        .font(.caption2.monospacedDigit()).foregroundStyle(Tema.texto2)
                } else {
                    ProgressView().progressViewStyle(.linear).tint(Tema.acento)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var cartaoTexto: some View {
        Cartao(titulo: "Transcrição", icone: "text.quote") {
            Text("\(origem) · \(texto.count) caracteres")
                .font(.subheadline)
            Text(String(texto.prefix(220)) + (texto.count > 220 ? "…" : ""))
                .font(.caption).foregroundStyle(Tema.texto2).lineLimit(4)
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button { escolhendoArquivo = true } label: {
                        Label("Arquivo", systemImage: "folder.fill").frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                    Button {
                        if let s = UIPasteboard.general.string, !s.isEmpty { texto = s; origem = "texto colado" }
                        else { aviso = "Não há texto copiado." }
                    } label: {
                        Label("Colar", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                    Button { texto = Transcricao.exemplo; origem = "texto de exemplo" } label: {
                        Label("Exemplo", systemImage: "sparkles").frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                }
            }
            Text("Aceita .txt e .srt (a legenda que o Estúdio gera).")
                .font(.caption).foregroundStyle(Tema.texto2)
        }
    }

    private var cartaoAjustes: some View {
        Cartao(titulo: "Ajustes do teste", icone: "slider.horizontal.3") {
            Picker("Contexto (quanto texto o modelo lê de uma vez)", selection: $contexto) {
                Text("4 mil").tag(4096)
                Text("8 mil").tag(8192)
                Text("16 mil").tag(16384)
                Text("32 mil").tag(32768)
            }
            Picker("Tamanho máximo da resposta", selection: $maxSaida) {
                Text("Curta (400)").tag(400)
                Text("Média (800)").tag(800)
                Text("Longa (1500)").tag(1500)
            }
            Toggle("Rodar na GPU", isOn: $naGPU)
            Text("Contexto maior usa mais memória. Se o texto não couber, o fim dele é cortado e a medição avisa.")
                .font(.caption).foregroundStyle(Tema.texto2)
        }
    }

    private var cartaoRodar: some View {
        Cartao {
            if rodando {
                if let andamento { ProgressView(value: andamento).tint(Tema.acento) }
                else { ProgressView().progressViewStyle(.linear).tint(Tema.acento) }
                Text(etapa).font(.subheadline)
                Button("Parar", role: .destructive) { parar.ligado = true }.buttonStyle(.glass)
                Text("Não feche o GerAta enquanto o teste roda.").font(.caption).foregroundStyle(Tema.texto2)
            } else {
                BotaoPrincipal(titulo: "Resumir", icone: "play.fill",
                               desativado: modeloEscolhido == nil || texto.isEmpty, acao: rodar)
                if modeloEscolhido == nil {
                    Text("Baixe um modelo e marque-o na lista.").font(.caption).foregroundStyle(Tema.texto2)
                }
            }
        }
    }

    private var cartaoResposta: some View {
        Cartao(titulo: "Resposta", icone: "doc.text") {
            Text(resposta).font(.callout).textSelection(.enabled)
            Button {
                UIPasteboard.general.string = resposta
                aviso = "Resposta copiada."
            } label: {
                Label("Copiar", systemImage: "doc.on.doc").frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.glass)
        }
    }

    private var cartaoMedicoes: some View {
        Cartao(titulo: "Medições", icone: "stopwatch") {
            ForEach(medicoes.reversed()) { m in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(m.modelo) · \(m.naGPU ? "GPU" : "processador") · contexto \(m.contexto)")
                        .font(.caption.weight(.semibold))
                    Text(linha(m)).font(.caption2.monospacedDigit()).foregroundStyle(Tema.texto2)
                }
                .padding(.vertical, 2)
            }
            Button {
                UIPasteboard.general.string = relatorio()
                aviso = "Relatório copiado. Cole na conversa."
            } label: {
                Label("Copiar relatório", systemImage: "doc.on.doc").frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent).tint(Tema.acento)
            Button(role: .destructive) {
                confirmar = Confirmacao(titulo: "Apagar as medições?", mensagem: "A lista de medições é zerada.") {
                    medicoes = []; gravarMedicoes()
                }
            } label: {
                Label("Apagar medições", systemImage: "trash").frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.glass)
        }
    }

    // MARK: lógica

    private var modeloEscolhido: Modelos.Modelo? {
        modelos.todos.first { $0.arquivo == escolhido && modelos.baixado($0) }
    }

    private func atualizarMemoria() {
        memoria = "Memória do app: \(Medidor.texto(Medidor.usada())) em uso · \(Medidor.texto(Medidor.livre())) livres para o app · aparelho com \(Medidor.texto(Medidor.totalDoAparelho))"
    }

    private func rodar() {
        guard let m = modeloEscolhido else { return }
        let sinal = Sinal()
        parar = sinal
        rodando = true; resposta = ""; andamento = nil; etapa = "Abrindo o modelo"
        emAndamento = "\(m.nome), contexto \(contexto), \(naGPU ? "GPU" : "processador")"
        UIApplication.shared.isIdleTimerDisabled = true
        let sistema = "Você escreve atas de reunião em português do Brasil. Use só o que está na transcrição. Não invente nomes, números, datas nem prazos."
        let pedido = """
        Leia a transcrição abaixo e escreva, em português:

        ## Resumo
        (até 5 linhas)

        ## Decisões
        (uma por linha, com o horário entre colchetes quando houver)

        ## Pendências
        (uma por linha: o que, quem e até quando, se foi dito)

        Omita a seção que não tiver conteúdo.

        TRANSCRIÇÃO:
        \(texto)
        """
        let arquivo = Modelos.arquivo(m.arquivo)
        let ctx = contexto, saida = maxSaida, gpu = naGPU, caracteres = texto.count
        Task {
            var med = Medicao(modelo: m.nome, naGPU: gpu, contexto: ctx, caracteres: caracteres, tokensEntrada: 0,
                              tokensSaida: 0, cortado: false, segCarregar: 0, segEntrada: 0, segSaida: 0,
                              memoriaModelo: 0, memoriaPico: 0, resultado: "ok")
            do {
                let r = try await MotorLLM.shared.gerar(
                    arquivo: arquivo, sistema: sistema, usuario: pedido, contexto: ctx, maxSaida: saida,
                    temperatura: 0.2, naGPU: gpu,
                    parar: { sinal.ligado },
                    andamento: { f in Task { @MainActor in etapa = "Lendo a transcrição"; andamento = f } },
                    texto: { s in Task { @MainActor in etapa = "Escrevendo"; andamento = nil; resposta = MotorLLM.semPensamento(s) } })
                resposta = r.texto
                med.tokensEntrada = Int(r.estat.tokensEntrada); med.tokensSaida = Int(r.estat.tokensSaida)
                med.cortado = r.estat.cortado == 1
                med.segCarregar = r.estat.segCarregar; med.segEntrada = r.estat.segEntrada; med.segSaida = r.estat.segSaida
                med.memoriaModelo = r.memoriaDepoisDeAbrir; med.memoriaPico = r.picoMemoria
                med.resultado = r.interrompido ? "interrompido" : "ok"
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                med.resultado = "erro: " + msg
                aviso = msg
            }
            medicoes.append(med); gravarMedicoes()
            emAndamento = ""
            rodando = false; andamento = nil; etapa = ""
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func gravarMedicoes() {
        if let d = try? JSONEncoder().encode(medicoes) { UserDefaults.standard.set(d, forKey: "medicoes") }
    }

    private func linha(_ m: Medicao) -> String {
        let vEntrada = m.segEntrada > 0 ? Double(m.tokensEntrada) / m.segEntrada : 0
        let vSaida = m.segSaida > 0 ? Double(m.tokensSaida) / m.segSaida : 0
        var s = String(format: "abrir %.1f s · ler %d tokens em %.1f s (%.0f/s) · escrever %d tokens em %.1f s (%.1f/s)",
                       m.segCarregar, m.tokensEntrada, m.segEntrada, vEntrada, m.tokensSaida, m.segSaida, vSaida)
        s += String(format: " · total %.1f s", m.segCarregar + m.segEntrada + m.segSaida)
        s += " · memória: modelo \(Medidor.texto(m.memoriaModelo)), pico \(Medidor.texto(m.memoriaPico))"
        if m.cortado { s += " · TEXTO CORTADO (não coube no contexto)" }
        if m.resultado != "ok" { s += " · " + m.resultado }
        return s
    }

    private func relatorio() -> String {
        var l = ["GerAta — medições", memoria, "Motor: " + MotorLLM.shared.motor.trimmingCharacters(in: .whitespacesAndNewlines), ""]
        for m in medicoes {
            l.append("\(m.quando.formatted(.dateTime.day().month().hour().minute())) · \(m.modelo) · \(m.naGPU ? "GPU" : "processador") · contexto \(m.contexto) · \(m.caracteres) caracteres")
            l.append("  " + linha(m))
        }
        return l.joined(separator: "\n")
    }
}
