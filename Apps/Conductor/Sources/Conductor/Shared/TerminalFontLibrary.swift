import AppKit
import CoreText
import Foundation

enum TerminalFontPreset: String, CaseIterable, Codable, Identifiable {
    case menlo
    case sfMono
    case monaco
    case jetBrainsMono
    case firaCode
    case cascadiaCode
    case hack
    case sourceCodePro
    case meslo
    case iosevka
    case ibmPlexMono
    case recursiveMono
    case dankMono
    case operatorMono
    case berkeleyMono
    case commitMono
    case robotoMono
    case ubuntuMono
    case inconsolata
    case victorMono
    case mapleMono
    case fantasqueSansMono
    case geistMono
    case zedMono
    case dejavuSansMono
    case consolas

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .menlo: "Menlo"
        case .sfMono: "SF Mono"
        case .monaco: "Monaco"
        case .jetBrainsMono: "JetBrains Mono"
        case .firaCode: "Fira Code"
        case .cascadiaCode: "Cascadia Code"
        case .hack: "Hack"
        case .sourceCodePro: "Source Code Pro"
        case .meslo: "MesloLGS NF"
        case .iosevka: "Iosevka"
        case .ibmPlexMono: "IBM Plex Mono"
        case .recursiveMono: "Recursive Mono"
        case .dankMono: "Dank Mono"
        case .operatorMono: "Operator Mono"
        case .berkeleyMono: "Berkeley Mono"
        case .commitMono: "CommitMono"
        case .robotoMono: "Roboto Mono"
        case .ubuntuMono: "Ubuntu Mono"
        case .inconsolata: "Inconsolata"
        case .victorMono: "Victor Mono"
        case .mapleMono: "Maple Mono"
        case .fantasqueSansMono: "Fantasque Sans Mono"
        case .geistMono: "Geist Mono"
        case .zedMono: "Zed Mono"
        case .dejavuSansMono: "DejaVu Sans Mono"
        case .consolas: "Consolas"
        }
    }

    var sourceTitle: String {
        switch self {
        case .menlo, .sfMono, .monaco:
            ConductorLocalization.text(zh: "macOS", en: "macOS")
        case .meslo, .jetBrainsMono, .firaCode, .cascadiaCode, .hack, .sourceCodePro, .iosevka, .mapleMono, .fantasqueSansMono, .inconsolata:
            ConductorLocalization.text(zh: "开发者常用", en: "Developer")
        case .dankMono, .operatorMono, .berkeleyMono, .commitMono, .victorMono, .geistMono, .zedMono:
            ConductorLocalization.text(zh: "精品字体", en: "Curated")
        case .ibmPlexMono, .recursiveMono, .robotoMono, .ubuntuMono, .dejavuSansMono, .consolas:
            ConductorLocalization.text(zh: "系统/开源", en: "System/Open")
        }
    }

    var candidateFamilyNames: [String] {
        switch self {
        case .menlo: ["Menlo"]
        case .sfMono: ["SF Mono", ".SF Mono"]
        case .monaco: ["Monaco"]
        case .jetBrainsMono: ["JetBrains Mono", "JetBrainsMono Nerd Font"]
        case .firaCode: ["Fira Code", "FiraCode Nerd Font"]
        case .cascadiaCode: ["Cascadia Code", "CaskaydiaCove Nerd Font"]
        case .hack: ["Hack", "Hack Nerd Font"]
        case .sourceCodePro: ["Source Code Pro", "SauceCodePro Nerd Font"]
        case .meslo: ["MesloLGS NF", "MesloLGS Nerd Font", "Meslo LG S"]
        case .iosevka: ["Iosevka", "Iosevka Nerd Font"]
        case .ibmPlexMono: ["IBM Plex Mono", "BlexMono Nerd Font"]
        case .recursiveMono: ["Recursive Mono", "Recursive"]
        case .dankMono: ["Dank Mono"]
        case .operatorMono: ["Operator Mono"]
        case .berkeleyMono: ["Berkeley Mono"]
        case .commitMono: ["CommitMono", "Commit Mono"]
        case .robotoMono: ["Roboto Mono", "RobotoMono Nerd Font"]
        case .ubuntuMono: ["Ubuntu Mono", "UbuntuMono Nerd Font"]
        case .inconsolata: ["Inconsolata", "InconsolataGo Nerd Font", "Inconsolata Nerd Font"]
        case .victorMono: ["Victor Mono", "VictorMono Nerd Font"]
        case .mapleMono: ["Maple Mono", "Maple Mono NF"]
        case .fantasqueSansMono: ["Fantasque Sans Mono", "FantasqueSansM Nerd Font"]
        case .geistMono: ["Geist Mono"]
        case .zedMono: ["Zed Mono"]
        case .dejavuSansMono: ["DejaVu Sans Mono", "DejaVuSansM Nerd Font"]
        case .consolas: ["Consolas"]
        }
    }

    var downloadURL: URL? {
        switch self {
        case .menlo, .sfMono, .monaco:
            nil
        case .jetBrainsMono:
            URL(string: "https://www.jetbrains.com/lp/mono/")
        case .firaCode:
            URL(string: "https://github.com/tonsky/FiraCode")
        case .cascadiaCode:
            URL(string: "https://github.com/microsoft/cascadia-code/releases")
        case .hack:
            URL(string: "https://sourcefoundry.org/hack/")
        case .sourceCodePro:
            URL(string: "https://github.com/adobe-fonts/source-code-pro")
        case .meslo:
            URL(string: "https://github.com/romkatv/powerlevel10k#manual-font-installation")
        case .iosevka:
            URL(string: "https://github.com/be5invis/Iosevka")
        case .ibmPlexMono:
            URL(string: "https://github.com/IBM/plex")
        case .recursiveMono:
            URL(string: "https://www.recursive.design/")
        case .dankMono:
            URL(string: "https://dank.sh/")
        case .operatorMono:
            URL(string: "https://www.typography.com/fonts/operator/styles")
        case .berkeleyMono:
            URL(string: "https://berkeleygraphics.com/typefaces/berkeley-mono/")
        case .commitMono:
            URL(string: "https://commitmono.com/")
        case .robotoMono:
            URL(string: "https://fonts.google.com/specimen/Roboto+Mono")
        case .ubuntuMono:
            URL(string: "https://design.ubuntu.com/font")
        case .inconsolata:
            URL(string: "https://fonts.google.com/specimen/Inconsolata")
        case .victorMono:
            URL(string: "https://rubjo.github.io/victor-mono/")
        case .mapleMono:
            URL(string: "https://github.com/subframe7536/maple-font")
        case .fantasqueSansMono:
            URL(string: "https://github.com/belluzj/fantasque-sans")
        case .geistMono:
            URL(string: "https://vercel.com/font")
        case .zedMono:
            URL(string: "https://github.com/zed-industries/zed-fonts")
        case .dejavuSansMono:
            URL(string: "https://dejavu-fonts.github.io/")
        case .consolas:
            URL(string: "https://learn.microsoft.com/en-us/typography/font-list/consolas")
        }
    }

    var directDownloadURL: URL? {
        let base = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/"
        return switch self {
        case .menlo, .sfMono, .monaco, .dankMono, .operatorMono, .berkeleyMono, .commitMono, .recursiveMono, .mapleMono, .geistMono, .zedMono, .consolas:
            nil
        case .jetBrainsMono:
            URL(string: "\(base)JetBrainsMono.zip")
        case .firaCode:
            URL(string: "\(base)FiraCode.zip")
        case .cascadiaCode:
            URL(string: "\(base)CascadiaCode.zip")
        case .hack:
            URL(string: "\(base)Hack.zip")
        case .sourceCodePro:
            URL(string: "\(base)SourceCodePro.zip")
        case .meslo:
            URL(string: "\(base)Meslo.zip")
        case .iosevka:
            URL(string: "\(base)Iosevka.zip")
        case .ibmPlexMono:
            URL(string: "\(base)IBMPlexMono.zip")
        case .robotoMono:
            URL(string: "\(base)RobotoMono.zip")
        case .ubuntuMono:
            URL(string: "\(base)UbuntuMono.zip")
        case .inconsolata:
            URL(string: "\(base)Inconsolata.zip")
        case .victorMono:
            URL(string: "\(base)VictorMono.zip")
        case .fantasqueSansMono:
            URL(string: "\(base)FantasqueSansMono.zip")
        case .dejavuSansMono:
            URL(string: "\(base)DejaVuSansMono.zip")
        }
    }
}

