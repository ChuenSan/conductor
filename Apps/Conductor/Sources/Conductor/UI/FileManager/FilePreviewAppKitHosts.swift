import AppKit
import SwiftUI

struct FileManagerSourcePreviewTextHost: NSViewRepresentable {
    let text: String
    let font: NSFont
    let backgroundColor: NSColor
    let textColor: NSColor
    let lineNumberColor: NSColor

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = FileManagerSourcePreviewScrollView()
        scrollView.drawsBackground = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.allowsUndo = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 16, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        scrollView.documentView = textView
        context.coordinator.apply(text: text, to: textView)
        context.coordinator.applyConfiguration(
            to: textView,
            scrollView: scrollView,
            font: font,
            backgroundColor: backgroundColor,
            textColor: textColor,
            lineNumberColor: lineNumberColor
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.applyConfiguration(
            to: textView,
            scrollView: scrollView,
            font: font,
            backgroundColor: backgroundColor,
            textColor: textColor,
            lineNumberColor: lineNumberColor
        )
        context.coordinator.apply(text: text, to: textView)
    }

    final class Coordinator {
        private var appliedText: String?
        private var appliedConfiguration: Configuration?

        @MainActor
        func apply(text: String, to textView: NSTextView) {
            guard text != appliedText else { return }
            appliedText = text
            textView.textStorage?.setAttributedString(attributedString(for: text))
        }

        @MainActor
        func applyConfiguration(
            to textView: NSTextView,
            scrollView: NSScrollView,
            font: NSFont,
            backgroundColor: NSColor,
            textColor: NSColor,
            lineNumberColor: NSColor
        ) {
            let configuration = Configuration(
                font: font,
                backgroundColor: backgroundColor,
                textColor: textColor,
                lineNumberColor: lineNumberColor
            )
            guard configuration != appliedConfiguration else { return }
            appliedConfiguration = configuration
            scrollView.backgroundColor = backgroundColor
            textView.backgroundColor = backgroundColor
            textView.font = font
            if let appliedText {
                textView.textStorage?.setAttributedString(attributedString(for: appliedText))
            }
        }

        private func attributedString(for text: String) -> NSAttributedString {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byClipping
            let attributed = NSMutableAttributedString(
                string: text,
                attributes: [
                    .font: appliedConfiguration?.font ?? .monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: appliedConfiguration?.textColor ?? NSColor.textColor,
                    .paragraphStyle: paragraphStyle
                ]
            )

            let lineNumberColor = appliedConfiguration?.lineNumberColor ?? NSColor.secondaryLabelColor
            let fullText = text as NSString
            var location = 0
            while location < fullText.length {
                let lineRange = fullText.lineRange(for: NSRange(location: location, length: 0))
                let line = fullText.substring(with: lineRange)
                let prefixLength = line.prefix { $0 == " " || $0.isNumber }.count
                let numberRange = NSRange(location: lineRange.location, length: min(prefixLength, lineRange.length))
                attributed.addAttribute(.foregroundColor, value: lineNumberColor, range: numberRange)
                location = NSMaxRange(lineRange)
            }
            return attributed
        }

        private struct Configuration: Equatable {
            let font: NSFont
            let backgroundColor: NSColor
            let textColor: NSColor
            let lineNumberColor: NSColor
        }
    }
}

final class FileManagerSourcePreviewScrollView: NSScrollView {
    override var isFlipped: Bool { true }
}

struct FileManagerTablePreviewHost: NSViewRepresentable {
    let document: FilePreviewTableDocument
    let font: NSFont
    let headerFont: NSFont
    let lineNumberFont: NSFont
    let backgroundColor: NSColor
    let textColor: NSColor
    let headerTextColor: NSColor
    let lineNumberTextColor: NSColor
    let lineNumberBackgroundColor: NSColor
    let headerBackgroundColor: NSColor
    let evenCellBackgroundColor: NSColor
    let oddCellBackgroundColor: NSColor
    let gridColor: NSColor

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay

        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = .zero
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .none
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = false
        tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        let menu = NSMenu()
        menu.delegate = context.coordinator
        tableView.menu = menu

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.apply(document: document, configuration: configuration, to: tableView, scrollView: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        context.coordinator.apply(document: document, configuration: configuration, to: tableView, scrollView: scrollView)
    }

