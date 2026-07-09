//
//  SharedComponents.swift
//  MovieBoxZAdmin
//
//  Shared UI components used across multiple views
//

import SwiftUI

// MARK: - Status Badge
struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

// MARK: - Detail Row
struct DetailRow: View {
    let label: String
    let value: String
    let labelWidth: CGFloat
    let showColon: Bool

    init(label: String, value: String, labelWidth: CGFloat = 100, showColon: Bool = false) {
        self.label = label
        self.value = value
        self.labelWidth = labelWidth
        self.showColon = showColon
    }

    var body: some View {
        HStack {
            Text(showColon ? "\(label):" : label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: labelWidth, alignment: .leading)
            Text(value)
                .font(.body)
            Spacer()
        }
    }
}

// MARK: - App Settings

struct AppSettingsView: View {
    @AppStorage("apiBaseURL") private var apiBaseURL = "https://movieboxz-backend-production.up.railway.app"
    @AppStorage("adminAPIKey") private var adminAPIKey = ""
    @State private var showKey = false
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSucceeded = false

    var body: some View {
        Form {
            Section("Backend") {
                TextField("Backend URL", text: $apiBaseURL)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    if showKey {
                        TextField("Admin API Key", text: $adminAPIKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Admin API Key", text: $adminAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(showKey ? "Hide" : "Show") {
                        showKey.toggle()
                    }
                }
            }

            Section {
                HStack {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        if isTesting {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Test Connection", systemImage: "bolt.fill")
                        }
                    }
                    .disabled(isTesting)

                    if let testResult {
                        Label(testResult, systemImage: testSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(testSucceeded ? .green : .red)
                    }
                }

                Text("Changes are saved automatically. Switch to another section and back for views to pick up a new key.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 500)
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil

        defer { isTesting = false }

        // Verify the admin key against a protected endpoint, not just /health
        guard let url = URL(string: "\(apiBaseURL)/api/admin/staging/stats") else {
            testSucceeded = false
            testResult = "Invalid URL"
            return
        }

        var request = URLRequest(url: url)
        request.setValue(adminAPIKey, forHTTPHeaderField: "x-admin-api-key")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200:
                testSucceeded = true
                testResult = "Connected — key is valid"
            case 401:
                testSucceeded = false
                testResult = "Backend reachable, but the API key was rejected"
            default:
                testSucceeded = false
                testResult = "Unexpected response (\(status))"
            }
        } catch {
            testSucceeded = false
            testResult = "Could not reach backend"
        }
    }
}