enum TerminalFontDownloadState: Equatable {
    case idle
    case downloading
    case installed(String)
    case failed(String)

    var isDownloading: Bool {
        if case .downloading = self {
            return true
        }
        return false
    }
}

struct TerminalFontChoice: Identifiable, Equatable {
    let preset: TerminalFontPreset
    let displayName: String
    let sourceTitle: String
    let resolvedFamilyName: String?
    let isInstalled: Bool

    var id: TerminalFontPreset { preset }

    var statusTitle: String {
        isInstalled
            ? ConductorLocalization.text(zh: "已安装", en: "Installed")
            : ConductorLocalization.text(zh: "未安装", en: "Missing")
    }

    var subtitle: String {
        if let resolvedFamilyName {
            return ConductorLocalization.text(
                zh: "\(sourceTitle) · 使用 \(resolvedFamilyName)",
                en: "\(sourceTitle) · Uses \(resolvedFamilyName)"
            )
        }
        return ConductorLocalization.text(
            zh: "\(sourceTitle) · 会回退到 Menlo",
            en: "\(sourceTitle) · Falls back to Menlo"
        )
    }

    var canDownload: Bool {
        preset.directDownloadURL != nil || preset.downloadURL != nil
    }
}

struct TerminalFontDownloadResult: Equatable {
    let preset: TerminalFontPreset
    let familyName: String
}

