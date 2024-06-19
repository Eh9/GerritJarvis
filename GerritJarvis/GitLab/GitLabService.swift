//
//  GitLabService.swift
//  GerritJarvis
//
//  Created by hudi on 2024/5/11.
//  Copyright © 2024 Chuanren Shang. All rights reserved.
//

import Foundation
import GitLabSwift
import OSLog
import ComposableArchitecture

private enum GitLabServiceKey: DependencyKey {
    static let liveValue: GitlabService = .shared
}

extension DependencyValues {
    var gitlabService: GitlabService {
        get { self[GitLabServiceKey.self] }
        set { self[GitLabServiceKey.self] = newValue }
    }
}

struct NewEventType: OptionSet {
    let rawValue: Int

    static let comment = NewEventType(rawValue: 1 << 0)
    static let approval = NewEventType(rawValue: 1 << 1)
    static let newMR = NewEventType(rawValue: 1 << 2)

    static let noneNewEvent: NewEventType = []
}

class GitlabService {
    static let shared = GitlabService()
    private init() {}

    @Shared(.shouldNotifyNewIncomingReview) var shouldNotifyNewIncomingReview = false
    @Shared(.onlyNotifyEventAboutMySelf) var onlyNotifyEventAboutMySelf = true

    private var user: String!
    private var gitlab: GLApi!
    private let logger = Logger()

    private(set) var trackingMRs: [GLModel.MergeRequest] = []
    private(set) var projectInfos: [Int: GLModel.Project] = [:] // projectID: project
    private(set) var discussionInfos: [Int: [GLModel.Discussion]] = [:] // mr.id: notes
    private(set) var approvalInfos: [Int: GLModel.MergeRequestApprovals] = [:] // mr.id: approvalInfo
    private(set) var mrsUpdated: [GLModel.MergeRequest] = []

    private var mrsNotTracking: [GLModel.MergeRequest] = []
    private var mrUpdateTime: [Int: Date?] = [:] // mr.id: updateDate
    private var hasFinishedFirstFetch = false
    private var mrsNewEventInfo: [Int: NewEventType] = [:]

    var showingMRs: [GitLabReviewDisplay.State] {
        trackingMRs.map { mr in
            let unResolvedThreads = discussionInfos[mr.id]?.filter { info in
                info.notes.contains { $0.resolvable == true && $0.resolved == false }
            }
            return GitLabReviewDisplay.State(
                id: mr.id,
                baseCell: ReviewDisplay.State(
                    project: projectInfos[mr.project_id]?.name ?? "null_project",
                    branch: mr.source_branch ?? "null_branch",
                    targetBranch: mr.target_branch,
                    name: mr.author?.name ?? "null_name",
                    commitMessage: mr.title ?? "null_message",
                    avatarUrl: mr.author?.avatar_url,
                    hasNewEvent: hasNewEvent(mr),
                    isMergeConflict: mr.has_conflicts ?? false
                ),
                upvotes: mr.upvotes,
                downvotes: mr.downvotes,
                threadCount: unResolvedThreads?.count ?? 0,
                approved: (approvalInfos[mr.id]?.approved_by?.map(\.user.name) ?? []).count > 0
            )
        }
    }

    var newEventCount: Int {
        trackingMRs.reduce(0) { result, mr in result + (hasNewEvent(mr) ? 1 : 0) }
    }

    func setup() async {
        self.user = GitLabConfigs.user
        guard let url = URL(string: GitLabConfigs.baseUrl.appending("/api/v4")) else {
            return
        }
        gitlab = GLApi(config: .init(baseURL: url) { $0.token = GitLabConfigs.token })
        await setupUserInfo()
    }

