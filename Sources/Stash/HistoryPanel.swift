import AppKit
import SwiftUI

struct HistoryPanel: View {
    /// One source of truth — the popover is told this too, otherwise it sizes itself from the
    /// view's fitting size and the header ends up under the popover's own rounded top edge.
    static let size = NSSize(width: 380, height: 560)

    let close: () -> Void
    let copied: (String) -> Void

    // loaded at init, not in onAppear — the panel is rebuilt on every open, and loading
    // later shows an empty list for one frame
    @State private var entries: [HistoryEntry] = HistoryStore.load()
    @State private var query = ""
    @State private var copiedID: Int?
    @State private var showToast = false
    @State private var toastTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    private var filtered: [HistoryEntry] {
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search clips", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 15))
                        .focused($searchFocused)
                        // the cursor starts here, so type-then-Enter is the fast path
                        .onSubmit {
                            guard let first = filtered.first else { return }
                            copy(first)
                            close()
                        }
                }
                Text(countLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            // clears the popover's rounded top edge so the search row is never shaved
            .padding(.top, 18)
            .padding(.bottom, 10)

            Divider()

            if entries.isEmpty {
                emptyState("Nothing copied yet")
            } else if filtered.isEmpty {
                emptyState("No matches")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        // non-lazy so scrollTo has real row geometry to anchor against, not an estimate
                        VStack(spacing: 0) {
                            ForEach(filtered) { entry in
                                ClipRow(entry: entry,
                                        isCopied: copiedID == entry.id,
                                        copy: { copy(entry) },
                                        delete: { delete(entry) })
                                Divider()
                            }
                        }
                    }
                    .onChange(of: query) { _, _ in
                        guard let first = filtered.first else { return }
                        proxy.scrollTo(first.id, anchor: .top)
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showToast {
                toast
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .onExitCommand { close() }
        .onAppear { searchFocused = true }
    }

    private var countLabel: String {
        query.isEmpty ? "\(entries.count) clips" : "\(filtered.count) of \(entries.count)"
    }

    private func emptyState(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var toast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Copied to clipboard")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 6)
    }

    /// Anything sensitive that slipped past the concealed-clip filter has to be removable
    /// on its own — clearing the whole history to get rid of one row is not a real remedy.
    private func delete(_ entry: HistoryEntry) {
        HistoryStore.remove(id: entry.id)
        entries = HistoryStore.load()
        // ids are byte offsets and the rewrite compacts the file, so a held id now points
        // at a different row
        copiedID = nil
    }

    private func copy(_ entry: HistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        copied(entry.text)

        copiedID = entry.id
        toastTask?.cancel()
        withAnimation { showToast = true }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { showToast = false }
            copiedID = nil
        }
    }
}

private struct ClipRow: View {
    let entry: HistoryEntry
    let isCopied: Bool
    let copy: () -> Void
    let delete: () -> Void

    @State private var hovering = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        Button(action: copy) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(Self.relativeFormatter.localizedString(for: entry.date, relativeTo: Date()))
                    Text("·")
                    Text(entry.source)
                    Spacer()
                    // always visible, just faint — an icon that only appears on hover leaves
                    // a first-time list looking like it does nothing
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(isCopied ? Color.green : Color.secondary)
                        .opacity(isCopied || hovering ? 1 : 0.35)
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .help(entry.date.formatted(date: .abbreviated, time: .standard))

                Text(entry.text)
                    .font(.system(size: 15))
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(hovering ? Color.primary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Delete Clip", role: .destructive, action: delete)
        }
    }
}
