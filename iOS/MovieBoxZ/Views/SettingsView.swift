import SwiftUI

struct SettingsView: View {
    @StateObject private var movieService = MovieService()
    @State private var isConnected = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Image(systemName: "tv.circle.fill")
                            .foregroundColor(.red)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("MovieBoxZ")
                                .font(.headline)
                            Text("Version 1.0.0")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 5)
                }

                Section("Connection") {
                    HStack {
                        Image(systemName: isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(isConnected ? .green : .red)
                        Text("Backend Service")
                        Spacer()
                        Text(isConnected ? "Connected" : "Offline")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button("Test Connection") {
                        movieService.checkConnection()
                    }
                }

                Section("YouTube Integration") {
                    HStack {
                        Image(systemName: "play.rectangle.fill")
                            .foregroundColor(.red)
                        Text("Deep Link to YouTube")
                        Spacer()
                        Text("Enabled")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Image(systemName: "tv")
                            .foregroundColor(.blue)
                        Text("Apple TV YouTube")
                        Spacer()
                        Text("Supported")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("About") {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("YouTube Terms Compliance")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }

                    HStack {
                        Image(systemName: "shield.checkered")
                        Text("Privacy Policy")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Image(systemName: "doc.text")
                        Text("Terms of Service")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }

                Section("Support") {
                    HStack {
                        Image(systemName: "questionmark.circle")
                        Text("Help & FAQ")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Image(systemName: "envelope")
                        Text("Contact Support")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .onReceive(movieService.$isConnected) { connected in
            isConnected = connected
        }
        .onAppear {
            isConnected = movieService.isConnected
        }
    }
}

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}