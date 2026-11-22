import Foundation
import SwiftUI

enum FileCategory: String, CaseIterable, Identifiable {
    case video = "视频"
    case image = "图片"
    case audio = "音频"
    case document = "文档"
    case archiveAndPackage = "压缩 / 安装包"
    case other = "其它文件"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .video: return "film.fill"
        case .image: return "photo.fill"
        case .audio: return "music.note"
        case .document: return "doc.text.fill"
        case .archiveAndPackage: return "archivebox.fill"
        case .other: return "doc.fill"
        }
    }

    var color: Color {
        switch self {
        case .video: return .purple
        case .image: return .blue
        case .audio: return .pink
        case .document: return .orange
        case .archiveAndPackage: return .teal
        case .other: return .gray
        }
    }

    static func classify(extension ext: String) -> FileCategory {
        switch ext.lowercased() {
        case "mp4", "mov", "m4v", "mkv", "avi", "flv", "webm", "ts", "wmv", "3gp":
            return .video
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "bmp", "tiff", "tif", "dng", "raw", "svg":
            return .image
        case "mp3", "m4a", "aac", "flac", "wav", "ogg", "opus", "aiff", "wma", "amr", "silk":
            return .audio
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md", "csv", "rtf", "pages", "numbers", "key", "epub", "json", "xml", "plist", "log":
            return .document
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "ipa", "deb", "dmg", "pkg", "tipa", "apk":
            return .archiveAndPackage
        default:
            return .other
        }
    }
}

struct FileEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let size: Int64
    let category: FileCategory
    let ownerLabel: String
    let modifiedDate: Date
}

struct CategorySummary: Identifiable {
    let category: FileCategory
    var totalBytes: Int64 = 0
    var fileCount: Int = 0
    var topFiles: [FileEntry] = []

    var id: String { category.id }
}

struct AppStorageEntry: Identifiable {
    let id: String
    let displayName: String
    let bundleID: String
    let containerPath: String
    let totalBytes: Int64
    let fileCount: Int
    let documentsBytes: Int64
    let libraryBytes: Int64
    let cachesBytes: Int64
    let tmpBytes: Int64
}

struct DirectoryItem: Identifiable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    let modifiedDate: Date
}

struct DiskOverview {
    let totalBytes: Int64
    let availableBytes: Int64

    var usedBytes: Int64 {
        max(0, totalBytes - availableBytes)
    }

    var usedRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(usedBytes) / Double(totalBytes)))
    }
}

struct ScanProgress {
    var scannedFiles: Int = 0
    var scannedBytes: Int64 = 0
    var currentSection: String = "准备中…"
}

struct ScanReport {
    let completedAt: Date
    let scannedFiles: Int
    let scannedBytes: Int64
    let mediaBytes: Int64
    let appsDataBytes: Int64
    let appGroupsBytes: Int64
    let cachesAndLogsBytes: Int64
    let userDocsBytes: Int64
    let categories: [CategorySummary]
    let largeFiles: [FileEntry]
    let apps: [AppStorageEntry]
}

enum ByteFormat {
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        f.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return f
    }()

    static func string(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: max(0, bytes))
    }
}
