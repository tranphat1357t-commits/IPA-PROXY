import SwiftUI

enum SupportedGame: String, Identifiable {
    case ffth
    case ffm

    var id: String { rawValue }
    var title: String {
        switch self {
        case .ffth: return "Free Fire TH"
        case .ffm: return "Free Fire Max"
        }
    }

    var bundleID: String {
        switch self {
        case .ffth: return "com.dts.freefireth"
        case .ffm: return "com.dts.freefiremax"
        }
    }

    var subtitle: String { bundleID }
    var tint: Color {
        switch self {
        case .ffth: return Color(red: 0.90, green: 0.14, blue: 0.60)
        case .ffm: return Color(red: 0.08, green: 0.76, blue: 0.34)
        }
    }
}

enum FFTHPatchPreset: String, CaseIterable, Identifiable {
    case body
    case drag
    case neck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .body: return "Proxy Body"
        case .drag: return "Proxy Drag"
        case .neck: return "Proxy Neck"
        }
    }

    var detail: String {
        switch self {
        case .body: return "Aim vào phần thân"
        case .drag: return "Hỗ trợ kéo tâm lên đầu"
        case .neck: return "Aim ưu tiên vùng cổ"
        }
    }

    var icon: String {
        switch self {
        case .body: return "figure.stand"
        case .drag: return "arrow.up.right"
        case .neck: return "scope"
        }
    }

    // Resource names are deliberately kept separate from display names so a
    // future FFTH package can be replaced without changing the UI.
    var resourceName: String {
        switch self {
        case .body: return "Aim_Body_Free_Fire_1787211276881"
        case .drag: return "Aim_Drag_Free_Fire_1787211276882"
        case .neck: return "Aim_Neck_Free_Fire_1787211276883"
        }
    }
}

@MainActor
final class FFTHPatchController: ObservableObject {
    @Published private(set) var enabled: [FFTHPatchPreset: Bool] = [:]
    @Published private(set) var busyPreset: FFTHPatchPreset?
    @Published var errorMessage: String?

    private static let installedKey = "ffth.bundledPatchesInstalled.v1"
    private static let idsKey = "ffth.bundledPatchIDs.v1"
    private let fileManager = FileManager.default
    private var packageIDs: [FFTHPatchPreset: UUID] = [:]

    func prepare() {
        guard !UserDefaults.standard.bool(forKey: Self.installedKey) else {
            loadPackageIDs()
            syncEnabledState()
            return
        }

        busyPreset = nil
        do {
            for preset in FFTHPatchPreset.allCases {
                guard let sourceURL = Bundle.main.url(
                    forResource: preset.resourceName,
                    withExtension: "3105"
                ) else {
                    throw PatchPackageError.invalidProject
                }

                let data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
                let summary = try PatchPackageCodec.inspect(data)
                guard !summary.isPasswordProtected else {
                    throw PatchPackageError.invalidPasswordOrCorruptedPackage
                }
                let decoded = try PatchPackageCodec.decode(data, password: nil)
                let existingURL = PatchProjectLibrary.load()
                    .first(where: { $0.id == summary.packageID })?
                    .packageURL
                try PatchProjectLibrary.installImportedPackage(
                    data: data,
                    decoded: decoded,
                    summary: summary,
                    existingURL: existingURL,
                    fileManager: fileManager
                )
                packageIDs[preset] = summary.packageID
            }
            savePackageIDs()
            UserDefaults.standard.set(true, forKey: Self.installedKey)
            syncEnabledState()
        } catch {
            errorMessage = "Không thể nạp bộ patch FFTH vào thư viện."
            log("ffth: bundled patch import failed: \(error)")
        }
    }

    func isEnabled(_ preset: FFTHPatchPreset) -> Bool {
        enabled[preset] ?? false
    }

    func setEnabled(_ value: Bool, for preset: FFTHPatchPreset) {
        guard busyPreset == nil else { return }
        busyPreset = preset

        guard let item = item(for: preset), let project = item.project else {
            busyPreset = nil
            errorMessage = "Không tìm thấy gói \(preset.title)."
            return
        }

        Task {
            do {
                if value {
                    _ = try await Task.detached(priority: .userInitiated) {
                        try DevicePatchService.apply(project: project)
                    }.value
                } else if let receipt = DevicePatchService.latestReceipt(projectID: item.id) {
                    try await Task.detached(priority: .userInitiated) {
                        try DevicePatchService.restore(receipt: receipt)
                    }.value
                }
                enabled[preset] = value
                busyPreset = nil
            } catch let error as PatchPackageError {
                busyPreset = nil
                errorMessage = error.errorDescription ?? "Không thể áp dụng patch."
            } catch {
                busyPreset = nil
                errorMessage = "Không thể \(value ? "áp dụng" : "khôi phục") \(preset.title)."
            }
        }
    }

