import Foundation

/// Returns true if the given URL string points to a loopback address.
public func isLocalhostURL(_ urlString: String) -> Bool {
    guard let url = URL(string: urlString), let host = url.host else { return false }
    return isLocalhostHost(host)
}

/// Returns true if the given host string is a loopback host.
public func isLocalhostHost(_ host: String) -> Bool {
    let lowered = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
    // URL(string:).host strips brackets from IPv6, so "[::1]" becomes "::1".
    return lowered == "localhost"
        || lowered == "::1"
        || lowered == "0:0:0:0:0:0:0:1"
        || lowered.hasPrefix("127.")
}
