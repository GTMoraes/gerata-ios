import SwiftUI

struct AjustesView: View {
    @Environment(Reunioes.self) private var reunioes
    @Environment(Processo.self) private var processo

    @AppStorage("seuNome") private var seuNome = ""
    @AppStorage("modeloPadrao") private var modeloPadrao = "opus"
    @AppStorage("glossario") private var glossario = ""

    @State private var usuario = ""
    @State private var senha = ""
    @State private var logado: String?
    @State private var entrando = false
    @State private var estadoClaude = ""
    @State private var aviso: String?
    @State private var confirmar: Confirmacao?
    @State private var preparo: String?
    @State private var preparoFracao: Double?
    @State private var tamanhoModelo: Int64 = 0
    @State private var tamanhoReunioes: Int64 = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    cartaoNuvem
                    cartaoVoce
                    cartaoGlossario
                    cartaoTranscricao
                    cartaoArmazenamento
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .telaEscura()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Ajustes")
            .confirmar($confirmar)
            .alert("Aviso", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(aviso ?? "") }
            .onAppear {
                logado = Nuvem.shared.usuario
                medir()
                if logado != nil { conferirClaude() }
            }
        }
    }

    // MARK: nuvem

    private var cartaoNuvem: some View {
        Cartao(titulo: "Nuvem", icone: "cloud.fill") {
            if let logado {
                Text("Conectado como \(logado)").font(.subheadline)
                if !estadoClaude.isEmpty {
                    Text(estadoClaude).font(.caption).foregroundStyle(Tema.texto2)
                }
                Button {
                    Task {
                        await Nuvem.shared.sair()
                        self.logado = nil
                        estadoClaude = ""
                    }
                } label: {
                    Label("Sair da nuvem", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.glass)
            } else {
                Text("O mesmo usuário e senha do Estúdio. A senha fica guardada no cofre do iPhone (Keychain).")
                    .font(.footnote).foregroundStyle(Tema.texto2)
                TextField("Usuário", text: $usuario)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(10).background(.white.opacity(0.06), in: .rect(cornerRadius: 12))
                SecureField("Senha", text: $senha)
                    .padding(10).background(.white.opacity(0.06), in: .rect(cornerRadius: 12))
                BotaoPrincipal(titulo: entrando ? "Entrando…" : "Entrar", icone: "person.fill.checkmark",
                               desativado: entrando || usuario.trimmingCharacters(in: .whitespaces).isEmpty || senha.isEmpty) {
                    entrar()
                }
            }
        }
    }

    private func entrar() {
        entrando = true
        let u = usuario.trimmingCharacters(in: .whitespaces)
        let s = senha
        Task {
            do {
                try await Nuvem.shared.entrar(usuario: u, senha: s)
                logado = u
                senha = ""
                conferirClaude()
            } catch {
                aviso = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            entrando = false
        }
    }

    private func conferirClaude() {
        estadoClaude = "Conferindo o Claude na nuvem…"
        Task {
            do {
                let e = try await Nuvem.shared.estadoClaude()
                if !e.pronto { estadoClaude = "O Claude ainda não está configurado no servidor (falta a chave do plano)." }
                else if !e.permitido { estadoClaude = "Esta conta não tem permissão para gerar atas (só o administrador)." }
                else { estadoClaude = "Claude pronto para gerar atas." }
            } catch {
                estadoClaude = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: você

    private var cartaoVoce: some View {
        Cartao(titulo: "Atas", icone: "doc.text") {
            Text("Seu nome, como deve aparecer na ata no lugar de “Eu” (gravações com duas trilhas).")
                .font(.footnote).foregroundStyle(Tema.texto2)
            TextField("Seu nome", text: $seuNome)
                .autocorrectionDisabled()
                .padding(10).background(.white.opacity(0.06), in: .rect(cornerRadius: 12))
            Text("Modelo padrão").font(.subheadline)
            Picker("Modelo padrão", selection: $modeloPadrao) {
                Text("Opus (melhor)").tag("opus")
                Text("Sonnet (mais rápido)").tag("sonnet")
            }
            .pickerStyle(.segmented)
            Text("Medido numa reunião de 2 h: o Opus gastou cerca de 3 pontos da sessão de 5 h do plano; o Sonnet, pouco mais de 1.")
                .font(.caption).foregroundStyle(Tema.texto2)
        }
    }

    private var cartaoGlossario: some View {
        Cartao(titulo: "Glossário", icone: "character.book.closed") {
            Text("Nomes e termos que aparecem nas suas reuniões, separados por vírgula. A transcrição erra a grafia (“lead” vira “líder”); com a lista, o Claude corrige na ata.")
                .font(.footnote).foregroundStyle(Tema.texto2)
            TextEditor(text: $glossario)
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()
                .padding(6).background(.white.opacity(0.06), in: .rect(cornerRadius: 12))
        }
    }

    // MARK: transcrição

    private var cartaoTranscricao: some View {
        Cartao(titulo: "Transcrição no iPhone", icone: "waveform") {
            let id = TranscritorLocal.modeloPadrao
            let baixado = TranscritorLocal.pastaDoModelo(id) != nil
            Text(textoModelo(baixado))
                .font(.footnote).foregroundStyle(Tema.texto2)
            if let preparo {
                if let f = preparoFracao { ProgressView(value: min(1, max(0, f))).tint(Tema.acento) }
                else { ProgressView().progressViewStyle(.linear).tint(Tema.acento) }
                Text(preparo).font(.caption)
            } else {
                Button { preparar() } label: {
                    Label(baixado && TranscritorLocal.compilado(id) ? "Modelo pronto" : "Deixar pronto agora", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.glass)
                .disabled(processo.rodando || (baixado && TranscritorLocal.compilado(id)))
                if baixado {
                    Button(role: .destructive) {
                        confirmar = Confirmacao(titulo: "Apagar o modelo de transcrição?",
                                                mensagem: "Libera \(formatarBytes(tamanhoModelo)). Ele é baixado de novo na próxima transcrição.") {
                            Task {
                                await TranscritorLocal.shared.apagarModelos()
                                medir()
                            }
                        }
                    } label: {
                        Label("Apagar o modelo", systemImage: "trash").frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                    .disabled(processo.rodando)
                }
            }
            Text("Depois de instalar ou atualizar o app, a primeira transcrição leva 3 a 4 minutos a mais: o iOS prepara o modelo para este iPhone.")
                .font(.caption).foregroundStyle(Tema.texto2)
        }
    }

    private func textoModelo(_ baixado: Bool) -> String {
        let base = "Whisper Large v3 Turbo, em português. "
        if baixado { return base + "Modelo no iPhone: " + formatarBytes(tamanhoModelo) + "." }
        return base + "O modelo (≈ 630 MB) é baixado na primeira transcrição."
    }

    private func preparar() {
        preparo = "Preparando"
        preparoFracao = nil
        Task {
            do {
                try await TranscritorLocal.shared.prepararDeAntemao(TranscritorLocal.modeloPadrao) { m, f in
                    Task { @MainActor in
                        preparo = m
                        preparoFracao = f
                    }
                }
            } catch {
                aviso = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            preparo = nil
            medir()
        }
    }

    // MARK: armazenamento

    private var cartaoArmazenamento: some View {
        Cartao(titulo: "Armazenamento", icone: "internaldrive") {
            Text("\(reunioes.lista.count) reuniões guardadas · \(formatarBytes(tamanhoReunioes))")
                .font(.subheadline)
            Text("Ficam no app Arquivos, em No Meu iPhone › GerAta › Reuniões: uma pasta por reunião, com a ata (.md) e a transcrição (.txt). Para apagar uma, abra-a em Resultados.")
                .font(.footnote).foregroundStyle(Tema.texto2)
            let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
            Text("GerAta \(v)").font(.caption).foregroundStyle(Tema.texto2)
        }
    }

    private func medir() {
        tamanhoModelo = TranscritorLocal.tamanhoEmDisco()
        tamanhoReunioes = reunioes.tamanhoEmDisco()
    }
}
