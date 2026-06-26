import Foundation
import Observation
import OrbitKit

/// Drives the Admin section: the user list + role/delete/create. Owned by `AppModel`; only the
/// Admin section (role-gated) ever shows it. The server enforces the real guards (last-admin,
/// self-delete); this surfaces the results.
@MainActor
@Observable
final class AdminModel {
    private(set) var users: [User] = []
    private(set) var loading = false
    var errorText: String?
    /// A generated password from a create/reset — shown once for the admin to hand off.
    var revealedPassword: String?

    private let api: APIClient

    init(baseURL: URL, tokenStore: TokenStore) {
        api = APIClient(baseURL: baseURL, tokenStore: tokenStore)
    }

    func user(_ id: String) -> User? { users.first { $0.id == id } }

    func load() async {
        loading = true
        defer { loading = false }
        do { users = try await api.adminUsers() }
        catch { errorText = friendly(error) }
    }

    func setRole(_ id: String, _ role: String) async {
        await mutate { _ = try await self.api.setUserRole(id, role: role) }
    }
    func delete(_ id: String) async {
        await mutate { try await self.api.deleteUser(id) }
    }
    func createUser(email: String, name: String?) async {
        do {
            let res = try await api.createUser(CreateUserRequest(email: email, name: name))
            revealedPassword = res.password
            await load()
        } catch { errorText = friendly(error) }
    }

    private func mutate(_ op: @escaping () async throws -> Void) async {
        do { try await op(); await load() }
        catch { errorText = friendly(error) }
    }

    private func friendly(_ error: Error) -> String {
        if case APIError.unauthorized = error { return "Session expired — sign in again." }
        if case APIError.http(_, let body) = error, let body, !body.isEmpty { return body }
        return "Request failed — check your connection."
    }
}