    private func item(for preset: FFTHPatchPreset) -> PatchLibraryItem? {
        guard let packageID = packageIDs[preset] else { return nil }
        return PatchProjectLibrary.load().first { $0.id == packageID }
    }

    private func syncEnabledState() {
        enabled = Dictionary(uniqueKeysWithValues: FFTHPatchPreset.allCases.map { preset in
            (preset, DevicePatchService.latestReceipt(projectID: item(for: preset)?.id ?? UUID()) != nil)
        })
    }

    private func loadPackageIDs() {
        let values = UserDefaults.standard.dictionary(forKey: Self.idsKey) as? [String: String] ?? [:]
        packageIDs = Dictionary(uniqueKeysWithValues: FFTHPatchPreset.allCases.compactMap { preset in
            guard let rawID = values[preset.rawValue], let id = UUID(uuidString: rawID) else {
                return nil
            }
            return (preset, id)
        })
    }

    private func savePackageIDs() {
        let values = Dictionary(uniqueKeysWithValues: packageIDs.map {
            ($0.key.rawValue, $0.value.uuidString)
        })
        UserDefaults.standard.set(values, forKey: Self.idsKey)
    }
}

struct GameSelectionView: View {
    var body: some View {
        Section {
            HStack(spacing: 12) {
                NavigationLink {
                    GamePatchView(game: .ffth)
                } label: {
                    GameCard(game: .ffth, status: "FFTH đã sẵn sàng")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    GamePatchView(game: .ffm)
                } label: {
                    GameCard(game: .ffm, status: "Đang chờ bộ file")
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("GAMES")
        } footer: {
            Text("Chọn game để mở các cấu hình patch riêng.")
        }
    }
}

private struct GameCard: View {
    let game: SupportedGame
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                LinearGradient(
                    colors: [game.tint.opacity(0.95), game.tint.opacity(0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: game == .ffth ? "scope" : "gamecontroller.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(game.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(game.subtitle)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(status)
                .font(.caption2)
                .foregroundStyle(game == .ffth ? .green : .secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(game.tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(game.tint.opacity(0.5), lineWidth: 1)
        )
    }
}

struct GamePatchView: View {
    let game: SupportedGame
    @StateObject private var controller = FFTHPatchController()

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: game == .ffth ? "scope" : "gamecontroller.fill")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(game.tint)
                    Text(game.title)
                        .font(.title2.weight(.bold))
                    Text(game.bundleID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }

            if game == .ffth {
                Section {
                    ForEach(FFTHPatchPreset.allCases) { preset in
                        Toggle(isOn: Binding(
                            get: { controller.isEnabled(preset) },
                            set: { controller.setEnabled($0, for: preset) }
                        )) {
                            HStack(spacing: 12) {
                                Image(systemName: preset.icon)
                                    .font(.headline)
                                    .foregroundStyle(game.tint)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(preset.title)
                                        .font(.body.weight(.semibold))
                                    Text(preset.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(controller.busyPreset != nil)
                    }
                } header: {
                    HStack {
                        Label("PROXY DELTA VIP", systemImage: "bolt.fill")
                        Spacer()
                        if controller.busyPreset != nil {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("AUTO")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(game.tint)
                        }
                    }
                } footer: {
                    Text("Khi bật, patch tương ứng sẽ được đưa vào đường dẫn của Free Fire TH. Khi tắt, bản sao lưu gần nhất sẽ được khôi phục.")
                }
            } else {
                Section {
                    Label("Bộ file FFM chưa được thêm", systemImage: "clock")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Màn hình Free Fire Max đã sẵn sàng. Thêm bộ .3105 của FFM sau để bật các công tắc.")
                }
            }
        }
        .navigationTitle(game.title)
        .navigationBarTitleDisplayMode(.inline)
        .tint(game.tint)
        .onAppear {
            if game == .ffth {
                controller.prepare()
            }
        }
        .alert(
            "Không thể thực hiện",
            isPresented: Binding(
                get: { controller.errorMessage != nil },
                set: { if !$0 { controller.errorMessage = nil } }
            )
        ) {
            Button("OK") { controller.errorMessage = nil }
        } message: {
            Text(controller.errorMessage ?? "")
        }
    }
}