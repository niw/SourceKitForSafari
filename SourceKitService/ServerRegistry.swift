import Foundation

final class ServerRegistry {
    static let shared = ServerRegistry()
    private var servers = [URL: LanguageServer]()

    private init() {}

    func get(teamIdentifierPrefix: String, resource: String, slug: String) -> LanguageServer {
        let key = makeKey(host: resource, slug: slug)
        if let server = servers[key] {
            return server
        }
        
        let server = LanguageServer(teamIdentifierPrefix: teamIdentifierPrefix, resource: resource, slug: slug)
        servers[key] = server
        return server
    }

    func remove(resource: String, slug: String) {
        servers.removeValue(forKey: makeKey(host: resource, slug: slug))
    }

    private func makeKey(host: String, slug: String) -> URL {
        URL(
            string: host.replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "/", with: "")
                .appending("/")
                .appending(slug)
            )!
    }
}
