import Foundation

extension AppContainer {
    // MARK: - Settings Persistence (Debounced)

    func persistSettingsIfNeeded(previous: AppSettings) {
        guard previous != settings else { return }
        isDirty = true
        scheduleDebouncedSave()
    }

    private func scheduleDebouncedSave() {
        debounceTask?.cancel()
        debounceTask = Task {
            do {
                try await Task.sleep(for: RuntimeConstants.settingsDebounceInterval)
                self.performSave()
            } catch {
                // Cancelled — a newer debounce or flush superseded this one
            }
        }
    }

    private func performSave() {
        guard isDirty else { return }
        do {
            try preferencesRepository?.save(settings)
            isDirty = false
        } catch {
            // Keep dirty for retry on next debounce cycle or flush
            statusMessage = "Failed to save settings: \(error.localizedDescription)"
        }
    }

    /// Force-save pending settings immediately. Call at lifecycle boundaries
    /// (app background/inactive scene phase transitions).
    func flushSettings() {
        debounceTask?.cancel()
        debounceTask = nil
        performSave()
    }
}
