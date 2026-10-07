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
        var modo: String?            // "tudo" ou "blocos"
        var blocos: Int?
        var comprimido: Bool?
        var enxuta: Bool?
        var coube: Int?              // % da transcrição que entrou (modo tudo)
        var menorLivre: UInt64?      // menor folga de memória vista durante o teste
        var loop: Bool?              // parou sozinho porque o modelo entrou em repetição
    }

    @AppStorage("modeloEscolhido") private var escolhido = ""
    @AppStorage("contexto") private var contexto = 8192
    @AppStorage("maxSaida") private var maxSaida = 800
    @AppStorage("naGPU") private var naGPU = true
    @AppStorage("emAndamento") private var emAndamento = ""
    @AppStorage("ultimaLivre") private var ultimaLivre = 0.0
    @AppStorage("modo") private var modo = "tudo"
    @AppStorage("comprimido") private var comprimido = false
    @AppStorage("enxuta") private var enxuta = true
    @AppStorage("nucleosFortes") private var nucleosFortes = false

    @State private var texto = Transcricao.exemplo
    @State private var origem = "texto de exemplo"
    @State private var resposta = ""
    @State private var etapa = ""
    @State private var andamento: Double?
    @State private var rodando = false
    @State private var parando = false
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
                            Text(caiu)
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
            .safeAreaInset(edge: .bottom) {
                if rodando {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(etapa).font(.subheadline.weight(.semibold))
                        Text(memoriaCurta).font(.caption.monospacedDigit()).foregroundStyle(Tema.texto2)
                        Button { parar.ligado = true; parando = true } label: {
                            Label(parando ? "Parando…" : "Parar", systemImage: "stop.fill")
                                .font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.glassProminent).tint(.red)
                    }
                    .padding(14)
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))
                    .padding(.horizontal).padding(.bottom, 6)
                }
            }
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
                if !emAndamento.isEmpty {
                    var t = "Estava fazendo: \(emAndamento). "
                    if ultimaLivre > 0 && ultimaLivre < 0.4 {
                        t += String(format: "A última leitura mostrava só %.2f GB livres: o mais provável é falta de memória. Tente um contexto menor ou o contexto comprimido.", ultimaLivre)
                    } else if ultimaLivre > 0 {
                        t += String(format: "A última leitura mostrava %.2f GB livres. Se foi você que fechou o app, ignore; se ele fechou sozinho, foi a memória de vídeo: tente um contexto ou um modelo menor.", ultimaLivre)
                    } else {
                        t += "Se ele fechou sozinho, o mais provável é falta de memória."
                    }
                    caiu = t; emAndamento = ""
                }
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
            Text("\(origem) · \(texto.count) caracteres" + (enxuta ? " · enxuta: \(Transcricao.enxugar(texto).count)" : ""))
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
            Picker("Modo", selection: $modo) {
                Text("Tudo de uma vez").tag("tudo")
                Text("Por blocos").tag("blocos")
            }
            .pickerStyle(.segmented)
            Picker("Contexto (quanto texto o modelo lê de uma vez)", selection: $contexto) {
                Text("4 mil").tag(4096)
                Text("8 mil").tag(8192)
                Text("16 mil").tag(16384)
                Text("24 mil").tag(24576)
                Text("32 mil").tag(32768)
            }
            Picker("Tamanho máximo da resposta", selection: $maxSaida) {
                Text("Curta (400)").tag(400)
                Text("Média (800)").tag(800)
                Text("Longa (1500)").tag(1500)
                Text("Bem longa (2500)").tag(2500)
            }
            Toggle("Rodar na GPU", isOn: $naGPU)
            Toggle("Contexto comprimido (metade da memória)", isOn: $comprimido)
            Toggle("Transcrição enxuta", isOn: $enxuta)
            Toggle("Só os núcleos fortes (\(max(2, MotorLLM.nucleosFortes)))", isOn: $nucleosFortes)
            Text("Tudo de uma vez: se a transcrição não couber no contexto, entra só o começo e a medição diz quanto coube. Por blocos: resume trecho a trecho e junta no fim. Enxuta: tira falas inventadas no silêncio e deixa um horário por minuto.")
                .font(.caption).foregroundStyle(Tema.texto2)
        }
    }

    private var cartaoRodar: some View {
        Cartao {
            if rodando {
                if let andamento { ProgressView(value: andamento).tint(Tema.acento) }
                else { ProgressView().progressViewStyle(.linear).tint(Tema.acento) }
                Text(etapa).font(.subheadline)
                Text("Não feche o GerAta enquanto o teste roda.").font(.caption).foregroundStyle(Tema.texto2)
            } else {
                BotaoPrincipal(titulo: "Resumir", icone: "play.fill",
                               desativado: modeloEscolhido == nil || texto.isEmpty, acao: { rodarCom(forcar: false) })
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
                    Text(titulo(m))
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

    private var memoriaCurta: String {
        "Em uso \(Medidor.texto(Medidor.usada())) · livres \(Medidor.texto(Medidor.livre()))"
    }

    private func atualizarMemoria() {
        let livre = Medidor.livre()
        memoria = "Memória do app: \(Medidor.texto(Medidor.usada())) em uso · \(Medidor.texto(livre)) livres para o app · aparelho com \(Medidor.texto(Medidor.totalDoAparelho)). O arquivo do modelo não entra em \"em uso\"; ele aparece como queda nos livres."
        if rodando { ultimaLivre = Double(livre) / 1_073_741_824 }
    }

    private static let sistema = "Você escreve atas de reunião em português do Brasil. Use só o que está no texto recebido. Não invente nomes, números, datas nem prazos. Não copie a transcrição: resuma."

    private static func pedidoAta(_ oQue: String) -> String {
        """
        Com base \(oQue) acima, escreva a ata da reunião em português, neste formato:

        ## Resumo
        (até 6 linhas)

        ## Decisões
        (uma por linha, com o horário entre colchetes quando houver)

        ## Pendências
        (uma por linha: o que, quem e até quando, se foi dito)

        ## Assuntos
        (um por linha, com o horário de início entre colchetes e uma frase sobre o que foi dito)

        Omita a seção que não tiver conteúdo. Escreva só a ata.
        """
    }

    /// Junta linhas até o limite de tokens. Devolve os grupos (um só se `varios` for falso: o que couber do começo).
    private func agrupar(_ linhas: [String], _ tokens: [Int], limite: Int, varios: Bool) -> [[String]] {
        var grupos: [[String]] = []
        var atual: [String] = []
        var soma = 0
        for i in linhas.indices {
            let t = (i < tokens.count ? tokens[i] : 0) + 1
            if soma + t > limite && !atual.isEmpty {
                grupos.append(atual)
                if !varios { return grupos }
                atual = []; soma = 0
            }
            if t > limite { continue }          // uma linha sozinha maior que o limite: fica de fora
            atual.append(linhas[i]); soma += t
        }
        if !atual.isEmpty { grupos.append(atual) }
        return grupos
    }

    private func rodarCom(forcar: Bool) {
        guard let m = modeloEscolhido else { return }
        let sinal = Sinal()
        parar = sinal
        rodando = true; parando = false; resposta = ""; andamento = nil; etapa = "Abrindo o modelo"
        let porBlocos = modo == "blocos"
        emAndamento = "\(m.nome), \(porBlocos ? "por blocos" : "tudo de uma vez"), contexto \(contexto)\(comprimido ? " comprimido" : ""), \(naGPU ? "GPU" : "processador")"
        ultimaLivre = Double(Medidor.livre()) / 1_073_741_824
        UIApplication.shared.isIdleTimerDisabled = true
        let arquivo = Modelos.arquivo(m.arquivo)
        let usarEnxuta = enxuta
        let base = usarEnxuta ? Transcricao.enxugar(texto) : texto
        let linhas = base.split(separator: "\n").map(String.init)
        let ctx = contexto, saida = min(maxSaida, contexto / 2), gpu = naGPU, caracteres = texto.count
        var op = MotorLLM.Opcoes()
        op.contexto = ctx; op.maxSaida = saida; op.naGPU = gpu
        op.kvComprimido = comprimido; op.nucleosFortes = nucleosFortes; op.forcar = forcar
        let opcoes = op
        Task {
            var med = Medicao(modelo: m.nome, naGPU: gpu, contexto: ctx, caracteres: caracteres, tokensEntrada: 0,
                              tokensSaida: 0, cortado: false, segCarregar: 0, segEntrada: 0, segSaida: 0,
                              memoriaModelo: 0, memoriaPico: 0, resultado: "ok")
            med.modo = porBlocos ? "blocos" : "tudo"
            med.comprimido = opcoes.kvComprimido; med.enxuta = usarEnxuta
            var faltouMemoria: String?
            do {
                let tokens = try await MotorLLM.shared.contar(arquivo: arquivo, naGPU: gpu, linhas: linhas)
                let fixos = try await MotorLLM.shared.contar(arquivo: arquivo, naGPU: gpu,
                                                             linhas: [Self.sistema, Self.pedidoAta("na transcrição")])
                let reserva = fixos.reduce(0, +) + 160        // instruções + marcadores de conversa + folga
                var escrito = ""

                // uma chamada ao modelo, somando tempos e memória na medição
                func chamar(_ pedido: String, _ o: MotorLLM.Opcoes, _ rotulo: String, mostra: Bool) async throws -> MotorLLM.Resultado {
                    let antes = escrito
                    let r = try await MotorLLM.shared.gerar(
                        arquivo: arquivo, sistema: Self.sistema, usuario: pedido, opcoes: o,
                        parar: { sinal.ligado },
                        andamento: { f in Task { @MainActor in etapa = rotulo + ": lendo"; andamento = f; atualizarMemoria() } },
                        texto: { s in Task { @MainActor in
                            etapa = rotulo + ": escrevendo"; andamento = nil
                            resposta = antes + MotorLLM.semPensamento(s)
                            atualizarMemoria()
                        } })
                    med.tokensEntrada += Int(r.estat.tokensEntrada); med.tokensSaida += Int(r.estat.tokensSaida)
                    if r.estat.cortado == 1 { med.cortado = true }
                    med.segCarregar += r.estat.segCarregar; med.segEntrada += r.estat.segEntrada; med.segSaida += r.estat.segSaida
                    if med.memoriaModelo == 0 { med.memoriaModelo = r.memoriaDepoisDeAbrir }
                    med.memoriaPico = max(med.memoriaPico, r.picoMemoria)
                    med.menorLivre = min(med.menorLivre ?? .max, r.menorLivre)
                    if r.loop { med.loop = true }
                    if mostra { escrito = antes + r.texto + "\n\n" }
                    return r
                }

                if porBlocos {
                    let limite = max(500, min(6000, ctx - 700 - reserva))
                    let grupos = agrupar(linhas, tokens, limite: limite, varios: true)
                    med.blocos = grupos.count
                    var notas: [String] = []
                    var oBloco = opcoes
                    oBloco.maxSaida = 600
                    var interrompido = false
                    for (i, g) in grupos.enumerated() {
                        let pedido = "TRECHO \(i + 1) DE \(grupos.count) DA TRANSCRIÇÃO:\n" + g.joined(separator: "\n")
                            + "\nFIM DO TRECHO.\n\nAcima está um trecho de uma reunião. Liste em tópicos curtos, com o horário entre colchetes: assuntos tratados, decisões, pendências (o que, quem, até quando), números e datas citados. Só o que está no trecho. Não escreva introdução nem conclusão."
                        escrito += "— Anotações do bloco \(i + 1) de \(grupos.count) —\n"
                        let r = try await chamar(pedido, oBloco, "Bloco \(i + 1) de \(grupos.count)", mostra: true)
                        notas.append(r.texto)
                        if r.interrompido { interrompido = true; break }
                    }
                    if interrompido {
                        med.resultado = "interrompido"
                    } else {
                        // as anotações precisam caber junto com a ata
                        let juntas = notas.joined(separator: "\n").split(separator: "\n").map(String.init)
                        let tk = try await MotorLLM.shared.contar(arquivo: arquivo, naGPU: gpu, linhas: juntas)
                        let cabem = agrupar(juntas, tk, limite: max(300, ctx - saida - reserva), varios: false)
                        let usadas = cabem.first ?? []
                        if usadas.count < juntas.count { med.cortado = true }
                        let pedido = "ANOTAÇÕES DA REUNIÃO, EM ORDEM:\n" + usadas.joined(separator: "\n")
                            + "\nFIM DAS ANOTAÇÕES.\n\n" + Self.pedidoAta("nas anotações")
                        escrito += "— Ata —\n"
                        let r = try await chamar(pedido, opcoes, "Ata", mostra: true)
                        if r.interrompido { med.resultado = "interrompido" }
                    }
                } else {
                    let cabem = agrupar(linhas, tokens, limite: max(200, ctx - saida - reserva), varios: false)
                    let usadas = cabem.first ?? []
                    med.coube = linhas.isEmpty ? 100 : Int((Double(usadas.count) / Double(linhas.count) * 100).rounded())
                    let pedido = "TRANSCRIÇÃO DA REUNIÃO:\n" + usadas.joined(separator: "\n")
                        + "\nFIM DA TRANSCRIÇÃO.\n\n" + Self.pedidoAta("na transcrição")
                    let r = try await chamar(pedido, opcoes, "Ata", mostra: true)
                    if r.interrompido { med.resultado = "interrompido" }
                }
                resposta = escrito.trimmingCharacters(in: .whitespacesAndNewlines)
                if med.loop == true { med.resultado = "parou sozinho: o modelo entrou em repetição" }
            } catch let e as MotorLLM.ErroMemoria {
                faltouMemoria = e.texto
                med.resultado = "não rodou: a conta de memória não fechou"
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                med.resultado = "erro: " + msg
                aviso = msg
            }
            medicoes.append(med); gravarMedicoes()
            emAndamento = ""
            rodando = false; andamento = nil; etapa = ""
            UIApplication.shared.isIdleTimerDisabled = false
            atualizarMemoria()
            if let faltouMemoria {
                confirmar = Confirmacao(titulo: "Pode faltar memória", mensagem: faltouMemoria,
                                        botao: "Rodar mesmo assim", destrutivo: false) { rodarCom(forcar: true) }
            }
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
        s += " · memória em uso: pico \(Medidor.texto(m.memoriaPico))"
        if let l = m.menorLivre, l != .max { s += ", menor folga \(Medidor.texto(l))" }
        if let c = m.coube, c < 100 { s += " · SÓ \(c)% DA TRANSCRIÇÃO COUBE" }
        if m.cortado { s += " · TEXTO CORTADO (não coube no contexto)" }
        if m.resultado != "ok" { s += " · " + m.resultado }
        return s
    }

    private func titulo(_ m: Medicao) -> String {
        var t = "\(m.modelo) · \(m.naGPU ? "GPU" : "processador") · contexto \(m.contexto)"
        if m.comprimido == true { t += " comprimido" }
        if let modo = m.modo { t += modo == "blocos" ? " · por blocos (\(m.blocos ?? 0))" : " · tudo de uma vez" }
        if m.enxuta == true { t += " · enxuta" }
        return t
    }

    private func relatorio() -> String {
        var l = ["GerAta — medições", memoria, "Motor: " + MotorLLM.shared.motor.trimmingCharacters(in: .whitespacesAndNewlines), ""]
        for m in medicoes {
            l.append("\(m.quando.formatted(.dateTime.day().month().hour().minute())) · \(titulo(m)) · \(m.caracteres) caracteres")
            l.append("  " + linha(m))
        }
        return l.joined(separator: "\n")
    }
}
