import Foundation

func bigEndianData(_ value: UInt32) -> Data {
    var encoded = value.bigEndian
    return Data(bytes: &encoded, count: MemoryLayout<UInt32>.size)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 3, arguments.count.isMultiple(of: 2) == false else {
    fputs("usage: make-icns output.icns type image.png [type image.png ...]\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: arguments[0])
let entries = Array(arguments.dropFirst())
var iconData = Data("icns".utf8)
iconData.append(bigEndianData(0))

for index in stride(from: 0, to: entries.count, by: 2) {
    let type = entries[index]
    guard type.utf8.count == 4 else {
        fputs("invalid ICNS entry type: \(type)\n", stderr)
        exit(2)
    }
    let imageData = try Data(contentsOf: URL(fileURLWithPath: entries[index + 1]))
    let entryLength = imageData.count + 8
    guard entryLength <= Int(UInt32.max) else {
        fputs("ICNS entry is too large\n", stderr)
        exit(2)
    }
    iconData.append(Data(type.utf8))
    iconData.append(bigEndianData(UInt32(entryLength)))
    iconData.append(imageData)
}

guard iconData.count <= Int(UInt32.max) else {
    fputs("ICNS file is too large\n", stderr)
    exit(2)
}
iconData.replaceSubrange(4..<8, with: bigEndianData(UInt32(iconData.count)))
try iconData.write(to: outputURL, options: .atomic)
