import AVKit
import PDFKit
import QuickLook
import SwiftUI
import UIKit

struct FilePreviewTarget: Identifiable {
    let id: String
    let name: String
    let path: String
    let size: Int64
}

struct FilePreviewSheet: View {
    let target: FilePreviewTarget
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var ext: String {
        (target.name as NSString).pathExtension.lowercased()
    }

    var body: some View {
        NavigationView {
            Group {
                if isImage {
                    ImageFilePreview(path: target.path)
                } else if isMedia {
                    MediaFilePreview(path: target.path)
                } else if ext == "pdf" {
                    PDFFilePreview(path: target.path)
                } else if isText && target.size <= 2 * 1024 * 1024 {
                    TextFilePreview(path: target.path)
                } else {
                    QuickLookOrFallbackView(target: target)
                }
            }
            .navigationTitle(target.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        UIPasteboard.general.string = target.path
                        copied = true
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    Button {
                        openInFilza(path: target.path)
                    } label: {
                        Image(systemName: "folder.badge.gearshape")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var isImage: Bool {
        ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "bmp", "tiff", "tif"].contains(ext)
    }

    private var isMedia: Bool {
        ["mp4", "mov", "m4v", "mp3", "m4a", "aac", "wav", "aiff", "caf"].contains(ext)
    }

    private var isText: Bool {
        ["txt", "md", "json", "xml", "plist", "log", "csv", "sh", "py", "js", "css", "html", "yml", "yaml", "conf", "ini", "strings", "swift", "h", "m", "c"].contains(ext)
    }
}

func openInFilza(path: String) {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "?#")
    let encoded = path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    if let url = URL(string: "filza://view\(encoded)") {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

private struct ImageFilePreview: View {
    let path: String
    @State private var scale: CGFloat = 1.0

    var body: some View {
        if let uiImage = UIImage(contentsOfFile: path) {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { val in
                                scale = max(1.0, min(5.0, val))
                            }
                    )
                    .onTapGesture(count: 2) {
                        scale = (scale > 1.0) ? 1.0 : 2.5
                    }
            }
            .background(Color.black)
        } else {
            unsupportedBanner("无法解码此图片文件")
        }
    }
}

private struct MediaFilePreview: UIViewControllerRepresentable {
    let path: String

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        let player = AVPlayer(url: URL(fileURLWithPath: path))
        vc.player = player
        player.play()
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: ()) {
        uiViewController.player?.pause()
        uiViewController.player = nil
    }
}

private struct PDFFilePreview: UIViewRepresentable {
    let path: String

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: URL(fileURLWithPath: path))
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}

private struct TextFilePreview: View {
    let path: String
    @State private var text: String = "正在读取…"

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .onAppear {
            DispatchQueue.global(qos: .userInitiated).async {
                let loaded = loadReadableText(at: path)
                DispatchQueue.main.async {
                    self.text = loaded
                }
            }
        }
    }

    private func loadReadableText(at path: String) -> String {
        let url = URL(fileURLWithPath: path)
        if let str = try? String(contentsOf: url, encoding: .utf8) {
            return str
        }
        // Support binary plist inspection safely
        if let data = try? Data(contentsOf: url),
           let obj = try? PropertyListSerialization.propertyList(from: data, format: nil) {
            return String(describing: obj)
        }
        return "（二进制或非 UTF-8 编码文件，可点击右上角在 Filza 中查看）"
    }
}

private struct QuickLookOrFallbackView: View {
    let target: FilePreviewTarget

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.fill")
                .font(.system(size: 52))
                .foregroundColor(.secondary)
            Text(target.name)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Text("体积：\(ByteFormat.string(target.size))")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(target.path)
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                openInFilza(path: target.path)
            } label: {
                Label("在 Filza 中打开定位", systemImage: "folder.fill")
                    .frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

private func unsupportedBanner(_ msg: String) -> some View {
    VStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle")
            .font(.largeTitle)
            .foregroundColor(.orange)
        Text(msg)
            .foregroundColor(.secondary)
    }
}
