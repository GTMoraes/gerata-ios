import Foundation
import AVFoundation

/// Trilhas de áudio de um arquivo (o OBS grava o microfone numa e o som da chamada noutra).
enum Trilhas {
    struct Info: Identifiable, Hashable {
        var id: Int { indice }
        var indice: Int          // 0, 1, ...
        var nome: String         // nome gravado no arquivo, se houver
        var canais: Int
    }

    /// Lista as trilhas de áudio. Arquivo sem áudio devolve lista vazia.
    static func listar(_ arquivo: URL) async -> [Info] {
        let asset = AVURLAsset(url: arquivo)
        guard let trilhas = try? await asset.loadTracks(withMediaType: .audio) else { return [] }
        var saida: [Info] = []
        for (i, t) in trilhas.enumerated() {
            var nome = ""
            if let itens = try? await t.load(.commonMetadata) {
                let titulos = AVMetadataItem.metadataItems(from: itens, filteredByIdentifier: .commonIdentifierTitle)
                if let primeiro = titulos.first, let valor = try? await primeiro.load(.stringValue) { nome = valor }
            }
            var canais = 0
            if let formatos = try? await t.load(.formatDescriptions), let f = formatos.first,
               let d = CMAudioFormatDescriptionGetStreamBasicDescription(f) {
                canais = Int(d.pointee.mChannelsPerFrame)
            }
            saida.append(Info(indice: i, nome: nome, canais: canais))
        }
        return saida
    }

    static func duracao(_ arquivo: URL) async -> Double? {
        let asset = AVURLAsset(url: arquivo)
        guard let d = try? await asset.load(.duration) else { return nil }
        let s = CMTimeGetSeconds(d)
        return s.isFinite && s > 0 ? s : nil
    }

    /// Copia UMA trilha de áudio para um .wav temporário (16 kHz, mono), que é o que o Whisper usa.
    /// O arquivo original só é lido, nunca copiado inteiro.
    static func extrair(_ arquivo: URL, indice: Int, progresso: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: arquivo)
        let trilhas = try await asset.loadTracks(withMediaType: .audio)
        guard indice >= 0, indice < trilhas.count else { throw ErroApp("Esse arquivo não tem a trilha \(indice + 1).") }
        let trilha = trilhas[indice]
        let total = CMTimeGetSeconds(try await asset.load(.duration))
        let destino = FileManager.default.temporaryDirectory.appendingPathComponent("trilha-\(indice + 1)-" + UUID().uuidString + ".wav")
        let leitor = try AVAssetReader(asset: asset)
        let ajustes: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000.0, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false]
        let saida = AVAssetReaderTrackOutput(track: trilha, outputSettings: ajustes)
        saida.alwaysCopiesSampleData = false
        guard leitor.canAdd(saida) else { throw ErroApp("Não consegui ler o áudio da trilha \(indice + 1).") }
        leitor.add(saida)
        // a leitura é trabalho pesado: roda fora do ator principal
        try await Task.detached(priority: .userInitiated) {
            try Trilhas.gravar(leitor: leitor, saida: saida, destino: destino, total: total, progresso: progresso)
        }.value
        return destino
    }

    private static func gravar(leitor: AVAssetReader, saida: AVAssetReaderTrackOutput, destino: URL, total: Double,
                               progresso: @Sendable (Double) -> Void) throws {
        guard let formato = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            throw ErroApp("Não consegui preparar o áudio.")
        }
        let noDisco: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000.0, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false]
        let arquivo = try AVAudioFile(forWriting: destino, settings: noDisco, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard leitor.startReading() else {
            throw ErroApp("Falha ao ler o áudio: \(leitor.error?.localizedDescription ?? "?")")
        }
        var ultimo = -1.0
        var falha: String?
        while falha == nil {
            if Task.isCancelled { falha = "cancelado"; break }
            guard let amostra = saida.copyNextSampleBuffer() else { break }
            guard let bloco = CMSampleBufferGetDataBuffer(amostra) else { continue }
            let n = CMBlockBufferGetDataLength(bloco) / MemoryLayout<Float>.size
            if n == 0 { continue }
            guard let buf = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: AVAudioFrameCount(n)),
                  let canal = buf.floatChannelData?[0] else { falha = "faltou memória"; break }
            let st = CMBlockBufferCopyDataBytes(bloco, atOffset: 0, dataLength: n * MemoryLayout<Float>.size, destination: canal)
            if st != kCMBlockBufferNoErr { falha = "falha ao ler o áudio"; break }
            buf.frameLength = AVAudioFrameCount(n)
            do { try arquivo.write(from: buf) } catch { falha = "falha ao gravar: \(error.localizedDescription)"; break }
            let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(amostra))
            if t.isFinite, total > 0 {
                let p = min(1, max(0, t / total))
                if p - ultimo >= 0.01 { ultimo = p; progresso(p) }
            }
        }
        if leitor.status == .failed { falha = falha ?? "falha ao ler: \(leitor.error?.localizedDescription ?? "?")" }
        leitor.cancelReading()
        if let falha {
            try? FileManager.default.removeItem(at: destino)
            if falha == "cancelado" { throw CancellationError() }
            throw ErroApp("Não consegui separar a trilha: \(falha).")
        }
        progresso(1)
    }
}

/// Toca alguns segundos de uma trilha, para você reconhecer qual é a sua.
@MainActor
final class Amostra {
    static let shared = Amostra()
    private var tocador: AVPlayer?
    private var vez: [Int: Int] = [:]
    private let pontos = [0.10, 0.30, 0.50, 0.70, 0.90]

    func parar() { tocador?.pause(); tocador = nil }

    /// Cada toque no mesmo botão toca outro ponto da gravação (a trilha do microfone tem muito silêncio).
    func tocar(_ arquivo: URL, indice: Int) async {
        parar()
        let asset = AVURLAsset(url: arquivo)
        guard let trilhas = try? await asset.loadTracks(withMediaType: .audio), indice < trilhas.count,
              let duracao = try? await asset.load(.duration) else { return }
        let total = CMTimeGetSeconds(duracao)
        guard total.isFinite, total > 0 else { return }
        let n = vez[indice, default: 0]
        vez[indice] = n + 1
        let inicio = total * pontos[n % pontos.count]
        let comprimento = min(12.0, max(1, total - inicio))
        let comp = AVMutableComposition()
        guard let ct = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return }
        let faixa = CMTimeRange(start: CMTime(seconds: inicio, preferredTimescale: 600),
                                duration: CMTime(seconds: comprimento, preferredTimescale: 600))
        do { try ct.insertTimeRange(faixa, of: trilhas[indice], at: .zero) } catch { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let p = AVPlayer(playerItem: AVPlayerItem(asset: comp))
        tocador = p
        p.play()
    }
}
