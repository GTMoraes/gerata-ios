import SwiftUI

@main
struct GerAtaApp: App {
    @State private var modelos = Modelos()

    var body: some Scene {
        WindowGroup {
            TesteView()
                .environment(modelos)
                .preferredColorScheme(.dark)
                .tint(Tema.acento)
        }
    }
}
