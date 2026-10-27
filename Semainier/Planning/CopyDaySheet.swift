import SwiftData
import SwiftUI

/// Copie un jour vers d'autres : les jours choisis prennent exactement ses plats et portions.
struct CopyDaySheet: View {
    var source: DayKey
    @Environment(\.modelContext) private var context
    @Environment(Toast.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<DayKey> = []

    /// Les 14 prochains jours (aujourd'hui compris), sauf le jour copié.
    private var targets: [DayKey] { Days.range(from: Days.today, count: 14).filter { $0 != source } }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        ForEach(targets, id: \.self) { d in
                            Button {
                                if selected.contains(d) { selected.remove(d) } else { selected.insert(d) }
                            } label: {
                                HStack {
                                    Text(Days.longLabel(d)).foregroundStyle(.primary)
                                    if let r = Days.relative(d) { Text(r).foregroundStyle(.secondary) }
                                    Spacer()
                                    if selected.contains(d) { Image(systemName: "checkmark").foregroundStyle(Color.accentColor).bold() }
                                }
                            }
                        }
                    } footer: {
                        Text("Les jours choisis prennent exactement les mêmes plats et portions. Leur contenu actuel est remplacé.")
                    }
                }
                .listRowBackground(Color.surface)
            }
            .screenBackground()
            .navigationTitle("Copier le \(Days.longLabel(source).lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copier", role: .confirm) {
                        PlanActions.copy(day: source, to: selected, in: context)
                        toast.show("Copié vers \(selected.count) jour\(selected.count > 1 ? "s" : "")")
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.appBackground)
    }
}
