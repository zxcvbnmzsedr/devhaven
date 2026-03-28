import XCTest
@testable import DevHavenCore

final class WorkspaceProjectTreeDisplayTests: XCTestCase {
    func testDisplayTreeCompactsJavaPackagesBelowSourceRoot() throws {
        let projectRootPath = "/repo"
        let srcPath = projectRootPath + "/src"
        let mainPath = srcPath + "/main"
        let javaPath = mainPath + "/java"
        let resourcesPath = mainPath + "/resources"
        let comPath = javaPath + "/com"
        let examplePath = comPath + "/example"
        let servicePath = examplePath + "/service"
        let appFilePath = servicePath + "/App.java"

        let state = WorkspaceProjectTreeState(
            rootProjectPath: projectRootPath,
            rootNodes: [
                directoryNode(path: srcPath, parentPath: projectRootPath, name: "src"),
            ],
            childrenByDirectoryPath: [
                projectRootPath: [
                    directoryNode(path: srcPath, parentPath: projectRootPath, name: "src"),
                ],
                srcPath: [
                    directoryNode(path: mainPath, parentPath: srcPath, name: "main"),
                ],
                mainPath: [
                    directoryNode(path: javaPath, parentPath: mainPath, name: "java"),
                    directoryNode(path: resourcesPath, parentPath: mainPath, name: "resources"),
                ],
                javaPath: [
                    directoryNode(path: comPath, parentPath: javaPath, name: "com"),
                ],
                comPath: [
                    directoryNode(path: examplePath, parentPath: comPath, name: "example"),
                ],
                examplePath: [
                    directoryNode(path: servicePath, parentPath: examplePath, name: "service"),
                ],
                servicePath: [
                    fileNode(path: appFilePath, parentPath: servicePath, name: "App.java"),
                ],
            ]
        )

        let javaDisplayNode = try XCTUnwrap(findDisplayNode(in: state.displayRootNodes, path: javaPath))
        XCTAssertEqual(javaDisplayNode.children.map(\.name), ["com.example.service"])

        let compactedNode = try XCTUnwrap(javaDisplayNode.children.first)
        XCTAssertEqual(compactedNode.path, servicePath)
        XCTAssertEqual(compactedNode.compactedDirectoryPaths, [comPath, examplePath, servicePath])
        XCTAssertEqual(compactedNode.children.map(\.name), ["App.java"])
    }

    func testDisplayTreeDoesNotCompactNonJavaDirectoriesOrDirectoryWithVisibleFiles() throws {
        let projectRootPath = "/repo"
        let srcPath = projectRootPath + "/src"
        let mainPath = srcPath + "/main"
        let javaPath = mainPath + "/java"
        let resourcesPath = mainPath + "/resources"
        let comPath = javaPath + "/com"
        let examplePath = comPath + "/example"
        let javaFilePath = comPath + "/package-info.java"
        let resourcesComPath = resourcesPath + "/com"
        let resourcesExamplePath = resourcesComPath + "/example"

        let state = WorkspaceProjectTreeState(
            rootProjectPath: projectRootPath,
            rootNodes: [
                directoryNode(path: srcPath, parentPath: projectRootPath, name: "src"),
            ],
            childrenByDirectoryPath: [
                projectRootPath: [
                    directoryNode(path: srcPath, parentPath: projectRootPath, name: "src"),
                ],
                srcPath: [
                    directoryNode(path: mainPath, parentPath: srcPath, name: "main"),
                ],
                mainPath: [
                    directoryNode(path: javaPath, parentPath: mainPath, name: "java"),
                    directoryNode(path: resourcesPath, parentPath: mainPath, name: "resources"),
                ],
                javaPath: [
                    directoryNode(path: comPath, parentPath: javaPath, name: "com"),
                ],
                comPath: [
                    directoryNode(path: examplePath, parentPath: comPath, name: "example"),
                    fileNode(path: javaFilePath, parentPath: comPath, name: "package-info.java"),
                ],
                resourcesPath: [
                    directoryNode(path: resourcesComPath, parentPath: resourcesPath, name: "com"),
                ],
                resourcesComPath: [
                    directoryNode(path: resourcesExamplePath, parentPath: resourcesComPath, name: "example"),
                ],
            ]
        )

        let javaDisplayNode = try XCTUnwrap(findDisplayNode(in: state.displayRootNodes, path: javaPath))
        XCTAssertEqual(javaDisplayNode.children.map(\.name), ["com"])

        let resourcesDisplayNode = try XCTUnwrap(findDisplayNode(in: state.displayRootNodes, path: resourcesPath))
        XCTAssertEqual(resourcesDisplayNode.children.map(\.name), ["com"])
    }

