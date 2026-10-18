import Foundation
import UIKit
import WebKit
import Capacitor

/// InsydeLive security check panel (v2.4.5, approved 18 Oct 2026).
/// Cloudflare Turnstile only runs on a real https address, and the iPhone app's own address is capacitor://,
/// so the app opens https://app.insydelive.com/captcha.html in this small panel. That page runs the check
/// and posts back {"token": "..."} (or {"error": "..."}) through the "insydeCaptcha" message handler.
@objc(InsydeCaptchaPlugin)
public class InsydeCaptchaPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "InsydeCaptchaPlugin"
    public let jsName = "InsydeCaptcha"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "getToken", returnType: CAPPluginReturnPromise)
    ]

    private var panel: InsydeCaptchaViewController?

    @objc func getToken(_ call: CAPPluginCall) {
        let urlString = call.getString("url") ?? "https://app.insydelive.com/captcha.html"
        // Only ever load our own check page.
        guard let url = URL(string: urlString), url.scheme == "https", url.host == "app.insydelive.com" else {
            call.reject("bad_url")
            return
        }
        DispatchQueue.main.async {
            if self.panel != nil { call.reject("busy"); return }
            let vc = InsydeCaptchaViewController(url: url) { [weak self] result in
                self?.panel = nil
                switch result {
                case .success(let token): call.resolve(["token": token])
                case .failure(let message): call.reject(message)
                }
            }
            self.panel = vc
            vc.modalPresentationStyle = .pageSheet
            if let sheet = vc.sheetPresentationController {
                sheet.detents = [.medium()]
                sheet.prefersGrabberVisible = true
            }
            guard let presenter = self.bridge?.viewController else {
                self.panel = nil
                call.reject("no_view")
                return
            }
            presenter.present(vc, animated: true)
        }
    }
}

enum InsydeCaptchaResult {
    case success(String)
    case failure(String)
}

final class InsydeCaptchaViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, UIAdaptivePresentationControllerDelegate {
    private let url: URL
    private var completion: ((InsydeCaptchaResult) -> Void)?
    private var webView: WKWebView!
    private var timeoutWork: DispatchWorkItem?

    init(url: URL, completion: @escaping (InsydeCaptchaResult) -> Void) {
        self.url = url
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 20/255, green: 11/255, blue: 34/255, alpha: 1)   // #140B22
        presentationController?.delegate = self

        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(WeakMessageHandler(self), name: "insydeCaptcha")
        config.userContentController = controller
        config.websiteDataStore = .default()

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = view.backgroundColor
        webView.scrollView.backgroundColor = view.backgroundColor
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))

        // Never leave the person stuck: give up after 90 seconds.
        let work = DispatchWorkItem { [weak self] in self?.finish(.failure("timeout")) }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: work)
    }

    // Messages from captcha.html: {"token": "..."} or {"error": "..."}
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let text = message.body as? String,
              let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let token = obj["token"] as? String, !token.isEmpty {
            finish(.success(token))
        } else if let err = obj["error"] as? String {
            finish(.failure("check_failed:" + err))
        }
    }

    // Keep the panel on our own page only (Cloudflare's challenge runs inside frames, which are allowed).
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if isMainFrame, let host = navigationAction.request.url?.host, host != "app.insydelive.com" {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure("load_failed"))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure("load_failed"))
    }

    // Swiped down / closed by the person.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish(.failure("cancelled"), dismiss: false)
    }

    private func finish(_ result: InsydeCaptchaResult, dismiss: Bool = true) {
        guard let done = completion else { return }
        completion = nil
        timeoutWork?.cancel()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "insydeCaptcha")
        if dismiss {
            self.dismiss(animated: true) { done(result) }
        } else {
            done(result)
        }
    }
}

/// Avoids a retain cycle between the web view's content controller and the panel.
final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
