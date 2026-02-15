import SwiftUI
import AppKit

struct EventBridgeScheduleBrowserView: View {
    @ObservedObject var service: EventBridgeSchedulerService
    let group: SchedulerScheduleGroup
    @ObservedObject var toolbarState: EventBridgeToolbarState
    @EnvironmentObject private var appState: AppState

    @State private var schedules: [SchedulerSchedule] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastLoadTime: Date?
    @State private var serviceError: ServiceError?
    @State private var searchText = ""

    // Drill-down state
    @State private var activeSchedule: SchedulerSchedule?

    // Sheets
    @State private var showCreateScheduleSheet = false
    @State private var schedulesToDelete: [SchedulerSchedule] = []

    // Session restore
    var restoreScheduleName: String?
    @State private var hasRestoredSession = false

    var body: some View {
        VStack(spacing: 0) {
            if let schedule = activeSchedule {
                scheduleDetailMode(schedule: schedule)
            } else {
                scheduleListMode
            }
        }
        .sheet(isPresented: $showCreateScheduleSheet) {
            EventBridgeCreateScheduleView(
                service: service,
                groupName: group.name,
                existingScheduleNames: Set(schedules.map(\.name))
            )
            .onDisappear { loadSchedules(force: true) }
        }
        .alert(
            schedulesToDelete.count == 1
                ? "Delete Schedule"
                : "Delete \(schedulesToDelete.count) Schedules",
            isPresented: Binding(
                get: { !schedulesToDelete.isEmpty },
                set: { if !$0 { schedulesToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteSchedules(schedulesToDelete)
            }
            Button("Cancel", role: .cancel) {
                schedulesToDelete = []
            }
        } message: {
            if schedulesToDelete.count == 1, let schedule = schedulesToDelete.first {
                Text("Are you sure you want to delete \"\(schedule.name)\"?")
            } else {
                let names = schedulesToDelete.map(\.name).joined(separator: "\n")
                Text("Are you sure you want to delete these schedules?\n\n\(names)\n\nThis cannot be undone.")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadSchedules() }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard activeSchedule == nil && !showCreateScheduleSheet && schedulesToDelete.isEmpty && !isLoading else { return }
            loadSchedules(force: true, silent: true)
        }
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .createSchedule:
                toolbarState.pendingAction = nil
                showCreateScheduleSheet = true
            default:
                break
            }
        }
    }

    private var filteredSchedules: [SchedulerSchedule] {
        guard !searchText.isEmpty else { return schedules }
        let query = searchText.lowercased()
        return schedules.filter { $0.name.lowercased().contains(query) }
    }

    // MARK: - Schedule List Mode

