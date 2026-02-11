import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showRegionPicker = false
    @State private var regionFilter = ""

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if let route = appState.selectedRoute {
                detailView(for: route)
            } else {
                welcomeView
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                regionBadge
            }
        }
    }

    private var isGlobalService: Bool {
        appState.selectedRoute == .s3
    }

    @ViewBuilder
    private var regionBadge: some View {
        if isGlobalService {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.caption)
                Text("Global")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.quaternary, in: Capsule())
            .padding(3)
            .opacity(0.5)
            .help("S3 buckets are global on LocalStack, not region-specific")
        } else {
            Button {
                showRegionPicker.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.caption)
                    Text(appState.region)
                        .font(.caption)
                        .fontWeight(.medium)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.quaternary, in: Capsule())
                .padding(3)
            }
            .buttonStyle(.plain)
            .help("Region: \(appState.region) — Click to change")
            .popover(isPresented: $showRegionPicker, arrowEdge: .bottom) {
                regionPickerPopover
            }
        }
    }

    private var filteredRegions: [AWSRegion] {
        let query = regionFilter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return AWSRegion.allRegions }
        return AWSRegion.allRegions.filter {
            $0.code.lowercased().contains(query)
                || $0.displayName.lowercased().contains(query)
        }
    }

    private var regionPickerPopover: some View {
        VStack(spacing: 0) {
            TextField("Filter...", text: $regionFilter)
                .textFieldStyle(.roundedBorder)
                .padding(8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredRegions, id: \.code) { region in
                            Button {
                                appState.region = region.code
                                showRegionPicker = false
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.weight(.bold))
                                        .opacity(region.code == appState.region ? 1 : 0)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(region.code)
                                            .font(.body)
                                        Text(region.displayName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                                .background(region.code == appState.region ? Color.accentColor.opacity(0.12) : Color.clear)
                            }
                            .buttonStyle(.plain)
                            .id(region.code)
                        }
                    }
                }
                .frame(maxHeight: 260)
                .onAppear {
                    regionFilter = ""
                    proxy.scrollTo(appState.region, anchor: .center)
                }
            }
        }
        .frame(width: 320)
    }

    @ViewBuilder
    private func detailView(for route: Route) -> some View {
        switch route {
        case .s3:
            S3ModuleView()
        case .sqs:
            SQSModuleView()
        case .sns:
            SNSModuleView()
        case .secretsManager:
            SecretsManagerModuleView()
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cloud")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("LocalStack Navigator")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text("Select a service from the sidebar to get started.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
