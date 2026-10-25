import Darwin
import Foundation

/// All mutations are synchronous, under a process lock, and retain unknown Apple fields.
struct WallpaperCatalog {
    static let categoryID = "6C7B4376-9206-467F-9185-18BDB9D8EB53"
    let paths: WallpaperPaths

    func checkAvailable() throws {
        _ = try readCatalog()
        _ = try readIndex()
    }

    func withLock<T>(_ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: paths.state, withIntermediateDirectories: true)
        let descriptor = open(paths.state.appendingPathComponent("wallpaper.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw WallpaperError.unavailable("Another Walldance wallpaper operation is running. Try again shortly.")
        }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }

    func register(_ video: LibraryVideo, commit: () throws -> Void = {}) throws {
        let wallpaper = video.wallpaper
        let before = try Data(contentsOf: paths.manifest)
        var catalog = try decodeCatalog(before)
        let original = catalog
        var assets = catalog["assets"] as! [[String: Any]]
        var categories = catalog["categories"] as! [[String: Any]]
        let id = wallpaper.assetID.uuidString
        let subID = wallpaper.subcategoryID.uuidString
        let thumbnail = paths.thumbnail(wallpaper.assetID).absoluteString
        let media = paths.video(wallpaper.assetID).absoluteString
        if let existing = assets.first(where: { $0["id"] as? String == id }) {
            guard existing["subcategories"] as? [String] == [subID],
                  existing["url-4K-SDR-240FPS"] as? String == media else {
                throw WallpaperError.invalidCatalog
            }
        }
        var asset = assets.first(where: { $0["id"] as? String == id }) ?? [:]
        asset.merge([
            "id": id, "shotID": "WALLDANCE_" + id.replacingOccurrences(of: "-", with: ""),
            "localizedNameKey": video.name, "accessibilityLabel": video.name,
            "preferredOrder": 0, "includeInShuffle": false, "showInTopLevel": true,
            "categories": [Self.categoryID], "subcategories": [subID],
            "previewImage": thumbnail, "url-4K-SDR-240FPS": media, "pointsOfInterest": [String: String]()
        ]) { _, new in new }
        if let index = assets.firstIndex(where: { $0["id"] as? String == id }) { assets[index] = asset }
        else { assets.append(asset) }
        var category = categories.first(where: { $0["id"] as? String == Self.categoryID }) ?? [
            "id": Self.categoryID, "localizedNameKey": "Walldance",
            "localizedDescriptionKey": "Your Walldance videos", "preferredOrder": -1
        ]
        var subs = category["subcategories"] as? [[String: Any]] ?? []
        var sub = subs.first(where: { $0["id"] as? String == subID }) ?? [:]
        sub.merge(["id": subID, "localizedNameKey": video.name,
            "localizedDescriptionKey": video.name, "previewImage": thumbnail,
            "representativeAssetID": id, "preferredOrder": sub["preferredOrder"] ?? subs.count]) { _, new in new }
        if let index = subs.firstIndex(where: { $0["id"] as? String == subID }) { subs[index] = sub }
        else { subs.append(sub) }
        category["subcategories"] = subs
        if !assets.contains(where: { $0["id"] as? String == category["representativeAssetID"] as? String }) {
            category["representativeAssetID"] = id
            category["previewImage"] = thumbnail
        }
        if let index = categories.firstIndex(where: { $0["id"] as? String == Self.categoryID }) { categories[index] = category }
        else { categories.append(category) }
        catalog["assets"] = assets
        catalog["categories"] = categories
        // Avoid rewriting an already registered catalogue on every launch or selection.
        if NSDictionary(dictionary: original).isEqual(to: catalog) { try commit(); return }
        try writeCatalog(catalog, replacing: before, commit: commit)
    }

