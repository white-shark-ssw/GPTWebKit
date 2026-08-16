import PhotosUI
import UIKit
import UniformTypeIdentifiers

final class UploadPanelCoordinator: NSObject {
    private weak var presenter: UIViewController?
    private var completion: (([URL]?) -> Void)?
    private var allowsMultipleSelection = false
    private let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("GPTWebKitUploads", isDirectory: true)

    func present(from presenter: UIViewController, allowsMultipleSelection: Bool, completion: @escaping ([URL]?) -> Void) {
        finish(nil)
        self.presenter = presenter
        self.completion = completion
        self.allowsMultipleSelection = allowsMultipleSelection

        let sheet = UIAlertController(title: "添加附件", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "照片和视频", style: .default) { [weak self] _ in self?.presentPhotoPicker() })
        sheet.addAction(UIAlertAction(title: "文件", style: .default) { [weak self] _ in self?.presentDocumentPicker() })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in self?.finish(nil) })
        if let popover = sheet.popoverPresentationController { popover.sourceView = presenter.view; popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY - 1, width: 1, height: 1) }
        presenter.present(sheet, animated: true)
    }

    private func presentDocumentPicker() {
        guard let presenter else { return finish(nil) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    private func presentPhotoPicker() {
        guard let presenter else { return finish(nil) }
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = allowsMultipleSelection ? 0 : 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    private func copyToTemporaryDirectory(from sourceURL: URL, suggestedName: String?) throws -> URL {
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let name = (suggestedName?.isEmpty == false ? suggestedName! : sourceURL.lastPathComponent)
        let destination = tempDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    private func finish(_ urls: [URL]?) {
        guard let completion else { return }
        self.completion = nil
        presenter = nil
        completion(urls)
    }
}

extension UploadPanelCoordinator: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finish(urls) }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(nil) }
}

extension UploadPanelCoordinator: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { return finish(nil) }

        let group = DispatchGroup()
        let lock = NSLock()
        var selectedURLs: [URL] = []

        for result in results {
            let provider = result.itemProvider
            let typeIdentifier = provider.registeredTypeIdentifiers.first(where: { identifier in
                guard let type = UTType(identifier) else { return false }
                return type.conforms(to: .movie) || type.conforms(to: .image)
            }) ?? provider.registeredTypeIdentifiers.first
            guard let typeIdentifier else { continue }

            group.enter()
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, _ in
                defer { group.leave() }
                guard let self, let url else { return }
                let suggestedName = provider.suggestedName.map { name in
                    let ext = url.pathExtension
                    return ext.isEmpty || name.hasSuffix(".\(ext)") ? name : "\(name).\(ext)"
                }
                guard let copied = try? self.copyToTemporaryDirectory(from: url, suggestedName: suggestedName) else { return }
                lock.lock(); selectedURLs.append(copied); lock.unlock()
            }
        }

        group.notify(queue: .main) { [weak self] in self?.finish(selectedURLs.isEmpty ? nil : selectedURLs) }
    }
}
