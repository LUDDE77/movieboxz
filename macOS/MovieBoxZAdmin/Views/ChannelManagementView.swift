import SwiftUI

struct ChannelManagementView: View {
    @StateObject private var apiService = AdminAPIService()

    // State
    @State private var channels: [ChannelWithPattern] = []
    @State private var selectedChannel: ChannelWithPattern?
    @State private var isLoading = false
    @State private var error: String?

    // Add channel form
    @State private var showAddChannel = false
    @State private var newChannelId = ""
    @State private var isAddingChannel = false

    // Pattern editor
    @State private var editingPattern = false
    @State private var patternRules: [EditablePatternRule] = []
    @State private var fallbackType = "first_segment"
    @State private var fallbackDivider = "|"
    @State private var isSavingPattern = false

    // Pattern testing
    @State private var testResults: PatternTestData?
    @State private var isTestingPattern = false

    var body: some View {
        NavigationSplitView {
            // MARK: - Sidebar (Channel List)
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Channels")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    Button(action: { showAddChannel = true }) {
                        Label("Add Channel", systemImage: "plus")
                    }
                }
                .padding()

                if isLoading && channels.isEmpty {
                    ProgressView("Loading channels...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = error {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text(error)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Channel list
                    List(channels, selection: $selectedChannel) { channel in
                        ChannelRow(channel: channel)
                            .tag(channel)
                    }
                    .onChange(of: selectedChannel) { oldValue, newValue in
                        // Clear pattern editor state when switching channels
                        print("🔄 [Channel] ==================== CHANNEL SWITCH ====================")
                        print("🔄 [Channel] Switched from: \(oldValue?.title ?? "none") (\(oldValue?.id ?? ""))")
                        print("🔄 [Channel] Switched to: \(newValue?.title ?? "none") (\(newValue?.id ?? ""))")
                        print("🔄 [Channel] New channel hasPattern: \(newValue?.hasPattern ?? false)")
                        print("🔄 [Channel] New channel pattern is nil: \(newValue?.pattern == nil)")

                        // Clear state
                        patternRules = []
                        fallbackType = "first_segment"
                        fallbackDivider = "|"
                        testResults = nil
                        error = nil

                        // If new channel has a pattern, load it and show editor
                        if let newChannel = newValue {
                            if newChannel.hasPattern == true {
                                if let pattern = newChannel.pattern {
                                    print("✅ [Channel] Loading pattern with \(pattern.patterns.count) rules")
                                    editingPattern = true

                                    // Load pattern into form fields
                                    patternRules = pattern.patterns.map { rule in
                                        var params: [String: String] = [:]
                                        for (key, param) in rule.parameters {
                                            switch param {
                                            case .int(let val):
                                                params[key] = String(val)
                                            case .string(let val):
                                                params[key] = val
                                            }
                                        }
                                        print("✅ [Channel] Loaded rule with regex: \(rule.regex)")
                                        return EditablePatternRule(regex: rule.regex, parameters: params)
                                    }

                                    if let fallback = pattern.fallbackPattern {
                                        fallbackType = fallback.type
                                        fallbackDivider = fallback.divider ?? "|"
                                    }
                                    print("✅ [Channel] Pattern loaded successfully, editingPattern=true")
                                } else {
                                    print("⚠️ [Channel] WARNING: hasPattern=true but pattern is nil!")
                                    editingPattern = false
                                }
                            } else {
                                print("🔄 [Channel] New channel has no pattern (hasPattern=false)")
                                editingPattern = false
                            }
                        } else {
                            print("🔄 [Channel] newValue is nil")
                            editingPattern = false
                        }
                        print("🔄 [Channel] =====================================================")
                    }
                }
            }
            .frame(minWidth: 300)

        } detail: {
            // MARK: - Detail View
            if let channel = selectedChannel {
                TabView {
                    // Pattern Tab
                    ChannelPatternView(
                        channel: channel,
                        editingPattern: $editingPattern,
                        patternRules: $patternRules,
                        fallbackType: $fallbackType,
                        fallbackDivider: $fallbackDivider,
                        testResults: $testResults,
                        onSavePattern: savePattern,
                        onTestPattern: testPattern,
                        onDeletePattern: deletePattern,
                        onDeleteChannel: deleteChannel,
                        isSavingPattern: isSavingPattern,
                        isTestingPattern: isTestingPattern
                    )
                    .tabItem {
                        Label("Pattern", systemImage: "doc.text.magnifyingglass")
                    }

                    // Settings Tab
                    ChannelSettingsView(channel: channel)
                        .tabItem {
                            Label("Settings", systemImage: "gear")
                        }

                    // Import Tab
                    BulkImportView(channel: channel)
                        .tabItem {
                            Label("Import", systemImage: "arrow.down.circle")
                        }

                    // Movies Tab
                    ChannelMoviesView(channel: channel)
                        .tabItem {
                            Label("Movies", systemImage: "film")
                        }

                    // History Tab
                    ImportHistoryView(channel: channel)
                        .tabItem {
                            Label("History", systemImage: "clock.arrow.circlepath")
                        }
                }
            } else {
                VStack {
                    Image(systemName: "tv")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Select a channel to configure")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showAddChannel) {
            AddChannelSheet(
                channelId: $newChannelId,
                isAdding: $isAddingChannel,
                onAdd: addChannel,
                onCancel: { showAddChannel = false }
            )
        }
        .task {
            await loadChannels()
        }
    }

    // MARK: - Actions

    func loadChannels() async {
        print("📥 [LoadChannels] Starting to load channels from API...")
        isLoading = true
        error = nil

        do {
            let data = try await apiService.getChannelsWithPatterns()
            channels = data.channels
            print("📥 [LoadChannels] Loaded \(channels.count) channels")

            // Log pattern status for each channel
            for channel in channels {
                print("📥 [LoadChannels] Channel: \(channel.title) (ID: \(channel.id))")
                print("📥 [LoadChannels]   - hasPattern: \(String(describing: channel.hasPattern))")
                print("📥 [LoadChannels]   - pattern is nil: \(channel.pattern == nil)")
                if let pattern = channel.pattern {
                    print("📥 [LoadChannels]   - pattern has \(pattern.patterns.count) rules")
                }
            }
        } catch {
            let errorMsg = "Failed to load channels: \(error.localizedDescription)"
            print("❌ [LoadChannels] \(errorMsg)")
            self.error = errorMsg
        }

        isLoading = false
        print("📥 [LoadChannels] Finished loading channels")
    }

    func addChannel() async {
        guard !newChannelId.isEmpty else { return }

        isAddingChannel = true

        do {
            let newChannel = try await apiService.addChannel(channelId: newChannelId)
            channels.append(newChannel)
            newChannelId = ""
            showAddChannel = false
        } catch {
            self.error = "Failed to add channel: \(error.localizedDescription)"
        }

        isAddingChannel = false
    }

    func savePattern() async {
        guard let channel = selectedChannel else {
            print("❌ [Pattern] No channel selected")
            return
        }

        print("💾 [Pattern] Starting save for channel: \(channel.id) - \(channel.title)")
        print("💾 [Pattern] Pattern rules count: \(patternRules.count)")

        // Validate that all patterns have a regex
        for (index, rule) in patternRules.enumerated() {
            print("💾 [Pattern] Rule #\(index + 1) regex: '\(rule.regex)'")
            if rule.regex.trimmingCharacters(in: .whitespaces).isEmpty {
                let errorMsg = "Pattern #\(index + 1) is missing a regular expression. Please fill in the 'Regular expression' field."
                print("❌ [Pattern] Validation failed: \(errorMsg)")
                self.error = errorMsg
                return
            }
        }

        isSavingPattern = true
        error = nil

        do {
            // Convert EditablePatternRule to API format
            let patterns = patternRules.map { rule in
                var params: [String: Any] = [:]
                for (key, value) in rule.parameters {
                    if let intVal = Int(value) {
                        params[key] = intVal
                    } else {
                        params[key] = value
                    }
                }
                return [
                    "regex": rule.regex,
                    "parameters": params
                ] as [String: Any]
            }

            let fallback: [String: String] = [
                "type": fallbackType,
                "divider": fallbackDivider
            ]

            print("💾 [Pattern] Sending patterns to API:")
            print("💾 [Pattern] Patterns: \(patterns)")
            print("💾 [Pattern] Fallback: \(fallback)")

            let savedPattern = try await apiService.updateChannelPattern(
                channelId: channel.id,
                channelName: channel.title,
                patterns: patterns,
                fallbackPattern: fallback
            )

            print("✅ [Pattern] Pattern saved successfully")
            print("✅ [Pattern] Saved pattern ID: \(savedPattern.id)")
            print("✅ [Pattern] Saved patterns count: \(savedPattern.patterns.count)")

            // Reload channels to get updated pattern
            let currentChannelId = channel.id
            await loadChannels()

            // Re-select the updated channel from the reloaded list
            if let updatedChannel = channels.first(where: { $0.id == currentChannelId }) {
                selectedChannel = updatedChannel
                print("✅ [Pattern] Re-selected updated channel: \(updatedChannel.title)")
                print("✅ [Pattern] Updated channel hasPattern: \(String(describing: updatedChannel.hasPattern))")

                // Reload the pattern into the form fields so user can see what they saved
                if let pattern = updatedChannel.pattern {
                    print("✅ [Pattern] Reloading saved pattern into form fields")
                    print("✅ [Pattern] Pattern has \(pattern.patterns.count) rules")

                    // Reload pattern data into form fields
                    patternRules = pattern.patterns.map { rule in
                        var params: [String: String] = [:]
                        for (key, param) in rule.parameters {
                            switch param {
                            case .int(let val):
                                params[key] = String(val)
                            case .string(let val):
                                params[key] = val
                            }
                        }
                        return EditablePatternRule(regex: rule.regex, parameters: params)
                    }

                    if let fallback = pattern.fallbackPattern {
                        fallbackType = fallback.type
                        fallbackDivider = fallback.divider ?? "|"
                    }
                } else {
                    print("⚠️ [Pattern] WARNING: Updated channel has no pattern!")
                }
            } else {
                print("⚠️ [Pattern] WARNING: Could not find channel \(currentChannelId) after reload")
            }

            // Keep editingPattern = true so user can see the saved pattern
            // editingPattern = false  // REMOVED - keep pattern visible after save

            // Show success message
            self.error = nil
            print("✅ [Pattern] Save complete, pattern still visible in editor")
        } catch {
            let errorMsg = "Failed to save pattern: \(error.localizedDescription)"
            print("❌ [Pattern] Save failed: \(errorMsg)")
            self.error = errorMsg
        }

        isSavingPattern = false
    }

    func testPattern() async {
        guard let channel = selectedChannel else { return }

        isTestingPattern = true
        testResults = nil

        do {
            let patterns = patternRules.map { rule in
                var params: [String: Any] = [:]
                for (key, value) in rule.parameters {
                    if let intVal = Int(value) {
                        params[key] = intVal
                    } else {
                        params[key] = value
                    }
                }
                return [
                    "regex": rule.regex,
                    "parameters": params
                ] as [String: Any]
            }

            let fallback: [String: String] = [
                "type": fallbackType,
                "divider": fallbackDivider
            ]

            let results = try await apiService.testChannelPattern(
                channelId: channel.id,
                patterns: patterns,
                fallbackPattern: fallback,
                sampleCount: 5
            )

            testResults = results
        } catch {
            self.error = "Failed to test pattern: \(error.localizedDescription)"
        }

        isTestingPattern = false
    }

    func deletePattern() async {
        guard let channel = selectedChannel else { return }

        do {
            try await apiService.deleteChannelPattern(channelId: channel.id)
            await loadChannels()
        } catch {
            self.error = "Failed to delete pattern: \(error.localizedDescription)"
        }
    }

    func deleteChannel() async {
        guard let channel = selectedChannel else { return }

        do {
            try await apiService.deleteChannel(channelId: channel.id)
            channels.removeAll { $0.id == channel.id }
            selectedChannel = nil
        } catch {
            self.error = "Failed to delete channel: \(error.localizedDescription)"
        }
    }
}

