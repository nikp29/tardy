import Foundation

/// Minimal seam over URLSession so tests can inject canned responses.
protocol HTTPFetching {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPFetching {}
