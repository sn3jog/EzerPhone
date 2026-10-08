import SwiftUI

struct RecentsView: View {
    @EnvironmentObject var settings: SipSettings
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var history = CallHistoryStore.shared
    @State private var showClearAllConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            InkScreenHeader(title: "История") {
                if !history.entries.isEmpty {
                    InkIconButton(glyph: .trash, label: "Очистить историю") {
                        showClearAllConfirm = true
                    }
                }
            }

            if history.entries.isEmpty {
                InkEmptyState(text: "Пока пусто")
                Spacer()
            } else {
                List {
                    ForEach(history.entries) { entry in
                        Button {
                            coordinator.placeCall(entry.remote, accountId: settings.selectedAccountId)
                        } label: {
                            VStack(spacing: 0) {
                                HistoryRow(entry: entry)
                                InkRule(seed: InkSeed.of(entry.id.uuidString))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!settings.isConfigured)
                        .inkRow()
                        .swipeActions {
                            Button(role: .destructive) {
                                history.remove(entry)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                            .tint(Ink.ink)
                        }
                    }
                    .onDelete { history.remove(at: $0) }
                }
                .inkList()
            }
        }
        .confirmationDialog("Удалить всю историю звонков?", isPresented: $showClearAllConfirm, titleVisibility: .visible) {
            Button("Удалить всё", role: .destructive) {
                history.clear()
            }
            Button("Отмена", role: .cancel) {}
        }
    }
}

struct HistoryRow: View {
    let entry: CallHistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            InkGlyphView(glyph: glyph, size: 22)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.remote)
                    .font(.ink(16, .regular, relativeTo: .body))
                    .foregroundStyle(Ink.ink)
                Text(entry.date, style: .relative)
                    .font(.ink(12, .italic, relativeTo: .caption))
                    .foregroundStyle(Ink.faded)
            }
            Spacer(minLength: 8)
            if entry.durationSeconds > 0 {
                Text(durationString)
                    .font(.ink(12, .italic, relativeTo: .caption))
                    .foregroundStyle(Ink.faded)
            }
            InkCallMini(size: 34)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    /// Direction without colour: an arrow out, an arrow in, or a dashed arrow in for a missed call.
    private var glyph: InkGlyph {
        switch entry.direction {
        case .outgoing: return .arrowOut
        case .incoming: return .arrowIn
        case .missed: return .arrowMissed
        }
    }

    private var durationString: String {
        let m = entry.durationSeconds / 60
        let s = entry.durationSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

#Preview {
    RecentsView()
        .environmentObject(SipSettings.shared)
        .environmentObject(AppCoordinator.shared)
}
