import SwiftUI

/// O que ainda está guardado na nuvem (gravação e transcrição das reuniões por link). Some sozinho depois
/// de alguns dias; a cópia da transcrição que veio para o iPhone fica em Resultados.
struct GravacoesView: View {
    @Environment(Gravador.self) private var gravador
    @Environment(Reunioes.self) private var reunioes

    @State private var confirmar: Confirmacao?
    @State private var aviso: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Cartao {
                    Text("A nuvem guarda a gravação e a transcrição por \(gravador.dias) dias e depois apaga sozinha. A transcrição que já veio para o iPhone continua em Resultados.")
                        .font(.footnote).foregroundStyle(Tema.texto2)
                }
                if gravador.terminadas.isEmpty {
                    Cartao { Text("Nada guardado na nuvem.").font(.subheadline) }
                }
                ForEach(gravador.terminadas) { g in
                    linha(g)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .telaEscura()
        .navigationTitle("Na nuvem")
        .navigationBarTitleDisplayMode(.inline)
        .confirmar($confirmar)
        .alert("Aviso", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(aviso ?? "") }
        .task { await gravador.atualizar(reunioes: reunioes) }
        .onChange(of: gravador.erro) { _, novo in
            if let novo { aviso = novo; gravador.erro = nil }
        }
    }

    @ViewBuilder
    private func linha(_ g: Gravacao) -> some View {
        let local = reunioes.lista.first { $0.gravacaoID == g.id }
        Cartao {
            Text(titulo(g, local)).font(.headline)
            Text(detalhe(g)).font(.caption).foregroundStyle(Tema.texto2)
            if g.fase == "erro", let d = g.detalhe, !d.isEmpty {
                Text(d).font(.caption).foregroundStyle(.yellow)
            }
            if g.qualidade == "ao_vivo" {
                Text(g.detalhe ?? "Transcrição de reserva: o texto perdeu trechos.")
                    .font(.caption).foregroundStyle(.yellow)
                Button {
                    Task { await gravador.refazer(g, reunioes: reunioes) }
                } label: {
                    Label("Refazer a transcrição", systemImage: "arrow.clockwise").frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.glass)
            }
            if let local {
                NavigationLink {
                    ReuniaoView(id: local.id)
                } label: {
                    Label("Abrir", systemImage: "doc.text").frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.glass)
            }
            Button(role: .destructive) {
                confirmar = Confirmacao(titulo: "Apagar da nuvem?",
                                        mensagem: "A gravação e a transcrição saem do servidor e não dá para refazer depois. A cópia no iPhone, em Resultados, continua.") {
                    Task { await gravador.apagar(g) }
                }
            } label: {
                Label("Apagar da nuvem", systemImage: "trash").frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.glass)
        }
    }

    private func titulo(_ g: Gravacao, _ local: Reuniao?) -> String {
        if let local { return local.titulo }
        return "Reunião no " + g.nomePlataforma
    }

    private func detalhe(_ g: Gravacao) -> String {
        var p: [String] = [g.nomePlataforma, g.textoDaFase]
        if let q = g.quando { p.append(q.formatted(.dateTime.day().month().hour().minute())) }
        if let d = formatarDuracao(g.duracao) { p.append(d) }
        return p.joined(separator: " · ")
    }
}