// MARK: - Channel Row

struct ChannelRow: View {
    let channel: ChannelWithPattern

    var body: some View {
        HStack {
            // Channel thumbnail
            if let thumbnailUrl = channel.thumbnailUrl, let url = URL(string: thumbnailUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else {
                Image(systemName: "tv.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(channel.title)
                    .font(.headline)

                HStack(spacing: 8) {
                    if channel.hasPattern == true {
                        Label("Pattern configured", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Label("No pattern", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    if let videoCount = channel.videoCount {
                        Text("\(videoCount) videos")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Channel Pattern View

struct ChannelPatternView: View {
    let channel: ChannelWithPattern
    @Binding var editingPattern: Bool
    @Binding var patternRules: [EditablePatternRule]
    @Binding var fallbackType: String
    @Binding var fallbackDivider: String
    @Binding var testResults: PatternTestData?

    let onSavePattern: () async -> Void
    let onTestPattern: () async -> Void
    let onDeletePattern: () async -> Void
    let onDeleteChannel: () async -> Void
    let isSavingPattern: Bool
    let isTestingPattern: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - Channel Info
                HStack(spacing: 16) {
                    if let thumbnailUrl = channel.thumbnailUrl, let url = URL(string: thumbnailUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.gray.opacity(0.2)
                        }
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(channel.title)
                            .font(.title)
                            .fontWeight(.bold)

                        if let description = channel.description {
                            Text(description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        HStack(spacing: 16) {
                            if let subs = channel.subscriberCount {
                                Label("\(formatNumber(subs)) subscribers", systemImage: "person.2")
                                    .font(.caption)
                            }
                            if let videos = channel.videoCount {
                                Label("\(videos) videos", systemImage: "play.rectangle")
                                    .font(.caption)
                            }
                        }
                        .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(role: .destructive, action: {
                        Task { await onDeleteChannel() }
                    }) {
                        Label("Delete Channel", systemImage: "trash")
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

                Divider()

                // MARK: - Pattern Configuration
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Title Extraction Pattern")
                            .font(.title2)
                            .fontWeight(.bold)

                        Spacer()

                        if channel.hasPattern == true {
                            if editingPattern {
                                Button("Reload Pattern") {
                                    loadExistingPattern()
                                }

                                Button("Save Pattern") {
                                    Task { await onSavePattern() }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isSavingPattern)

                                Button(role: .destructive, action: {
                                    Task { await onDeletePattern() }
                                }) {
                                    Label("Delete Pattern", systemImage: "trash")
                                }
                            } else {
                                // Auto-load pattern when channel has one
                                Button("Show Pattern") {
                                    editingPattern = true
                                    loadExistingPattern()
                                }
                                .buttonStyle(.borderedProminent)
                                .onAppear {
                                    // Auto-show pattern when channel has one
                                    editingPattern = true
                                    loadExistingPattern()
                                }

                                Button(role: .destructive, action: {
                                    Task { await onDeletePattern() }
                                }) {
                                    Label("Delete Pattern", systemImage: "trash")
                                }
                            }
                        } else {
                            Button("Create Pattern") {
                                editingPattern = true
                                patternRules = [EditablePatternRule()]
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    if channel.hasPattern != true && !editingPattern {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary)
                            Text("No pattern configured")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Create a pattern to extract movie information from video titles")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    }

                    if editingPattern {
                        PatternEditorView(
                            patternRules: $patternRules,
                            fallbackType: $fallbackType,
                            fallbackDivider: $fallbackDivider
                        )

                        // Action Buttons
                        VStack(spacing: 12) {
                            // Test Pattern Button
                            HStack {
                                Spacer()
                                Button(action: {
                                    Task { await onTestPattern() }
                                }) {
                                    Label("Test Pattern on Sample Videos", systemImage: "play.circle")
                                }
                                .buttonStyle(.bordered)
                                .disabled(isTestingPattern || patternRules.isEmpty)
                                Spacer()
                            }

                            // Save Pattern Button
                            HStack {
                                Spacer()
                                Button(action: {
                                    Task { await onSavePattern() }
                                }) {
                                    if isSavingPattern {
                                        HStack {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                            Text("Saving...")
                                        }
                                    } else {
                                        Label("Save Pattern", systemImage: "checkmark.circle.fill")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(isSavingPattern || patternRules.isEmpty)
                                Spacer()
                            }
                        }
                        .padding(.top)
                    }

                    // Test Results
                    if let results = testResults {
                        PatternTestResultsView(results: results)
                    }
                }
                .padding()
            }
            .padding()
        }
    }

    func loadExistingPattern() {
        guard let pattern = channel.pattern else { return }

        patternRules = pattern.patterns.map { rule in
            var params: [String: String] = [:]
            for (key, param) in rule.parameters {
                switch param {
                case .int(let val):
                    params[key] = String(val)
                case .string(let val):
                    params[key] = val
                }
            }
            return EditablePatternRule(regex: rule.regex, parameters: params)
        }

        if let fallback = pattern.fallbackPattern {
            fallbackType = fallback.type
            fallbackDivider = fallback.divider ?? "|"
        }
    }

    func formatNumber(_ num: Int) -> String {
        if num >= 1_000_000 {
            return String(format: "%.1fM", Double(num) / 1_000_000)
        } else if num >= 1_000 {
            return String(format: "%.1fK", Double(num) / 1_000)
        }
        return String(num)
    }
}

// MARK: - Pattern Editor

struct EditablePatternRule: Identifiable {
    let id = UUID()
    var regex: String = ""
    var parameters: [String: String] = [
        "title": "1",
        "actors": "",
        "genre": "",
        "year": ""
    ]
}

struct PatternEditorView: View {
    @Binding var patternRules: [EditablePatternRule]
    @Binding var fallbackType: String
    @Binding var fallbackDivider: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Pattern Rules
            ForEach($patternRules) { $rule in
                PatternRuleEditor(rule: $rule, onDelete: {
                    patternRules.removeAll { $0.id == rule.id }
                })
            }

            // Add Pattern Rule Button
            Button(action: {
                patternRules.append(EditablePatternRule())
            }) {
                Label("Add Pattern Rule", systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)

            Divider()
                .padding(.vertical, 8)

            // Fallback Pattern
            VStack(alignment: .leading, spacing: 8) {
                Text("Fallback Pattern")
                    .font(.headline)
                Text("Used when no regex pattern matches")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Picker("Type", selection: $fallbackType) {
                        Text("First Segment").tag("first_segment")
                    }
                    .frame(width: 200)

                    Text("Divider:")
                    TextField("Divider", text: $fallbackDivider)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)

            // Help Text
            VStack(alignment: .leading, spacing: 8) {
                Text("Pattern Help")
                    .font(.headline)
                Text("Use regex capture groups (parentheses) to extract parts of the title. Reference groups by number in parameters.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Example: `^(.+?)\\s*\\|\\s*(.+?)$` with title=1, actors=2")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontDesign(.monospaced)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

struct PatternRuleEditor: View {
    @Binding var rule: EditablePatternRule
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Regex Pattern")
                    .font(.headline)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
            }

            TextField("Regular expression (required)", text: $rule.regex)
                .textFieldStyle(.roundedBorder)
                .fontDesign(.monospaced)

            if rule.regex.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("⚠️ Regular expression is required")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Text("Parameters (capture group numbers or static values)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(rule.parameters.keys.sorted()), id: \.self) { key in
                    HStack {
                        Text(key.capitalized + ":")
                            .frame(width: 60, alignment: .trailing)
                        TextField("Group # or value", text: Binding(
                            get: { rule.parameters[key] ?? "" },
                            set: { rule.parameters[key] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Pattern Test Results

struct PatternTestResultsView: View {
    let results: PatternTestData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Test Results")
                    .font(.title3)
                    .fontWeight(.bold)

                Spacer()

                Text("Match Rate: \(results.matchRate)")
                    .font(.headline)
                    .foregroundColor(matchRateColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(matchRateColor.opacity(0.1))
                    .cornerRadius(8)
            }

            ForEach(Array(results.results.enumerated()), id: \.offset) { index, result in
                TestResultRow(result: result, index: index + 1)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }

    var matchRateColor: Color {
        let rate = Double(results.matchRate.replacingOccurrences(of: "%", with: "")) ?? 0
        if rate >= 80 {
            return .green
        } else if rate >= 50 {
            return .orange
        } else {
            return .red
        }
    }
}

struct TestResultRow: View {
    let result: PatternTestResult
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Video \(index)")
                    .font(.headline)
                Spacer()
                Image(systemName: result.matched ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result.matched ? .green : .red)
            }

            Text("YouTube Title:")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(result.youtubeTitle)
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)

            if let title = result.extracted.title {
                HStack {
                    Text("Extracted Title:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(title)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }

            if let actors = result.extracted.actorsArray, !actors.isEmpty {
                HStack {
                    Text("Actors:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(actors.joined(separator: ", "))
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }

            if let genre = result.extracted.genre {
                HStack {
                    Text("Genre:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(genre)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }

            if let year = result.extracted.year {
                HStack {
                    Text("Year:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(year))
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }

            if let error = result.extracted.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.5))
        .cornerRadius(8)
    }
}

// MARK: - Add Channel Sheet

struct AddChannelSheet: View {
    @Binding var channelId: String
    @Binding var isAdding: Bool
    let onAdd: () async -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Add YouTube Channel")
                .font(.title)
                .fontWeight(.bold)

            Text("Enter the YouTube channel ID to add")
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextField("Channel ID (e.g., UC6A_LC-A5NVJ2vw9A0OjCug)", text: $channelId)
                .textFieldStyle(.roundedBorder)
                .frame(width: 400)

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)

                Button("Add Channel") {
                    Task {
                        await onAdd()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(channelId.isEmpty || isAdding)
            }

            if isAdding {
                ProgressView("Adding channel...")
                    .padding()
            }
        }
        .padding(30)
        .frame(width: 500)
    }
}

#Preview {
    ChannelManagementView()
}