    func fetchMRs() async {
        guard !user.isEmpty else { return }
        await setupUserInfo()

        let mrs: [GLModel.MergeRequest] = await withTaskGroup(
            of: [GLModel.MergeRequest].self,
            returning: [GLModel.MergeRequest].self
        ) { [weak self] taskGroup in
            guard let self else { return [] }
            for text in concernedTexts {
                taskGroup.addTask { await self.fetchMRList(searchText: text) ?? [] }
            }
            for groupId in GitLabConfigs.groupInfo.observedGroups {
                taskGroup.addTask { await self.fetchMRListInGroup(id: groupId) ?? [] }
            }
            taskGroup.addTask { await self.fetchOwnedMRs() ?? [] }
            taskGroup.addTask { await self.fetchReviewedMRs() ?? [] }
            return await taskGroup.reduce(into: []) { result, groupMRs in
                result.append(contentsOf: groupMRs)
            }.reduce(into: []) { result, mr in
                if !result.contains(where: { $0.id == mr.id }), mr.draft != true {
                    result.append(mr)
                }
            }.sorted {
                self.sortMRs($0, $1)
            }.reduce(into: []) { result, mr in // 把自己的 MR 放到最前
                if mr.author?.isNotMe == false { result.insert(mr, at: 0) }
                else { result.append(mr) }
            }
        }
        notifyNewMR(newMrs: mrs)
        mrsNotTracking = trackingMRs.filter { mr in !mrs.contains(where: { $0.id == mr.id }) }
        mrsUpdated = mrs.compactMap { if let t = mrUpdateTime[$0.id], t != $0.updated_at { $0 } else { nil } }
        notifyVotes(newMrs: mrs)
        trackingMRs = mrs
        mrUpdateTime = .init(uniqueKeysWithValues: mrs.map { ($0.id, $0.updated_at) })
        for mr in mrs {
            async let project =
                projectInfos[mr.project_id] == nil ? fetchProject(id: mr.project_id) : nil
            async let discussions =
                discussionInfos[mr.id] == nil ? fetchMRDiscussions(id: mr.iid, projectId: mr.project_id) : nil
            async let approvals =
                approvalInfos[mr.id] == nil ? fetchMRApprovals(id: mr.iid, projectId: mr.project_id) : nil
            if let project = await project { projectInfos[mr.project_id] = project }
            if let discussions = await discussions { discussionInfos[mr.id] = discussions.filter { $0.isNotSystem } }
            if let approvals = await approvals { approvalInfos[mr.id] = approvals }
        }
        await notityNotTrackingMR()
        await notifyUpdatedMR()
        // TODO: repeat notify when fetch error
        hasFinishedFirstFetch = true
    }

    func resetNewStateOfMR(id: Int) {
        mrsNewEventInfo[id] = nil
    }

    func clearNewEvent() {
        mrsNewEventInfo = [:]
    }

    func clear() {
        trackingMRs = []
        projectInfos = [:]
        discussionInfos = [:]
        approvalInfos = [:]
        mrsUpdated = []

        mrsNotTracking = []
        mrUpdateTime = [:]
        GitLabConfigs.groups = []
        GitLabConfigs.userInfo = nil
        GitLabConfigs.user = ""
        GitLabConfigs.hasSetup = GitLabConfigs.userInfo != nil
        Task { await GitLabConfigs.setupGroupInfo() }
        hasFinishedFirstFetch = false
        mrsNewEventInfo = [:]
    }

    private var concernedTexts: [String] {
        var concernedTexts = GitLabConfigs.groupInfo.groups.filter {
            GitLabConfigs.groupInfo.observedGroups.contains($0.id)
        }.compactMap(\.fullName)
        if let userName = GitLabConfigs.user.split(separator: "@").first { concernedTexts.append(String(userName)) }
        return concernedTexts.map { "@" + $0 }
    }

    private func hasNewEvent(_ mr: GLModel.MergeRequest?) -> Bool {
        guard let mr, let info = mrsNewEventInfo[mr.id] else { return false }
        return info != .noneNewEvent
    }

