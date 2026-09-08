// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchClipboardView: View {
    let service: NotchService
    @ObservedObject private var history = ClipboardHistoryService.shared
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @State private var query = ""
    @State private var copiedID: UUID?
    private var text: ClipboardFeatureStrings { FeatureStrings.clipboard(l10n.language) }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(text.search, text: $query).textFieldStyle(.plain)
                    .accessibilityLabel(text.search)
                NotchIconButton(symbol: "arrow.up.forward.app", title: text.title) {
                    service.perform { history.showHistoryWindow(preferNotch: false) }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(.black, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.14), lineWidth: 0.6) }
            let entries = history.filteredEntries(matching: query)
            if entries.isEmpty {
                NotchEmptyView(symbol: "doc.on.clipboard", message: text.empty)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(entries) { entry in
                        HStack(spacing: 10) {
                            Button {
                                if permissions.accessibility {
                                    service.collapse()
                                    history.copyQuickEntry(entry)
                                } else {
                                    history.copy(entry) { copied in if copied { copiedID = entry.id } }
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    preview(entry)
                                    Text(entry.kind == .image ? text.imageEntryLabel : entry.preview)
                                        .font(.system(size: 11)).lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).help(permissions.accessibility ? text.clickRowShortcut : text.copy)
                            NotchIconButton(symbol: copiedID == entry.id ? "checkmark" : "doc.on.doc",
                                            title: copiedID == entry.id ? text.copied : text.copy) {
                                history.copy(entry) { copied in if copied { copiedID = entry.id } }
                            }
                            NotchIconButton(symbol: entry.isPinned ? "pin.fill" : "pin",
                                            title: entry.isPinned ? text.unpin : text.pin) {
                                history.togglePin(entry)
                            }
                        }
                        .padding(10)
                        .background(.black, in: RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(entry.isPinned ? 0.25 : 0.1), lineWidth: 0.6) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func preview(_ entry: ClipboardHistoryEntry) -> some View {
        if entry.kind == .image, let name = entry.imageFile,
           let image = ClipboardImageStore.thumbnail(named: name) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: 36, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            Image(systemName: entry.kind == .files ? "doc" : "text.alignleft")
                .foregroundStyle(.secondary).frame(width: 24)
        }
    }
}
