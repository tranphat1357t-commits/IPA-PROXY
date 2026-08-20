import SwiftUI

struct ContactView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    contactLink(
                        title: "Admin Zalo",
                        detail: "84379957836",
                        icon: "bubble.left.and.bubble.right.fill",
                        url: "http://zalo.me/84379957836"
                    )
                    contactLink(
                        title: "Telegram",
                        detail: "@nguyen_quan_dz",
                        icon: "paperplane.fill",
                        url: "https://t.me/nguyen_quan_dz"
                    )
                    contactLink(
                        title: "Box Zalo",
                        detail: "Tham gia nhóm hỗ trợ",
                        icon: "person.3.fill",
                        url: "https://zalo.me/g/gjjxyw976"
                    )
                } header: {
                    Text("Liên hệ hỗ trợ")
                } footer: {
                    Text("Chạm vào một mục để mở liên kết liên hệ.")
                }
            }
            .navigationTitle("Liên hệ")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func contactLink(
        title: String,
        detail: String,
        icon: String,
        url: String
    ) -> some View {
        Link(destination: URL(string: url)!) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 26)
            }
        }
    }
}