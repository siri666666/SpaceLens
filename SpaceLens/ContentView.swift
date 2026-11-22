import SwiftUI
import UIKit

struct MainTabView: View {
    @ObservedObject var vm: SpaceLensViewModel

    var body: some View {
        TabView {
            OverviewView(vm: vm)
                .tabItem {
                    Label("文件分类", systemImage: "square.grid.2x2.fill")
                }

            AppsStorageView(vm: vm)
                .tabItem {
                    Label("应用目录", systemImage: "app.badge.fill")
                }

            LargeFilesView(vm: vm)
                .tabItem {
                    Label("大文件", systemImage: "doc.badge.ellipsis")
                }
        }
    }
}

struct OverviewView: View {
    @ObservedObject var vm: SpaceLensViewModel

    var body: some View {
        NavigationView {
            List {
                diskCardSection
                if let report = vm.report {
                    categoriesSection(report)
                    bucketsSection(report)
                }
            }
            .navigationTitle("空间透视")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if vm.isScanning {
                        Button("停止") { vm.cancelScan() }
                            .foregroundColor(.red)
                    } else {
                        Button {
                            vm.startScan()
                        } label: {
                            Label("重新扫描", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var diskCardSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("本机储存（纯只读）")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(String(format: "已用 %.1f%%", vm.disk.usedRatio * 100))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundColor(vm.disk.usedRatio > 0.9 ? .red : (vm.disk.usedRatio > 0.8 ? .orange : .blue))
                }

                ProgressView(value: vm.disk.usedRatio)
                    .tint(vm.disk.usedRatio > 0.9 ? .red : (vm.disk.usedRatio > 0.8 ? .orange : .blue))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("已用 \(ByteFormat.string(vm.disk.usedBytes))")
                            .font(.caption.monospacedDigit())
                        Text("总计 \(ByteFormat.string(vm.disk.totalBytes))")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("可用 \(ByteFormat.string(vm.disk.availableBytes))")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundColor(vm.disk.availableBytes < 8 * 1024 * 1024 * 1024 ? .red : .green)
                        if vm.isScanning {
                            Text("\(vm.progress.currentSection) (\(vm.progress.scannedFiles) 项)")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        } else if let rep = vm.report {
                            Text("已扫描 \(rep.scannedFiles) 文件 · \(ByteFormat.string(rep.scannedBytes))")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        } footer: {
            Text("纯离线只读分析，不联网、不修改或删除任何文件。点任意条目可复制路径以便按需在系统或 Filza 中定位。")
        }
    }

    private func categoriesSection(_ report: ScanReport) -> some View {
        Section("按文件类型分类") {
            ForEach(report.categories) { summary in
                NavigationLink {
                    CategoryDetailView(summary: summary)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: summary.category.iconName)
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(summary.category.color)
                            .cornerRadius(8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.category.rawValue)
                                .font(.body.weight(.medium))
                            Text("\(summary.fileCount) 个文件")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text(ByteFormat.string(summary.totalBytes))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                }
            }
        }
    }

    private func bucketsSection(_ report: ScanReport) -> some View {
        Section("主要目录归属") {
            bucketRow("系统相册 (DCIM / PhotoData)", bytes: report.mediaBytes, path: "/var/mobile/Media")
            bucketRow("已装应用数据 (Containers)", bytes: report.appsDataBytes, path: "/var/mobile/Containers/Data/Application")
            bucketRow("应用共享组 (AppGroup)", bytes: report.appGroupsBytes, path: "/var/mobile/Containers/Shared/AppGroup")
            bucketRow("系统缓存与日志", bytes: report.cachesAndLogsBytes, path: "/var/mobile/Library/Caches")
            bucketRow("本地文档与下载", bytes: report.userDocsBytes, path: "/var/mobile/Documents")
        }
    }

    private func bucketRow(_ title: String, bytes: Int64, path: String) -> some View {
        NavigationLink {
            DirectoryBrowserView(title: title, path: path)
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(ByteFormat.string(bytes))
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct CategoryDetailView: View {
    let summary: CategorySummary
    @State private var copiedPath: String?

    var body: some View {
        List {
            Section {
                HStack {
                    Text("分类总计")
                    Spacer()
                    Text("\(ByteFormat.string(summary.totalBytes)) · \(summary.fileCount) 项")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }

            Section("体积 Top \(summary.topFiles.count)（仅展示 ≥ 1 MB，点击复制路径）") {
                if summary.topFiles.isEmpty {
                    Text("该分类下无 ≥ 1 MB 的文件")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(summary.topFiles) { file in
                        FileRowView(file: file, copiedPath: $copiedPath)
                    }
                }
            }
        }
        .navigationTitle(summary.category.rawValue)
    }
}

struct AppsStorageView: View {
    @ObservedObject var vm: SpaceLensViewModel
    @State private var searchText = ""

    private var filteredApps: [AppStorageEntry] {
        let all = vm.report?.apps ?? []
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return all
        }
        let q = searchText.lowercased()
        return all.filter { $0.displayName.lowercased().contains(q) || $0.bundleID.lowercased().contains(q) }
    }

    var body: some View {
        NavigationView {
            List {
                if filteredApps.isEmpty {
                    Text(vm.isScanning ? "正在扫描应用容器…" : "暂无应用数据")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(filteredApps) { app in
                        NavigationLink {
                            DirectoryBrowserView(title: app.displayName, path: app.containerPath)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(app.displayName)
                                        .font(.body.weight(.medium))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(ByteFormat.string(app.totalBytes))
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                        .foregroundColor(app.totalBytes > 2 * 1024 * 1024 * 1024 ? .red : .primary)
                                }
                                Text("文档 \(ByteFormat.string(app.documentsBytes)) · 缓存 \(ByteFormat.string(app.cachesBytes)) · 库 \(ByteFormat.string(app.libraryBytes))")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索中文名或包名")
            .navigationTitle("应用目录")
        }
        .navigationViewStyle(.stack)
    }
}

struct LargeFilesView: View {
    @ObservedObject var vm: SpaceLensViewModel
    @State private var copiedPath: String?

    var body: some View {
        NavigationView {
            List {
                let files = vm.report?.largeFiles ?? []
                if files.isEmpty {
                    Text(vm.isScanning ? "正在扫描大文件…" : "未发现 ≥ 20 MB 的大文件")
                        .foregroundColor(.secondary)
                } else {
                    Section("全机 ≥ 20 MB 大文件 Top \(files.count)（点击复制路径）") {
                        ForEach(files) { file in
                            FileRowView(file: file, copiedPath: $copiedPath)
                        }
                    }
                }
            }
            .navigationTitle("大文件排行")
        }
        .navigationViewStyle(.stack)
    }
}

struct DirectoryBrowserView: View {
    let title: String
    let path: String
    @State private var items: [DirectoryItem] = []
    @State private var isLoading = true
    @State private var copiedPath: String?

    var body: some View {
        List {
            Section {
                Button {
                    UIPasteboard.general.string = path
                    copiedPath = path
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(copiedPath == path ? "已复制当前目录路径" : "点击复制当前目录路径")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text(path)
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            Section("子目录与文件（按体积降序）") {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("正在计算目录大小…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if items.isEmpty {
                    Text("空目录或无读取权限")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(items) { item in
                        if item.isDirectory {
                            NavigationLink {
                                DirectoryBrowserView(title: item.name, path: item.path)
                            } label: {
                                dirRow(item)
                            }
                        } else {
                            Button {
                                UIPasteboard.general.string = item.path
                                copiedPath = item.path
                            } label: {
                                dirRow(item)
                            }
                            .foregroundColor(.primary)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .onAppear {
            guard isLoading else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let loaded = StorageScanner.listDirectory(at: path)
                DispatchQueue.main.async {
                    self.items = loaded
                    self.isLoading = false
                }
            }
        }
    }

    private func dirRow(_ item: DirectoryItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundColor(item.isDirectory ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline)
                    .lineLimit(1)
                if copiedPath == item.path {
                    Text("已复制路径")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            Spacer()
            Text(ByteFormat.string(item.size))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundColor(.secondary)
        }
    }
}

private struct FileRowView: View {
    let file: FileEntry
    @Binding var copiedPath: String?

    var body: some View {
        Button {
            UIPasteboard.general.string = file.path
            copiedPath = file.path
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(file.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text(ByteFormat.string(file.size))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundColor(file.size >= 100 * 1024 * 1024 ? .red : .orange)
                }
                HStack {
                    Text(file.ownerLabel)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(file.category.color.opacity(0.15))
                        .foregroundColor(file.category.color)
                        .cornerRadius(4)
                    Text(copiedPath == file.path ? "已复制路径到剪贴板" : file.path)
                        .font(.caption2)
                        .foregroundColor(copiedPath == file.path ? .green : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