    private func notifyNewMR(newMrs: [GLModel.MergeRequest]) {
        guard hasFinishedFirstFetch, shouldNotifyNewIncomingReview else { return }
        newMrs.forEach { newMr in
            guard !trackingMRs.contains(where: { $0.id == newMr.id }),
                  newMr.author?.isNotMe == true
            else { return }
            if mrsNewEventInfo[newMr.id] == nil { mrsNewEventInfo[newMr.id] = .noneNewEvent }
            mrsNewEventInfo[newMr.id]?.insert(.newMR)
            UserNotificationHandler.shared.sendNotification(
                title: "\(newMr.title ?? "")",
                body: "New Review MergeRequest from \(newMr.author?.name ?? "null_name")",
                url: newMr.web_url.absoluteString
            ) { [weak self] in
                self?.mrsNewEventInfo[newMr.id]?.remove(.newMR)
            }
        }
    }

    // TODO: how to filter votes action from the user
    private func notifyVotes(newMrs: [GLModel.MergeRequest]) {
        newMrs.forEach { newMr in
            if let oldMr = trackingMRs.first(where: { $0.id == newMr.id }),
               oldMr.downvotes != newMr.downvotes || oldMr.upvotes != newMr.upvotes
            {
                if onlyNotifyEventAboutMySelf, newMr.author?.isNotMe == true { return }
                UserNotificationHandler.shared.sendNotification(
                    title: "\(newMr.title ?? "")",
                    body: "votes updated. 👍:\(newMr.upvotes)     👎:\(newMr.downvotes)",
                    url: newMr.web_url.absoluteString
                )
            }
        }
    }

    private func notityNotTrackingMR() async {
        for mr in mrsNotTracking {
            if onlyNotifyEventAboutMySelf, mr.author?.isNotMe == true { return }
            if let updatedMR = await fetchMRStatus(id: mr.iid, projectId: mr.project_id) {
                var message: String = ""
                if let mergedBy = updatedMR.merged_by, let mergedAt = updatedMR.merged_at, mergedBy.isNotMe {
                    message = "merged by \(mergedBy.name) at \(mergedAt)"
                }
                if let closedBy = updatedMR.closed_by, let closedAt = updatedMR.closed_at, closedBy.isNotMe {
                    message = "closed by \(closedBy.name) at \(closedAt)"
                }
                guard !message.isEmpty else { return }
                UserNotificationHandler.shared.sendNotification(
                    title: "\(mr.title ?? "")",
                    body: message,
                    url: updatedMR.web_url.absoluteString
                )
            }
        }
        mrsNotTracking.removeAll()
    }

