//
//  ReviewListCell.swift
//  GerritJarvis
//
//  Created by Chuanren Shang on 2019/4/26.
//  Copyright © 2019 Chuanren Shang. All rights reserved.
//

import Cocoa

protocol ReviewListCellDelegate: NSObjectProtocol {
    func reviewListCellDidClickTriggerButton(_ cell: ReviewListCell)
    func reviewListCellDidClickAuthor(_ cell: ReviewListCell)
    func reviewListCellDidClickProject(_ cell: ReviewListCell)
    func reviewListCellDidClickBranch(_ cell: ReviewListCell)
}

class ReviewListCell: NSTableCellView {
    weak var delegate: ReviewListCellDelegate?

    @IBOutlet var projectLabel: NSTextField!
    @IBOutlet var branchLabel: NSTextField!
    @IBOutlet var commitLabel: NSTextField!

    @IBOutlet var nameLabel: NSTextField!
    @IBOutlet var avatarImageView: NSImageView!

    @IBOutlet var newReviewImageView: NSImageView!
    @IBOutlet var commentLabel: NSTextField!
    @IBOutlet var commentImageView: NSImageView!
    @IBOutlet var reviewImageView: NSImageView!
    @IBOutlet var conflictImageView: NSImageView!

    @IBAction func buttonAction(_ sender: Any) {
        delegate?.reviewListCellDidClickTriggerButton(self)
    }

    @IBAction func authorPressAction(_ sender: Any) {
        delegate?.reviewListCellDidClickAuthor(self)
    }

    @IBAction func projectPressAction(_ sender: Any) {
        delegate?.reviewListCellDidClickProject(self)
    }

    @IBAction func branchPressAction(_ sender: Any) {
        delegate?.reviewListCellDidClickBranch(self)
    }

    private(set) var gitlabUrl: URL?

    override func prepareForReuse() {
        super.prepareForReuse()
        gitlabUrl = nil
    }

    func bindData(with viewModel: ReviewListCellViewModel) {
        projectLabel.stringValue = viewModel.project
        branchLabel.stringValue = viewModel.branch
        commitLabel.stringValue = viewModel.commitMessage
        nameLabel.stringValue = viewModel.name
        gitlabUrl = viewModel.gitlabWebUrl
        if let avatar = viewModel.avatar {
            avatarImageView.image = avatar
        } else if let url = viewModel.avatarUrl {
            avatarImageView.sd_setImage(with: URL(string: url))
        }

        newReviewImageView.isHidden = !viewModel.hasNewEvent
        conflictImageView.isHidden = !viewModel.isMergeConflict

        commentLabel.stringValue = "\(viewModel.newComments)"
        commentLabel.isHidden = (viewModel.newComments == 0)
        commentImageView.isHidden = (viewModel.newComments == 0)

        reviewImageView.image = switch viewModel.reviewScore {
        case .PlusTwo: NSImage(named: "ReviewPlus2")
        case .PlusOne: NSImage(named: "ReviewPlus1")
        case .Zero: NSImage(named: "")
        case .MinusOne: NSImage(named: "ReviewMinus1")
        case .MinusTwo: NSImage(named: "ReviewMinus2")
        }
    }

    private func hasChinese(in string: String) -> Bool {
        for (_, value) in string.enumerated() {
            if value >= "\u{4E00}", value <= "\u{9FA5}" {
                return true
            }
        }
        return false
    }
}
