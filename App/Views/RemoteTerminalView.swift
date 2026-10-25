//
//  RemoteTerminalView.swift
//  ClaudeRemote
//
//  TerminalView cua SwiftTerm, vuot chi cuon TAI CHO tren iPhone (khong gui gi sang PC).
//
//  - Giao dien co dien (server ep Claude chay CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1): lich su nam
//    trong scrollback -> vuot cuon nhu binh thuong.
//  - Chuong trinh dung alt screen (vd Claude /tui fullscreen, agy altscreen): khong co scrollback de
//    cuon, tat cuon san co de khung hinh khong bi lech (logo hien 2 lan).
//  - Ban 1.8-2.2 doi vuot thanh con lan chuot gui sang Claude -> Claude tren PC cuon theo; da bo
//    theo yeu cau "chi cuon tren iPhone".
//  - Khong goi super.mouseModeChanged: super bat pan "keo chuot" (Claude hieu la boi den chu).
//    Cham van gui su kien chuot binh thuong.
//

import UIKit
import SwiftTerm

final class RemoteTerminalView: TerminalView {
    override func mouseModeChanged(source: Terminal) {
        updateNativeScroll(source)
    }

    override func bufferActivated(source: Terminal) {
        super.bufferActivated(source: source)
        updateNativeScroll(source)
    }

    /// Dung `source`, khong goi getTerminal(): ham nay co the chay ngay trong super.init.
    private func updateNativeScroll(_ source: Terminal) {
        isScrollEnabled = !source.isCurrentBufferAlternate
    }

    /// Cho test: cuon san co cua terminal dang bat hay khong
    var isNativeScrollEnabled: Bool {
        isScrollEnabled
    }
}
