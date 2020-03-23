import Foundation
import LanguageServerProtocol
import LanguageServerProtocolJSONRPC
import OSLog

final class LanguageServer {
    static private var servers = [URL: LanguageServer]()

    private let teamIdentifierPrefix: String
    private let resource: String
    private let slug: String

    private let clientToServer = Pipe()
    private let serverToClient = Pipe()

    private lazy var connection = JSONRPCConnection(
        protocol: .lspProtocol,
        inFD: serverToClient.fileHandleForReading.fileDescriptor,
        outFD: clientToServer.fileHandleForWriting.fileDescriptor
    )

    private let queue = DispatchQueue(label: "request-queue")

    private var isInitialized = false
    private let serverProcess = Process()

    init(teamIdentifierPrefix: String, resource: String, slug: String) {
        self.teamIdentifierPrefix = teamIdentifierPrefix
        self.resource = resource
        self.slug = slug
    }

    func sendInitializeRequest(context: [String : String], completion: @escaping (Result<InitializeRequest.Response, ResponseError>) -> Void) {
        if isInitialized {
            completion(Result<InitializeRequest.Response, ResponseError>.success(InitializeRequest.Response(capabilities: ServerCapabilities())))
            return
        }

        guard let serverPath = context["serverPath"] else { return }
        guard let SDKPath = context["SDKPath"] else { return }
        guard let target = context["target"] else { return }

        os_log("[initialize] server: %{public}s, SDK: %{public}s, target: %{public}s", log: log, type: .debug, "\(serverPath) \(SDKPath) \(target)")

        let rootURI = Workspace.documentRoot(teamIdentifierPrefix: teamIdentifierPrefix, resource: resource, slug: slug)

        connection.start(receiveHandler: Client())
        isInitialized = true

        serverProcess.launchPath = serverPath
        if let toolchain = context["toolchain"] {
            serverProcess.environment = [
                "SOURCEKIT_TOOLCHAIN_PATH": toolchain
            ]
        }
        serverProcess.arguments = [
            "--log-level", "info",
            "-Xswiftc", "-sdk",
            "-Xswiftc", SDKPath,
            "-Xswiftc", "-target",
            "-Xswiftc", target
        ]

        os_log("Initialize language server: %{public}s", log: log, type: .debug, "\(serverProcess.launchPath!) \(serverProcess.arguments!.joined(separator: " "))")

        serverProcess.standardOutput = serverToClient
        serverProcess.standardInput = clientToServer
        serverProcess.terminationHandler = { [weak self] process in
            self?.connection.close()
        }
        serverProcess.launch()

        let request = InitializeRequest(
            rootURI: DocumentURI(rootURI), capabilities: ClientCapabilities(), workspaceFolders: [WorkspaceFolder(uri: DocumentURI(rootURI))]
        )
        _ = connection.send(request, queue: queue) {
            completion($0)
        }
    }

    func sendInitializedNotification(context: [String : String]) {
        connection.send(InitializedNotification())
    }

    func sendDidOpenNotification(context: [String : String], document: String, text: String) {
        os_log("[didOpen] document %{public}s", log: log, type: .debug, "\(document)")

        let documentRoot = Workspace.documentRoot(teamIdentifierPrefix: teamIdentifierPrefix, resource: resource, slug: slug)
        let identifier = documentRoot.appendingPathComponent(document)

        let ext = identifier.pathExtension
        let language: Language
        switch ext {
        case "swift":
            language = .swift
        case "m":
            language = .objective_c
        case "mm":
            language = .objective_cpp
        case "c":
            language = .c
        case "cpp", "cc", "cxx", "c++":
            language = .cpp
        case "h":
            language = .objective_c
        case "hpp":
            language = .objective_cpp
        default:
            language = .swift
        }

        let document = TextDocumentItem(
            uri: DocumentURI(identifier),
            language: language,
            version: 1,
            text: text
        )
        connection.send(DidOpenTextDocumentNotification(textDocument: document))
    }

    func sendDocumentSymbolRequest(context: [String : String], document: String, completion: @escaping (Result<DocumentSymbolRequest.Response, ResponseError>) -> Void) {
        let documentRoot = Workspace.documentRoot(teamIdentifierPrefix: teamIdentifierPrefix, resource: resource, slug: slug)
        let identifier = documentRoot.appendingPathComponent(document)

        let documentSymbolRequest = DocumentSymbolRequest(
            textDocument: TextDocumentIdentifier(DocumentURI(identifier))
        )
        _ = connection.send(documentSymbolRequest, queue: queue) {
            completion($0)
        }
    }

    func sendHoverRequest(context: [String : String], document: String, line: Int, character: Int, completion: @escaping (Result<HoverRequest.Response, ResponseError>) -> Void) {
        let documentRoot = Workspace.documentRoot(teamIdentifierPrefix: teamIdentifierPrefix, resource: resource, slug: slug)
        let identifier = documentRoot.appendingPathComponent(document)

        let hoverRequest = HoverRequest(
            textDocument: TextDocumentIdentifier(DocumentURI(identifier)),
            position: Position(line: line, utf16index: character)
        )
        _ = connection.send(hoverRequest, queue: queue) {
            completion($0)
        }
    }

    func sendDefinitionRequest(context: [String : String], document: String, line: Int, character: Int, completion: @escaping (Result<DefinitionRequest.Response, ResponseError>) -> Void) {
        let documentRoot = Workspace.documentRoot(teamIdentifierPrefix: teamIdentifierPrefix, resource: resource, slug: slug)
        let identifier = documentRoot.appendingPathComponent(document)

        let definitionRequest = DefinitionRequest(
            textDocument: TextDocumentIdentifier(DocumentURI(identifier)),
            position: Position(line: line, utf16index: character)
        )
        _ = connection.send(definitionRequest, queue: queue) {
            completion($0)
        }
    }

    func sendShutdownRequest(context: [String : String], completion: @escaping (Result<ShutdownRequest.Response, ResponseError>) -> Void) {
        guard isInitialized else {
            completion(.success(ShutdownRequest.Response()))
            return
        }
        let request = ShutdownRequest()
        _ = connection.send(request, queue: queue) {
            completion($0)
        }
    }

    func sendExitNotification() {
        connection.send(ExitNotification())
        serverProcess.terminate()
    }
}

private final class Client: MessageHandler {
    func handle<Notification>(_ notification: Notification, from: ObjectIdentifier) where Notification: NotificationType {
        os_log("%{public}s", log: log, type: .debug, "\(notification)")
    }

    func handle<Request>(_ request: Request, id: RequestID, from: ObjectIdentifier, reply: @escaping (Result<Request.Response, ResponseError>) -> Void) where Request: RequestType {}
}
