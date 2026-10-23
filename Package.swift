// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "ToDoApp", platforms: [.macOS(.v26)], products: [.executable(name: "ToDoApp", targets: ["ToDoApp"])], targets: [.executableTarget(name: "ToDoApp")])
