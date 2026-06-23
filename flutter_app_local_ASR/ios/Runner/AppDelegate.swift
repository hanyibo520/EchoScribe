import Flutter
import AVFoundation
import Darwin
import MoonshineVoice
import UIKit
import UniformTypeIdentifiers
import whisper

private enum NativeBridgeFailure: Error {
  case invalidArguments(String)
  case runtime(String)
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private var pendingAudioPickerResult: FlutterResult?
  private var nativeBridgeChannel: FlutterMethodChannel?
  private var moonshineTranscriber: MicTranscriber?
  private var moonshineModelPath: String?
  private var moonshineFileTranscribers: [Transcriber] = []
  private var moonshineFileModelPath: String?
  private let moonshineFileTranscriberLock = NSLock()
  private var isMoonshineListening = false
  private let moonshineRequiredFiles = [
    "adapter.ort",
    "cross_kv.ort",
    "decoder_kv.ort",
    "decoder_kv_with_attention.ort",
    "encoder.ort",
    "frontend.ort",
    "streaming_config.json",
    "tokenizer.bin"
  ]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerNativeBridge(binaryMessenger: engineBridge.applicationRegistrar.messenger())
  }

  private func registerNativeBridge(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "local_meeting_asr/native_bridge",
      binaryMessenger: binaryMessenger
    )
    nativeBridgeChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "BRIDGE_UNAVAILABLE",
            message: "Native bridge owner was released",
            details: nil
          )
        )
        return
      }

      switch call.method {
      case "applicationSupportDirectory":
        do {
          result(try self.applicationSupportDirectory())
        } catch NativeBridgeFailure.runtime(let message) {
          result(FlutterError(code: "DIRECTORY_UNAVAILABLE", message: message, details: nil))
        } catch {
          result(
            FlutterError(
              code: "DIRECTORY_UNAVAILABLE",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      case "resolveBundledAssetPath":
        do {
          result(try self.resolveBundledAssetPath(arguments: call.arguments))
        } catch NativeBridgeFailure.invalidArguments(let message) {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: message, details: nil))
        } catch {
          result(
            FlutterError(
              code: "ASSET_RESOLVE_FAILED",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      case "inspectBridges":
        result(self.inspectBridges(arguments: call.arguments))
      case "checkMoonshine":
        result(self.checkMoonshine(arguments: call.arguments))
      case "startMoonshine":
        do {
          result(try self.startMoonshine(arguments: call.arguments))
        } catch NativeBridgeFailure.invalidArguments(let message) {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: message, details: nil))
        } catch NativeBridgeFailure.runtime(let message) {
          result(FlutterError(code: "MOONSHINE_FAILED", message: message, details: nil))
        } catch {
          result(
            FlutterError(
              code: "MOONSHINE_FAILED",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      case "stopMoonshine":
        do {
          result(try self.stopMoonshine())
        } catch {
          result(
            FlutterError(
              code: "MOONSHINE_STOP_FAILED",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      case "disposeMoonshine":
        self.disposeMoonshine()
        result(nil)
      case "pickAudioFile":
        self.pickAudioFile(result: result)
      case "installBundledDirectory":
        DispatchQueue.global(qos: .utility).async {
          do {
            let response = try self.installBundledDirectory(arguments: call.arguments)
            DispatchQueue.main.async {
              result(response)
            }
          } catch NativeBridgeFailure.invalidArguments(let message) {
            DispatchQueue.main.async {
              result(FlutterError(code: "INVALID_ARGUMENTS", message: message, details: nil))
            }
          } catch NativeBridgeFailure.runtime(let message) {
            DispatchQueue.main.async {
              result(FlutterError(code: "ASSET_INSTALL_FAILED", message: message, details: nil))
            }
          } catch {
            DispatchQueue.main.async {
              result(
                FlutterError(
                  code: "ASSET_INSTALL_FAILED",
                  message: error.localizedDescription,
                  details: nil
                )
              )
            }
          }
        }
      case "transcribeWithWhisperCpp":
        DispatchQueue.global(qos: .userInitiated).async {
          do {
            let response = try self.transcribeWithWhisperCpp(arguments: call.arguments)
            DispatchQueue.main.async {
              result(response)
            }
          } catch NativeBridgeFailure.invalidArguments(let message) {
            DispatchQueue.main.async {
              result(FlutterError(code: "INVALID_ARGUMENTS", message: message, details: nil))
            }
          } catch NativeBridgeFailure.runtime(let message) {
            DispatchQueue.main.async {
              result(FlutterError(code: "WHISPER_CPP_FAILED", message: message, details: nil))
            }
          } catch {
            DispatchQueue.main.async {
              result(
                FlutterError(
                  code: "WHISPER_CPP_FAILED",
                  message: error.localizedDescription,
                  details: nil
                )
              )
            }
          }
        }
      case "transcribeAudioFileWithWhisperCpp":
        DispatchQueue.global(qos: .userInitiated).async {
          do {
            let response = try self.transcribeAudioFileWithWhisperCpp(arguments: call.arguments)
            DispatchQueue.main.async {
              result(response)
            }
          } catch NativeBridgeFailure.invalidArguments(let message) {
            DispatchQueue.main.async {
              result(FlutterError(code: "INVALID_ARGUMENTS", message: message, details: nil))
            }
          } catch NativeBridgeFailure.runtime(let message) {
            DispatchQueue.main.async {
              result(FlutterError(code: "WHISPER_CPP_FAILED", message: message, details: nil))
            }
          } catch {
            DispatchQueue.main.async {
              result(
                FlutterError(
                  code: "WHISPER_CPP_FAILED",
                  message: error.localizedDescription,
                  details: nil
                )
              )
            }
          }
        }
      case "transcribeAudioFileWithMoonshine":
        DispatchQueue.global(qos: .userInitiated).async {
          do {
            let response = try self.transcribeAudioFileWithMoonshine(arguments: call.arguments)
            DispatchQueue.main.async {
              result(response)
            }
          } catch NativeBridgeFailure.invalidArguments(let message) {
            DispatchQueue.main.async {
              result(FlutterError(code: "INVALID_ARGUMENTS", message: message, details: nil))
            }
          } catch NativeBridgeFailure.runtime(let message) {
            DispatchQueue.main.async {
              result(FlutterError(code: "MOONSHINE_FILE_FAILED", message: message, details: nil))
            }
          } catch {
            DispatchQueue.main.async {
              result(
                FlutterError(
                  code: "MOONSHINE_FILE_FAILED",
                  message: error.localizedDescription,
                  details: nil
                )
              )
            }
          }
        }
      case "decodeAudioFileToPcm16":
        DispatchQueue.global(qos: .userInitiated).async {
          do {
            let response = try self.decodeAudioFileToPcm16(arguments: call.arguments)
            DispatchQueue.main.async {
              result(response)
            }
          } catch NativeBridgeFailure.invalidArguments(let message) {
            DispatchQueue.main.async {
              result(FlutterError(code: "INVALID_ARGUMENTS", message: message, details: nil))
            }
          } catch NativeBridgeFailure.runtime(let message) {
            DispatchQueue.main.async {
              result(FlutterError(code: "AUDIO_DECODE_FAILED", message: message, details: nil))
            }
          } catch {
            DispatchQueue.main.async {
              result(
                FlutterError(
                  code: "AUDIO_DECODE_FAILED",
                  message: error.localizedDescription,
                  details: nil
                )
              )
            }
          }
        }
      case "deleteImportedAudioIfNeeded":
        do {
          guard let values = call.arguments as? [String: Any],
                let audioFilePath = values["audioFilePath"] as? String else {
            throw NativeBridgeFailure.invalidArguments("Missing audio file path")
          }
          self.removeImportedAudioIfNeeded(filePath: audioFilePath)
          result(nil)
        } catch NativeBridgeFailure.invalidArguments(let message) {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: message, details: nil))
        } catch {
          result(
            FlutterError(
              code: "AUDIO_DELETE_FAILED",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      case "summarizeWithLlamaCpp":
        result(
          FlutterError(
            code: "LLAMA_CPP_UNAVAILABLE",
            message: "llama.cpp runtime is not linked into the iOS target",
            details: nil
          )
        )
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func applicationSupportDirectory() throws -> [String: Any] {
    guard let directory = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else {
      throw NativeBridgeFailure.runtime("Application Support directory was not found")
    }

    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return ["path": directory.path]
  }

  private func resolveBundledAssetPath(arguments: Any?) throws -> [String: Any]? {
    guard let values = arguments as? [String: Any] else {
      throw NativeBridgeFailure.invalidArguments("Missing bundled asset arguments")
    }
    guard let assetDirectory = values["assetDirectory"] as? String, !assetDirectory.isEmpty else {
      throw NativeBridgeFailure.invalidArguments("Missing asset directory")
    }
    guard let fileName = values["fileName"] as? String, !fileName.isEmpty else {
      throw NativeBridgeFailure.invalidArguments("Missing asset file name")
    }

    guard let sourceRoot = try? flutterAssetURL(for: assetDirectory) else {
      return nil
    }

    let source = sourceRoot.appendingPathComponent(fileName)
    if FileManager.default.fileExists(atPath: source.path) {
      return ["path": source.path]
    }
    return nil
  }

  private func inspectBridges(arguments: Any?) -> [String: Any] {
    let values = arguments as? [String: Any]
    return [
      "whisperCpp": runtimeStatus(
        name: "whisper.cpp",
        modelPath: values?["whisperModelPath"] as? String,
        requiredSymbols: [
          "whisper_init_from_file_with_params",
          "whisper_init_from_file",
          "whisper_full"
        ],
        callableWhenLinked: true
      ),
      "llamaCpp": runtimeStatus(
        name: "llama.cpp",
        modelPath: values?["llamaModelPath"] as? String,
        requiredSymbols: [
          "llama_model_load_from_file",
          "llama_load_model_from_file",
          "llama_backend_init"
        ],
        callableWhenLinked: true
      ),
      "moonshine": checkMoonshine(modelPath: values?["moonshineModelPath"] as? String)
    ]
  }

  private func checkMoonshine(arguments: Any?) -> [String: Any] {
    let values = arguments as? [String: Any]
    return checkMoonshine(modelPath: values?["modelPath"] as? String)
  }

  private func checkMoonshine(modelPath: String?) -> [String: Any] {
    do {
      let resolvedPath = try validateMoonshineModelPath(modelPath)
      return [
        "available": true,
        "detail": "MoonshineVoice runtime is linked; model path \(resolvedPath)"
      ]
    } catch NativeBridgeFailure.invalidArguments(let message) {
      return [
        "available": false,
        "reason": message
      ]
    } catch NativeBridgeFailure.runtime(let message) {
      return [
        "available": false,
        "reason": message
      ]
    } catch {
      return [
        "available": false,
        "reason": error.localizedDescription
      ]
    }
  }

  private func startMoonshine(arguments: Any?) throws -> [String: Any] {
    guard let values = arguments as? [String: Any],
          let modelPath = values["modelPath"] as? String else {
      throw NativeBridgeFailure.invalidArguments("Missing Moonshine model path")
    }

    let resolvedPath = try validateMoonshineModelPath(modelPath)
    let transcriber = try ensureMoonshineTranscriber(modelPath: resolvedPath)
    if !isMoonshineListening {
      do {
        try transcriber.start()
        isMoonshineListening = true
        sendMoonshineEvent("moonshineStatus", text: "Listening with Moonshine Tiny Streaming")
      } catch {
        disposeMoonshine()
        throw error
      }
    }
    return ["started": true]
  }

  private func stopMoonshine() throws -> [String: Any] {
    if isMoonshineListening, let transcriber = moonshineTranscriber {
      try transcriber.stop()
      isMoonshineListening = false
      sendMoonshineEvent("moonshineStatus", text: "Stopped")
    }
    return ["stopped": true]
  }

  private func disposeMoonshine() {
    try? stopMoonshine()
    moonshineTranscriber = nil
    moonshineModelPath = nil
    moonshineFileTranscriberLock.lock()
    moonshineFileTranscribers = []
    moonshineFileModelPath = nil
    moonshineFileTranscriberLock.unlock()
    isMoonshineListening = false
  }

  private func ensureMoonshineTranscriber(modelPath: String) throws -> MicTranscriber {
    if let transcriber = moonshineTranscriber, moonshineModelPath == modelPath {
      return transcriber
    }

    disposeMoonshine()
    let transcriber = try MicTranscriber(
      modelPath: modelPath,
      modelArch: ModelArch.tinyStreaming
    )
    transcriber.addListener { [weak self] event in
      guard let self else {
        return
      }
      if event is LineStarted {
        self.sendMoonshineEvent("moonshineStatus", text: "Speech started")
      } else if event is LineTextChanged {
        self.sendMoonshineEvent("moonshinePartial", text: event.line.text)
      } else if event is LineCompleted {
        let text = event.line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
          self.sendMoonshineEvent("moonshineSegment", text: text)
        }
      }
    }
    moonshineTranscriber = transcriber
    moonshineModelPath = modelPath
    sendMoonshineEvent("moonshineStatus", text: "Moonshine initialized")
    return transcriber
  }

  private func ensureMoonshineFileTranscribers(
    modelPath: String,
    count: Int
  ) throws -> ([Transcriber], Int) {
    if moonshineFileModelPath != modelPath {
      moonshineFileTranscribers = []
      moonshineFileModelPath = modelPath
    }

    var createdCount = 0
    while moonshineFileTranscribers.count < count {
      moonshineFileTranscribers.append(
        try Transcriber(
          modelPath: modelPath,
          modelArch: ModelArch.tinyStreaming
        )
      )
      createdCount += 1
    }
    return (Array(moonshineFileTranscribers.prefix(count)), createdCount)
  }

  private func sendMoonshineEvent(_ method: String, text: String) {
    DispatchQueue.main.async { [weak self] in
      self?.nativeBridgeChannel?.invokeMethod(method, arguments: ["text": text])
    }
  }

  private func validateMoonshineModelPath(_ modelPath: String?) throws -> String {
    guard let modelPath, !modelPath.isEmpty else {
      throw NativeBridgeFailure.invalidArguments("Moonshine model path is empty")
    }

    let directory = URL(fileURLWithPath: modelPath, isDirectory: true)
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
      throw NativeBridgeFailure.runtime("Moonshine model directory is missing at \(directory.path)")
    }

    for fileName in moonshineRequiredFiles {
      let file = directory.appendingPathComponent(fileName)
      guard fileManager.fileExists(atPath: file.path) else {
        throw NativeBridgeFailure.runtime("Moonshine model is missing \(fileName)")
      }
      guard let attributes = try? fileManager.attributesOfItem(atPath: file.path),
            let size = attributes[.size] as? NSNumber,
            size.intValue >= moonshineMinimumBytes(fileName) else {
        throw NativeBridgeFailure.runtime("Moonshine model file is incomplete: \(fileName)")
      }
    }

    return directory.path
  }

  private func moonshineMinimumBytes(_ fileName: String) -> Int {
    if fileName == "streaming_config.json" {
      return 64
    }
    if fileName == "tokenizer.bin" {
      return 1024
    }
    return 1024
  }

  private func runtimeStatus(
    name: String,
    modelPath: String?,
    requiredSymbols: [String],
    callableWhenLinked: Bool
  ) -> [String: Any] {
    if let modelPath, !modelPath.isEmpty, !FileManager.default.fileExists(atPath: modelPath) {
      return [
        "available": false,
        "reason": "\(name) model is missing at \(modelPath)"
      ]
    }

    guard let symbol = firstLinkedSymbol(requiredSymbols) else {
      return [
        "available": false,
        "reason": "\(name) runtime is not linked into the iOS target"
      ]
    }

    if callableWhenLinked {
      return [
        "available": true,
        "detail": "\(name) runtime symbol \(symbol) is linked"
      ]
    }

    return [
      "available": false,
      "reason": "\(name) runtime symbol \(symbol) is linked, but the callable entrypoint is not implemented"
    ]
  }

  private func firstLinkedSymbol(_ names: [String]) -> String? {
    guard let handle = dlopen(nil, RTLD_LAZY) else {
      return nil
    }
    for name in names where dlsym(handle, name) != nil {
      return name
    }
    return nil
  }

  private func installBundledDirectory(arguments: Any?) throws -> [String: Any] {
    guard let values = arguments as? [String: Any] else {
      throw NativeBridgeFailure.invalidArguments("Missing bundled directory arguments")
    }
    guard let assetDirectory = values["assetDirectory"] as? String, !assetDirectory.isEmpty else {
      throw NativeBridgeFailure.invalidArguments("Missing asset directory")
    }
    guard let destinationDirectory = values["destinationDirectory"] as? String,
          !destinationDirectory.isEmpty else {
      throw NativeBridgeFailure.invalidArguments("Missing destination directory")
    }
    guard let fileNames = values["fileNames"] as? [String], !fileNames.isEmpty else {
      throw NativeBridgeFailure.invalidArguments("Missing file list")
    }

    let sourceRoot = try flutterAssetURL(for: assetDirectory)
    let destinationRoot = URL(fileURLWithPath: destinationDirectory, isDirectory: true)
    let fileManager = FileManager.default
    try fileManager.createDirectory(
      at: destinationRoot,
      withIntermediateDirectories: true
    )

    for fileName in fileNames {
      let source = sourceRoot.appendingPathComponent(fileName)
      let destination = destinationRoot.appendingPathComponent(fileName)
      guard fileManager.fileExists(atPath: source.path) else {
        throw NativeBridgeFailure.runtime("Missing bundled asset \(source.path)")
      }

      if fileManager.fileExists(atPath: destination.path),
         fileSize(source) == fileSize(destination) {
        continue
      }

      let temp = destinationRoot.appendingPathComponent("\(fileName).installing")
      if fileManager.fileExists(atPath: temp.path) {
        try fileManager.removeItem(at: temp)
      }
      try fileManager.copyItem(at: source, to: temp)
      if fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
      }
      try fileManager.moveItem(at: temp, to: destination)
    }

    return [
      "installed": true,
      "sourcePath": sourceRoot.path,
      "destinationPath": destinationRoot.path
    ]
  }

  private func flutterAssetURL(for assetDirectory: String) throws -> URL {
    let normalized = assetDirectory.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let candidates = [
      Bundle.main.privateFrameworksURL?
        .appendingPathComponent("App.framework")
        .appendingPathComponent("flutter_assets")
        .appendingPathComponent(normalized),
      Bundle.main.resourceURL?
        .appendingPathComponent("flutter_assets")
        .appendingPathComponent(normalized),
      Bundle.main.resourceURL?
        .appendingPathComponent(normalized)
    ].compactMap { $0 }

    for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
      return candidate
    }

    throw NativeBridgeFailure.runtime(
      "Bundled Flutter asset directory was not found: \(assetDirectory)"
    )
  }

  private func fileSize(_ url: URL) -> UInt64? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          let size = attributes[.size] as? NSNumber else {
      return nil
    }
    return size.uint64Value
  }

  private func pickAudioFile(result: @escaping FlutterResult) {
    if !Thread.isMainThread {
      DispatchQueue.main.async {
        self.pickAudioFile(result: result)
      }
      return
    }

    guard pendingAudioPickerResult == nil else {
      result(
        FlutterError(
          code: "PICKER_BUSY",
          message: "An audio picker is already open",
          details: nil
        )
      )
      return
    }
    guard let presenter = topViewController() else {
      result(
        FlutterError(
          code: "PICKER_UNAVAILABLE",
          message: "Unable to present audio picker",
          details: nil
        )
      )
      return
    }

    pendingAudioPickerResult = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio])
    picker.allowsMultipleSelection = false
    picker.delegate = self
    presenter.present(picker, animated: true)
  }

  private func topViewController() -> UIViewController? {
    let root = activeRootViewController()
    return topViewController(from: root)
  }

  private func activeRootViewController() -> UIViewController? {
    if let controller = window?.rootViewController {
      return controller
    }

    let scenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .sorted { lhs, rhs in
        scenePriority(lhs.activationState) < scenePriority(rhs.activationState)
      }

    for scene in scenes {
      let activeWindow =
        scene.windows.first(where: { $0.isKeyWindow }) ??
        scene.windows.first(where: { !$0.isHidden && $0.alpha > 0 })
      if let controller = activeWindow?.rootViewController {
        return controller
      }
    }

    return nil
  }

  private func scenePriority(_ state: UIScene.ActivationState) -> Int {
    switch state {
    case .foregroundActive:
      return 0
    case .foregroundInactive:
      return 1
    case .background:
      return 2
    case .unattached:
      return 3
    @unknown default:
      return 4
    }
  }

  private func topViewController(from root: UIViewController?) -> UIViewController? {
    var controller = root
    while true {
      if let navigation = controller as? UINavigationController {
        controller = navigation.visibleViewController
        continue
      }
      if let tab = controller as? UITabBarController {
        controller = tab.selectedViewController
        continue
      }
      if let presented = controller?.presentedViewController {
        controller = presented
        continue
      }
      break
    }

    return controller
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = pendingAudioPickerResult else {
      return
    }
    pendingAudioPickerResult = nil

    guard let source = urls.first else {
      result(nil)
      return
    }

    let didAccess = source.startAccessingSecurityScopedResource()
    defer {
      if didAccess {
        source.stopAccessingSecurityScopedResource()
      }
    }

    do {
      let destination = try copyImportedAudio(source)
      result([
        "path": destination.path,
        "name": source.lastPathComponent
      ])
    } catch {
      result(
        FlutterError(
          code: "AUDIO_IMPORT_FAILED",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingAudioPickerResult?(nil)
    pendingAudioPickerResult = nil
  }

  private func copyImportedAudio(_ source: URL) throws -> URL {
    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory.appendingPathComponent(
      "ImportedAudio",
      isDirectory: true
    )
    if fileManager.fileExists(atPath: directory.path) {
      try fileManager.removeItem(at: directory)
    }
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

    let destination = directory.appendingPathComponent(
      "\(UUID().uuidString)-\(source.lastPathComponent)"
    )
    if fileManager.fileExists(atPath: destination.path) {
      try fileManager.removeItem(at: destination)
    }
    try fileManager.copyItem(at: source, to: destination)
    return destination
  }

  private func removeImportedAudioIfNeeded(filePath: String) {
    let url = URL(fileURLWithPath: filePath)
    guard url.deletingLastPathComponent().lastPathComponent == "ImportedAudio" else {
      return
    }
    try? FileManager.default.removeItem(at: url)
  }

  private func transcribeWithWhisperCpp(arguments: Any?) throws -> [String: Any] {
    guard let values = arguments as? [String: Any] else {
      throw NativeBridgeFailure.invalidArguments("Missing whisper.cpp arguments")
    }
    guard let modelPath = values["modelPath"] as? String, !modelPath.isEmpty else {
      throw NativeBridgeFailure.invalidArguments("Missing whisper.cpp model path")
    }
    guard FileManager.default.fileExists(atPath: modelPath) else {
      throw NativeBridgeFailure.invalidArguments("Missing whisper.cpp model at \(modelPath)")
    }
    guard let audioData = values["pcm16Audio"] as? FlutterStandardTypedData else {
      throw NativeBridgeFailure.invalidArguments("Missing PCM16 audio data")
    }

    let languageCode = values["languageCode"] as? String ?? "zh"
    let text = try runWhisper(
      modelPath: modelPath,
      pcm16Data: audioData.data,
      languageCode: languageCode
    )
    return ["text": text]
  }

  private func transcribeAudioFileWithWhisperCpp(arguments: Any?) throws -> [String: Any] {
    guard let values = arguments as? [String: Any] else {
      throw NativeBridgeFailure.invalidArguments("Missing whisper.cpp file arguments")
    }
    guard let modelPath = values["modelPath"] as? String, !modelPath.isEmpty else {
      throw NativeBridgeFailure.invalidArguments("Missing whisper.cpp model path")
    }
    guard FileManager.default.fileExists(atPath: modelPath) else {
      throw NativeBridgeFailure.invalidArguments("Missing whisper.cpp model at \(modelPath)")
    }
    guard let audioFilePath = values["audioFilePath"] as? String, !audioFilePath.isEmpty else {
      throw NativeBridgeFailure.invalidArguments("Missing audio file path")
    }
    guard FileManager.default.fileExists(atPath: audioFilePath) else {
      throw NativeBridgeFailure.invalidArguments("Missing audio file at \(audioFilePath)")
    }

    let languageCode = values["languageCode"] as? String ?? "zh"
    defer {
      removeImportedAudioIfNeeded(filePath: audioFilePath)
    }
    let samples = try decodeAudioFileSamples(filePath: audioFilePath)
    let text = try runWhisper(
      modelPath: modelPath,
      samples: samples,
      languageCode: languageCode
    )
    return ["text": text]
  }

  private func transcribeAudioFileWithMoonshine(arguments: Any?) throws -> [String: Any] {
    let totalStartedAt = timingNow()
    guard let values = arguments as? [String: Any] else {
      throw NativeBridgeFailure.invalidArguments("Missing Moonshine file arguments")
    }
    guard let modelPath = values["modelPath"] as? String, !modelPath.isEmpty else {
      throw NativeBridgeFailure.invalidArguments("Missing Moonshine model path")
    }
    guard let audioFilePath = values["audioFilePath"] as? String, !audioFilePath.isEmpty else {
      throw NativeBridgeFailure.invalidArguments("Missing audio file path")
    }
    guard FileManager.default.fileExists(atPath: audioFilePath) else {
      throw NativeBridgeFailure.invalidArguments("Missing audio file at \(audioFilePath)")
    }

    let resolvedModelPath = try validateMoonshineModelPath(modelPath)
    let decodeStartedAt = timingNow()
    let samples = try decodeAudioFileSamples(filePath: audioFilePath)
    let decodeMs = timingMilliseconds(since: decodeStartedAt)
    if samples.isEmpty {
      print(
        "[ASR timing] native engine=Moonshine decodeMs=\(decodeMs) initMs=0 "
        + "inferMs=0 parseMs=0 totalMs=\(timingMilliseconds(since: totalStartedAt)) "
        + "audioDurationMs=0 rtf=0.000 reused=false segments=0 samples=0"
      )
      return ["segments": []]
    }

    let audioDurationMs = Int((Double(samples.count) / 16000.0) * 1000.0)
    let lockWaitStartedAt = timingNow()
    moonshineFileTranscriberLock.lock()
    let lockWaitMs = timingMilliseconds(since: lockWaitStartedAt)
    defer {
      moonshineFileTranscriberLock.unlock()
    }

    let initStartedAt = timingNow()
    let (transcribers, createdTranscriberCount) = try ensureMoonshineFileTranscribers(
      modelPath: resolvedModelPath,
      count: 1
    )
    let initMs = timingMilliseconds(since: initStartedAt)

    let inferStartedAt = timingNow()
    let transcriber = transcribers[0]
    let transcript = try transcriber.transcribeWithoutStreaming(
      audioData: samples,
      sampleRate: 16000
    )
    let inferMs = timingMilliseconds(since: inferStartedAt)

    let parseStartedAt = timingNow()
    let segments = moonshineSegments(from: transcript)
    let parseMs = timingMilliseconds(since: parseStartedAt)
    let totalMs = timingMilliseconds(since: totalStartedAt)
    let rtf = audioDurationMs > 0 ? Double(totalMs) / Double(audioDurationMs) : 0.0
    print(
      "[ASR timing] native engine=Moonshine decodeMs=\(decodeMs) "
      + "initMs=\(initMs) inferMs=\(inferMs) parseMs=\(parseMs) "
      + "lockWaitMs=\(lockWaitMs) totalMs=\(totalMs) audioDurationMs=\(audioDurationMs) "
      + "rtf=\(String(format: "%.3f", rtf)) reused=\(createdTranscriberCount == 0) "
      + "createdTranscribers=\(createdTranscriberCount) chunks=1 mode=full "
      + "segments=\(segments.count) samples=\(samples.count)"
    )
    return [
      "segments": segments,
      "text": segments.compactMap { $0["text"] as? String }.joined(separator: "\n")
    ]
  }

  private func moonshineSegments(
    from transcript: Transcript,
    offsetSeconds: Double = 0,
    minimumStartSeconds: Double? = nil,
    maximumStartSeconds: Double? = nil
  ) -> [[String: Any]] {
    return transcript.lines.compactMap { line -> [String: Any]? in
      let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if text.isEmpty {
        return nil
      }
      let absoluteStartSeconds = Double(line.startTime) + offsetSeconds
      if let minimumStartSeconds, absoluteStartSeconds < minimumStartSeconds {
        return nil
      }
      if let maximumStartSeconds, absoluteStartSeconds >= maximumStartSeconds {
        return nil
      }
      return [
        "text": text,
        "startTimeSeconds": absoluteStartSeconds,
        "durationSeconds": Double(line.duration)
      ]
    }
  }

  private func timingNow() -> UInt64 {
    return DispatchTime.now().uptimeNanoseconds
  }

  private func timingMilliseconds(since startedAt: UInt64) -> Int {
    let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
    return Int(elapsed / 1_000_000)
  }

  private func decodeAudioFileToPcm16(arguments: Any?) throws -> [String: Any] {
    guard let values = arguments as? [String: Any] else {
      throw NativeBridgeFailure.invalidArguments("Missing audio decode arguments")
    }
    guard let audioFilePath = values["audioFilePath"] as? String, !audioFilePath.isEmpty else {
      throw NativeBridgeFailure.invalidArguments("Missing audio file path")
    }
    guard FileManager.default.fileExists(atPath: audioFilePath) else {
      throw NativeBridgeFailure.invalidArguments("Missing audio file at \(audioFilePath)")
    }

    let samples = try decodeAudioFileSamples(filePath: audioFilePath)
    let pcm16Data = float32SamplesToPcm16Data(samples)
    return [
      "pcm16Audio": FlutterStandardTypedData(bytes: pcm16Data),
      "sampleRate": 16000
    ]
  }

  private func runWhisper(
    modelPath: String,
    pcm16Data: Data,
    languageCode: String
  ) throws -> String {
    let samples = pcm16ToFloat32(pcm16Data)
    return try runWhisper(
      modelPath: modelPath,
      samples: samples,
      languageCode: languageCode
    )
  }

  private func runWhisper(
    modelPath: String,
    samples: [Float],
    languageCode: String
  ) throws -> String {
    if samples.isEmpty {
      return ""
    }

    var contextParams = whisper_context_default_params()
    contextParams.use_gpu = true
    contextParams.flash_attn = false

    guard let context = modelPath.withCString({
      whisper_init_from_file_with_params($0, contextParams)
    }) else {
      throw NativeBridgeFailure.runtime("Failed to initialize whisper.cpp model")
    }
    defer {
      whisper_free(context)
    }

    var fullParams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
    fullParams.n_threads = 2
    fullParams.print_progress = false
    fullParams.print_realtime = false
    fullParams.print_timestamps = false
    fullParams.no_timestamps = true
    fullParams.translate = false

    let language = whisperLanguageCode(languageCode)
    let decodeResult = samples.withUnsafeBufferPointer { sampleBuffer in
      language.withCString { languagePointer in
        fullParams.language = languagePointer
        return whisper_full(
          context,
          fullParams,
          sampleBuffer.baseAddress,
          Int32(sampleBuffer.count)
        )
      }
    }
    if decodeResult != 0 {
      throw NativeBridgeFailure.runtime("whisper_full failed with code \(decodeResult)")
    }

    let segmentCount = whisper_full_n_segments(context)
    var parts: [String] = []
    for index in 0..<segmentCount {
      if let segment = whisper_full_get_segment_text(context, index) {
        let text = String(cString: segment).trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
          parts.append(text)
        }
      }
    }
    return parts.joined(separator: "\n")
  }

  private func decodeAudioFileSamples(filePath: String) throws -> [Float] {
    let sourceURL = URL(fileURLWithPath: filePath)
    let audioFile = try AVAudioFile(forReading: sourceURL)
    guard let inputBuffer = AVAudioPCMBuffer(
      pcmFormat: audioFile.processingFormat,
      frameCapacity: AVAudioFrameCount(audioFile.length)
    ) else {
      throw NativeBridgeFailure.runtime("Failed to allocate audio input buffer")
    }
    try audioFile.read(into: inputBuffer)

    guard let targetFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: 16000,
      channels: 1,
      interleaved: false
    ) else {
      throw NativeBridgeFailure.runtime("Failed to create target audio format")
    }
    guard let converter = AVAudioConverter(from: inputBuffer.format, to: targetFormat) else {
      throw NativeBridgeFailure.runtime("Failed to create audio converter")
    }

    let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
    let outputCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 1024
    guard let outputBuffer = AVAudioPCMBuffer(
      pcmFormat: targetFormat,
      frameCapacity: outputCapacity
    ) else {
      throw NativeBridgeFailure.runtime("Failed to allocate audio output buffer")
    }

    var didProvideInput = false
    var conversionError: NSError?
    let status = converter.convert(to: outputBuffer, error: &conversionError) {
      _, outStatus in
      if didProvideInput {
        outStatus.pointee = .noDataNow
        return nil
      }
      didProvideInput = true
      outStatus.pointee = .haveData
      return inputBuffer
    }
    if let conversionError {
      throw conversionError
    }
    if status == .error {
      throw NativeBridgeFailure.runtime("Audio conversion failed")
    }

    guard let channel = outputBuffer.floatChannelData?[0] else {
      throw NativeBridgeFailure.runtime("Converted audio has no samples")
    }
    return Array(
      UnsafeBufferPointer(start: channel, count: Int(outputBuffer.frameLength))
    )
  }

  private func pcm16ToFloat32(_ data: Data) -> [Float] {
    var samples: [Float] = []
    samples.reserveCapacity(data.count / 2)
    data.withUnsafeBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      var index = 0
      while index + 1 < bytes.count {
        let value = UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
        let sample = Int16(bitPattern: value)
        samples.append(Float(sample) / 32768.0)
        index += 2
      }
    }
    return samples
  }

  private func float32SamplesToPcm16Data(_ samples: [Float]) -> Data {
    var data = Data()
    data.reserveCapacity(samples.count * 2)
    for sample in samples {
      let scaled = max(-1.0, min(1.0, sample)) * 32767.0
      let value = Int16(clamping: Int(scaled.rounded()))
      data.append(UInt8(truncatingIfNeeded: value))
      data.append(UInt8(truncatingIfNeeded: value >> 8))
    }
    return data
  }

  private func whisperLanguageCode(_ value: String) -> String {
    if value.lowercased().hasPrefix("zh") {
      return "zh"
    }
    if value.lowercased().hasPrefix("en") {
      return "en"
    }
    return value
  }
}
