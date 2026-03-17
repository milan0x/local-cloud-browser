import SwiftUI

struct CloudWatchPutMetricView: View {
    @ObservedObject var service: CloudWatchService
    @Environment(\.dismiss) private var dismiss

    @State private var namespace = ""
    @State private var metricName = ""
    @State private var valueText = ""
    @State private var unit: CloudWatchUnit = .none
    @State private var dimensions: [(name: String, value: String)] = []
    @State private var serviceError: ServiceError?
    @State private var isSaving = false

    private var isValid: Bool {
        !namespace.trimmingCharacters(in: .whitespaces).isEmpty &&
        !metricName.trimmingCharacters(in: .whitespaces).isEmpty &&
        Double(valueText) != nil
    }

    var body: some View {
        CreateFormScaffold(
            width: 450,
            isValid: isValid,
            isCreating: isSaving,
            createLabel: "Put Metric",
            serviceError: $serviceError,
            onCreate: save
        ) {
                TextField("Namespace", text: $namespace)
                TextField("Metric Name", text: $metricName)
                TextField("Value", text: $valueText)

                Picker("Unit", selection: $unit) {
                    ForEach(CloudWatchUnit.allCases, id: \.self) { u in
                        Text(u.rawValue).tag(u)
                    }
                }

                Section("Dimensions (optional)") {
                    ForEach(dimensions.indices, id: \.self) { i in
                        HStack {
                            TextField("Name", text: Binding(
                                get: { dimensions[i].name },
                                set: { dimensions[i].name = $0 }
                            ))
                            TextField("Value", text: Binding(
                                get: { dimensions[i].value },
                                set: { dimensions[i].value = $0 }
                            ))
                            Button {
                                dimensions.remove(at: i)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button("Add Dimension") {
                        dimensions.append((name: "", value: ""))
                    }
                    .buttonStyle(.borderless)
                }
        }
    }

    private func save() {
        guard let value = Double(valueText) else { return }
        isSaving = true
        serviceError = nil
        Task {
            do {
                let dims = dimensions
                    .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
                    .map { CloudWatchDimension(name: $0.name.trimmingCharacters(in: .whitespaces), value: $0.value.trimmingCharacters(in: .whitespaces)) }
                try await service.putMetricData(
                    namespace: namespace.trimmingCharacters(in: .whitespaces),
                    metricName: metricName.trimmingCharacters(in: .whitespaces),
                    value: value,
                    unit: unit.rawValue,
                    dimensions: dims
                )
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
