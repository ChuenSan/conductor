import CoreGraphics
import Foundation

struct WindowRecord: Codable {
    var id: Int
    var ownerPID: Int
    var ownerName: String
    var title: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

let arguments = Array(CommandLine.arguments.dropFirst())
let target = arguments.first { !$0.hasPrefix("--") } ?? "Conductor"
let firstIDOnly = arguments.contains("--first-id")
let pidFilter: Int? = {
    guard let index = arguments.firstIndex(of: "--pid"),
          arguments.indices.contains(index + 1) else {
        return nil
    }
    return Int(arguments[index + 1])
}()
let titleFilter: String? = {
    guard let index = arguments.firstIndex(of: "--title"),
          arguments.indices.contains(index + 1) else {
        return nil
    }
    return arguments[index + 1]
}()

let windowInfo = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
) as? [[String: Any]] ?? []

let records = windowInfo.compactMap { item -> WindowRecord? in
    guard let ownerName = item[kCGWindowOwnerName as String] as? String,
          ownerName.localizedStandardContains(target),
          let id = item[kCGWindowNumber as String] as? Int else {
        return nil
    }

    let ownerPID = item[kCGWindowOwnerPID as String] as? Int ?? 0
    if let pidFilter, ownerPID != pidFilter {
        return nil
    }

    let layer = item[kCGWindowLayer as String] as? Int ?? 0
    guard layer == 0 else { return nil }

    let title = item[kCGWindowName as String] as? String ?? ""
    if let titleFilter, !title.localizedStandardContains(titleFilter) {
        return nil
    }

    guard let bounds = item[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double,
          let height = bounds["Height"] as? Double,
          width >= 320,
          height >= 240 else {
        return nil
    }

    let x = bounds["X"] as? Double ?? 0
    let y = bounds["Y"] as? Double ?? 0
    return WindowRecord(
        id: id,
        ownerPID: ownerPID,
        ownerName: ownerName,
        title: title,
        x: x,
        y: y,
        width: width,
        height: height
    )
}
.sorted {
    if $0.ownerName == $1.ownerName {
        return ($0.width * $0.height) > ($1.width * $1.height)
    }
    return $0.ownerName.localizedStandardCompare($1.ownerName) == .orderedAscending
}

if firstIDOnly {
    if let id = records.first?.id {
        print(id)
    }
    exit(records.isEmpty ? 1 : 0)
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try encoder.encode(records)
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
