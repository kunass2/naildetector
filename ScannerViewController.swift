//
//  ScannerViewController.swift
//  Nails
//
//  Created by Bartłomiej Semańczyk on 08/06/2020.
//  Copyright © 2020 Bartłomiej Semańczyk. All rights reserved.
//
class ScannerViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let mainView: ScannerView
    private let viewModel: ScannerViewModelable
    var model: DeepLabModel!
    var session: AVCaptureSession!
    var videoDataOutput: AVCaptureVideoDataOutput!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var maskView: UIView!
    var selectedDevice: AVCaptureDevice?
    var selectedColor = UIColor.red
    
    private let imageEdgeSize = 257
    private let rgbaComponentsCount = 4
    private let rgbComponentsCount = 3
    // MARK: - Initialization
    init(view: ScannerView, viewModel: ScannerViewModelable) {
        self.mainView = view
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) {
        return nil
    }
    // MARK: - Life Cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        model = DeepLabModel()
        let result = model.load()
        if (result == false) {
            fatalError("Can't load model.")
        }
        setupAVCapture(position: .back)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        maskView.frame = mainView.preview.bounds
        previewLayer.frame = mainView.preview.bounds
    }
    // MARK: - Private
    private func setupView() {
        view = mainView
        mainView.setupView()
    }
    private func setupAVCapture(position: AVCaptureDevice.Position) {
        if let existedSession = session, existedSession.isRunning {
            existedSession.stopRunning()
        }
        
        session = AVCaptureSession()
        session.sessionPreset = .hd1280x720
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: position) else {
            print("error")
            return
        }
        selectedDevice = device
        do {
            let deviceInput = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(deviceInput) else {
                print("error")
                return
            }
            session.addInput(deviceInput)
        } catch {
            print("error")
            return
        }
        
        videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String : kCVPixelFormatType_32BGRA]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        let videoDataOutputQueue = DispatchQueue(label: "VideoDataOutputQueue")
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        
        guard session.canAddOutput(videoDataOutput) else {
            print("error")
            return
        }
        session.addOutput(videoDataOutput)
        
        guard let connection = videoDataOutput.connection(with: .video) else {
            print("error")
            return
        }
        
        connection.isEnabled = true
        preparePreviewLayer(for: session)
        session.startRunning()
    }
    private func preparePreviewLayer(for session: AVCaptureSession) {
        guard previewLayer == nil else {
            previewLayer.session = session
            return
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        
        previewLayer.backgroundColor = UIColor.black.cgColor
        previewLayer.videoGravity = .resizeAspect
        
        mainView.preview.layer.addSublayer(previewLayer)
        
        
        maskView = UIView()
        mainView.preview.addSubview(maskView)
        mainView.preview.bringSubviewToFront(maskView)
    }
    private func processFrame(pixelBuffer: CVPixelBuffer) {
        let convertedColor = UInt32(selectedColor.switchBlueToRed()!)
        let result: UnsafeMutablePointer<UInt8> = model.process(pixelBuffer, additionalColor: convertedColor)
        let buffer = UnsafeMutableRawPointer(result)
        DispatchQueue.main.async {
            self.draw(buffer: buffer, size: self.imageEdgeSize*self.imageEdgeSize*self.rgbaComponentsCount)
        }
    }
    private func draw(buffer: UnsafeMutableRawPointer, size: Int) {
        let callback:CGDataProviderReleaseDataCallback  = { (pointer: UnsafeMutableRawPointer?, rawPointer: UnsafeRawPointer, size: Int) in }
        
        let width = imageEdgeSize
        let height = imageEdgeSize
        let bitsPerComponent = 8
        let bitsPerPixel = 32
        let bytesPerRow = rgbaComponentsCount * width
        let colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()
        
        let bitmapInfo: CGBitmapInfo = CGBitmapInfo(rawValue: CGImageByteOrderInfo.orderDefault.rawValue).union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        
        let renderingIntent: CGColorRenderingIntent = CGColorRenderingIntent.defaultIntent
        guard let provider = CGDataProvider(dataInfo: nil,
                                            data: buffer,
                                            size: size,
                                            releaseData: callback) else { return }
        
        guard let cgImage = CGImage(width: width,
                                    height: height,
                                    bitsPerComponent: bitsPerComponent,
                                    bitsPerPixel: bitsPerPixel,
                                    bytesPerRow: bytesPerRow,
                                    space: colorSpace,
                                    bitmapInfo: bitmapInfo,
                                    provider: provider,
                                    decode: nil,
                                    shouldInterpolate: false,
                                    intent: renderingIntent) else { return }
        if let device = selectedDevice, device.position == .front {
            maskView.layer.contents = cgImage
            return
        }
        
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else { return }
        
        var transform: CGAffineTransform = CGAffineTransform.identity
        transform = transform.translatedBy(x: CGFloat(width), y: 0)
        transform = transform.scaledBy(x: -1.0, y: 1.0)
        
        context.concatenate(transform)
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        maskView.layer.contents = context.makeImage()
    }
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("aaa")
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            processFrame(pixelBuffer: pixelBuffer)
        }
    }
}
