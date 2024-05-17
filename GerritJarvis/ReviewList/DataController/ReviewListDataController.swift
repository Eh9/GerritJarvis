//
//  GerritAgent.swift
//  GerritJarvis
//
//  Created by Chuanren Shang on 2019/5/10.
//  Copyright © 2019 Chuanren Shang. All rights reserved.
//

import Cocoa
import GitLabSwift

class ReviewListDataController: NSObject {
    static let ReviewListUpdatedNotification = Notification.Name("ReviewListUpdatedNotification")
    static let ReviewListNewEventsNotification = Notification.Name("ReviewListNewEventsNotification")
    static let ReviewListNewEventsKey = "ReviewListNewEventsKey"
    static let ReviewChangeNumberKey = "ReviewChangeNumberKey"

    private let ReviewNewEventStatusKey = "ReviewNewEventStatusKey"
    private let ReviewNewCommentsKey = "ReviewNewCommentsKey"
    private let ReviewLastestMessageIdKey = "ReviewLastestMessageIdKey"

    private(set) var cellViewModels = [ReviewListCellViewModel]()
    private(set) var changes: [Change]?
    @objc dynamic var isFetchingList: Bool = false

    private var gerritService: GerritService?
    private var gitlabService: GitlabService = .shared
    private var timer: Timer?
    private var isFirstLoading: Bool = false
    private var newEventStates: [String: Bool] {
        get {
            guard let status = UserDefaults.standard.object(forKey: ReviewNewEventStatusKey) as? [String: Bool] else {
                return [String: Bool]()
            }
            return status
        }
        set {
            UserDefaults.standard.set(newValue, forKey: ReviewNewEventStatusKey)
        }
    }

    private var newComments: [String: Int] {
        get {
            guard let comments = UserDefaults.standard.object(forKey: ReviewNewCommentsKey) as? [String: Int] else {
                return [String: Int]()
            }
            return comments
        }
        set {
            UserDefaults.standard.set(newValue, forKey: ReviewNewCommentsKey)
        }
    }

    private var latestMessageIds: [String: String] {
        get {
            guard let messageIds = UserDefaults.standard.object(forKey: ReviewLastestMessageIdKey) as? [String: String]
            else {
                return [String: String]()
            }
            return messageIds
        }
        set {
            UserDefaults.standard.set(newValue, forKey: ReviewLastestMessageIdKey)
        }
    }

    override init() {
        super.init()
        NSUserNotificationCenter.default.delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAccountUpdated(notification:)),
            name: ConfigManager.AccountUpdatedNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRefreshFrequencyUpdated(notification:)),
            name: ConfigManager.RefreshFrequencyUpdatedNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setupAccount() {
        stopTimer()
        isFirstLoading = true
        if let user = ConfigManager.shared.user,
           let password = ConfigManager.shared.password,
           let baseUrl = ConfigManager.shared.baseUrl
        {
            gerritService = GerritService(user: user, password: password, baseUrl: baseUrl)
        }
        Task {
            defer { startTimer() }
            guard GitLabConfigs.userInfo == nil else { return }
            await gitlabService.setup()
        }
    }

    func fetchReviewList() {
        if isFetchingList {
            return
        }
        isFetchingList = true
        let dispathGroup = DispatchGroup()
        var newChanges: [Change] = []
        if let gerritService = gerritService {
            dispathGroup.enter()
            gerritService.fetchReviewList { changes in
                defer { dispathGroup.leave() }
                guard let changes = changes else {
                    return
                }
                newChanges = self.reorderChanges(changes)
                self.checkMerged(newChanges)
            }
        }
        dispathGroup.enter()
        Task {
            defer { dispathGroup.leave() }
            await gitlabService.fetchMRs()
        }
        dispathGroup.notify(queue: .main) {
            self.updateChanges(newChanges)
            self.updateGitlabMRs()
            self.updateAllNewEventsCount()
            self.sendReviewListUpdatedNotification()
            self.isFirstLoading = false
            self.isFetchingList = false
        }
    }

    func updateAllNewEventsCount() {
        var newEvents = 0
        for vm in cellViewModels {
            if vm.hasNewEvent {
                newEvents += 1
            }
        }
        saveNewEventStates()
        saveNewComments()
        saveLatestMessageIds()

        let userInfo = [ReviewListDataController.ReviewListNewEventsKey: newEvents]
        NotificationCenter.default.post(
            name: ReviewListDataController.ReviewListNewEventsNotification,
            object: nil,
            userInfo: userInfo
        )
    }

    func clearAllNewEvents() {
        for vm in cellViewModels {
            vm.resetEvent()
        }
        updateAllNewEventsCount()
    }

    func revisionRange(of changeNumber: Int) -> (Int, Int)? {
        guard let changes = changes else {
            return nil
        }
        var target: Change?
        for change in changes {
            if let number = change.number, number == changeNumber {
                target = change
                break
            }
        }
        return target?.diffRevisionRange()
    }

    @objc func handleAccountUpdated(notification: Notification) {
        setupAccount()
    }

    @objc func handleRefreshFrequencyUpdated(notification: Notification) {
        stopTimer()
        startTimer()
    }
}

