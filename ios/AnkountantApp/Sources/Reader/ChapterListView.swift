import AnkountantReader
import SwiftUI

struct ChapterListView: View {
    let book: ReaderBook
    let progress: ReaderProgressCoordinator

    private var savedProgress: ReaderSavedProgress? { progress.resolved(bookID: book.id) }

    var body: some View {
        Group {
            if book.chapters.isEmpty {
                ContentUnavailableView(
                    "No Chapters",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("This book has no chapter notes. Check the Reader field mapping or add chapter notes to the selected deck.")
                )
            } else {
                List(book.chapters) { chapter in
                    NavigationLink(value: chapter) {
                        ChapterRow(
                            chapter: chapter,
                            savedProgress: savedProgress?.chapterID == chapter.id ? savedProgress : nil
                        )
                    }
                }
            }
        }
        .navigationDestination(for: ReaderChapter.self) { chapter in
            ChapterReaderView(book: book, chapter: chapter, progress: progress)
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let savedProgress, let chapter = book.chapters.first(where: { $0.id == savedProgress.chapterID }) {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: chapter) {
                        Label("Resume", systemImage: "play.fill")
                    }
                }
            }
        }
    }
}

private struct ChapterRow: View {
    let chapter: ReaderChapter
    let savedProgress: ReaderSavedProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(chapter.title).font(.body)
            if let order = chapter.order {
                Text("Chapter \(order)").font(.caption).foregroundStyle(.secondary)
            }
            if let savedProgress {
                ProgressView(value: savedProgress.progress)
                    .tint(.accentColor)
                    .padding(.top, 2)
                    .accessibilityLabel("Reading progress")
                    .accessibilityValue("\(Int(savedProgress.progress * 100)) percent")
            }
        }
    }
}
