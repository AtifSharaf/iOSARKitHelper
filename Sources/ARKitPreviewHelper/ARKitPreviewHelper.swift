import Foundation
import ARKit
import Combine

public enum ARKitHandlerPreviewPresentorError: Error{
    case failedToDownload
    case unsupported
}

/// This object act as the delegat for QLPreviewController. And contain the url being used to display Preview content
public class ARKitPreviewerDelegateHandler
{
    /// URL used to display content from device file system
    let localResourceURL: URL
    /// Orignal URL which trigger preview presentation
    let originalURL: URL

    init(localResourceURL: URL, orignalURL: URL) {
        self.localResourceURL = localResourceURL
        self.originalURL = orignalURL
    }
    
    
    /// Initialize QLPreviewController and set its deletegate to self and reload UI. It ready to be presented
    /// - Returns: QLPreviewController
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

public protocol ARKitResourceLoadable {
    /// It load Preview content in device and return it location
    /// - Parameters:
    ///   - url: URL of orignal preview content. If url is not a location, than it will use it to download content
    ///   - completion: Completion block with result of local file locaiton or error if any
    ///   - beginLoading: If file need to be loaded, this block is called so you can present the UI and dismiss it in completion block
    func getARPreviewHandler(atURL url: URL, completion: @escaping (Result<ARKitPreviewerDelegateHandler, ARKitHandlerPreviewPresentorError>) -> Void, beginLoading:(()-> Void)?)
    
    func getCachedLocalARPreviewURL(originalURL url: URL) -> URL?
    func storeLocalARPreviewURL(orignalURL url: URL, localURL: URL)
}

public extension ARKitResourceLoadable {
    
    func getCachedLocalARPreviewURL(originalURL url: URL) -> URL? {
        let cache_key = "arkit!" + url.absoluteString
        if let cached_url = UserDefaults.standard.url(forKey: cache_key), FileManager.default.fileExists(atPath: cached_url.path) {
            return cached_url
        }
        return nil
    }
    func storeLocalARPreviewURL(orignalURL url: URL, localURL: URL) {
        let cache_key = "arkit!" + url.absoluteString
        UserDefaults.standard.set(url, forKey: cache_key)
        UserDefaults.standard.synchronize()
    }
    
    func getARPreviewHandler(atURL url: URL, completion: @escaping (Result<ARKitPreviewerDelegateHandler, ARKitHandlerPreviewPresentorError>) -> Void, beginLoading:(()-> Void)?) {
        if url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https" {
            guard let docURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first  else {
                print("fail to load arkit model")
                return
            }
            if let cached_url = self.getCachedLocalARPreviewURL(originalURL: url) {
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
                    self.storeLocalARPreviewURL(orignalURL: url, localURL: newURL)
                    
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

/// This protocol is used to provide default  preview presentation implementation with some customization
public protocol ARKitPreviewPresenter: NSObjectProtocol {
    /// Propterty to Preview loading Viewcontroller which is presented on  - ARKitResourceLoadable.getARPreviewHandle  begin closure
    var arLoadingVC: UIViewController? {get set}
    /// Its a custom point to provide Loading view controller
    func createARLoadingViewController() -> UIViewController
    /// Handle result by presenting preview content controller or handle error
    func handleARResult(result:Result<ARKitPreviewerDelegateHandler, ARKitHandlerPreviewPresentorError>, presentScreenWithAnimation animation: Bool)
    func presentARResourceForURL(url: URL)
    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? )
    func handleARError(error: ARKitHandlerPreviewPresentorError)
}

public extension ARKitPreviewPresenter where Self:ARKitResourceLoadable
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
    
    func presentARResourceForURL(url: URL)
    {
        if arLoadingVC?.parent != nil {
            arLoadingVC?.dismiss(animated: false, completion: nil)
        }
        
        self.getARPreviewHandler(atURL: url) { (result:Result<ARKitPreviewerDelegateHandler, ARKitHandlerPreviewPresentorError>) in
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
