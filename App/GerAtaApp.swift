import SwiftUI

@main
struct GerAtaApp: App {
    @State private var reunioes = Reunioes()
    @State private var processo = Processo()
    @State private var gravador = Gravador()

    var body: some Scene {
        WindowGroup {
            RaizView()
                .environment(reunioes)
                .environment(processo)
                .environment(gravador)
                .preferredColorScheme(.dark)
                .tint(Tema.acento)
        }
    }
}

struct RaizView: View {
    @State private var aba = 0

    var body: some View {
        TabView(selection: $aba) {
            Tab("Nova", systemImage: "plus.circle.fill", value: 0) {
                NovaView()
            }
            Tab("Resultados", systemImage: "tray.full.fill", value: 1) {
                ResultadosView()
            }
            Tab("Ajustes", systemImage: "gearshape.fill", value: 2) {
                AjustesView()
            }
        }
    }
}