enum TerminalFontLibrary {
    static let fallbackFamilyName = "Menlo"

    static var choices: [TerminalFontChoice] {
        TerminalFontPreset.allCases.map { preset in
            let resolved = TerminalFontAvailability.installedCandidate(for: preset)
            return TerminalFontChoice(
                preset: preset,
                displayName: preset.displayName,
                sourceTitle: preset.sourceTitle,
                resolvedFamilyName: resolved,
                isInstalled: resolved != nil
            )
        }
    }

    static func resolvedFamilyName(
        preset: TerminalFontPreset,
        customFamilyName: String?,
        customFontFilePath: String?,
        customFontBookmarkData: Data?,
        useCustomFont: Bool
    ) -> String {
        if useCustomFont,
           let customFamilyName,
           !customFamilyName.isEmpty {
            registerCustomFontIfNeeded(path: customFontFilePath, bookmarkData: customFontBookmarkData)
            TerminalFontAvailability.refresh()
            if TerminalFontAvailability.isFamilyInstalled(customFamilyName) {
                return customFamilyName
            }
        }

        let installed = TerminalFontAvailability.installedFamilyNames
        return preset.candidateFamilyNames.first { installed.contains($0) }
            ?? fallbackFamilyName
    }

    @discardableResult
    static func registerCustomFontIfNeeded(path: String?, bookmarkData: Data? = nil) -> Bool {
        let url = resolvedFontURL(path: path, bookmarkData: bookmarkData)
        guard let url else { return false }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        var error: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if ok {
            TerminalFontAvailability.refresh()
            return true
        }
        guard let nsError = error?.takeRetainedValue() as Error? else { return false }
        let alreadyRegistered = (nsError as NSError).code == CTFontManagerError.alreadyRegistered.rawValue
        if alreadyRegistered {
            TerminalFontAvailability.refresh()
        }
        return alreadyRegistered
    }

    static func familyName(in fontFileURL: URL) -> String? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontFileURL as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first,
              let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String,
              !family.isEmpty else {
            return nil
        }
        return family
    }

    static func downloadAndRegisterPreset(_ preset: TerminalFontPreset) async throws -> TerminalFontDownloadResult {
        guard let archiveURL = preset.directDownloadURL else {
            throw NSError(
                domain: "Conductor.TerminalFontDownload",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: ConductorLocalization.text(zh: "这个字体没有可自动下载的公开安装包。", en: "This font does not have a public package Conductor can download automatically.")]
            )
        }

        let destination = try fontInstallDirectory(for: preset)
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destination)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let (downloadedArchive, response) = try await URLSession.shared.download(from: archiveURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw NSError(
                domain: "Conductor.TerminalFontDownload",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: ConductorLocalization.text(zh: "字体下载失败：HTTP \(httpResponse.statusCode)", en: "Font download failed: HTTP \(httpResponse.statusCode)")]
            )
        }

        let archiveCopy = destination.appendingPathComponent("\(preset.rawValue).zip")
        try? fileManager.removeItem(at: archiveCopy)
        try fileManager.moveItem(at: downloadedArchive, to: archiveCopy)
        try extractZip(at: archiveCopy, to: destination)

        let fonts = fontFiles(in: destination)
        guard !fonts.isEmpty else {
            throw NSError(
                domain: "Conductor.TerminalFontDownload",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: ConductorLocalization.text(zh: "下载包里没有找到可用字体文件。", en: "No usable font files were found in the downloaded package.")]
            )
        }

        var registered = false
        for font in fonts {
            registered = registerCustomFontIfNeeded(path: font.path) || registered
        }
        TerminalFontAvailability.refresh()
        guard registered,
              let familyName = TerminalFontAvailability.installedCandidate(for: preset) else {
            throw NSError(
                domain: "Conductor.TerminalFontDownload",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: ConductorLocalization.text(zh: "字体已下载，但系统暂时没有识别到这个字体。", en: "The font was downloaded, but macOS did not recognize it yet.")]
            )
        }

        return TerminalFontDownloadResult(preset: preset, familyName: familyName)
    }

    static func bookmarkData(for fontFileURL: URL) -> Data? {
        try? fontFileURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private static func resolvedFontURL(path: String?, bookmarkData: Data?) -> URL? {
        if let bookmarkData {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                return url
            }
        }

        guard let path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func fontInstallDirectory(for preset: TerminalFontPreset) throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("Conductor", isDirectory: true)
            .appendingPathComponent("Fonts", isDirectory: true)
            .appendingPathComponent(preset.rawValue, isDirectory: true)
    }

    private static func extractZip(at archiveURL: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "Conductor.TerminalFontDownload",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: ConductorLocalization.text(zh: "字体包解压失败。", en: "Failed to extract the font package.")]
            )
        }
    }

    private static func fontFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            let ext = url.pathExtension.lowercased()
            return ["ttf", "otf", "ttc"].contains(ext) ? url : nil
        }
    }
}
