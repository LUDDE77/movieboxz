import SwiftUI

struct ChannelManagementView: View {
    @StateObject private var apiService = AdminAPIService()

    // State
    @State private var channels: [ChannelWithPattern] = []
    @State private var selectedChannel: ChannelWithPattern?
    @State private var isLoading = false
    @State private var error: String?

    // Filter state
    @State private var channelFilter: ChannelFilter = .all

    // Add channel form
    @State private var showAddChannel = false
    @State private var newChannelId = ""
    @State private var isAddingChannel = false
    @State private var addedChannel: ChannelWithPattern?
    @State private var addChannelError: String?

    // Pattern editor
    @State private var editingPattern = false
    @State private var patternRules: [EditablePatternRule] = []
    @State private var fallbackType = "first_segment"
    @State private var fallbackDivider = "|"
    @State private var isSavingPattern = false

    // Pattern testing
    @State private var testResults: PatternTestData?
    @State private var isTestingPattern = false
    @State private var testSampleCount = 5
    @State private var testSampleMode = "newest"
    @State private var testTitleSource = "channel" // "channel" | "pasted"
    @State private var testPastedTitles = ""

    // Tab selection
    @State private var selectedTab = 0

    // Filtered channels based on selected filter
    var filteredChannels: [ChannelWithPattern] {
        switch channelFilter {
        case .all:
            return channels
        case .movies:
            return channels.filter { $0.hasMovies }
        case .series:
            return channels.filter { $0.hasSeries }
        case .kids:
            return channels.filter { $0.hasKidsContent }
        }
    }