    func unregister(_ video: LibraryVideo, commit: () throws -> Void = {}) throws {
        let wallpaper = video.wallpaper
        let before = try Data(contentsOf: paths.manifest)
        var catalog = try decodeCatalog(before)
        var assets = catalog["assets"] as! [[String: Any]]
        if let asset = assets.first(where: { $0["id"] as? String == wallpaper.assetID.uuidString }) {
            guard asset["subcategories"] as? [String] == [wallpaper.subcategoryID.uuidString],
                  asset["url-4K-SDR-240FPS"] as? String == paths.video(wallpaper.assetID).absoluteString else {
                throw WallpaperError.invalidCatalog
            }
        }
        assets.removeAll { $0["id"] as? String == wallpaper.assetID.uuidString }
        var categories = catalog["categories"] as! [[String: Any]]
        if let index = categories.firstIndex(where: { $0["id"] as? String == Self.categoryID }) {
            var category = categories[index]
            let subs = (category["subcategories"] as? [[String: Any]] ?? [])
                .filter { $0["id"] as? String != wallpaper.subcategoryID.uuidString }
            category["subcategories"] = subs
            let remaining = assets.filter { ($0["categories"] as? [String])?.contains(Self.categoryID) == true }
            if subs.isEmpty && remaining.isEmpty {
                categories.remove(at: index)
            } else {
                if category["representativeAssetID"] as? String == wallpaper.assetID.uuidString {
                    category["representativeAssetID"] = remaining.first?["id"]
                    category["previewImage"] = remaining.first?["previewImage"]
                }
                categories[index] = category
            }
        }
        catalog["assets"] = assets
        catalog["categories"] = categories
        try writeCatalog(catalog, replacing: before, commit: commit)
    }

    func selectedIDs() throws -> Set<UUID> {
        Self.selectedIDs(in: try readIndex())
    }

    static func selectedIDs(in value: Any) -> Set<UUID> {
        if let dictionary = value as? [String: Any] {
            var ids = Set<UUID>()
            if dictionary["Provider"] as? String == "com.apple.wallpaper.choice.aerials",
               let data = dictionary["Configuration"] as? Data,
               let configuration = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let id = configuration["assetID"] as? String, let uuid = UUID(uuidString: id) { ids.insert(uuid) }
            for child in dictionary.values { ids.formUnion(selectedIDs(in: child)) }
            return ids
        }
        if let array = value as? [Any] { return array.reduce(into: Set<UUID>()) { $0.formUnion(selectedIDs(in: $1)) } }
        return []
    }

    func apply(_ wallpaper: PreparedWallpaper, managedIDs: Set<UUID>) throws {
        try editSelection { index in
            if Self.selectedIDs(in: index).isDisjoint(with: managedIDs) {
                try self.plistData(index).write(to: self.fallback, options: .atomic)
            }
            let configuration = try self.plistData(["assetID": wallpaper.assetID.uuidString])
            let choice: [String: Any] = ["Provider": "com.apple.wallpaper.choice.aerials",
                "Configuration": configuration, "Files": [String]()]
            return try self.mapContainers(index) { container, _ in
                var result = container
                var linked = container["Linked"] as? [String: Any] ?? [:]
                var content = linked["Content"] as? [String: Any]
                    ?? (container["Desktop"] as? [String: Any])?["Content"] as? [String: Any] ?? [:]
                if content["EncodedOptionValues"] == nil {
                    content["EncodedOptionValues"] = try self.plistData([
                        "values": ["placement": ["picker": ["_0": ["id": "FillScreen"]]]]
                    ])
                }
                content["Choices"] = [choice]
                content["Shuffle"] = "$null"
                linked["Content"] = content
                linked["LastSet"] = Date()
                linked["LastUse"] = Date()
                result["Type"] = "linked"
                result["Linked"] = linked
                result.removeValue(forKey: "Desktop")
                result.removeValue(forKey: "Idle")
                return result
            }
        }
    }

    func restoreSelection(removing id: UUID) throws {
        guard try selectedIDs().contains(id) else { return }
        guard let saved = try? Data(contentsOf: fallback),
              let previous = try? decodeIndex(saved), Self.selectedIDs(in: previous).contains(id) == false,
              let replacement = previous["AllSpacesAndDisplays"] as? [String: Any] else {
            throw WallpaperError.unavailable("Choose another wallpaper before removing this video; the previous wallpaper settings are unavailable.")
        }
        try editSelection { index in
            try self.mapContainers(index) { container, path in
                guard Self.selectedIDs(in: container).contains(id) else { return container }
                var saved: Any? = previous
                for component in path {
                    if let dictionary = saved as? [String: Any] { saved = dictionary[component] }
                    else if let array = saved as? [Any], let offset = Int(component), array.indices.contains(offset) { saved = array[offset] }
                    else { saved = nil; break }
                }
                let original = saved as? [String: Any] ?? replacement
                var restored = container
                for key in ["Type", "Linked", "Desktop", "Idle"] { restored[key] = original[key] }
                return restored
            }
        }
    }

    private var fallback: URL { paths.state.appendingPathComponent("previous-wallpaper.plist") }