    @ViewBuilder
    private var scheduleListMode: some View {
        // Warning banner
        HStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.orange)
            Text("Schedules are stored but will NOT execute in LocalStack")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))

        Divider()

        // Header
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            Spacer()
            Button { showCreateScheduleSheet = true } label: {
                Image(systemName: "plus")
                    .foregroundStyle(appState.isReadOnly ? .gray : Color.primary)
            }
            .buttonStyle(.borderless)
            .disabled(appState.isReadOnly)
            .help("Create Schedule")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

        Divider()

        if isLoading && schedules.isEmpty {
            ProgressView("Loading schedules...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, schedules.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadSchedules(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if schedules.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No schedules")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .contextMenu {
                Button("Create Schedule") {
                    showCreateScheduleSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if schedules.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter schedules")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredSchedules) { schedule in
                    Button {
                        drillIntoSchedule(schedule)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(schedule.name)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(schedule.isEnabled ? "ENABLED" : "DISABLED")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(
                                            (schedule.isEnabled ? Color.green : Color.gray).opacity(0.15),
                                            in: Capsule()
                                        )
                                        .foregroundStyle(schedule.isEnabled ? .green : .gray)
                                    if let expr = schedule.scheduleExpression {
                                        Text(ScheduleExpressionHelper.humanReadable(expr) ?? expr)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                HStack(spacing: 4) {
                                    let targetType = schedule.targetServiceType
                                    Image(systemName: targetType.systemImage)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(targetType.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("View Schedule") {
                            drillIntoSchedule(schedule)
                        }
                        Divider()
                        if schedule.isEnabled {
                            Button("Disable Schedule") {
                                toggleSchedule(schedule, enable: false)
                            }
                            .disabled(appState.isReadOnly)
                        } else {
                            Button("Enable Schedule") {
                                toggleSchedule(schedule, enable: true)
                            }
                            .disabled(appState.isReadOnly)
                        }
                        Divider()
                        Button("Copy Name") { copyToClipboard(schedule.name) }
                        if let arn = schedule.arn {
                            Button("Copy ARN") { copyToClipboard(arn) }
                        }
                        Divider()
                        Button("Create Schedule") {
                            showCreateScheduleSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        Button("Delete", role: .destructive) {
                            schedulesToDelete = [schedule]
                        }
                        .disabled(appState.isReadOnly)
                    }
                }
                .contextMenu {
                    Button("Create Schedule") {
                        showCreateScheduleSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

                // Status bar
                Divider()
                HStack {
                    Text("\(schedules.count) schedule\(schedules.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Schedule Detail Mode

    @ViewBuilder
    private func scheduleDetailMode(schedule: SchedulerSchedule) -> some View {
        // Header with back button
        HStack {
            Button {
                activeSchedule = nil
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Schedules")
                }
            }
            .buttonStyle(.borderless)

            Spacer()

            Text(schedule.name)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            if schedule.isEnabled {
                Button {
                    toggleSchedule(schedule, enable: false)
                } label: {
                    Image(systemName: "pause.circle")
                        .foregroundStyle(appState.isReadOnly ? .gray : .orange)
                }
                .buttonStyle(.borderless)
                .disabled(appState.isReadOnly)
                .help("Disable Schedule")
            } else {
                Button {
                    toggleSchedule(schedule, enable: true)
                } label: {
                    Image(systemName: "play.circle")
                        .foregroundStyle(appState.isReadOnly ? .gray : .green)
                }
                .buttonStyle(.borderless)
                .disabled(appState.isReadOnly)
                .help("Enable Schedule")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)

        Divider()

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                scheduleInfoSection(schedule: schedule)
                scheduleExpressionSection(schedule: schedule)
                targetSection(schedule: schedule)
                if let mode = schedule.flexibleTimeWindowMode, mode != "OFF" {
                    flexibleTimeWindowSection(schedule: schedule)
                }
            }
            .padding()
        }

        // Status bar
        Divider()
        HStack {
            if let arn = schedule.arn {
                Text(arn)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func scheduleInfoSection(schedule: SchedulerSchedule) -> some View {
        GroupBox("Schedule Info") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("State") {
                    Text(schedule.state)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            (schedule.isEnabled ? Color.green : Color.gray).opacity(0.15),
                            in: Capsule()
                        )
                        .foregroundStyle(schedule.isEnabled ? .green : .gray)
                }
                if let groupName = schedule.groupName {
                    LabeledContent("Group") {
                        Text(groupName)
                            .foregroundStyle(.secondary)
                    }
                }
                if let desc = schedule.description, !desc.isEmpty {
                    LabeledContent("Description") {
                        Text(desc)
                            .foregroundStyle(.secondary)
                    }
                }
                if let tz = schedule.scheduleExpressionTimezone, !tz.isEmpty {
                    LabeledContent("Timezone") {
                        Text(tz)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    @ViewBuilder
    private func scheduleExpressionSection(schedule: SchedulerSchedule) -> some View {
        if let expr = schedule.scheduleExpression {
            GroupBox("Schedule Expression") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(expr)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let human = ScheduleExpressionHelper.humanReadable(expr) {
                        Text(human)
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }

                    let occurrences = ScheduleExpressionHelper.nextOccurrences(
                        expr, count: 5, timezone: schedule.scheduleExpressionTimezone
                    )
                    if !occurrences.isEmpty {
                        Divider()
                        Text("Next Occurrences")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        ForEach(Array(occurrences.enumerated()), id: \.offset) { _, date in
                            Text(date.formatted(date: .abbreviated, time: .standard))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
        }
    }

    @ViewBuilder
    private func targetSection(schedule: SchedulerSchedule) -> some View {
        GroupBox("Target") {
            VStack(alignment: .leading, spacing: 8) {
                if let arn = schedule.targetArn {
                    LabeledContent("Target ARN") {
                        HStack(spacing: 4) {
                            let targetType = schedule.targetServiceType
                            Image(systemName: targetType.systemImage)
                                .font(.caption)
                            Text(targetType.displayName)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.purple.opacity(0.15), in: Capsule())
                                .foregroundStyle(.purple)
                        }
                    }
                    Text(arn)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
                if let roleArn = schedule.targetRoleArn, !roleArn.isEmpty {
                    LabeledContent("Role ARN") {
                        Text(roleArn)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                if let input = schedule.prettyTargetInput, !input.isEmpty {
                    Divider()
                    Text("Input")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Text(input)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    @ViewBuilder
    private func flexibleTimeWindowSection(schedule: SchedulerSchedule) -> some View {
        GroupBox("Flexible Time Window") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Mode") {
                    Text(schedule.flexibleTimeWindowMode ?? "OFF")
                        .foregroundStyle(.secondary)
                }
                if let minutes = schedule.flexibleTimeWindowMaximumWindowInMinutes {
                    LabeledContent("Maximum Window") {
                        Text("\(minutes) minutes")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    // MARK: - Data

    private func drillIntoSchedule(_ schedule: SchedulerSchedule) {
        // Fetch full detail
        Task {
            do {
                let detail = try await service.getSchedule(name: schedule.name, groupName: group.name)
                activeSchedule = detail
            } catch {
                // Fall back to list data
                activeSchedule = schedule
            }
        }
    }

    private func loadSchedules(force: Bool = false, silent: Bool = false) {
        guard !isLoading else { return }
        if !force, let lastLoadTime, Date().timeIntervalSince(lastLoadTime) < 2.0 {
            return
        }
        if !silent {
            isLoading = true
            errorMessage = nil
        }
        Task {
            do {
                let loaded = try await service.listSchedules(groupName: group.name)
                let freshSchedules = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                if schedules != freshSchedules {
                    schedules = freshSchedules
                }
                if !hasRestoredSession, let savedName = restoreScheduleName,
                   let schedule = schedules.first(where: { $0.name == savedName }) {
                    drillIntoSchedule(schedule)
                }
                hasRestoredSession = true
            } catch {
                if !silent {
                    errorMessage = error.localizedDescription
                }
            }
            if !silent {
                isLoading = false
                lastLoadTime = Date()
            }
        }
    }

    private func toggleSchedule(_ schedule: SchedulerSchedule, enable: Bool) {
        Task {
            do {
                try await service.updateScheduleState(
                    name: schedule.name,
                    groupName: group.name,
                    enable: enable,
                    schedule: schedule
                )
                // Refresh
                if activeSchedule != nil {
                    let updated = try await service.getSchedule(name: schedule.name, groupName: group.name)
                    activeSchedule = updated
                }
                loadSchedules(force: true)
            } catch {
                serviceError = error.asServiceError
            }
        }
    }

    private func deleteSchedules(_ targets: [SchedulerSchedule]) {
        Task {
            for schedule in targets {
                do {
                    try await service.deleteSchedule(name: schedule.name, groupName: group.name)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if activeSchedule != nil {
                activeSchedule = nil
            }
            loadSchedules(force: true)
        }
    }

    private func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
