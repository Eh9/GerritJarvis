//
//  ReviewListCellViewModel.swift
//  GerritJarvis
//
//  Created by Chuanren Shang on 2019/5/10.
//  Copyright © 2019 Chuanren Shang. All rights reserved.
//

import Cocoa
import GitLabSwift
import SDWebImage

class ReviewListCellViewModel: NSObject {
    let changeNumber: Int?
    let newEventKey: String
    let changeNumberKey: String
    let latestMessageId: String?
    let project: String
    let branch: String
    let name: String
    let commitMessage: String
    var avatar: NSImage?
    var avatarUrl: String?
    var newComments: Int = 0
    var reviewScore: ReviewScore = .Zero
    var hasNewEvent: Bool = false
    var isMergeConflict: Bool = false
    var isOurNotReady: Bool = false
    var gitlabWebUrl: URL?

    init(change: Change) {
        changeNumber = change.number
        newEventKey = change.newEventKey()
        changeNumberKey = change.changeNumberKey()
        latestMessageId = change.messages?.last?.id
        project = change.project ?? ""
        branch = change.branch ?? ""
        if let displayName = change.owner?.displayName {
            name = displayName
        } else {
            name = change.owner?.name ?? ""
        }
        commitMessage = change.subject ?? ""
        avatar = change.owner?.avatarImage()
        hasNewEvent = change.hasNewEvent()
        isMergeConflict = !(change.mergeable ?? true)
        let (score, author) = change.calculateReviewScore()
        reviewScore = score
        if change.isOurs() {
            // 自己提的 Review 被自己 -2，说明还没准备好
            if let author = author,
               score == .MinusTwo, author.isMe()
            {
                isOurNotReady = true
            }
        }

        super.init()
    }

    init(mr: GLModel.MergeRequest, project: GLModel.Project?) {
        changeNumber = mr.iid
        newEventKey = ""
        changeNumberKey = ""
        latestMessageId = String(mr.user_notes_count)
        self.project = project?.name ?? "null_project"
        branch = mr.source_branch ?? "null_branch"
        name = mr.author?.name ?? "null_name"
        avatarUrl = mr.author?.avatar_url
        commitMessage = mr.title ?? "null_title"
        hasNewEvent = false
        isMergeConflict = mr.has_conflicts == true
        gitlabWebUrl = mr.web_url
        reviewScore = switch mr.upvotes {
        case 1: .PlusOne
        case 2...: .PlusTwo
        default: .Zero
        }
        if GitlabService.shared.approvalInfos[mr.id]?.user_has_approved == true {
            reviewScore = .PlusTwo
        }
        super.init()
    }

    func resetEvent() {
        hasNewEvent = false
        newComments = 0
    }
}
