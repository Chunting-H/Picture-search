import SwiftUI

struct AuthorizationView: View {
    let state: PhotoLibraryAuthorizationState
    let isLoading: Bool
    let requestAccess: () -> Void
    let refreshStatus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(state.title, systemImage: state.canReadLibrary ? "checkmark.shield.fill" : "lock.shield")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(state.canReadLibrary ? AppTheme.mint : AppTheme.ink)
                Spacer()
            }

            Text(state.canReadLibrary ? "PhotoKit 只读访问已开启，原图不会被修改或上传。" : state.message)
                .font(.caption)
                .foregroundStyle(AppTheme.ink.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)

            if !state.canReadLibrary {
                HStack {
                    Button {
                        requestAccess()
                    } label: {
                        Label(state.primaryActionTitle, systemImage: "photo.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)

                    Button {
                        refreshStatus()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("刷新权限状态")
                    .disabled(isLoading)
                }
                .controlSize(.small)
            } else {
                Button {
                    requestAccess()
                } label: {
                    Label("重新检查权限", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(AppTheme.ink.opacity(0.55))
                .disabled(isLoading)
            }
        }
        .consolePanel()
    }
}