    func testCanonicalizedForDisplayMapsSelectionAndExpansionToCompactedDirectory() throws {
        let projectRootPath = "/repo"
        let javaPath = projectRootPath + "/src/main/java"
        let comPath = javaPath + "/com"
        let examplePath = comPath + "/example"
        let servicePath = examplePath + "/service"

        let state = WorkspaceProjectTreeState(
            rootProjectPath: projectRootPath,
            rootNodes: [
                directoryNode(path: javaPath, parentPath: projectRootPath, name: "java"),
            ],
            childrenByDirectoryPath: [
                projectRootPath: [
                    directoryNode(path: javaPath, parentPath: projectRootPath, name: "java"),
                ],
                javaPath: [
                    directoryNode(path: comPath, parentPath: javaPath, name: "com"),
                ],
                comPath: [
                    directoryNode(path: examplePath, parentPath: comPath, name: "example"),
                ],
                examplePath: [
                    directoryNode(path: servicePath, parentPath: examplePath, name: "service"),
                ],
            ],
            expandedDirectoryPaths: [comPath, examplePath],
            selectedPath: examplePath
        )

        let canonicalState = state.canonicalizedForDisplay()

        XCTAssertEqual(canonicalState.selectedPath, servicePath)
        XCTAssertEqual(canonicalState.expandedDirectoryPaths, [servicePath])
    }

    func testDisplayTreeCompactsJavaPackagesInsideNestedModuleSourceRoot() throws {
        let projectRootPath = "/repo"
        let modulePath = projectRootPath + "/whale-module-ai"
        let srcPath = modulePath + "/src"
        let mainPath = srcPath + "/main"
        let javaPath = mainPath + "/java"
        let comPath = javaPath + "/com"
        let whalePath = comPath + "/whale"
        let serverPath = whalePath + "/server"
        let modulePackagePath = serverPath + "/module"
        let aiPath = modulePackagePath + "/ai"
        let appFilePath = aiPath + "/AiApplication.java"

        let state = WorkspaceProjectTreeState(
            rootProjectPath: projectRootPath,
            rootNodes: [
                directoryNode(path: modulePath, parentPath: projectRootPath, name: "whale-module-ai"),
            ],
            childrenByDirectoryPath: [
                projectRootPath: [
                    directoryNode(path: modulePath, parentPath: projectRootPath, name: "whale-module-ai"),
                ],
                modulePath: [
                    directoryNode(path: srcPath, parentPath: modulePath, name: "src"),
                ],
                srcPath: [
                    directoryNode(path: mainPath, parentPath: srcPath, name: "main"),
                ],
                mainPath: [
                    directoryNode(path: javaPath, parentPath: mainPath, name: "java"),
                ],
                javaPath: [
                    directoryNode(path: comPath, parentPath: javaPath, name: "com"),
                ],
                comPath: [
                    directoryNode(path: whalePath, parentPath: comPath, name: "whale"),
                ],
                whalePath: [
                    directoryNode(path: serverPath, parentPath: whalePath, name: "server"),
                ],
                serverPath: [
                    directoryNode(path: modulePackagePath, parentPath: serverPath, name: "module"),
                ],
                modulePackagePath: [
                    directoryNode(path: aiPath, parentPath: modulePackagePath, name: "ai"),
                ],
                aiPath: [
                    fileNode(path: appFilePath, parentPath: aiPath, name: "AiApplication.java"),
                ],
            ]
        )

        let javaDisplayNode = try XCTUnwrap(findDisplayNode(in: state.displayRootNodes, path: javaPath))
        XCTAssertEqual(javaDisplayNode.children.map(\.name), ["com.whale.server.module.ai"])
    }
}

private func directoryNode(path: String, parentPath: String?, name: String) -> WorkspaceProjectTreeNode {
    WorkspaceProjectTreeNode(
        path: path,
        parentPath: parentPath,
        name: name,
        kind: .directory,
        isHidden: false
    )
}

private func fileNode(path: String, parentPath: String?, name: String) -> WorkspaceProjectTreeNode {
    WorkspaceProjectTreeNode(
        path: path,
        parentPath: parentPath,
        name: name,
        kind: .file,
        isHidden: false
    )
}

private func findDisplayNode(
    in nodes: [WorkspaceProjectTreeDisplayNode],
    path: String
) -> WorkspaceProjectTreeDisplayNode? {
    let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
    for node in nodes {
        if URL(fileURLWithPath: node.path).standardizedFileURL.path == normalizedPath {
            return node
        }
        if let child = findDisplayNode(in: node.children, path: normalizedPath) {
            return child
        }
    }
    return nil
}
