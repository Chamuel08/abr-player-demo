//
//  LibraryView.swift
//  ABRPlayerDemo
//
//  内容库：NavigationStack + List，展示内置流 + 最近播放。tap 推到 PlayerScreen。
//  见 spec.md FR-6、plan.md §2.2。
//

import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \PlaybackHistoryItem.lastPlayedAt, order: .reverse) private var recents: [PlaybackHistoryItem]
    @State private var navigationDestination: StreamItem?
    @State private var customURLText = ""
    @State private var urlError: String?
    @FocusState private var urlFieldFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section("自定义 URL") {
                    HStack {
                        TextField("https://.../master.m3u8",
                                  text: $customURLText,
                                  axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .focused($urlFieldFocused)
                            .lineLimit(1...3)
                        Button {
                            playCustomURL()
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        .disabled(customURLText.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("播放此 URL")
                    }
                    if let urlError {
                        Text(urlError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("内置测试流") {
                    ForEach(StreamLibrary.builtin) { item in
                        streamRow(item)
                    }
                }
                let extraRecents = StreamLibrary.combined(with: recents).filter { !$0.isBuiltin }
                if !extraRecents.isEmpty {
                    Section("最近播放") {
                        ForEach(extraRecents) { item in
                            streamRow(item)
                        }
                    }
                }
            }
            .navigationTitle("ABR Player")
            .navigationDestination(item: $navigationDestination) { item in
                PlayerScreen(stream: item)
            }
        }
    }

    private func playCustomURL() {
        let trimmed = customURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            urlError = "URL 无效，需要 http(s):// 开头的 HLS 地址"
            return
        }
        urlError = nil
        let title = url.lastPathComponent.isEmpty ? (url.host() ?? trimmed) : url.lastPathComponent
        let item = StreamItem(id: trimmed, title: title, url: url, isBuiltin: false)
        touchPlaybackHistory(item)
        navigationDestination = item
    }

    private func streamRow(_ item: StreamItem) -> some View {
        Button {
            navigationDestination = item
            touchPlaybackHistory(item)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(item.url.host() ?? item.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func touchPlaybackHistory(_ item: StreamItem) {
        if let existing = recents.first(where: { $0.url.absoluteString == item.url.absoluteString }) {
            existing.lastPlayedAt = .now
        } else {
            env.modelContext.insert(PlaybackHistoryItem(url: item.url, title: item.title))
        }
        try? env.modelContext.save()
    }
}

#Preview {
    LibraryView()
        .environment(AppEnvironment())
}