    private func notifyUpdatedMR() async {
        // discusstion updated
        for mr in mrsUpdated {
            guard let discussions = await fetchMRDiscussions(id: mr.iid, projectId: mr.project_id) else { continue }
            let newDiscussionInfos = discussions.filter { $0.isNotSystem }
            defer { discussionInfos[mr.id] = newDiscussionInfos }
            guard let oldNotes = discussionInfos[mr.id]?.flatMap(\.notes) else { continue }
            let newNotes = if onlyNotifyEventAboutMySelf {
                newDiscussionInfos.filter {
                    mr.author?.isNotMe == false || $0.iParticipatedInDiscussion || $0.mentionsAnyTexts(concernedTexts)
                }.flatMap(\.notes)
            } else {
                newDiscussionInfos.flatMap(\.notes)
            }
            let updateNotes: [GLModel.Discussion.Note] = newNotes.filter { $0.author?.isNotMe == true }
                .compactMap { note in
                    if let oldNote = oldNotes.first(where: { $0.id == note.id }),
                       oldNote.updated_at == note.updated_at
                    { return nil }
                    return note
                }.sorted { $0.updated_at! < $1.updated_at! }
            if !updateNotes.isEmpty {
                if mrsNewEventInfo[mr.id] == nil { mrsNewEventInfo[mr.id] = .noneNewEvent }
                mrsNewEventInfo[mr.id]?.insert(.comment)
                UserNotificationHandler.shared.sendNotification(
                    title: "\(mr.title ?? "")",
                    body: "New comments",
                    url: mr.web_url.absoluteString + "#note_\(updateNotes.first!.id)"
                ) { [weak self] in
                    self?.mrsNewEventInfo[mr.id]?.remove(.comment)
                }
            }
        }
        // approval updated
        for mr in mrsUpdated {
            guard let approval = await fetchMRApprovals(id: mr.iid, projectId: mr.project_id) else { continue }
            defer { approvalInfos[mr.id] = approval }
            guard let oldApproval = approvalInfos[mr.id] else { continue }
            if let newUsers = approval.approved_by?.compactMap({ approvalBy in
                if (oldApproval.approved_by ?? []).contains(where: { $0.user.id == approvalBy.user.id }) == false,
                   approvalBy.user.isNotMe
                { return approvalBy.user } else { return nil }
            }), !newUsers.isEmpty {
                UserNotificationHandler.shared.sendNotification(
                    title: "\(mr.title ?? "")",
                    body: "approved by \(newUsers.map(\.name).joined(separator: "、"))",
                    url: mr.web_url.absoluteString
                )
            }
        }
    }

    private func setupUserInfo() async {
        GitLabConfigs.groups = await fetchGroupInfo()
        GitLabConfigs.userInfo = await fetchUserInfo()
        if let email = GitLabConfigs.userInfo?.email { GitLabConfigs.user = email }
        GitLabConfigs.hasSetup = GitLabConfigs.userInfo != nil
        await GitLabConfigs.setupGroupInfo()
    }

    private func sortMRs(_ mr1: GLModel.MergeRequest, _ mr2: GLModel.MergeRequest) -> Bool {
        guard let t1 = mr1.updated_at, let t2 = mr2.updated_at else { return false }
        return t1 > t2
    }
}

// MARK: - GitLab Requests

private extension GitlabService {
    private func fetchUserInfo() async -> GLModel.User? {
        do { return try await gitlab.users.me().decode() }
        catch {
            print(error)
            return nil
        }
    }

    private func fetchGroupInfo() async -> [GLModel.Group] {
        do {
            let response: GLResponse<[GLModel.Group]> = try await gitlab.execute(.init(endpoint: CustomURLs.groups))
            let result = try response.decode() ?? []
            return result
        } catch {
            logger.error("\(error, privacy: .public)")
            return []
        }
    }

    private func fetchMRList(searchText: String) async -> [GLModel.MergeRequest]? {
        guard let text = searchText.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else { return nil }
        do {
            let response: GLResponse<[GLModel.MergeRequest]>? =
                try await gitlab.execute(.init(endpoint: CustomURLs.mergeRequest(searchText: text)))
            return try response?.decode()
        } catch {
            logger.error("\(error, privacy: .public)")
            return nil
        }
    }

    private func fetchMRListInGroup(id: Int) async -> [GLModel.MergeRequest]? {
        do {
            return try await gitlab.mergeRequest.list(group: id) {
                $0.state = .opened
                $0.perPage = 100
            }.decode()
        } catch {
            logger.error("\(error, privacy: .public)")
            return nil
        }
    }

    private func fetchOwnedMRs() async -> [GLModel.MergeRequest]? {
        do {
            return try await gitlab.mergeRequest.list(options: {
                $0.authorId = GitLabConfigs.userInfo?.id
                $0.state = .opened
                $0.perPage = 100
            }).decode()
        } catch {
            logger.error("\(error, privacy: .public)")
            return nil
        }
    }

    private func fetchReviewedMRs() async -> [GLModel.MergeRequest]? {
        do {
            return try await gitlab.mergeRequest.list(options: {
                $0.reviewerId = GitLabConfigs.userInfo?.id
                $0.state = .opened
                $0.perPage = 100
            }).decode()
        } catch {
            logger.error("\(error, privacy: .public)")
            return nil
        }
    }

