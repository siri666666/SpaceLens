import SwiftUI

final class SpaceLensViewModel: ObservableObject {
    @Published var disk: DiskOverview = StorageScanner.readDiskOverview()
    @Published var report: ScanReport?
    @Published var progress: ScanProgress = ScanProgress()
    @Published var isScanning: Bool = false

    private var cancelRequested = false

    func startScan() {
        guard !isScanning else { return }
        disk = StorageScanner.readDiskOverview()
        isScanning = true
        cancelRequested = false
        progress = ScanProgress(scannedFiles: 0, scannedBytes: 0, currentSection: "正在启动扫描…")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = StorageScanner.performFullScan(
                shouldCancel: { self.cancelRequested },
                onProgress: { prog in
                    DispatchQueue.main.async {
                        self.progress = prog
                    }
                }
            )
            let updatedDisk = StorageScanner.readDiskOverview()
            DispatchQueue.main.async {
                self.disk = updatedDisk
                self.report = result
                self.isScanning = false
            }
        }
    }

    func cancelScan() {
        cancelRequested = true
    }
}

@main
struct SpaceLensApp: App {
    @StateObject private var vm = SpaceLensViewModel()

    var body: some Scene {
        WindowGroup {
            MainTabView(vm: vm)
                .onAppear {
                    if vm.report == nil && !vm.isScanning {
                        vm.startScan()
                    }
                }
        }
    }
}