    /// Keep display/Space mappings and unrelated keys rather than clearing overrides.
    private func mapContainers(_ index: [String: Any], transform: ([String: Any], [String]) throws -> [String: Any]) throws -> [String: Any] {
        func visit(_ value: Any, path: [String]) throws -> Any {
            if let dictionary = value as? [String: Any] {
                if let type = dictionary["Type"] as? String {
                    guard ["linked", "individual"].contains(type) else { throw WallpaperError.invalidSelection }
                    guard let selection = dictionary[type == "linked" ? "Linked" : "Desktop"] as? [String: Any],
                          let content = selection["Content"] as? [String: Any], content["Choices"] is [[String: Any]] else {
                        throw WallpaperError.invalidSelection
                    }
                    return try transform(dictionary, path)
                }
                var result = dictionary
                for (key, child) in dictionary { result[key] = try visit(child, path: path + [key]) }
                return result
            }
            if let array = value as? [Any] { return try array.enumerated().map { try visit($0.element, path: path + [String($0.offset)]) } }
            return value
        }
        var result = index
        for key in ["AllSpacesAndDisplays", "SystemDefault", "Displays", "Spaces"] {
            if let value = result[key] { result[key] = try visit(value, path: [key]) }
        }
        return result
    }

    private func editSelection(_ transform: ([String: Any]) throws -> [String: Any]) throws {
        // Pause the agent so it cannot flush stale in-memory settings over our edit.
        // SIGCONT is guaranteed on every path; a successful write then reloads the agents.
        let pids = try agentPIDs()
        for pid in pids { kill(pid, SIGSTOP) }
        defer { for pid in pids { kill(pid, SIGCONT) } }
        let before = try Data(contentsOf: paths.index)
        let index = try decodeIndex(before)
        let changed = try transform(index)
        let output = try plistData(changed)
        try backup(before, name: "Index.plist")
        guard try Data(contentsOf: paths.index) == before else { throw WallpaperError.changedDuringWrite }
        try output.write(to: paths.index, options: .atomic)
        for pid in pids { kill(pid, SIGTERM) }
        restartAerials()
    }

    func reload() {
        guard let pids = try? agentPIDs() else { return }
        for pid in pids { kill(pid, SIGTERM) }
        restartAerials()
    }

    private func agentPIDs(named name: String = "WallpaperAgent") throws -> [pid_t] {
        guard paths.controlsWallpaperProcesses else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-u", String(getuid()), "-x", name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard [0, 1].contains(process.terminationStatus) else { throw WallpaperError.invalidSelection }
        return String(decoding: output, as: UTF8.self).split(whereSeparator: \.isWhitespace).compactMap { Int32($0) }
    }

    private func restartAerials() {
        for pid in (try? agentPIDs(named: "WallpaperAerialsExtension")) ?? [] { kill(pid, SIGTERM) }
    }

    private func readCatalog() throws -> [String: Any] { try decodeCatalog(Data(contentsOf: paths.manifest)) }

    private func decodeCatalog(_ data: Data) throws -> [String: Any] {
        guard let catalog = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WallpaperError.invalidCatalog
        }
        for key in ["assets", "categories"] {
            guard let entries = catalog[key] as? [[String: Any]] else { throw WallpaperError.invalidCatalog }
            let ids = entries.compactMap { $0["id"] as? String }
            guard ids.count == entries.count, Set(ids).count == ids.count else { throw WallpaperError.invalidCatalog }
            if key == "categories" {
                for entry in entries where entry["subcategories"] != nil {
                    guard let subs = entry["subcategories"] as? [[String: Any]],
                          subs.allSatisfy({ $0["id"] is String }) else { throw WallpaperError.invalidCatalog }
                }
            }
        }
        return catalog
    }

    private func readIndex() throws -> [String: Any] { try decodeIndex(Data(contentsOf: paths.index)) }

    private func decodeIndex(_ data: Data) throws -> [String: Any] {
        guard let index = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let global = index["AllSpacesAndDisplays"] as? [String: Any],
              let type = global["Type"] as? String, ["linked", "individual"].contains(type),
              global[type == "linked" ? "Linked" : "Desktop"] is [String: Any] else {
            throw WallpaperError.invalidSelection
        }
        return index
    }

    private func plistData(_ value: Any) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }

    private func writeCatalog(_ catalog: [String: Any], replacing before: Data, commit: () throws -> Void) throws {
        let output = try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try backup(before, name: "entries.json")
        guard try Data(contentsOf: paths.manifest) == before else { throw WallpaperError.changedDuringWrite }
        try output.write(to: paths.manifest, options: .atomic)
        do { try commit() } catch {
            if (try? Data(contentsOf: paths.manifest)) == output { try before.write(to: paths.manifest, options: .atomic) }
            throw error
        }
    }

    private func backup(_ data: Data, name: String) throws {
        let directory = paths.state.appendingPathComponent("Backups/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}
