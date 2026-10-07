import Foundation
import Observation

/// Os modelos de linguagem (.gguf) guardados no iPhone e o download deles do Hugging Face.
@MainActor
@Observable
final class Modelos: NSObject, URLSessionDownloadDelegate {
    struct Modelo: Identifiable, Codable, Equatable {
        var id: String { arquivo }
        var nome: String
        var arquivo: String          // nome do .gguf
        var url: String
        var nota: String
    }

    /// Candidatos da etapa 1. O endereço segue o padrão do Hugging Face: /<repositório>/resolve/main/<arquivo>.
    static let sugeridos: [Modelo] = [
        Modelo(nome: "Qwen3 4B Instruct", arquivo: "Qwen3-4B-Instruct-2507-Q4_K_M.gguf",
               url: "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf",
               nota: "4B · cerca de 2,5 GB · bom em português"),
        Modelo(nome: "Gemma 3 4B", arquivo: "gemma-3-4b-it-Q4_K_M.gguf",
               url: "https://huggingface.co/unsloth/gemma-3-4b-it-GGUF/resolve/main/gemma-3-4b-it-Q4_K_M.gguf",
               nota: "4B · cerca de 2,5 GB · outra família, para comparar"),
        Modelo(nome: "Qwen2.5 7B Instruct", arquivo: "Qwen2.5-7B-Instruct-Q4_K_M.gguf",
               url: "https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf",
               nota: "7B · cerca de 4,7 GB · teste de limite: pode não caber"),
    ]

    private(set) var extras: [Modelo] = []
    var todos: [Modelo] { Self.sugeridos + extras }

    private(set) var baixando: String?          // arquivo em download
    private(set) var recebido: Int64 = 0
    private(set) var total: Int64 = 0
    var erro: String?
    private(set) var versao = 0                 // sobe quando um arquivo chega ou sai (a tela relê)

    @ObservationIgnored private var sessao: URLSession!
    @ObservationIgnored private var tarefa: URLSessionDownloadTask?

    override init() {
        super.init()
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 60
        c.waitsForConnectivity = true
        sessao = URLSession(configuration: c, delegate: self, delegateQueue: nil)
        if let d = UserDefaults.standard.data(forKey: "modelosExtras"),
           let l = try? JSONDecoder().decode([Modelo].self, from: d) { extras = l }
    }

    nonisolated static var pasta: URL {
        var u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Modelos", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        var v = URLResourceValues(); v.isExcludedFromBackup = true
        try? u.setResourceValues(v)
        return u
    }

    nonisolated static func arquivo(_ nome: String) -> URL { pasta.appendingPathComponent(nome) }

    func baixado(_ m: Modelo) -> Bool { FileManager.default.fileExists(atPath: Self.arquivo(m.arquivo).path) }

    func tamanho(_ m: Modelo) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: Self.arquivo(m.arquivo).path)[.size]) as? NSNumber)?.int64Value ?? 0
    }

    /// Endereço de um .gguf do Hugging Face colado à mão (para testar qualquer outro modelo).
    func adicionar(_ endereco: String) -> String? {
        let limpo = endereco.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/blob/", with: "/resolve/")
        guard let u = URL(string: limpo), u.scheme == "https", u.pathExtension.lowercased() == "gguf" else {
            return "Cole o endereço https de um arquivo .gguf."
        }
        let nome = u.lastPathComponent
        if todos.contains(where: { $0.arquivo == nome }) { return "Esse modelo já está na lista." }
        var semConsulta = URLComponents(url: u, resolvingAgainstBaseURL: false)
        semConsulta?.query = nil
        extras.append(Modelo(nome: nome.replacingOccurrences(of: ".gguf", with: ""), arquivo: nome,
                             url: semConsulta?.url?.absoluteString ?? limpo, nota: "adicionado por você"))
        gravarExtras()
        return nil
    }

    func tirarDaLista(_ m: Modelo) {
        extras.removeAll { $0.arquivo == m.arquivo }
        gravarExtras()
    }

    private func gravarExtras() {
        if let d = try? JSONEncoder().encode(extras) { UserDefaults.standard.set(d, forKey: "modelosExtras") }
    }

    func baixar(_ m: Modelo) {
        guard baixando == nil, let u = URL(string: m.url) else { return }
        erro = nil; recebido = 0; total = 0
        let retomada = Self.arquivo(m.arquivo + ".retomar")
        let t: URLSessionDownloadTask
        if let d = try? Data(contentsOf: retomada) {
            t = sessao.downloadTask(withResumeData: d)
            try? FileManager.default.removeItem(at: retomada)
        } else {
            t = sessao.downloadTask(with: u)
        }
        t.taskDescription = m.arquivo
        tarefa = t; baixando = m.arquivo
        t.resume()
    }

    func cancelar() {
        guard let t = tarefa, let nome = baixando else { return }
        t.cancel { dados in
            if let dados { try? dados.write(to: Modelos.arquivo(nome + ".retomar")) }
        }
    }

    func apagar(_ m: Modelo) {
        try? FileManager.default.removeItem(at: Self.arquivo(m.arquivo))
        try? FileManager.default.removeItem(at: Self.arquivo(m.arquivo + ".retomar"))
        versao += 1
    }

    // MARK: URLSessionDownloadDelegate (chega fora da fila principal)

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in
            self.recebido = totalBytesWritten
            self.total = totalBytesExpectedToWrite
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        // o arquivo temporário some quando este método retorna: mover agora
        let nome = downloadTask.taskDescription ?? "modelo.gguf"
        let codigo = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        var falha: String?
        if !(200..<300).contains(codigo) {
            falha = codigo == 401 || codigo == 403
                ? "O Hugging Face pediu login para esse arquivo (modelo restrito). Escolha outro repositório."
                : "O Hugging Face respondeu \(codigo): confira o endereço do arquivo."
        } else {
            let destino = Modelos.arquivo(nome)
            try? FileManager.default.removeItem(at: destino)
            do { try FileManager.default.moveItem(at: location, to: destino) }
            catch { falha = "Não consegui guardar o modelo: \(error.localizedDescription)" }
        }
        Task { @MainActor in
            if let falha { self.erro = falha }
            self.versao += 1
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let nome = task.taskDescription ?? ""
        var falha: String?
        if let e = error as NSError? {
            if let d = e.userInfo[NSURLSessionDownloadTaskResumeData] as? Data, !nome.isEmpty {
                try? d.write(to: Modelos.arquivo(nome + ".retomar"))
            }
            if e.code != NSURLErrorCancelled {
                falha = "O download parou: \(e.localizedDescription) Toque em Baixar para continuar de onde parou."
            }
        }
        Task { @MainActor in
            if let falha { self.erro = falha }
            self.baixando = nil
            self.tarefa = nil
        }
    }
}
