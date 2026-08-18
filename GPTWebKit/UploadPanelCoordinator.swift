import PhotosUI
import UIKit
import UniformTypeIdentifiers
import WebKit

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

private enum WebDownloadRegistry {
    private static var destinations: [ObjectIdentifier: URL] = [:]
    private static let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GPTWebKitDownloads", isDirectory: true)

    static func destination(for download: WKDownload, suggestedFilename: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let raw = suggestedFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        var name = raw.components(separatedBy: invalid).joined(separator: "_")
        if name.isEmpty { name = "ChatGPT-Download" }
        var destination = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) {
            let ext = destination.pathExtension
            let base = destination.deletingPathExtension().lastPathComponent
            let suffix = String(UUID().uuidString.prefix(8))
            destination = directory.appendingPathComponent(ext.isEmpty ? "\(base)-\(suffix)" : "\(base)-\(suffix).\(ext)")
        }
        destinations[ObjectIdentifier(download)] = destination
        return destination
    }

    static func takeDestination(for download: WKDownload) -> URL? { destinations.removeValue(forKey: ObjectIdentifier(download)) }
    static func forget(_ download: WKDownload) { destinations.removeValue(forKey: ObjectIdentifier(download)) }
}

extension WebViewController {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload { decisionHandler(.download); return }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        if disposition.contains("attachment") || !navigationResponse.canShowMIMEType { decisionHandler(.download); return }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil, let url = navigationAction.request.url else { return nil }
        if url.scheme?.lowercased() == "blob" {
            guard let data = try? JSONEncoder().encode(url.absoluteString), let literal = String(data: data, encoding: .utf8) else { return nil }
            webView.evaluateJavaScript("location.href=\(literal); true", completionHandler: nil)
        } else {
            webView.load(navigationAction.request)
        }
        return nil
    }

    fileprivate func presentDownloadedFile(_ url: URL, attempt: Int = 0) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard presentedViewController == nil else {
            guard attempt < 12 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.presentDownloadedFile(url, attempt: attempt + 1) }
            return
        }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: url) }
        if let popover = activity.popoverPresentationController { popover.sourceView = view; popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1) }
        present(activity, animated: true)
    }

    fileprivate func presentDownloadError(_ error: Error) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "下载失败", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

extension WebViewController: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        do { completionHandler(try WebDownloadRegistry.destination(for: download, suggestedFilename: suggestedFilename)) }
        catch { completionHandler(nil); presentDownloadError(error) }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = WebDownloadRegistry.takeDestination(for: download) else { return }
        DispatchQueue.main.async { [weak self] in self?.presentDownloadedFile(url) }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        WebDownloadRegistry.forget(download)
        DispatchQueue.main.async { [weak self] in self?.presentDownloadError(error) }
    }
}