    private var configuration: Coordinator.Configuration {
        Coordinator.Configuration(
            font: font,
            headerFont: headerFont,
            lineNumberFont: lineNumberFont,
            backgroundColor: backgroundColor,
            textColor: textColor,
            headerTextColor: headerTextColor,
            lineNumberTextColor: lineNumberTextColor,
            lineNumberBackgroundColor: lineNumberBackgroundColor,
            headerBackgroundColor: headerBackgroundColor,
            evenCellBackgroundColor: evenCellBackgroundColor,
            oddCellBackgroundColor: oddCellBackgroundColor,
            gridColor: gridColor
        )
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        struct Configuration: Equatable {
            let font: NSFont
            let headerFont: NSFont
            let lineNumberFont: NSFont
            let backgroundColor: NSColor
            let textColor: NSColor
            let headerTextColor: NSColor
            let lineNumberTextColor: NSColor
            let lineNumberBackgroundColor: NSColor
            let headerBackgroundColor: NSColor
            let evenCellBackgroundColor: NSColor
            let oddCellBackgroundColor: NSColor
            let gridColor: NSColor
        }

        weak var tableView: NSTableView?
        private var document = FilePreviewTableDocument(rows: [], delimiterName: "CSV", sourceLineCount: 0)
        private var appliedColumnCount = -1
        private var appliedConfiguration: Configuration?
        private var contextMenuTarget: (row: Int, column: Int)?

        @MainActor
        func apply(
            document: FilePreviewTableDocument,
            configuration: Configuration,
            to tableView: NSTableView,
            scrollView: NSScrollView
        ) {
            let columnsChanged = appliedColumnCount != document.columnCount
            let documentChanged = self.document != document
            let configurationChanged = appliedConfiguration != configuration

            self.document = document
            appliedConfiguration = configuration
            scrollView.backgroundColor = configuration.backgroundColor
            tableView.backgroundColor = configuration.backgroundColor
            tableView.gridColor = configuration.gridColor

            if columnsChanged {
                rebuildColumns(in: tableView, columnCount: document.columnCount)
                appliedColumnCount = document.columnCount
            }
            if columnsChanged || documentChanged || configurationChanged {
                tableView.reloadData()
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            document.rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < document.rows.count,
                  let tableColumn,
                  let configuration = appliedConfiguration else {
                return nil
            }
            let identifier = tableColumn.identifier
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? FileManagerTableCellView ??
                FileManagerTableCellView(identifier: identifier)
            let isLineNumber = identifier.rawValue == Self.lineNumberIdentifier
            let columnIndex = columnIndex(for: identifier)
            let text: String
            if isLineNumber {
                text = "\(row + 1)"
            } else if let columnIndex {
                text = Self.cell(row: document.rows[row], columnIndex: columnIndex)
            } else {
                text = ""
            }
            cell.configure(
                text: text,
                alignment: isLineNumber ? .right : .left,
                font: isLineNumber ? configuration.lineNumberFont : (row == 0 ? configuration.headerFont : configuration.font),
                textColor: isLineNumber ? configuration.lineNumberTextColor : (row == 0 ? configuration.headerTextColor : configuration.textColor),
                backgroundColor: backgroundColor(row: row, columnIndex: columnIndex, isLineNumber: isLineNumber, configuration: configuration)
            )
            return cell
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let tableView else { return }
            let row = tableView.clickedRow
            let column = tableView.clickedColumn
            guard row >= 0, row < document.rows.count, column >= 0 else { return }
            contextMenuTarget = (row, column)
            if column > 0 {
                let copyCell = NSMenuItem(title: fileManagerL("复制单元格", "Copy Cell"), action: #selector(copyCell), keyEquivalent: "")
                copyCell.target = self
                menu.addItem(copyCell)
            }
            let copyRow = NSMenuItem(title: fileManagerL("复制行", "Copy Row"), action: #selector(copyRow), keyEquivalent: "")
            copyRow.target = self
            menu.addItem(copyRow)
        }

        @objc private func copyCell() {
            guard let contextMenuTarget, contextMenuTarget.column > 0 else { return }
            copyText(Self.cell(row: document.rows[contextMenuTarget.row], columnIndex: contextMenuTarget.column - 1))
        }

        @objc private func copyRow() {
            guard let contextMenuTarget else { return }
            copyText(document.rows[contextMenuTarget.row].joined(separator: document.delimiterName == "TSV" ? "\t" : ","))
        }

        @MainActor
        private func rebuildColumns(in tableView: NSTableView, columnCount: Int) {
            for column in tableView.tableColumns {
                tableView.removeTableColumn(column)
            }
            let lineColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(Self.lineNumberIdentifier))
            lineColumn.width = 46
            lineColumn.minWidth = 40
            lineColumn.maxWidth = 62
            tableView.addTableColumn(lineColumn)

            for index in 0..<max(columnCount, 1) {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("\(Self.columnPrefix)\(index)"))
                column.width = FileManagerTablePreviewHost.cellWidth
                column.minWidth = 92
                column.maxWidth = 420
                tableView.addTableColumn(column)
            }
        }

        private func backgroundColor(
            row: Int,
            columnIndex: Int?,
            isLineNumber: Bool,
            configuration: Configuration
        ) -> NSColor {
            if isLineNumber {
                return configuration.lineNumberBackgroundColor
            }
            if row == 0 {
                return configuration.headerBackgroundColor
            }
            guard let columnIndex else { return configuration.oddCellBackgroundColor }
            return columnIndex.isMultiple(of: 2) ? configuration.evenCellBackgroundColor : configuration.oddCellBackgroundColor
        }

        private func columnIndex(for identifier: NSUserInterfaceItemIdentifier) -> Int? {
            guard identifier.rawValue.hasPrefix(Self.columnPrefix) else { return nil }
            return Int(identifier.rawValue.dropFirst(Self.columnPrefix.count))
        }

        private func copyText(_ text: String) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        private static func cell(row: [String], columnIndex: Int) -> String {
            guard row.indices.contains(columnIndex) else { return "" }
            let value = row[columnIndex]
            guard value.count > 160 else { return value }
            return String(value.prefix(160)) + " ..."
        }

        private static let lineNumberIdentifier = "line"
        private static let columnPrefix = "column-"
    }

    private static let rowHeight: CGFloat = 26
    private static let cellWidth: CGFloat = 156
}

final class FileManagerTableCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")
    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        wantsLayer = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.allowsExpansionToolTips = true
        addSubview(label)
        let leadingConstraint = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8)
        let trailingConstraint = label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        self.leadingConstraint = leadingConstraint
        self.trailingConstraint = trailingConstraint
        NSLayoutConstraint.activate([
            leadingConstraint,
            trailingConstraint,
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(
        text: String,
        alignment: NSTextAlignment,
        font: NSFont,
        textColor: NSColor,
        backgroundColor: NSColor,
        leadingInset: CGFloat = 8,
        trailingInset: CGFloat = 8
    ) {
        label.stringValue = text
        label.alignment = alignment
        label.font = font
        label.textColor = textColor
        leadingConstraint?.constant = leadingInset
        trailingConstraint?.constant = -trailingInset
        layer?.backgroundColor = backgroundColor.cgColor
    }
}

struct FileManagerKeyValuePreviewHost: NSViewRepresentable {
    let document: FilePreviewKeyValueDocument
    let valueFont: NSFont
    let keyFont: NSFont
    let lineNumberFont: NSFont
    let backgroundColor: NSColor
    let valueTextColor: NSColor
    let keyTextColor: NSColor
    let lineNumberTextColor: NSColor
    let lineNumberBackgroundColor: NSColor
    let keyBackgroundColor: NSColor
    let evenValueBackgroundColor: NSColor
    let oddValueBackgroundColor: NSColor
    let gridColor: NSColor

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay

        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = .zero
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .none
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = false
        tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        let menu = NSMenu()
        menu.delegate = context.coordinator
        tableView.menu = menu

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.apply(document: document, configuration: configuration, to: tableView, scrollView: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        context.coordinator.apply(document: document, configuration: configuration, to: tableView, scrollView: scrollView)
    }

    private var configuration: Coordinator.Configuration {
        Coordinator.Configuration(
            valueFont: valueFont,
            keyFont: keyFont,
            lineNumberFont: lineNumberFont,
            backgroundColor: backgroundColor,
            valueTextColor: valueTextColor,
            keyTextColor: keyTextColor,
            lineNumberTextColor: lineNumberTextColor,
            lineNumberBackgroundColor: lineNumberBackgroundColor,
            keyBackgroundColor: keyBackgroundColor,
            evenValueBackgroundColor: evenValueBackgroundColor,
            oddValueBackgroundColor: oddValueBackgroundColor,
            gridColor: gridColor
        )
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        struct Configuration: Equatable {
            let valueFont: NSFont
            let keyFont: NSFont
            let lineNumberFont: NSFont
            let backgroundColor: NSColor
            let valueTextColor: NSColor
            let keyTextColor: NSColor
            let lineNumberTextColor: NSColor
            let lineNumberBackgroundColor: NSColor
            let keyBackgroundColor: NSColor
            let evenValueBackgroundColor: NSColor
            let oddValueBackgroundColor: NSColor
            let gridColor: NSColor
        }

        weak var tableView: NSTableView?
        private var document = FilePreviewKeyValueDocument(rows: [], formatLabel: "", sourceLineCount: 0)
        private var didBuildColumns = false
        private var appliedConfiguration: Configuration?
        private var contextMenuTargetRow: Int?

        @MainActor
        func apply(
            document: FilePreviewKeyValueDocument,
            configuration: Configuration,
            to tableView: NSTableView,
            scrollView: NSScrollView
        ) {
            let documentChanged = self.document != document
            let configurationChanged = appliedConfiguration != configuration

            self.document = document
            appliedConfiguration = configuration
            scrollView.backgroundColor = configuration.backgroundColor
            tableView.backgroundColor = configuration.backgroundColor
            tableView.gridColor = configuration.gridColor

            if !didBuildColumns {
                rebuildColumns(in: tableView)
                didBuildColumns = true
            }
            if documentChanged || configurationChanged {
                tableView.reloadData()
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            document.rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < document.rows.count,
                  let tableColumn,
                  let configuration = appliedConfiguration else {
                return nil
            }
            let identifier = tableColumn.identifier
            let previewRow = document.rows[row]
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? FileManagerTableCellView ??
                FileManagerTableCellView(identifier: identifier)
            let text: String
            let font: NSFont
            let textColor: NSColor
            let backgroundColor: NSColor
            let alignment: NSTextAlignment
            switch identifier.rawValue {
            case Self.lineNumberIdentifier:
                text = "\(previewRow.index)"
                font = configuration.lineNumberFont
                textColor = configuration.lineNumberTextColor
                backgroundColor = configuration.lineNumberBackgroundColor
                alignment = .right
            case Self.keyIdentifier:
                text = previewRow.key
                font = configuration.keyFont
                textColor = configuration.keyTextColor
                backgroundColor = configuration.keyBackgroundColor
                alignment = .left
            default:
                text = Self.previewText(previewRow.value)
                font = configuration.valueFont
                textColor = configuration.valueTextColor
                backgroundColor = row.isMultiple(of: 2) ? configuration.evenValueBackgroundColor : configuration.oddValueBackgroundColor
                alignment = .left
            }
            cell.configure(
                text: text,
                alignment: alignment,
                font: font,
                textColor: textColor,
                backgroundColor: backgroundColor
            )
            return cell
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let tableView else { return }
            let row = tableView.clickedRow
            guard row >= 0, row < document.rows.count else { return }
            contextMenuTargetRow = row

            let copyKey = NSMenuItem(title: fileManagerL("复制 Key", "Copy Key"), action: #selector(copyKey), keyEquivalent: "")
            copyKey.target = self
            menu.addItem(copyKey)

            let copyValue = NSMenuItem(title: fileManagerL("复制 Value", "Copy Value"), action: #selector(copyValue), keyEquivalent: "")
            copyValue.target = self
            menu.addItem(copyValue)

            let copyLine = NSMenuItem(title: fileManagerL("复制整行", "Copy Line"), action: #selector(copyLine), keyEquivalent: "")
            copyLine.target = self
            menu.addItem(copyLine)
        }

        @objc private func copyKey() {
            guard let row = contextMenuTargetRow else { return }
            copyText(document.rows[row].key)
        }

        @objc private func copyValue() {
            guard let row = contextMenuTargetRow else { return }
            copyText(document.rows[row].value)
        }

        @objc private func copyLine() {
            guard let row = contextMenuTargetRow else { return }
            copyText(document.rows[row].raw)
        }

        @MainActor
        private func rebuildColumns(in tableView: NSTableView) {
            for column in tableView.tableColumns {
                tableView.removeTableColumn(column)
            }

            let lineColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(Self.lineNumberIdentifier))
            lineColumn.width = 46
            lineColumn.minWidth = 40
            lineColumn.maxWidth = 62
            tableView.addTableColumn(lineColumn)

            let keyColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(Self.keyIdentifier))
            keyColumn.width = 210
            keyColumn.minWidth = 120
            keyColumn.maxWidth = 360
            tableView.addTableColumn(keyColumn)

            let valueColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(Self.valueIdentifier))
            valueColumn.width = 360
            valueColumn.minWidth = 180
            valueColumn.maxWidth = 720
            tableView.addTableColumn(valueColumn)
        }

        private func copyText(_ text: String) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        private static func previewText(_ value: String) -> String {
            guard value.count > 240 else { return value }
            return String(value.prefix(240)) + " ..."
        }

        private static let lineNumberIdentifier = "line"
        private static let keyIdentifier = "key"
        private static let valueIdentifier = "value"
    }

    private static let rowHeight: CGFloat = 27
}

struct FileManagerStructuredPreviewHost: NSViewRepresentable {
    let document: FilePreviewStructuredDocument
    let pathFont: NSFont
    let kindFont: NSFont
    let valueFont: NSFont
    let backgroundColor: NSColor
    let pathTextColor: NSColor
    let kindTextColor: NSColor
    let valueTextColor: NSColor
    let pathBackgroundColor: NSColor
    let evenValueBackgroundColor: NSColor
    let oddValueBackgroundColor: NSColor
    let gridColor: NSColor

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay

        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = .zero
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .none
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = false
        tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        let menu = NSMenu()
        menu.delegate = context.coordinator
        tableView.menu = menu

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.apply(document: document, configuration: configuration, to: tableView, scrollView: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        context.coordinator.apply(document: document, configuration: configuration, to: tableView, scrollView: scrollView)
    }

    private var configuration: Coordinator.Configuration {
        Coordinator.Configuration(
            pathFont: pathFont,
            kindFont: kindFont,
            valueFont: valueFont,
            backgroundColor: backgroundColor,
            pathTextColor: pathTextColor,
            kindTextColor: kindTextColor,
            valueTextColor: valueTextColor,
            pathBackgroundColor: pathBackgroundColor,
            evenValueBackgroundColor: evenValueBackgroundColor,
            oddValueBackgroundColor: oddValueBackgroundColor,
            gridColor: gridColor
        )
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        struct Configuration: Equatable {
            let pathFont: NSFont
            let kindFont: NSFont
            let valueFont: NSFont
            let backgroundColor: NSColor
            let pathTextColor: NSColor
            let kindTextColor: NSColor
            let valueTextColor: NSColor
            let pathBackgroundColor: NSColor
            let evenValueBackgroundColor: NSColor
            let oddValueBackgroundColor: NSColor
            let gridColor: NSColor
        }

        weak var tableView: NSTableView?
        private var document = FilePreviewStructuredDocument(rows: [], formatLabel: "", sourceLineCount: 0)
        private var didBuildColumns = false
        private var appliedConfiguration: Configuration?
        private var contextMenuTargetRow: Int?

        @MainActor
        func apply(
            document: FilePreviewStructuredDocument,
            configuration: Configuration,
            to tableView: NSTableView,
            scrollView: NSScrollView
        ) {
            let documentChanged = self.document != document
            let configurationChanged = appliedConfiguration != configuration

            self.document = document
            appliedConfiguration = configuration
            scrollView.backgroundColor = configuration.backgroundColor
            tableView.backgroundColor = configuration.backgroundColor
            tableView.gridColor = configuration.gridColor

            if !didBuildColumns {
                rebuildColumns(in: tableView)
                didBuildColumns = true
            }
            if documentChanged || configurationChanged {
                tableView.reloadData()
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            document.rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < document.rows.count,
                  let tableColumn,
                  let configuration = appliedConfiguration else {
                return nil
            }
            let identifier = tableColumn.identifier
            let previewRow = document.rows[row]
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? FileManagerTableCellView ??
                FileManagerTableCellView(identifier: identifier)
            let text: String
            let font: NSFont
            let textColor: NSColor
            let backgroundColor: NSColor
            let leadingInset: CGFloat
            switch identifier.rawValue {
            case Self.pathIdentifier:
                text = previewRow.path
                font = configuration.pathFont
                textColor = configuration.pathTextColor
                backgroundColor = configuration.pathBackgroundColor
                leadingInset = 10 + CGFloat(min(previewRow.depth, 8)) * 16
            case Self.kindIdentifier:
                text = previewRow.kind
                font = configuration.kindFont
                textColor = configuration.kindTextColor
                backgroundColor = row.isMultiple(of: 2) ? configuration.evenValueBackgroundColor : configuration.oddValueBackgroundColor
                leadingInset = 8
            default:
                text = Self.previewText(previewRow.value.isEmpty ? " " : previewRow.value)
                font = configuration.valueFont
                textColor = configuration.valueTextColor
                backgroundColor = row.isMultiple(of: 2) ? configuration.evenValueBackgroundColor : configuration.oddValueBackgroundColor
                leadingInset = 8
            }
            cell.configure(
                text: text,
                alignment: .left,
                font: font,
                textColor: textColor,
                backgroundColor: backgroundColor,
                leadingInset: leadingInset
            )
            return cell
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let tableView else { return }
            let row = tableView.clickedRow
            guard row >= 0, row < document.rows.count else { return }
            contextMenuTargetRow = row

            let copyPath = NSMenuItem(title: fileManagerL("复制路径", "Copy Path"), action: #selector(copyPath), keyEquivalent: "")
            copyPath.target = self
            menu.addItem(copyPath)

            let copyKey = NSMenuItem(title: fileManagerL("复制键", "Copy Key"), action: #selector(copyKey), keyEquivalent: "")
            copyKey.target = self
            menu.addItem(copyKey)

            let copyValue = NSMenuItem(title: fileManagerL("复制值", "Copy Value"), action: #selector(copyValue), keyEquivalent: "")
            copyValue.target = self
            menu.addItem(copyValue)

            let copyPathAndValue = NSMenuItem(title: fileManagerL("复制路径和值", "Copy Path and Value"), action: #selector(copyPathAndValue), keyEquivalent: "")
            copyPathAndValue.target = self
            menu.addItem(copyPathAndValue)
        }

        @objc private func copyPath() {
            guard let row = contextMenuTargetRow else { return }
            copyText(document.rows[row].path)
        }

        @objc private func copyKey() {
            guard let row = contextMenuTargetRow else { return }
            copyText(document.rows[row].key)
        }

        @objc private func copyValue() {
            guard let row = contextMenuTargetRow else { return }
            copyText(document.rows[row].value)
        }

        @objc private func copyPathAndValue() {
            guard let row = contextMenuTargetRow else { return }
            let previewRow = document.rows[row]
            copyText("\(previewRow.path) = \(previewRow.value)")
        }

        @MainActor
        private func rebuildColumns(in tableView: NSTableView) {
            for column in tableView.tableColumns {
                tableView.removeTableColumn(column)
            }

            let pathColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(Self.pathIdentifier))
            pathColumn.width = 300
            pathColumn.minWidth = 180
            pathColumn.maxWidth = 560
            tableView.addTableColumn(pathColumn)

            let kindColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(Self.kindIdentifier))
            kindColumn.width = 78
            kindColumn.minWidth = 64
            kindColumn.maxWidth = 120
            tableView.addTableColumn(kindColumn)

            let valueColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(Self.valueIdentifier))
            valueColumn.width = 420
            valueColumn.minWidth = 180
            valueColumn.maxWidth = 760
            tableView.addTableColumn(valueColumn)
        }

        private func copyText(_ text: String) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        private static func previewText(_ value: String) -> String {
            guard value.count > 260 else { return value }
            return String(value.prefix(260)) + " ..."
        }

        private static let pathIdentifier = "path"
        private static let kindIdentifier = "kind"
        private static let valueIdentifier = "value"
    }

    private static let rowHeight: CGFloat = 28
}

