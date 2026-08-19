import UIKit

@MainActor
final class ConversationExportCoordinator {
    private weak var presenter: UIViewController?
    private let client: ChatGPTClient
    private var activeTask: Task<Data, Error>?
    private var generation = 0

    init(presenter: UIViewController) {
        self.presenter = presenter
        self.client = .shared
        MarkdownExporter.cleanupOldExports()
    }

    func begin(_ conversation: ChatGPTConversation, requiresConfirmation: Bool) {
        guard let presenter else { return }
        if requiresConfirmation {
            let alert = UIAlertController(title: "导出 Markdown", message: "确定导出当前《\(conversation.title)》会话吗？", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
                DispatchQueue.main.async { self?.promptRename(for: conversation) }
            })
            presenter.present(alert, animated: true)
        } else {
            promptRename(for: conversation)
        }
    }

    private func promptRename(for conversation: ChatGPTConversation) {
        guard let presenter else { return }
        generation += 1
        let currentGeneration = generation
        activeTask?.cancel()
        let fetchTask = Task<Data, Error> { [client] in try await client.fetchConversationData(id: conversation.id) }
        activeTask = fetchTask

        let alert = UIAlertController(title: "重命名 Markdown", message: "完整会话已在后台开始读取。", preferredStyle: .alert)
        alert.addTextField { field in
            field.text = conversation.title
            field.clearButtonMode = .whileEditing
            field.autocorrectionType = .no
            field.spellCheckingType = .no
            field.returnKeyType = .done
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            guard let self, currentGeneration == self.generation else { return }
            self.activeTask?.cancel()
            self.activeTask = nil
        })
        alert.addAction(UIAlertAction(title: "导出", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            let filename = name?.isEmpty == false ? name! : conversation.title
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                self.finishExport(conversation: conversation, filename: filename, fetchTask: fetchTask, generation: currentGeneration)
            }
        })
        presenter.present(alert, animated: true) { [weak alert] in
            alert?.textFields?.first?.selectAll(nil)
        }
    }

    private func finishExport(conversation: ChatGPTConversation, filename: String, fetchTask: Task<Data, Error>, generation: Int) {
        guard let presenter, generation == self.generation else { return }
        let progress = makeProgressAlert()
        presenter.present(progress, animated: true)

        Task { [weak self, weak progress] in
            guard let self else { return }
            do {
                let data = try await fetchTask.value
                guard generation == self.generation else { return }
                let outputURL = try await Task.detached(priority: .userInitiated) {
                    let markdown = try MarkdownExporter.makeMarkdown(from: data, fallbackTitle: conversation.title)
                    return try MarkdownExporter.write(markdown: markdown, filename: filename)
                }.value
                self.activeTask = nil
                progress?.dismiss(animated: true) { [weak self] in self?.presentSavePicker(url: outputURL) }
            } catch is CancellationError {
                progress?.dismiss(animated: true)
            } catch {
                self.activeTask = nil
                progress?.dismiss(animated: true) { [weak self] in self?.showError(error.localizedDescription) }
            }
        }
    }

    private func makeProgressAlert() -> UIAlertController {
        let alert = UIAlertController(title: "正在导出…", message: "正在获取完整会话并生成 Markdown\n\n", preferredStyle: .alert)
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        alert.view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
            spinner.bottomAnchor.constraint(equalTo: alert.view.bottomAnchor, constant: -18)
        ])
        return alert
    }

    private func presentSavePicker(url: URL) {
        guard let presenter else { return }
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.shouldShowFileExtensions = true
        presenter.present(picker, animated: true)
    }

    private func showError(_ message: String) {
        guard let presenter else { return }
        let alert = UIAlertController(title: "导出失败", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        presenter.present(alert, animated: true)
    }
}
