import Foundation

struct Workspace {
    static func root(teamIdentifierPrefix: String) -> URL {
        FileManager().containerURL(forSecurityApplicationGroupIdentifier: "\(teamIdentifierPrefix).com.kishikawakatsumi.SourceKitForSafari")!
    }

    static func documentRoot(teamIdentifierPrefix: String, resource: String, slug: String) -> URL {
        root(teamIdentifierPrefix: teamIdentifierPrefix).appendingPathComponent(resource).appendingPathComponent(slug)
    }
}