// MARK: - Refresh Timer

extension ReviewListDataController {
    private func startTimer() {
        if timer != nil {
            return
        }
        let interval: TimeInterval = ConfigManager.shared.refreshFrequency * 60
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true, block: { _ in
            self.fetchReviewList()
        })
        timer?.fire()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Update Changes

extension ReviewListDataController {
    private func updateChanges(_ newChanges: [Change]) {
        var viewModels = [ReviewListCellViewModel]()
        for change in newChanges {
            var originChange: Change?
            guard let newId = change.id else {
                continue
            }
            if let changes = changes {
                for old in changes {
                    guard let oldId = old.id else {
                        continue
                    }
                    if newId == oldId {
                        originChange = old
                        break
                    }
                }
            }

            let viewModel = ReviewListCellViewModel(change: change)

            var commentCounts = 0
            if let originCommentCounts = newComments[change.changeNumberKey()] {
                commentCounts = originCommentCounts
            }
            var messageId = originChange?.messages?.last?.id
            if let originMessageId = latestMessageIds[change.changeNumberKey()] {
                messageId = originMessageId
            }
            let messages = change.newMessages(baseOn: messageId)
            let originRevision = originChange?.messages?.last?.revisionNumber ?? 1
            let comments = GerritUtils.parseNewCommentCounts(messages, originRevision: originRevision)
            if change.shouldListenReviewEvent() {
                viewModel.newComments = GerritUtils.calculateNewCommentCount(
                    originCount: commentCounts,
                    comments: comments,
                    authorFilter: { author in
                        return change.shouldListen(author: author)
                    }
                )
            }

            var raiseMergeConflict = false
            if let hasNewEvent = newEventStates[change.newEventKey()] {
                if hasNewEvent {
                    viewModel.hasNewEvent = hasNewEvent
                } else {
                    viewModel.resetEvent()
                }
            } else if change.isOurs() {
                raiseMergeConflict = change.isRaiseMergeConflict(with: originChange)
                if raiseMergeConflict {
                    viewModel.hasNewEvent = true
                }
            }

            if originChange != nil {
                if raiseMergeConflict {
                    notifyMergeConflict(change)
                }
            } else {
                if !change.isOurs() {
                    notifyNewChange(change)
                }
            }

            if change.shouldListenReviewEvent() {
                let scores = GerritUtils.parseReviewScores(messages, originRevision: originRevision)
                let filterComments = GerritUtils.filterComments(comments, authorFilter: { author in
                    return change.shouldListen(author: author)
                })
                notifyReviewEvents(
                    scores: scores,
                    comments: filterComments,
                    change: change
                )
            }

            if viewModel.isOurNotReady, !ConfigManager.shared.showOurNotReadyReview {
                continue
            }
            if change.isInBlacklist() {
                continue
            }
            viewModels.append(viewModel)
        }
        self.changes = newChanges
        cellViewModels = viewModels
    }

    private func updateGitlabMRs() {
        let gitLabCellModels = gitlabService.trackingMRs.map { mr in
            let viewModel = ReviewListCellViewModel(mr: mr, project: gitlabService.projectInfos[mr.project_id])
            return viewModel
        }
        cellViewModels.append(contentsOf: gitLabCellModels)
    }

    private func reorderChanges(_ changes: [Change]) -> [Change] {
        var newChanges = [Change]()
        var insert = 0
        for change in changes {
            if change.hasNoReviewers() {
                continue
            }
            if change.isOurs() {
                newChanges.insert(change, at: insert)
                insert += 1
            } else {
                newChanges.append(change)
            }
        }
        return newChanges
    }

    private func saveNewEventStates() {
        var states = [String: Bool]()
        for vm in cellViewModels {
            states[vm.newEventKey] = vm.hasNewEvent
        }
        newEventStates = states
    }

    private func saveNewComments() {
        var comments = [String: Int]()
        for vm in cellViewModels {
            comments[vm.changeNumberKey] = vm.hasNewEvent ? vm.newComments : 0
        }
        newComments = comments
    }