    var body: some View {
        NavigationSplitView {
            // MARK: - Sidebar (Channel List)
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    HStack {
                        Text("Channels")
                            .font(.title2)
                            .fontWeight(.bold)
                        Spacer()
                        Button(action: { showAddChannel = true }) {
                            Label("Add Channel", systemImage: "plus")
                        }
                    }

                    // Filter buttons
                    HStack(spacing: 8) {
                        FilterButton(
                            title: "All",
                            count: channels.count,
                            isSelected: channelFilter == .all,
                            action: { channelFilter = .all }
                        )

                        FilterButton(
                            title: "Movies",
                            count: channels.filter { $0.hasMovies }.count,
                            isSelected: channelFilter == .movies,
                            action: { channelFilter = .movies }
                        )

                        FilterButton(
                            title: "Series",
                            count: channels.filter { $0.hasSeries }.count,
                            isSelected: channelFilter == .series,
                            action: { channelFilter = .series }
                        )

                        FilterButton(
                            title: "Kids",
                            count: channels.filter { $0.hasKidsContent }.count,
                            isSelected: channelFilter == .kids,
                            action: { channelFilter = .kids }
                        )
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
                    List(filteredChannels, selection: $selectedChannel) { channel in
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

                        // Reset to Pattern tab when switching channels
                        selectedTab = 0
                        print("🔄 [Channel] Reset to Pattern tab (tab 0)")

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
                TabView(selection: $selectedTab) {
                    // Pattern Tab
                    ChannelPatternView(
                        channel: channel,
                        editingPattern: $editingPattern,
                        patternRules: $patternRules,
                        fallbackType: $fallbackType,
                        fallbackDivider: $fallbackDivider,
                        testResults: $testResults,
                        testSampleCount: $testSampleCount,
                        testSampleMode: $testSampleMode,
                        testTitleSource: $testTitleSource,
                        testPastedTitles: $testPastedTitles,
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
                    .tag(0)

                    // Settings Tab
                    ChannelSettingsView(channel: channel)
                        .tabItem {
                            Label("Settings", systemImage: "gear")
                        }
                        .tag(1)

                    // Import Tab
                    BulkImportView(channel: channel, onReviewMovies: { selectedTab = 3 })
                        .tabItem {
                            Label("Import", systemImage: "arrow.down.circle")
                        }
                        .tag(2)

                    // Movies Tab
                    ChannelMoviesView(channel: channel)
                        .tabItem {
                            Label("Movies", systemImage: "film")
                        }
                        .tag(3)

                    // History Tab
                    ImportHistoryView(channel: channel)
                        .tabItem {
                            Label("History", systemImage: "clock.arrow.circlepath")
                        }
                        .tag(4)
                }
                .id(channel.id) // Force full view recreation when channel changes
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
                addedChannel: $addedChannel,
                errorMessage: $addChannelError,
                onAdd: addChannel,
                onClose: {
                    showAddChannel = false
                    addedChannel = nil
                    addChannelError = nil
                    newChannelId = ""
                }
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
        addChannelError = nil

        do {
            // The backend resolves channel URLs, @handles, and raw channel IDs.
            let newChannel = try await apiService.addChannel(channelId: newChannelId.trimmingCharacters(in: .whitespacesAndNewlines))
            channels.append(newChannel)
            // Keep the sheet open and show the resolved channel as confirmation.
            addedChannel = newChannel
            newChannelId = ""
        } catch {
            addChannelError = error.localizedDescription
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

        // Validate that all patterns have a regex that compiles
        for (index, rule) in patternRules.enumerated() {
            print("💾 [Pattern] Rule #\(index + 1) regex: '\(rule.regex)'")
            if let compileError = regexCompileError(rule.regex) {
                let errorMsg = "Pattern #\(index + 1): \(compileError)"
                print("❌ [Pattern] Validation failed: \(errorMsg)")
                self.error = errorMsg
                return
            }
        }

        isSavingPattern = true
        error = nil

        do {
            let patterns = patternRulesAsPayload(patternRules)

            let fallback: [String: String] = [
                "type": fallbackType,
                "divider": fallbackDivider
            ]

            print("💾 [Pattern] Sending patterns to API:")
            print("💾 [Pattern] Patterns: \(patterns)")
            print("💾 [Pattern] Fallback: \(fallback)")

            // Sent via the direct helper (not AdminAPIService.updateChannelPattern)
            // so a backend 400 regex-compile error surfaces its message instead of
            // a bare "HTTP error: 400".
            let data = try await ChannelAdminDirectAPI.send(
                path: "/channels/\(channel.id)/pattern",
                method: "PUT",
                body: [
                    "channelName": channel.title,
                    "patterns": patterns,
                    "fallbackPattern": fallback
                ]
            )
            let savedPattern = try ChannelAdminDirectAPI.decode(ChannelPattern.self, from: data)

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
        error = nil

        do {
            let patterns = patternRulesAsPayload(patternRules)

            let fallback: [String: String] = [
                "type": fallbackType,
                "divider": fallbackDivider
            ]

            // Built via the direct helper because AdminAPIService.testChannelPattern
            // does not yet expose sampleMode/sampleTitles (backend supports both),
            // and it also surfaces backend 400 regex errors properly.
            var body: [String: Any] = [
                "patterns": patterns,
                "fallbackPattern": fallback
            ]

            if testTitleSource == "pasted" {
                let titles = testPastedTitles
                    .split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                guard !titles.isEmpty else {
                    self.error = "Paste at least one video title to test against."
                    isTestingPattern = false
                    return
                }
                body["sampleTitles"] = Array(titles.prefix(50))
                body["sampleCount"] = min(max(titles.count, 1), 50)
            } else {
                body["sampleCount"] = testSampleCount
                body["sampleMode"] = testSampleMode
            }

            let data = try await ChannelAdminDirectAPI.send(
                path: "/channels/\(channel.id)/test-pattern",
                method: "POST",
                body: body
            )
            testResults = try ChannelAdminDirectAPI.decode(PatternTestData.self, from: data)
        } catch {
            self.error = "Failed to test pattern: \(error.localizedDescription)"
        }

        isTestingPattern = false
    }

    /// Convert editable rules to the API payload shape, converting capture-group
    /// numbers to Ints and dropping parameters left empty.
    private func patternRulesAsPayload(_ rules: [EditablePatternRule]) -> [[String: Any]] {
        rules.map { rule in
            var params: [String: Any] = [:]
            for (key, value) in rule.parameters {
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                if let intVal = Int(trimmed) {
                    params[key] = intVal
                } else {
                    params[key] = trimmed
                }
            }
            return [
                "regex": rule.regex,
                "parameters": params
            ] as [String: Any]
        }
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

                // Content type badges
                HStack(spacing: 4) {
                    if channel.hasMovies {
                        Text("Movies")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                    if channel.hasSeries {
                        Text("Series")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2))
                            .foregroundColor(.purple)
                            .cornerRadius(4)
                    }
                    if channel.hasKidsContent {
                        Text("Kids")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                    if channel.patternSource == "description" {
                        Text("⚙️ Desc")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
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
    @Binding var testSampleCount: Int
    @Binding var testSampleMode: String
    @Binding var testTitleSource: String
    @Binding var testPastedTitles: String

    let onSavePattern: () async -> Void
    let onTestPattern: () async -> Void
    let onDeletePattern: () async -> Void
    let onDeleteChannel: () async -> Void
    let isSavingPattern: Bool
    let isTestingPattern: Bool

    /// All rules present and every regex compiles client-side.
    var allPatternsValid: Bool {
        !patternRules.isEmpty && patternRules.allSatisfy { regexCompileError($0.regex) == nil }
    }

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

                // MARK: - Channel Classification
                ChannelClassificationView(channel: channel)

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
                                .disabled(isSavingPattern || !allPatternsValid)

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

                        // Pattern Testing Controls
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Test Pattern")
                                .font(.headline)

                            Picker("Test against", selection: $testTitleSource) {
                                Text("Channel videos").tag("channel")
                                Text("Pasted titles").tag("pasted")
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 300)

                            if testTitleSource == "channel" {
                                HStack(spacing: 20) {
                                    Stepper(value: $testSampleCount, in: 5...50, step: 5) {
                                        Text("Sample size: \(testSampleCount)")
                                    }
                                    .frame(width: 200, alignment: .leading)

                                    Picker("Sample", selection: $testSampleMode) {
                                        Text("Newest").tag("newest")
                                        Text("Oldest").tag("oldest")
                                        Text("Random").tag("random")
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 250)
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Paste sample video titles (one per line, max 50):")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextEditor(text: $testPastedTitles)
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(height: 120)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                }
                            }

                            HStack {
                                Spacer()
                                Button(action: {
                                    Task { await onTestPattern() }
                                }) {
                                    if isTestingPattern {
                                        HStack {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                            Text("Testing...")
                                        }
                                    } else {
                                        Label(testTitleSource == "pasted"
                                              ? "Test Pattern on Pasted Titles"
                                              : "Test Pattern on Sample Videos",
                                              systemImage: "play.circle")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isTestingPattern || !allPatternsValid)
                                Spacer()
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(8)

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
                            .disabled(isSavingPattern || !allPatternsValid)
                            Spacer()
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

/// Client-side regex validation. Returns nil when the pattern compiles,
/// otherwise a human-readable error. The backend (JS RegExp) remains the
/// authority — its 400 compile errors are surfaced on save/test too.
func regexCompileError(_ pattern: String) -> String? {
    let trimmed = pattern.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty {
        return "Regular expression is required"
    }
    do {
        _ = try NSRegularExpression(pattern: pattern)
        return nil
    } catch {
        let nsError = error as NSError
        if let reason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
            return "Invalid regex: \(reason)"
        }
        return "Invalid regular expression"
    }
}

struct EditablePatternRule: Identifiable {
    /// Parameter keys the extractor understands (channelPatternManager.extractMetadata).
    static let knownParameterKeys = ["title", "actors", "genre", "year", "episode_name", "season", "episode"]

    let id = UUID()
    var regex: String = ""
    var parameters: [String: String] = [
        "title": "1"
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

    @State private var customKeyName = ""

    /// Keys ordered: known keys first (in canonical order), then custom keys alphabetically.
    private var orderedParameterKeys: [String] {
        let known = EditablePatternRule.knownParameterKeys.filter { rule.parameters.keys.contains($0) }
        let custom = rule.parameters.keys
            .filter { !EditablePatternRule.knownParameterKeys.contains($0) }
            .sorted()
        return known + custom
    }

    private var availableKnownKeys: [String] {
        EditablePatternRule.knownParameterKeys.filter { !rule.parameters.keys.contains($0) }
    }

    private var regexError: String? {
        regexCompileError(rule.regex)
    }

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

            if let regexError = regexError {
                Label(regexError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            } else {
                Label("Regex compiles", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            Text("Parameters (capture group numbers or static values)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(orderedParameterKeys, id: \.self) { key in
                    HStack {
                        Text(parameterLabel(key) + ":")
                            .frame(width: 90, alignment: .trailing)
                        TextField("Group # or value", text: Binding(
                            get: { rule.parameters[key] ?? "" },
                            set: { rule.parameters[key] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Button(action: { rule.parameters.removeValue(forKey: key) }) {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove this parameter")
                    }
                }
            }

            // Add parameter controls
            HStack(spacing: 12) {
                Menu {
                    ForEach(availableKnownKeys, id: \.self) { key in
                        Button(parameterLabel(key)) {
                            rule.parameters[key] = ""
                        }
                    }
                } label: {
                    Label("Add Parameter", systemImage: "plus.circle")
                }
                .frame(width: 160)
                .disabled(availableKnownKeys.isEmpty)

                TextField("Custom key", text: $customKeyName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)

                Button("Add Custom") {
                    let key = customKeyName
                        .trimmingCharacters(in: .whitespaces)
                        .lowercased()
                        .replacingOccurrences(of: " ", with: "_")
                    guard !key.isEmpty, rule.parameters[key] == nil else { return }
                    rule.parameters[key] = ""
                    customKeyName = ""
                }
                .disabled(customKeyName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(regexError == nil ? Color.gray.opacity(0.3) : Color.red.opacity(0.5), lineWidth: 1)
        )
    }

    private func parameterLabel(_ key: String) -> String {
        switch key {
        case "episode_name": return "Episode Name"
        case "season": return "Season #"
        case "episode": return "Episode #"
        default: return key.capitalized
        }
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
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Add Channel Sheet

struct AddChannelSheet: View {
    @Binding var channelId: String
    @Binding var isAdding: Bool
    @Binding var addedChannel: ChannelWithPattern?
    @Binding var errorMessage: String?
    let onAdd: () async -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Add YouTube Channel")
                .font(.title)
                .fontWeight(.bold)

            if let added = addedChannel {
                // Success confirmation with the resolved channel
                VStack(spacing: 12) {
                    if let thumbnailUrl = added.thumbnailUrl, let url = URL(string: thumbnailUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.gray.opacity(0.2)
                        }
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "tv.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(.blue)
                    }

                    Label("Channel added", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundColor(.green)

                    Text(added.title)
                        .font(.title3)
                        .fontWeight(.semibold)

                    if let videos = added.videoCount {
                        Text("\(videos) videos")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.green.opacity(0.08))
                .cornerRadius(12)

                HStack(spacing: 12) {
                    Button("Add Another") {
                        addedChannel = nil
                        errorMessage = nil
                    }
                    .buttonStyle(.bordered)

                    Button("Done", action: onClose)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Text("Enter a channel URL, @handle, or channel ID")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("Channel URL, @handle, or ID", text: $channelId)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 400)

                Text("Accepts youtube.com/channel/UC…, youtube.com/@handle, a bare @handle, or a raw channel ID — the server resolves them all.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 400)

                if let errorMessage = errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(width: 400)
                }

                HStack(spacing: 12) {
                    Button("Cancel", action: onClose)
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
                    ProgressView("Resolving channel...")
                        .padding()
                }
            }
        }
        .padding(30)
        .frame(width: 500)
    }
}

// MARK: - Channel Classification View

struct ChannelClassificationView: View {
    let channel: ChannelWithPattern
    @StateObject private var apiService = AdminAPIService()
    @State private var hasMovies: Bool
    @State private var hasSeries: Bool
    @State private var hasKidsContent: Bool
    @State private var patternSource: String
    @State private var isSaving = false
    @State private var saveMessage: String?

    init(channel: ChannelWithPattern) {
        self.channel = channel
        _hasMovies = State(initialValue: channel.hasMovies)
        _hasSeries = State(initialValue: channel.hasSeries)
        _hasKidsContent = State(initialValue: channel.hasKidsContent)
        _patternSource = State(initialValue: channel.patternSource)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Channel Classification")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if let message = saveMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Content Type")
                    .font(.headline)

                Toggle("Contains Movies", isOn: $hasMovies)
                Toggle("Contains TV Series", isOn: $hasSeries)
                Toggle("Contains Kids Content", isOn: $hasKidsContent)

                Divider()
                    .padding(.vertical, 4)

                Text("Pattern Source")
                    .font(.headline)

                Picker("Extract metadata from", selection: $patternSource) {
                    Text("Title").tag("title")
                    Text("Description").tag("description")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                Text(patternSource == "title"
                    ? "Patterns will extract metadata from video titles (recommended)"
                    : "Patterns will extract metadata from video descriptions (use when titles lack structure)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button(action: { Task { await saveChanges() } }) {
                    if isSaving {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Saving...")
                        }
                    } else {
                        Label("Save Changes", systemImage: "checkmark.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || !hasChanges)
                Spacer()
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }

    var hasChanges: Bool {
        hasMovies != channel.hasMovies ||
        hasSeries != channel.hasSeries ||
        hasKidsContent != channel.hasKidsContent ||
        patternSource != channel.patternSource
    }

    func saveChanges() async {
        isSaving = true
        saveMessage = nil

        do {
            _ = try await apiService.updateChannelClassification(
                channelId: channel.id,
                hasMovies: hasMovies,
                hasSeries: hasSeries,
                hasKidsContent: hasKidsContent,
                patternSource: patternSource
            )
            saveMessage = "✓ Saved"

            // Clear message after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                saveMessage = nil
            }
        } catch {
            saveMessage = "Failed to save: \(error.localizedDescription)"
        }

        isSaving = false
    }
}

// MARK: - Channel Filter Enum

enum ChannelFilter {
    case all
    case movies
    case series
    case kids
}

// MARK: - Filter Button Component

struct FilterButton: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Text("(\(count))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.gray.opacity(0.1))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Direct Admin API Helper

/// Thin request helper for admin endpoints/parameters that `AdminAPIService`
/// does not expose yet (pattern testing with sampleMode/sampleTitles, pattern
/// save with backend-error surfacing, reimport with force, import-history
/// extras). Reads the same UserDefaults configuration as `AdminAPIService`
/// and parses backend `{ error / message }` bodies into
/// `APIError.server(status:message:)` so `localizedDescription` carries the
/// backend message (e.g. regex compile errors, reimport 409 refusals).
enum ChannelAdminDirectAPI {
    static func send(path: String, method: String = "POST", body: [String: Any]? = nil) async throws -> Data {
        let baseURL = UserDefaults.standard.string(forKey: "apiBaseURL") ?? ""
        let apiKey = UserDefaults.standard.string(forKey: "adminAPIKey") ?? ""

        guard let url = URL(string: "\(baseURL)/api/admin\(path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "x-admin-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw APIError.unauthorized
            }
            var message = "Request failed (HTTP \(httpResponse.statusCode))"
            if let decoded = try? JSONDecoder().decode(BasicResponse.self, from: data),
               let backendMessage = decoded.error ?? decoded.message,
               !backendMessage.isEmpty {
                message = backendMessage
            } else if let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !raw.isEmpty, raw.count < 300 {
                message = raw
            }
            throw APIError.server(status: httpResponse.statusCode, message: message)
        }

        return data
    }

    /// Decode the `data` payload of a standard `{ success, data }` envelope.
    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(APIResponse<T>.self, from: data).data
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }
}

#Preview {
    ChannelManagementView()
}
