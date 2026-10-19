import UIKit
import Capacitor

/// The app's main screen. Same as Capacitor's own, plus InsydeLive's built-in plugins.
class InsydeBridgeViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(InsydeCaptchaPlugin())
        bridge?.registerPluginInstance(InsydeScannerPlugin())   // v2.4.6: Apple's own QR scanner for door codes
    }
}