    private func saveLatestMessageIds() {
        var messageIds = [String: String]()
        for vm in cellViewModels {
            guard let messageId = vm.latestMessageId else {
                continue
            }
            messageIds[vm.changeNumberKey] = messageId
        }
        latestMessageIds = messageIds
    }

    private func sendReviewListUpdatedNotification() {
        NotificationCenter.default.post(
            name: ReviewListDataController.ReviewListUpdatedNotification,
            object: nil,
            userInfo: nil
        )
    }
}

// MARK: - Local Notification

extension ReviewListDataController: NSUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        guard let userInfo = notification.userInfo,
              let number = userInfo[ReviewListDataController.ReviewChangeNumberKey] as? Int
        else {
            return
        }

        var target: ReviewListCellViewModel?
        for vm in cellViewModels {
            guard let changeNumber = vm.changeNumber else {
                continue
            }
            if changeNumber == number {
                target = vm
                break
            }
        }
        if let target = target {
            target.resetEvent()
            updateAllNewEventsCount()
            sendReviewListUpdatedNotification()
        }
        GerritUtils.openGerrit(number: number, revisionRange: revisionRange(of: number))
    }

    private func notifyReviewEvents(
        scores: [(Author, ReviewScore)],
        comments: [(Author, Int)],
        change: Change
    ) {
        let reviewEvents = GerritUtils.combineReviewEvents(scores: scores, comments: comments)
        for (author, score, comments) in reviewEvents {
            if author.isMe() || author.isInBlackList() || (score == .Zero && comments == 0) {
                continue
            }

            var title = author.name ?? ""
            var imageName = "Comment"
            if score != .Zero {
                title += " Code-Review\(score.rawValue)"
                imageName = "Review\(score.rawValue)"
            }
            if comments != 0 {
                title += " (\(comments) "
                if comments == 1 {
                    title += "Comment)"
                } else {
                    title += "Comments)"
                }
            }
            postLocationNotification(title: title, image: NSImage(named: imageName), change: change)
        }
    }

    private func notifyMergeConflict(_ change: Change) {
        guard ConfigManager.shared.shouldNotifyMergeConflict else {
            return
        }
        postLocationNotification(
            title: "Merge Conflict",
            image: NSImage(named: "Conflict"),
            change: change
        )
    }

    private func notifyNewChange(_ change: Change) {
        guard ConfigManager.shared.shouldNotifyNewIncomingReview, change.hasNewEvent() else {
            return
        }
        let name = change.owner?.name ?? ""
        postLocationNotification(
            title: "New Review by \(name)",
            image: change.owner?.avatarImage(),
            change: change
        )
    }

    private func postLocationNotification(title: String, image: NSImage?, change: Change) {
        if isFirstLoading {
            // 第一次加载该用户的 Review List 时，不做任何通知
            return
        }
        if change.isInBlacklist() {
            return
        }
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = change.subject
        notification.contentImage = image
        if let number = change.number {
            notification.userInfo = [ReviewListDataController.ReviewChangeNumberKey: number]
        }
        debugPrint(notification)
        NSUserNotificationCenter.default.deliver(notification)
    }
}

// MARK: - Merged

extension ReviewListDataController {
    private func checkMerged(_ newChanges: [Change]) {
        guard let changes = changes else {
            return
        }
        var leaveChanges = [Change]()
        for change in changes {
            var found = false
            for new in newChanges {
                if new.id == change.id {
                    found = true
                    break
                }
            }
            if !found {
                leaveChanges.append(change)
            }
        }

        for change in leaveChanges {
            let hasTrigger = MergedTriggerManager.shared.hasTrigger(change: change)
            guard change.isOurs() || hasTrigger,
                  let changeId = change.changeId
            else {
                continue
            }
            gerritService?.fetchChangeDetail(changeId: changeId, completion: { change in
                guard let change = change, change.isMerged() else {
                    return
                }
                var title = ""
                if change.isOurs(),
                   let name = change.owner?.name,
                   let mergedName = change.mergedBy(),
                   name != mergedName
                {
                    title += NSLocalizedString("ReviewMerged", comment: "")
                }
                if hasTrigger {
                    MergedTriggerManager.shared.callTrigger(change: change)
                    if !title.isEmpty {
                        title += "，"
                    }
                    title += NSLocalizedString("RunTrigger", comment: "")
                }
                if title.isEmpty {
                    return
                }
                self.postLocationNotification(
                    title: title,
                    image: NSImage(named: "Merged"),
                    change: change
                )
            })
        }
    }
}
