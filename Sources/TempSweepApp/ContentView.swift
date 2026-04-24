import AppKit
import SwiftUI
import TempSweepCore

struct ContentView: View {
    @StateObject private var viewModel = ScanViewModel()
    @State private var showingDeleteChoice = false

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(viewModel: viewModel, showingDeleteChoice: $showingDeleteChoice)
                .padding(24)

            Divider()

            if viewModel.groups.isEmpty && !viewModel.isScanning {
                EmptyStateView(scanMode: viewModel.scanMode) {
                    viewModel.scan()
                }
            } else {
                ResultsView(viewModel: viewModel)
            }
        }
        .confirmationDialog(
            "Clean \(viewModel.selectedCount) selected item\(viewModel.selectedCount == 1 ? "" : "s")?",
            isPresented: $showingDeleteChoice,
            titleVisibility: .visible
        ) {
            Button("Move to Trash") {
                viewModel.cleanSelected(mode: .moveToTrash)
            }
            Button("Delete Permanently", role: .destructive) {
                viewModel.cleanSelected(mode: .permanentDelete)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Selected size: \(TempSweepFormatters.bytes(viewModel.selectedSize)). This action only affects checked items.")
        }
        .alert("Cleanup Complete", isPresented: Binding(
            get: { viewModel.cleanSummary != nil },
            set: { if !$0 { viewModel.cleanSummary = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(viewModel.cleanSummary ?? "")
        }
    }
}

private struct HeaderView: View {
    @ObservedObject var viewModel: ScanViewModel
    @Binding var showingDeleteChoice: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 34, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(width: 52, height: 52)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("TempSweep")
                        .font(.system(size: 30, weight: .semibold))
                    Text("Find temporary files over 1 MB, review them, then choose how to clean.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Scan Mode", selection: $viewModel.scanMode) {
                    ForEach(ScanMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 420)
                .disabled(viewModel.isScanning)

                Button {
                    viewModel.scan()
                } label: {
                    Label(viewModel.isScanning ? "Scanning" : "Scan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isScanning)
                .keyboardShortcut("r", modifiers: [.command])
            }

            if let caution = viewModel.scanMode.caution {
                Label(caution, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            SummaryStrip(viewModel: viewModel, showingDeleteChoice: $showingDeleteChoice)

            if viewModel.isScanning {
                ScanProgressBar(progress: viewModel.scanProgress)
            }
        }
    }
}

private struct ScanProgressBar: View {
    let progress: ScanProgress

    private var percent: Int {
        Int((progress.fractionComplete * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(progress.status, systemImage: "waveform.path.ecg")
                    .font(.callout.weight(.medium))
                Spacer()
                Text("\(percent)%")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress.fractionComplete, total: 1)
                .progressViewStyle(.linear)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SummaryStrip: View {
    @ObservedObject var viewModel: ScanViewModel
    @Binding var showingDeleteChoice: Bool

    var body: some View {
        HStack(spacing: 14) {
            MetricView(title: "Found", value: "\(viewModel.totalCount)", detail: TempSweepFormatters.bytes(viewModel.totalSize))
            MetricView(title: "Selected", value: "\(viewModel.selectedCount)", detail: TempSweepFormatters.bytes(viewModel.selectedSize))
            MetricView(title: "Warnings", value: "\(viewModel.errors.count)", detail: viewModel.errors.isEmpty ? "No scan issues" : "Review below")

            Spacer()

            Picker("Sort", selection: $viewModel.sortOrder) {
                ForEach(ResultSortOrder.allCases) { sortOrder in
                    Text(sortOrder.displayName).tag(sortOrder)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
            .disabled(viewModel.groups.isEmpty)

            Button {
                showingDeleteChoice = true
            } label: {
                Label("Clean Selected", systemImage: "trash")
                    .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(viewModel.selectedCount == 0)
        }
    }
}

private struct MetricView: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 150, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct EmptyStateView: View {
    let scanMode: ScanMode
    let scan: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 58))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("No scan results yet")
                .font(.title2.weight(.semibold))
            Text("Start with \(scanMode.displayName). Recommended files are selected automatically, and fresh files stay unchecked.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Button {
                scan()
            } label: {
                Label("Scan Now", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct ResultsView: View {
    @ObservedObject var viewModel: ScanViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(viewModel.groups) { group in
                    GroupResultView(viewModel: viewModel, group: group)
                }

                if !viewModel.errors.isEmpty {
                    WarningList(errors: viewModel.errors)
                }
            }
            .padding(24)
        }
    }
}

private struct GroupResultView: View {
    private let pageSize = 150

    @ObservedObject var viewModel: ScanViewModel
    let group: ScanResultGroup
    @State private var visibleCandidateLimit = 150

    private var visibleCandidates: ArraySlice<FileCandidate> {
        group.candidates.prefix(visibleCandidateLimit)
    }

    var body: some View {
        DisclosureGroup {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(visibleCandidates) { candidate in
                    CandidateRow(
                        candidate: candidate,
                        isSelected: Binding(
                            get: { viewModel.isSelected(candidate) },
                            set: { viewModel.setSelected(candidate, selected: $0) }
                        )
                    )
                    Divider()
                }

                if group.candidates.count > visibleCandidateLimit {
                    ShowMoreRow(
                        visibleCount: visibleCandidateLimit,
                        totalCount: group.candidates.count
                    ) {
                        visibleCandidateLimit += pageSize
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(
                    get: { viewModel.isGroupSelected(group) },
                    set: { viewModel.setGroupSelected(group, selected: $0) }
                ))
                .labelsHidden()

                VStack(alignment: .leading, spacing: 3) {
                    Text(group.title)
                        .font(.headline)
                    Text(group.rootURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer()

                Text("\(group.candidates.count) items")
                    .foregroundStyle(.secondary)
                Text(TempSweepFormatters.bytes(group.totalSize))
                    .font(.headline.monospacedDigit())
                    .frame(width: 96, alignment: .trailing)
            }
            .contentShape(Rectangle())
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button("Copy Path") {
                copyPath(group.rootURL.path)
            }
        }
    }
}

private struct ShowMoreRow: View {
    let visibleCount: Int
    let totalCount: Int
    let showMore: () -> Void

    private var remainingCount: Int {
        max(totalCount - visibleCount, 0)
    }

    var body: some View {
        HStack {
            Text("Showing \(visibleCount) of \(totalCount) files")
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                showMore()
            } label: {
                Label("Show \(min(150, remainingCount)) more", systemImage: "chevron.down")
            }
        }
        .font(.callout)
        .padding(.vertical, 12)
    }
}

private struct CandidateRow: View {
    let candidate: FileCandidate
    @Binding var isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $isSelected)
                .labelsHidden()

            Image(systemName: candidate.isRecommendedForDeletion ? "doc" : "clock.badge.exclamationmark")
                .foregroundStyle(candidate.isRecommendedForDeletion ? Color.secondary : Color.orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.url.lastPathComponent)
                    .lineLimit(1)
                Text(candidate.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer()

            if !candidate.isRecommendedForDeletion {
                Text("Fresh")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.12), in: Capsule())
            }

            Text(TempSweepFormatters.bytes(candidate.size))
                .font(.callout.monospacedDigit())
                .frame(width: 86, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .contextMenu {
            Button("Copy File Path") {
                copyPath(candidate.url.path)
            }
            Button("Copy Folder Path") {
                copyPath(candidate.url.deletingLastPathComponent().path)
            }
        }
    }
}

private struct WarningList: View {
    let errors: [ScanError]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Scan Warnings", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.orange)

            Text("macOS may block some folders. For broader scans, grant Full Disk Access in System Settings > Privacy & Security.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    openFullDiskAccessSettings()
                } label: {
                    Label("Open Full Disk Access", systemImage: "gearshape")
                }
            }
            .buttonStyle(.bordered)

            ForEach(errors.prefix(12)) { error in
                VStack(alignment: .leading, spacing: 2) {
                    Text(error.url.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(error.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private func copyPath(_ path: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(path, forType: .string)
}

private func openFullDiskAccessSettings() {
    let urls = [
        "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
        "x-apple.systempreferences:com.apple.preference.security"
    ].compactMap(URL.init(string:))

    for url in urls where NSWorkspace.shared.open(url) {
        return
    }
}
