import Foundation
import ARKit
import Combine

public enum ARKitHandlerPreviewPresentorError: Error{
    case failedToDownload
    case unsupported
}

public class ARKitPreviewerDelegateHandler
{
    let localResourceURL: URL
    let originalURL: URL

    init(localResourceURL: URL, orignalURL: URL) {
        self.localResourceURL = localResourceURL
        self.originalURL = orignalURL
    }
    
    public func getPreviewViewController() ->QLPreviewController
    {
        let previewController = QLPreviewController()
        previewController.dataSource = self
        previewController.reloadData()
        return previewController
    }
}

extension ARKitPreviewerDelegateHandler: QLPreviewControllerDataSource
{
    public func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
         1
    }
    
    public func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return localResourceURL as QLPreviewItem
    }
}

public protocol ARKitPreviewHelperable {
    func getARPreviewController(atURL url: URL, completion: @escaping (Result<ARKitPreviewerDelegateHandler, ARKitHandlerPreviewPresentorError>) -> Void, beginLoading:(()-> Void)?)
}

public extension ARKitPreviewHelperable {
    func getARPreviewController(atURL url: URL, completion: @escaping (Result<ARKitPreviewerDelegateHandler, ARKitHandlerPreviewPresentorError>) -> Void, beginLoading:(()-> Void)?) {
        if url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https" {
            guard let docURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first  else {
                print("fail to load arkit model")
                return
            }
            let cache_key = "arkit!" + url.absoluteString
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

public protocol ARKitPreviewPresenter: NSObjectProtocol {
    var arLoadingVC: UIViewController? {get set}
    func createARLoadingViewController() -> UIViewController
    func handleARResult(result:Result<ARKitPreviewerDelegateHandler, ARKitHandlerPreviewPresentorError>, presentScreenWithAnimation animation: Bool)
    func loadARModelForURL(url: URL)
    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? )
    func handleARError(error: ARKitHandlerPreviewPresentorError)
}

public extension ARKitPreviewPresenter where Self:ARKitPreviewHelperable
{
    func handleARResult(result:Result<ARKitPreviewerDelegateHandler, ARKitHandlerPreviewPresentorError>, presentScreenWithAnimation animation: Bool)
    {
        switch result {
        case .success(let handler):
            let pVC = handler.getPreviewViewController()
            self.present(pVC, animated: animation, completion: nil)
        case .failure(let error):
            handleARError(error: error)
        }
    }
    
    func loadARModelForURL(url: URL)
    {
        if arLoadingVC?.parent != nil {
            arLoadingVC?.dismiss(animated: false, completion: nil)
        }
        
        self.getARPreviewController(atURL: url) { (result:Result<ARKitPreviewerDelegateHandler, ARKitHandlerPreviewPresentorError>) in
            if self.arLoadingVC == nil {
                self.handleARResult(result: result, presentScreenWithAnimation: true)
            }else {
                self.arLoadingVC?.dismiss(animated: false, completion: {
                    self.handleARResult(result: result, presentScreenWithAnimation: false)
                })
            }
        } beginLoading: { [weak self] in
            guard let self = self else { return }
            let vc = self.createARLoadingViewController()
            self.arLoadingVC = vc
            self.present(vc, animated: true, completion: nil)
        }
    }
}
