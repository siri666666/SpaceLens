import Darwin
import Foundation

final class StorageScanner {
    static let largeFileThreshold: Int64 = 20 * 1024 * 1024 // 20 MB
    private static let maxTopFilesPerBucket = 150

    static func readDiskOverview() -> DiskOverview {
        var st = statfs()
        if statfs("/var", &st) == 0 {
            let blockSize = Int64(st.f_bsize)
            let total = Int64(st.f_blocks) * blockSize
            let avail = Int64(st.f_bavail) * blockSize
            return DiskOverview(totalBytes: total, availableBytes: avail)
        }
        return DiskOverview(totalBytes: 0, availableBytes: 0)
    }

    /// Maps Bundle ID -> Localized Chinese (or fallback) display name by reading installed .app Info.plists (read-only).
    static func buildAppNameMap() -> [String: String] {
        var map: [String: String] = [:]
        let fm = FileManager.default
        let bundleRoots = [
            "/var/containers/Bundle/Application",
            "/Applications"
        ]

        for root in bundleRoots {
            guard let topItems = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for item in topItems {
                let full = (root as NSString).appendingPathComponent(item)
                if item.hasSuffix(".app") {
                    readAppInfo(at: full, into: &map)
                } else {
                    guard let subItems = try? fm.contentsOfDirectory(atPath: full) else { continue }
                    for sub in subItems where sub.hasSuffix(".app") {
                        readAppInfo(at: (full as NSString).appendingPathComponent(sub), into: &map)
                    }
                }
            }
        }
        return map
    }

