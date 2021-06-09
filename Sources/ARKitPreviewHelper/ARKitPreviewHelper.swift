import Foundation
import ARKit
import Combine

enum ARKitHandlerPreviewPresentorError: Error{
    case failedToDownload
    case unsupported
}

class ARKitPreviewerDelegateHandler: QLPreviewControllerDataSource
{
    let localResourceURL: URL
    let originalURL: URL

    init(localResourceURL: URL, orignalURL: URL) {
        self.localResourceURL = localResourceURL
        self.originalURL = orignalURL
    }
    
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
         1
    }
    
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return localResourceURL as QLPreviewItem
    }
    
    func getPreviewViewController() ->QLPreviewController
    {
        let previewController = QLPreviewController()
        previewController.dataSource = self
        previewController.reloadData()
        return previewController
    }
}

protocol ARKitPreviewHelperable {
    func getARPreviewController(atURL url: URL, completion: @escaping (Result<ARKitPreviewerDelegateHandler, ARKitHandlerPreviewPresentorError>) -> Void, beginLoading:(()-> Void)?)
}

extension ARKitPreviewHelperable {
    func getARPreviewController(atURL url: URL, completion: @escaping (Result<ARKitPreviewerDelegateHandler, ARKitHandlerPreviewPresentorError>) -> Void, beginLoading:(()-> Void)?) {
        if url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https" {
            guard let docURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first  else {
                print("fail to load arkit model")
                return
            }
            let cache_key = "arkit!" + docURL.absoluteString
            if let cached_url = UserDefaults.standard.url(forKey: cache_key), FileManager.default.fileExists(atPath: cached_url.path) {
                if QLPreviewController.canPreview(cached_url as QLPreviewItem) {
                    completion(.success(ARKitPreviewerDelegateHandler(localResourceURL: cached_url, orignalURL: url)))
                }else {
                    completion(.failure(.unsupported))
                }
            }
            let lastPath = url.lastPathComponent
            let req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 60)
            beginLoading?()
            let task = URLSession.shared.downloadTask(with: req) { localURL, response, error in
                guard let fileURL = localURL else {
                    completion(.failure(.failedToDownload))
                    return
                }
                var newURL = docURL
                newURL.appendPathComponent(lastPath)

                do {
                    if FileManager.default.fileExists(atPath: newURL.path) {
                        try FileManager.default.removeItem(atPath: newURL.path)
                    }
                    try FileManager.default.moveItem(at: fileURL, to: newURL)
                    print("local url: " + newURL.absoluteString )
                    UserDefaults.standard.set(newURL, forKey: cache_key)
                    UserDefaults.standard.synchronize()
                    
                    OperationQueue.main.addOperation {
                        if QLPreviewController.canPreview(newURL as QLPreviewItem) {
                            completion(.success(ARKitPreviewerDelegateHandler(localResourceURL: newURL, orignalURL: url)))
                        }else {
                            completion(.failure(.unsupported))
                        }
                    }
                }
                catch {
                    print("exception")
                    completion(.failure(.failedToDownload))
                }
                   
            }
            task.resume()
        }
        
    }
}

