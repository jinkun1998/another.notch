import Foundation
import SwiftUI

struct QuickNotesView: View {
    @ObservedObject private var store = QuickNoteStore.shared
    @State private var selectedNoteID: QuickNote.ID?
    @State private var hoveredNoteID: QuickNote.ID?
    @State private var deleteConfirmationID: QuickNote.ID?
    @State private var isDeleteHovering = false
    @FocusState private var isDeleteFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            noteList
            editor
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            resetDeleteConfirmationIfNeeded()
        })
        .onAppear(perform: selectFirstNoteIfNeeded)
        .onChange(of: store.notes) { _, _ in selectFirstNoteIfNeeded() }
    }

    private var noteList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quick Notes")
                    .font(.headline)
                Spacer()
                HoverButton(icon: "plus", accessibilityLabel: "New note", action: createNote)
            }

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.notes) { note in
                        Button {
                            deleteConfirmationID = nil
                            selectedNoteID = note.id
                        } label: {
                            Text(note.text.isEmpty ? "New note" : note.text)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: 28, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    selectedNoteID == note.id
                                        ? Color.accentColor.opacity(0.28)
                                        : hoveredNoteID == note.id ? Color.white.opacity(0.10) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .onHover { hoveredNoteID = $0 ? note.id : nil }
                    }
                }
            }
        }
        .frame(width: 160, alignment: .leading)
    }

    @ViewBuilder
    private var editor: some View {
        if let selectedNote {
            VStack(alignment: .trailing, spacing: 8) {
                TextEditor(text: noteTextBinding(for: selectedNote.id))
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                    .simultaneousGesture(TapGesture().onEnded {
                        resetDeleteConfirmationIfNeeded()
                    })

                let isConfirmingDelete = deleteConfirmationID == selectedNote.id
                Button(action: { confirmDelete(selectedNote.id) }) {
                    HStack(spacing: 5) {
                        Image(systemName: isConfirmingDelete ? "trash.fill" : "trash")
                        Text(isConfirmingDelete ? "Are you sure?" : "Delete")
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isConfirmingDelete ? .white : .red)
                    .padding(.horizontal, isConfirmingDelete ? 12 : 10)
                    .frame(height: 28)
                    .background(
                        isConfirmingDelete
                            ? Color.red
                            : isDeleteHovering ? Color.red.opacity(0.16) : Color.red.opacity(0.08),
                        in: Capsule()
                    )
                    .overlay(Capsule().stroke(Color.red.opacity(isConfirmingDelete ? 0 : 0.25)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .focused($isDeleteFocused)
                .accessibilityLabel(isConfirmingDelete ? "Confirm delete note" : "Delete note")
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        isDeleteHovering = hovering
                    }
                    if !hovering {
                        resetDeleteConfirmationIfNeeded()
                    }
                }
                .onChange(of: isDeleteFocused) { _, focused in
                    if !focused {
                        resetDeleteConfirmationIfNeeded()
                    }
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.74), value: isConfirmingDelete)
            }
        } else {
            ContentUnavailableView("No Notes", systemImage: "note.text", description: Text("Create a note to keep it in the notch."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var selectedNote: QuickNote? {
        store.notes.first { $0.id == selectedNoteID }
    }

    private func noteTextBinding(for id: QuickNote.ID) -> Binding<String> {
        Binding(
            get: { store.notes.first(where: { $0.id == id })?.text ?? "" },
            set: { store.update(id, text: $0) }
        )
    }

    private func createNote() {
        deleteConfirmationID = nil
        selectedNoteID = store.create().id
    }

    private func confirmDelete(_ id: QuickNote.ID) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.74)) {
            guard deleteConfirmationID == id else {
                deleteConfirmationID = id
                isDeleteFocused = true
                return
            }
            delete(id)
        }
    }

    private func delete(_ id: QuickNote.ID) {
        store.delete(id)
        deleteConfirmationID = nil
        selectedNoteID = store.notes.first?.id
    }

    private func selectFirstNoteIfNeeded() {
        guard selectedNote == nil else { return }
        selectedNoteID = store.notes.first?.id
    }

    private func resetDeleteConfirmationIfNeeded() {
        guard deleteConfirmationID != nil else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.74)) {
            deleteConfirmationID = nil
        }
    }
}