    private static func readAppInfo(at appPath: String, into map: inout [String: String]) {
        let infoPath = (appPath as NSString).appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: infoPath)),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bid = plist["CFBundleIdentifier"] as? String, !bid.isEmpty else {
            return
        }

        var name = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension

        for lproj in ["zh-Hans.lproj", "zh_CN.lproj"] {
            let strPath = ((appPath as NSString).appendingPathComponent(lproj) as NSString)
                .appendingPathComponent("InfoPlist.strings")
            if let ldata = try? Data(contentsOf: URL(fileURLWithPath: strPath)),
               let ldict = try? PropertyListSerialization.propertyList(from: ldata, format: nil) as? [String: Any] {
                if let dn = ldict["CFBundleDisplayName"] as? String, !dn.isEmpty {
                    name = dn
                    break
                }
                if let bn = ldict["CFBundleName"] as? String, !bn.isEmpty {
                    name = bn
                    break
                }
            }
        }
        map[bid] = name
    }

    private static func containerMetadataIdentifier(at containerPath: String) -> String? {
        let metaPath = (containerPath as NSString)
            .appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bid = plist["MCMMetadataIdentifier"] as? String, !bid.isEmpty else {
            return nil
        }
        return bid
    }

    /// Fast POSIX recursive directory walker using opendir + lstat (never follows symlinks, strictly read-only).
    private static func walkDirectory(
        _ rootPath: String,
        ownerLabel: String,
        shouldCancel: () -> Bool,
        onFile: (_ name: String, _ fullPath: String, _ size: Int64, _ mtime: TimeInterval) -> Void
    ) {
        var stack: [String] = [rootPath]
        stack.reserveCapacity(128)

        while let dirPath = stack.popLast() {
            if shouldCancel() { return }
            guard let dir = opendir(dirPath) else { continue }
            defer { closedir(dir) }

            while let entPtr = readdir(dir) {
                if shouldCancel() { return }
                let name = withUnsafePointer(to: &entPtr.pointee.d_name) { ptr -> String in
                    ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN)) {
                        String(cString: $0)
                    }
                }
                if name == "." || name == ".." { continue }

                let fullPath = dirPath.hasSuffix("/") ? (dirPath + name) : (dirPath + "/" + name)
                var st = stat()
                if lstat(fullPath, &st) != 0 { continue }

                let mode = st.st_mode & S_IFMT
                if mode == S_IFDIR {
                    stack.append(fullPath)
                } else if mode == S_IFREG {
                    // Use actual allocated disk blocks when available, fallback to st_size
                    let allocated = Int64(st.st_blocks) * 512
                    let size = allocated > 0 ? min(allocated, Int64(st.st_size)) : Int64(st.st_size)
                    let mtime = TimeInterval(st.st_mtimespec.tv_sec)
                    onFile(name, fullPath, max(0, size), mtime)
                }
            }
        }
    }

    private static func insertTopFile(_ item: FileEntry, into list: inout [FileEntry], limit: Int) {
        if list.count < limit {
            list.append(item)
            if list.count == limit {
                list.sort { $0.size > $1.size }
            }
            return
        }
        guard let last = list.last, item.size > last.size else { return }
        list[list.count - 1] = item
        list.sort { $0.size > $1.size }
    }

    static func performFullScan(
        shouldCancel: @escaping () -> Bool,
        onProgress: @escaping (ScanProgress) -> Void
    ) -> ScanReport {
        let appNames = buildAppNameMap()

        var catMap: [FileCategory: CategorySummary] = [:]
        for c in FileCategory.allCases {
            catMap[c] = CategorySummary(category: c)
        }
        var largeFiles: [FileEntry] = []
        var apps: [AppStorageEntry] = []

        var scannedFiles = 0
        var scannedBytes: Int64 = 0
        var mediaBytes: Int64 = 0
        var appsDataBytes: Int64 = 0
        var appGroupsBytes: Int64 = 0
        var cachesAndLogsBytes: Int64 = 0
        var userDocsBytes: Int64 = 0
        var lastEmit = CFAbsoluteTimeGetCurrent()

        func emit(_ section: String, force: Bool = false) {
            let now = CFAbsoluteTimeGetCurrent()
            if force || (now - lastEmit) >= 0.2 {
                lastEmit = now
                onProgress(ScanProgress(scannedFiles: scannedFiles, scannedBytes: scannedBytes, currentSection: section))
            }
        }

        func recordFile(name: String, path: String, size: Int64, mtime: TimeInterval, owner: String, section: String) {
            scannedFiles += 1
            scannedBytes += size

            let ext = (name as NSString).pathExtension
            let cat = FileCategory.classify(extension: ext)
            var summary = catMap[cat]!
            summary.fileCount += 1
            summary.totalBytes += size

            if size >= 1024 * 1024 { // Track >= 1 MB for per-category top files
                let entry = FileEntry(
                    id: path,
                    name: name,
                    path: path,
                    size: size,
                    category: cat,
                    ownerLabel: owner,
                    modifiedDate: Date(timeIntervalSince1970: mtime)
                )
                insertTopFile(entry, into: &summary.topFiles, limit: maxTopFilesPerBucket)
                if size >= largeFileThreshold {
                    insertTopFile(entry, into: &largeFiles, limit: maxTopFilesPerBucket)
                }
            }
            catMap[cat] = summary
            emit(section)
        }

        // 1. Photos & Media
        emit("正在扫描相册与媒体…", force: true)
        for mediaDir in ["/var/mobile/Media/DCIM", "/var/mobile/Media/PhotoData"] {
            if shouldCancel() { break }
            walkDirectory(mediaDir, ownerLabel: "系统相册", shouldCancel: shouldCancel) { name, path, size, mtime in
                mediaBytes += size
                recordFile(name: name, path: path, size: size, mtime: mtime, owner: "系统相册", section: "正在扫描相册与媒体…")
            }
        }

        // 2. User App Containers (mapped to Chinese display names)
        emit("正在扫描已装应用数据…", force: true)
        let dataAppRoot = "/var/mobile/Containers/Data/Application"
        if let uuids = try? FileManager.default.contentsOfDirectory(atPath: dataAppRoot) {
            for uuid in uuids {
                if shouldCancel() { break }
                let containerPath = (dataAppRoot as NSString).appendingPathComponent(uuid)
                let bid = containerMetadataIdentifier(at: containerPath) ?? uuid
                let displayName = appNames[bid] ?? bid

                var appTotal: Int64 = 0
                var appCount = 0
                var docsBytes: Int64 = 0
                var libBytes: Int64 = 0
                var cachesBytes: Int64 = 0
                var tmpBytes: Int64 = 0

                let docsPrefix = containerPath + "/Documents/"
                let cachesPrefix = containerPath + "/Library/Caches/"
                let libPrefix = containerPath + "/Library/"
                let tmpPrefix = containerPath + "/tmp/"

                walkDirectory(containerPath, ownerLabel: displayName, shouldCancel: shouldCancel) { name, path, size, mtime in
                    appTotal += size
                    appCount += 1
                    appsDataBytes += size

                    if path.hasPrefix(docsPrefix) {
                        docsBytes += size
                    } else if path.hasPrefix(cachesPrefix) {
                        cachesBytes += size
                    } else if path.hasPrefix(libPrefix) {
                        libBytes += size
                    } else if path.hasPrefix(tmpPrefix) {
                        tmpBytes += size
                    }

                    recordFile(name: name, path: path, size: size, mtime: mtime, owner: displayName, section: "正在扫描：\(displayName)")
                }

                if appTotal > 0 {
                    apps.append(
                        AppStorageEntry(
                            id: uuid,
                            displayName: displayName,
                            bundleID: bid,
                            containerPath: containerPath,
                            totalBytes: appTotal,
                            fileCount: appCount,
                            documentsBytes: docsBytes,
                            libraryBytes: libBytes,
                            cachesBytes: cachesBytes,
                            tmpBytes: tmpBytes
                        )
                    )
                }
            }
        }

        // 3. AppGroup shared containers
        emit("正在扫描应用共享组…", force: true)
        let groupRoot = "/var/mobile/Containers/Shared/AppGroup"
        if let groups = try? FileManager.default.contentsOfDirectory(atPath: groupRoot) {
            for uuid in groups {
                if shouldCancel() { break }
                let gpath = (groupRoot as NSString).appendingPathComponent(uuid)
                let gid = containerMetadataIdentifier(at: gpath) ?? "AppGroup"
                walkDirectory(gpath, ownerLabel: gid, shouldCancel: shouldCancel) { name, path, size, mtime in
                    appGroupsBytes += size
                    recordFile(name: name, path: path, size: size, mtime: mtime, owner: gid, section: "正在扫描应用共享组…")
                }
            }
        }

        // 4. User Documents & Downloads
        emit("正在扫描用户文档与下载…", force: true)
        for docDir in ["/var/mobile/Documents", "/var/mobile/Media/Downloads"] {
            if shouldCancel() { break }
            walkDirectory(docDir, ownerLabel: "本地文档", shouldCancel: shouldCancel) { name, path, size, mtime in
                userDocsBytes += size
                recordFile(name: name, path: path, size: size, mtime: mtime, owner: "本地文档", section: "正在扫描用户文档与下载…")
            }
        }

        // 5. System Caches & Logs
        emit("正在扫描缓存与日志…", force: true)
        for cacheDir in ["/var/mobile/Library/Caches", "/var/mobile/Library/Logs"] {
            if shouldCancel() { break }
            walkDirectory(cacheDir, ownerLabel: "系统缓存/日志", shouldCancel: shouldCancel) { name, path, size, mtime in
                cachesAndLogsBytes += size
                recordFile(name: name, path: path, size: size, mtime: mtime, owner: "系统缓存/日志", section: "正在扫描缓存与日志…")
            }
        }

        var categories = FileCategory.allCases.map { cat -> CategorySummary in
            var s = catMap[cat]!
            s.topFiles.sort { $0.size > $1.size }
            return s
        }
        categories.sort { $0.totalBytes > $1.totalBytes }
        largeFiles.sort { $0.size > $1.size }
        apps.sort { $0.totalBytes > $1.totalBytes }

        return ScanReport(
            completedAt: Date(),
            scannedFiles: scannedFiles,
            scannedBytes: scannedBytes,
            mediaBytes: mediaBytes,
            appsDataBytes: appsDataBytes,
            appGroupsBytes: appGroupsBytes,
            cachesAndLogsBytes: cachesAndLogsBytes,
            userDocsBytes: userDocsBytes,
            categories: categories,
            largeFiles: largeFiles,
            apps: apps
        )
    }

    /// Lists direct children of a directory with shallow directory sizes (read-only).
    static func listDirectory(at path: String) -> [DirectoryItem] {
        guard let dir = opendir(path) else { return [] }
        defer { closedir(dir) }

        var items: [DirectoryItem] = []
        while let entPtr = readdir(dir) {
            let name = withUnsafePointer(to: &entPtr.pointee.d_name) { ptr -> String in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN)) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            let full = path.hasSuffix("/") ? (path + name) : (path + "/" + name)
            var st = stat()
            if lstat(full, &st) != 0 { continue }

            let mode = st.st_mode & S_IFMT
            let isDir = (mode == S_IFDIR)
            let size: Int64
            if isDir {
                size = computeDirectorySize(full)
            } else {
                let allocated = Int64(st.st_blocks) * 512
                size = allocated > 0 ? min(allocated, Int64(st.st_size)) : Int64(st.st_size)
            }
            items.append(
                DirectoryItem(
                    id: full,
                    name: name,
                    path: full,
                    isDirectory: isDir,
                    size: max(0, size),
                    modifiedDate: Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
                )
            )
        }

        items.sort { lhs, rhs in
            if lhs.size != rhs.size { return lhs.size > rhs.size }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return items
    }

    private static func computeDirectorySize(_ rootPath: String) -> Int64 {
        var total: Int64 = 0
        walkDirectory(rootPath, ownerLabel: "", shouldCancel: { false }) { _, _, size, _ in
            total += size
        }
        return total
    }
}
