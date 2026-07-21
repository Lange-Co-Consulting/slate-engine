import Foundation

/// Session delegate for the few opt-in network features Slate offers. A redirect
/// can silently change the origin of a request (and, for cloud providers, carry
/// an Authorization header with it), so callers must explicitly use the final
/// URL rather than inheriting URLSession's redirect policy.
final class RefuseRedirectsDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                willPerformHTTPRedirection response: HTTPURLResponse,
                                newRequest request: URLRequest,
                                completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Shared infrastructure for Slate's opt-in network clients (cloud chat, the
/// updater, and the private licensing layer). Public so all of them build the
/// same hardened session.
public enum LockedDownURLSession {
    /// No persistent cache or cookies, and no automatic redirects. The caller
    /// retains normal TLS validation from URLSession/Foundation.
    public static func make() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration,
                          delegate: RefuseRedirectsDelegate(),
                          delegateQueue: nil)
    }
}