    private func fetchMRStatus(id: Int, projectId: Int) async -> GLModel.MergeRequest? {
        do { return try await gitlab.mergeRequest.get(id, project: .id(projectId)).decode() }
        catch {
            logger.error("\(error, privacy: .public)")
            return nil
        }
    }

    private func fetchProject(id: Int) async -> GLModel.Project? {
        do { return try await gitlab.projects.get(project: .id(id)).decode() }
        catch {
            logger.error("\(error, privacy: .public)")
            return nil
        }
    }

    private func fetchMRDiscussions(id: Int, projectId: Int, page: Int = 1) async -> [GLModel.Discussion]? {
        do {
            let response: GLResponse<[GLModel.Discussion]>? =
                try await gitlab.execute(
                    .init(endpoint: CustomURLs.discusstions(mrId: id, projectId: projectId, page: page))
                )
            let result = try response?.decode() ?? []
            if let nextPage = Int(response?.httpResponse.headers.value(for: "x-next-page") ?? ""), nextPage > 0 {
                let moreData = await fetchMRDiscussions(id: id, projectId: projectId, page: nextPage)
                return result + (moreData ?? [])
            } else {
                return result
            }
        } catch {
            logger.error("\(error, privacy: .public)")
            return nil
        }
    }

    private func fetchMRApprovals(id: Int, projectId: Int) async -> GLModel.MergeRequestApprovals? {
        do { return try await gitlab.mergeRequest.approvals(id, project: .id(projectId)).decode() }
        catch {
            logger.error("\(error, privacy: .public)")
            return nil
        }
    }
}

// MARK: - Jump URL getter

extension GitlabService {
    func mrURL(id: Int) -> URL? {
        guard let mr = trackingMRs.first(where: { $0.id == id }) else { return nil }
        return mr.web_url
    }

    func authorURL(id: Int) -> URL? {
        guard let mr = trackingMRs.first(where: { $0.id == id }) else { return nil }
        return .init(string: mr.author?.web_url ?? "")
    }

    func projectURL(id: Int) -> URL? {
        guard let mr = trackingMRs.first(where: { $0.id == id }) else { return nil }
        return projectInfos[mr.project_id]?.web_url
    }

    func branchURL(id: Int) -> URL? {
        guard let mr = trackingMRs.first(where: { $0.id == id }),
              let projectURL = projectInfos[mr.project_id]?.web_url,
              let sourceBranch = mr.source_branch
        else { return nil }
        return projectURL.appendingPathComponent("commits/\(sourceBranch)")
    }
}

private extension GLModel.User {
    var isNotMe: Bool {
        id != GitLabConfigs.userInfo?.id
    }
}

private extension GLModel.Discussion {
    var isNotSystem: Bool {
        notes.contains { $0.system == false }
    }

    var iParticipatedInDiscussion: Bool {
        notes.contains { $0.author?.isNotMe == false }
    }

    func mentionsAnyTexts(_ texts: [String]) -> Bool {
        texts.contains { mentionsText($0) }
    }

    func mentionsText(_ text: String) -> Bool {
        notes.contains { $0.body?.contains(text) == true }
    }
}

// MARK: - Extra Gitlab Apis

private enum CustomURLs: GLEndpoint {
    case groups
    case mergeRequest(searchText: String)
    case discusstions(mrId: Int, projectId: Int, page: Int)

    public var value: String {
        switch self {
        case .groups: "/groups"
        case let .mergeRequest(searchText): "/merge_requests?state=opened&scope=all&per_page=100&search=\(searchText)"
        case let .discusstions(mrId, projectId, page):
            "/projects/\(projectId)/merge_requests/\(mrId)/discussions?page=\(page)"
        }
    }
}
