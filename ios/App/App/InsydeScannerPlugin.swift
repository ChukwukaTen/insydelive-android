import Foundation
import UIKit
import AVFoundation
import Capacitor

/// InsydeLive door-code scanner (v2.4.6, approved 19 Oct 2026).
/// Uses Apple's own camera and QR reader (AVFoundation), so the iPhone app no longer downloads a
/// JavaScript decoder. JavaScript calls InsydeScanner.scan() and gets {"value": "<code>"} back,
/// or an error: "cancelled", "denied" (camera access off) or "unavailable" (no camera).
@objc(InsydeScannerPlugin)
public class InsydeScannerPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "InsydeScannerPlugin"
    public let jsName = "InsydeScanner"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "scan", returnType: CAPPluginReturnPromise)
    ]

    private var scanner: InsydeScannerViewController?

    @objc func scan(_ call: CAPPluginCall) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            present(call)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.present(call) } else { call.reject("denied") }
                }
            }
        default:
            call.reject("denied")
        }
    }

    private func present(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if self.scanner != nil { call.reject("busy"); return }
            guard AVCaptureDevice.default(for: .video) != nil else { call.reject("unavailable"); return }
            guard let presenter = self.bridge?.viewController else { call.reject("unavailable"); return }
            let vc = InsydeScannerViewController { [weak self] value in
                self?.scanner = nil
                if let value = value { call.resolve(["value": value]) } else { call.reject("cancelled") }
            }
            vc.modalPresentationStyle = .fullScreen
            self.scanner = vc
            presenter.present(vc, animated: true)
        }
    }
}

final class InsydeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var completion: ((String?) -> Void)?
    private let frameSize: CGFloat = 240
    private let gold = UIColor(red: 228/255, green: 185/255, blue: 78/255, alpha: 1)   // #E4B94E
    private let dim = CAShapeLayer()
    private let corners = CAShapeLayer()
    private let torchButton = UIButton(type: .system)

    init(completion: @escaping (String?) -> Void) {
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            finish(nil)
            return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { finish(nil); return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        if output.availableMetadataObjectTypes.contains(.qr) { output.metadataObjectTypes = [.qr] }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        preview = layer

        dim.fillRule = .evenOdd
        dim.fillColor = UIColor(white: 0, alpha: 0.45).cgColor
        view.layer.addSublayer(dim)
        corners.strokeColor = gold.cgColor
        corners.fillColor = UIColor.clear.cgColor
        corners.lineWidth = 5
        corners.lineCap = .round
        view.layer.addSublayer(corners)

        let title = UILabel()
        title.text = "Scan a code"
        title.textColor = .white
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(title)

        let hint = UILabel()
        hint.text = "Point the camera at the QR code.\nIt's checked as soon as it's in the frame."
        hint.textColor = .white
        hint.font = .systemFont(ofSize: 16)
        hint.numberOfLines = 0
        hint.textAlignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)

        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.setTitleColor(.white, for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        cancel.backgroundColor = UIColor(white: 1, alpha: 0.16)
        cancel.layer.cornerRadius = 14
        cancel.accessibilityLabel = "Cancel scanning"
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancel)

        torchButton.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
        torchButton.tintColor = .white
        torchButton.backgroundColor = UIColor(white: 1, alpha: 0.16)
        torchButton.layer.cornerRadius = 22
        torchButton.accessibilityLabel = "Torch"
        torchButton.isHidden = !device.hasTorch
        torchButton.addTarget(self, action: #selector(torchTapped), for: .touchUpInside)
        torchButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(torchButton)

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: g.topAnchor, constant: 16),
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            torchButton.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 20),
            torchButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            torchButton.widthAnchor.constraint(equalToConstant: 44),
            torchButton.heightAnchor.constraint(equalToConstant: 44),
            hint.topAnchor.constraint(equalTo: view.centerYAnchor, constant: frameSize / 2 + 28),
            hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            cancel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            cancel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            cancel.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -24),
            cancel.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
        let box = CGRect(x: (view.bounds.width - frameSize) / 2, y: (view.bounds.height - frameSize) / 2, width: frameSize, height: frameSize)
        let dimPath = UIBezierPath(rect: view.bounds)
        dimPath.append(UIBezierPath(roundedRect: box, cornerRadius: 18))
        dim.path = dimPath.cgPath
        dim.frame = view.bounds

        let len: CGFloat = 40, r: CGFloat = 18
        let p = UIBezierPath()
        // top-left
        p.move(to: CGPoint(x: box.minX, y: box.minY + len)); p.addLine(to: CGPoint(x: box.minX, y: box.minY + r))
        p.addQuadCurve(to: CGPoint(x: box.minX + r, y: box.minY), controlPoint: CGPoint(x: box.minX, y: box.minY)); p.addLine(to: CGPoint(x: box.minX + len, y: box.minY))
        // top-right
        p.move(to: CGPoint(x: box.maxX - len, y: box.minY)); p.addLine(to: CGPoint(x: box.maxX - r, y: box.minY))
        p.addQuadCurve(to: CGPoint(x: box.maxX, y: box.minY + r), controlPoint: CGPoint(x: box.maxX, y: box.minY)); p.addLine(to: CGPoint(x: box.maxX, y: box.minY + len))
        // bottom-right
        p.move(to: CGPoint(x: box.maxX, y: box.maxY - len)); p.addLine(to: CGPoint(x: box.maxX, y: box.maxY - r))
        p.addQuadCurve(to: CGPoint(x: box.maxX - r, y: box.maxY), controlPoint: CGPoint(x: box.maxX, y: box.maxY)); p.addLine(to: CGPoint(x: box.maxX - len, y: box.maxY))
        // bottom-left
        p.move(to: CGPoint(x: box.minX + len, y: box.maxY)); p.addLine(to: CGPoint(x: box.minX + r, y: box.maxY))
        p.addQuadCurve(to: CGPoint(x: box.minX, y: box.maxY - r), controlPoint: CGPoint(x: box.minX, y: box.maxY)); p.addLine(to: CGPoint(x: box.minX, y: box.maxY - len))
        corners.path = p.cgPath
        corners.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.session.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setTorch(false)
        if session.isRunning { DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.session.stopRunning() } }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let code = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first(where: { $0.type == .qr }),
              let value = code.stringValue, !value.isEmpty else { return }
        finish(value)
    }

    @objc private func cancelTapped() { finish(nil) }

    @objc private func torchTapped() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        setTorch(device.torchMode != .on)
    }

    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            torchButton.setImage(UIImage(systemName: on ? "flashlight.on.fill" : "flashlight.off.fill"), for: .normal)
        } catch {}
    }

    private func finish(_ value: String?) {
        guard let done = completion else { return }
        completion = nil
        // Async so it also works if the camera fails while the screen is still opening.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.presentingViewController != nil else { done(value); return }
            self.dismiss(animated: true) { done(value) }
        }
    }
}
