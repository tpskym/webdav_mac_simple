import SwiftUI

struct ContentView: View {
    @StateObject private var settings = SettingsStore()
    @State private var currentPath = ""
    @State private var resources: [WebDAVResource] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedIds: Set<String> = []
    @State private var pathStack: [String] = []
    @State private var showPassword = false
    @State private var successMessage: String?

    private var canConnect: Bool {
        !settings.serverURL.isEmpty && settings.serverURL.hasPrefix("https")
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            actionBar
            Divider()
            listSection
        }
        .frame(minWidth: 620, minHeight: 440)
        // Скрытые кнопки только для клавиатурных сочетаний
        .background(Group {
            Button("") { openSelectedFolder() }
                .keyboardShortcut("o", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
        })
        .alert("Ошибка", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Готово", isPresented: .constant(successMessage != nil)) {
            Button("OK") { successMessage = nil }
        } message: {
            Text(successMessage ?? "")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Text("Сервер")
                    .gridColumnAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .frame(width: 54)
                TextField("https://webdav.example.com", text: $settings.serverURL)
                    .textFieldStyle(.roundedBorder)
                    .gridCellColumns(3)
            }
            GridRow {
                Text("Логин")
                    .gridColumnAlignment(.trailing)
                    .foregroundStyle(.secondary)
                TextField("", text: $settings.login)
                    .textFieldStyle(.roundedBorder)
                Text("Пароль")
                    .foregroundStyle(.secondary)
                passwordField
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var passwordField: some View {
        HStack(spacing: 4) {
            Group {
                if showPassword {
                    TextField("", text: $settings.password)
                } else {
                    SecureField("", text: $settings.password)
                }
            }
            .textFieldStyle(.roundedBorder)
            Button(action: { showPassword.toggle() }) {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(showPassword ? "Скрыть пароль" : "Показать пароль")
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 2) {

            // Обновить
            toolbarButton("arrow.clockwise", help: "Обновить список (⌘R)", disabled: isLoading || !canConnect, action: loadList)
                .keyboardShortcut("r", modifiers: .command)

            toolbarDivider

            // Навигация
            toolbarButton("chevron.backward", help: "На уровень выше", disabled: isLoading || pathStack.isEmpty, action: goUp)
            toolbarButton("arrow.forward.circle", help: "Войти в выбранную папку (⌘O)", disabled: isLoading || !selectedFolderAvailable, action: openSelectedFolder)

            toolbarDivider

            // Хлебные крошки / путь
            HStack(spacing: 4) {
                Image(systemName: pathStack.isEmpty ? "server.rack" : "folder")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                Text(pathStack.isEmpty ? (canConnect ? hostName : "—") : currentPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minWidth: 80)
            }
            .padding(.horizontal, 6)

            Spacer()

            // Прогресс
            if isLoading {
                ProgressView()
                    .scaleEffect(0.65)
                    .frame(width: 20, height: 20)
                    .padding(.horizontal, 4)
            }

            toolbarDivider

            // Папка сохранения
            Button(action: pickSaveDirectory) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.badge.plus")
                        .foregroundStyle(settings.saveDirectory != nil ? .blue : .secondary)
                    Text(settings.saveDirectory?.lastPathComponent ?? "Куда скачать")
                        .font(.system(size: 11))
                        .foregroundStyle(settings.saveDirectory != nil ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 140, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .help(settings.saveDirectory?.path ?? "Выберите папку для скачивания")

            toolbarDivider

            // Скачать / Загрузить
            toolbarButton("arrow.down.circle",
                          help: "Скачать выбранные файлы",
                          disabled: isLoading || selectedIds.isEmpty || settings.saveDirectory == nil,
                          action: downloadSelected)

            toolbarButton("arrow.up.circle",
                          help: "Загрузить файл на сервер",
                          disabled: isLoading || !canConnect,
                          action: uploadFile)
                .padding(.trailing, 4)
        }
        .frame(height: 34)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var selectedFolderAvailable: Bool {
        guard let id = selectedIds.first else { return false }
        return resources.first(where: { $0.id == id })?.isCollection == true
    }

    private var hostName: String {
        URL(string: settings.serverURL)?.host ?? settings.serverURL
    }

    @ViewBuilder
    private func toolbarButton(_ icon: String, help: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(disabled ? .tertiary : .primary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }

    private var toolbarDivider: some View {
        Divider()
            .frame(height: 18)
            .padding(.horizontal, 4)
    }

    // MARK: - File list

    private var listSection: some View {
        Group {
            if !isLoading && resources.isEmpty && currentPath.isEmpty && canConnect {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("Нажмите «Обновить список»")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !isLoading && resources.isEmpty && !currentPath.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("Папка пуста")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(sortedResources, selection: $selectedIds) { res in
                    HStack(spacing: 10) {
                        Image(systemName: res.isCollection ? "folder.fill" : fileIcon(for: res.displayName))
                            .font(.system(size: 15))
                            .foregroundStyle(res.isCollection ? Color.yellow : Color.accentColor.opacity(0.8))
                            .frame(width: 22, alignment: .center)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(res.displayName)
                                .font(.body)
                            if let len = res.contentLength, !res.isCollection {
                                Text(ByteCountFormatter.string(fromByteCount: len, countStyle: .file))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        if let date = res.lastModified {
                            Text(date, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(res.id)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .background(
                    TableDoubleClickSetup { row in
                        let items = sortedResources
                        guard row < items.count, items[row].isCollection else { return }
                        enterDirectory(items[row])
                    }
                )
            }
        }
    }

    private var sortedResources: [WebDAVResource] {
        resources.sorted { a, b in
            if a.isCollection != b.isCollection { return a.isCollection }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf":                             return "doc.richtext"
        case "jpg", "jpeg", "png", "gif",
             "heic", "tiff", "bmp", "webp":    return "photo"
        case "mp4", "mov", "avi", "mkv":       return "film"
        case "mp3", "aac", "wav", "flac":      return "music.note"
        case "zip", "gz", "tar", "rar", "7z":  return "archivebox"
        case "swift", "py", "js", "ts",
             "kt", "java", "c", "cpp", "h":    return "curlybraces"
        case "md", "txt", "log":               return "doc.text"
        case "xls", "xlsx", "csv":             return "tablecells"
        case "doc", "docx", "rtf":             return "doc.richtext"
        default:                                return "doc"
        }
    }

    // MARK: - Actions

    private func loadList() {
        guard let base = URL(string: settings.serverURL.trimmingCharacters(in: .whitespaces)),
              base.scheme == "https" else {
            errorMessage = "Укажите корректный HTTPS URL"
            return
        }
        let serverTrimmed = settings.serverURL.trimmingCharacters(in: .whitespaces)
        var pathToLoad = currentPath.isEmpty ? "/" : currentPath

        // Восстановить последнюю открытую папку при первом открытии списка
        if pathStack.isEmpty && currentPath.isEmpty,
           let savedServer = settings.lastOpenPathServerURL,
           let savedPath = settings.lastOpenPath,
           savedServer == serverTrimmed,
           !savedPath.isEmpty {
            let path = savedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !path.isEmpty {
                let comps = path.split(separator: "/").map(String.init)
                var stack: [String] = []
                for c in comps {
                    stack.append(stack.isEmpty ? c : stack.last! + "/" + c)
                }
                pathStack = stack
                currentPath = stack.last ?? ""
                pathToLoad = currentPath.isEmpty ? "/" : currentPath
            }
        }

        isLoading = true
        errorMessage = nil
        let creds = WebDAVCredentials(baseURL: base, login: settings.login, password: settings.password)
        let service = WebDAVService(credentials: creds)
        Task {
            do {
                var list = try await service.list(path: pathToLoad)
                list = list.filter { $0.href != pathToLoad && $0.href != pathToLoad + "/" }
                await MainActor.run {
                    resources = list
                    isLoading = false
                    saveLastOpenPath()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func saveLastOpenPath() {
        let serverTrimmed = settings.serverURL.trimmingCharacters(in: .whitespaces)
        guard !serverTrimmed.isEmpty else { return }
        settings.lastOpenPathServerURL = serverTrimmed
        settings.lastOpenPath = currentPath.isEmpty ? nil : currentPath
    }

    private func goUp() {
        guard !pathStack.isEmpty else { return }
        pathStack.removeLast()
        currentPath = pathStack.last ?? ""
        saveLastOpenPath()
        loadList()
    }

    private func openSelectedFolder() {
        guard let id = selectedIds.first,
              let res = resources.first(where: { $0.id == id }),
              res.isCollection else { return }
        enterDirectory(res)
    }

    private func enterDirectory(_ res: WebDAVResource) {
        pathStack.append(currentPath)
        var hrefPath = res.href
        if let hrefURL = URL(string: hrefPath), hrefURL.scheme != nil {
            hrefPath = hrefURL.path
        }
        hrefPath = hrefPath.removingPercentEncoding ?? hrefPath

        let normalizedCurrentPath = currentPath == "/"
            ? ""
            : currentPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let base = URL(string: settings.serverURL.trimmingCharacters(in: .whitespaces)),
           !base.path.isEmpty {
            var basePath = base.path
            if !basePath.hasSuffix("/") { basePath += "/" }
            var href = hrefPath
            if !href.hasSuffix("/") { href += "/" }
            if href.hasPrefix(basePath) {
                currentPath = String(href.dropFirst(basePath.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            } else if !href.hasPrefix("/") {
                // Некоторые WebDAV-серверы возвращают относительный href для вложенных папок.
                let relative = href.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if normalizedCurrentPath.isEmpty {
                    currentPath = relative
                } else {
                    currentPath = normalizedCurrentPath + "/" + relative
                }
            } else {
                currentPath = href.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
        } else {
            let lastComponent = (hrefPath as NSString).lastPathComponent
            if normalizedCurrentPath.isEmpty {
                currentPath = lastComponent
            } else {
                currentPath = normalizedCurrentPath + "/" + lastComponent
            }
        }
        if currentPath.isEmpty { currentPath = "/" }
        saveLastOpenPath()
        loadList()
    }

    private func pickSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectory = url
        }
    }

    private func uploadFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let fileURL = panel.url else { return }
        guard let base = URL(string: settings.serverURL.trimmingCharacters(in: .whitespaces)),
              base.scheme == "https" else { return }

        isLoading = true
        errorMessage = nil
        let creds = WebDAVCredentials(baseURL: base, login: settings.login, password: settings.password)
        let service = WebDAVService(credentials: creds)
        let remotePath = currentPath.isEmpty || currentPath == "/"
            ? fileURL.lastPathComponent
            : currentPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
              + "/" + fileURL.lastPathComponent

        Task {
            do {
                try await service.upload(localFile: fileURL, remotePath: remotePath)
                await MainActor.run {
                    isLoading = false
                    successMessage = "Файл «\(fileURL.lastPathComponent)» успешно загружен на сервер."
                    loadList()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Не удалось загрузить файл «\(fileURL.lastPathComponent)».\n\(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    private func downloadSelected() {
        guard let base = URL(string: settings.serverURL.trimmingCharacters(in: .whitespaces)),
              base.scheme == "https",
              let saveDir = settings.saveDirectory else { return }

        let creds = WebDAVCredentials(baseURL: base, login: settings.login, password: settings.password)
        let service = WebDAVService(credentials: creds)
        let toDownload = resources.filter { selectedIds.contains($0.id) && !$0.isCollection }

        isLoading = true
        errorMessage = nil
        Task {
            var savedNew: [String] = []
            var overwritten: [String] = []
            var failed: [(String, String)] = []
            let fm = FileManager.default
            for res in toDownload {
                let fileName = (res.href as NSString).lastPathComponent
                let localURL = saveDir.appendingPathComponent(fileName)
                let existed = fm.fileExists(atPath: localURL.path)
                do {
                    try await service.download(href: res.href, to: localURL)
                    if existed { overwritten.append(fileName) } else { savedNew.append(fileName) }
                } catch {
                    failed.append((fileName, error.localizedDescription))
                }
            }
            await MainActor.run {
                isLoading = false
                selectedIds.removeAll()
                if failed.isEmpty {
                    let folder = saveDir.lastPathComponent
                    var parts: [String] = []
                    if !savedNew.isEmpty {
                        parts.append(savedNew.count == 1
                            ? "Сохранён: «\(savedNew[0])»"
                            : "Сохранено новых: \(savedNew.count)")
                    }
                    if !overwritten.isEmpty {
                        parts.append(overwritten.count == 1
                            ? "Перезаписан: «\(overwritten[0])»"
                            : "Перезаписано: \(overwritten.count)")
                    }
                    successMessage = parts.joined(separator: "\n") + "\nПапка: «\(folder)»"
                } else if savedNew.isEmpty && overwritten.isEmpty {
                    let names = failed.map { "• \($0.0): \($0.1)" }.joined(separator: "\n")
                    errorMessage = "Не удалось скачать файлы:\n\(names)"
                } else {
                    let ok = savedNew.count + overwritten.count
                    let names = failed.map { "• \($0.0): \($0.1)" }.joined(separator: "\n")
                    errorMessage = "Скачано: \(ok), ошибок: \(failed.count)\n\(names)"
                }
            }
        }
    }
}
