import Foundation

// REST request/response models mirroring the apiserver. Fields are generously optional so a
// newer/older server shape decodes rather than throwing. Only what Phase 0 needs is modeled;
// extend as the app grows.

public struct User: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let email: String
    public let name: String?
    public let role: String?
}

public struct LoginRequest: Codable, Sendable {
    public let email: String
    public let password: String
    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

public struct LoginResponse: Codable, Sendable {
    public let accessToken: String
    public let user: User
}

public struct SetupStatus: Codable, Sendable {
    public let needsSetup: Bool
}

public struct Agent: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let model: String?
    public let permissionMode: String?
    public let workDir: String?
}

public struct Runner: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let status: RunnerStatus?
    public let online: Bool?
    public let version: String?
    public let maxConcurrent: Int?
}

/// A session row (list + detail share this; detail carries the extra worktree/stat fields).
public struct Session: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String?
    public let status: RunStatus
    public let agentId: String?
    public let assignedRunnerId: String?
    public let pendingApprovals: Int?
    public let branch: String?
    public let updatedAt: String?
}

/// POST /sessions/:id/turns — send a user message or raw shell command.
public struct SessionTurnRequest: Codable, Sendable {
    public let clientTurnId: String   // client UUID, idempotency key
    public let content: String
    public let kind: String           // "message" | "shell"
    public let attachmentIds: [String]?
    public init(clientTurnId: String, content: String, kind: String = "message", attachmentIds: [String]? = nil) {
        self.clientTurnId = clientTurnId
        self.content = content
        self.kind = kind
        self.attachmentIds = attachmentIds
    }
}

public struct TurnAccepted: Codable, Sendable {
    public let turnId: String?
    public let seq: Int?
    public let status: String?
}

/// POST /sessions — create a session with an initial prompt.
public struct CreateSessionRequest: Codable, Sendable {
    public let prompt: String
    public let title: String?
    public let agentId: String?
    public let assignedRunnerId: String?
    public let model: String?
    public let permissionMode: String?
    public let attachmentIds: [String]?
    public init(prompt: String, title: String? = nil, agentId: String? = nil, assignedRunnerId: String? = nil,
                model: String? = nil, permissionMode: String? = nil, attachmentIds: [String]? = nil) {
        self.prompt = prompt
        self.title = title
        self.agentId = agentId
        self.assignedRunnerId = assignedRunnerId
        self.model = model
        self.permissionMode = permissionMode
        self.attachmentIds = attachmentIds
    }
}

/// The durable approval record (GET /sessions/:id/approvals). Distinct from the live
/// `approval_request` SSE nudge; this is the source of truth on (re)connect.
public struct ApprovalInfo: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let toolName: String?
    public let status: String?
    public let input: JSONValue?
}

public enum ApprovalBehavior: String, Codable, Sendable {
    case allow
    case deny
}

/// POST /sessions/:id/approvals/:approvalId/decision
public struct ApprovalDecisionRequest: Codable, Sendable {
    public let behavior: ApprovalBehavior
    public let message: String?
    /// AskUserQuestion answers: question text → selected labels.
    public let answers: [String: [String]]?
    /// Optional "remember this kind" rule (tool/prefix). Kept as JSON to track the server shape.
    public let rememberRule: JSONValue?
    public init(behavior: ApprovalBehavior, message: String? = nil,
                answers: [String: [String]]? = nil, rememberRule: JSONValue? = nil) {
        self.behavior = behavior
        self.message = message
        self.answers = answers
        self.rememberRule = rememberRule
    }
}
