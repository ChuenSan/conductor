import Foundation

struct FileWorkspaceCoordinator {
    private(set) var tabs: [ConductorWorkspaceFileTab] = []
    private(set) var dirtyTabIDs: Set<String> = []
    private(set) var externallyChangedTabIDs: Set<String> = []
    private(set) var selectedContentTabID: ConductorWorkspaceContentTabID?

    init(
        tabs: [ConductorWorkspaceFileTab] = [],
        dirtyTabIDs: Set<String> = [],
        externallyChangedTabIDs: Set<String> = [],
        selectedContentTabID: ConductorWorkspaceContentTabID? = nil
    ) {
        self.tabs = tabs
        self.dirtyTabIDs = dirtyTabIDs
        self.externallyChangedTabIDs = externallyChangedTabIDs
        self.selectedContentTabID = selectedContentTabID
    }

    mutating func openFile(_ fileURL: URL, rootURL: URL) {
        let tab = ConductorWorkspaceFileTab(fileURL: fileURL, rootURL: rootURL)
        tabs = [tab]
        dirtyTabIDs.formIntersection([tab.id])
        externallyChangedTabIDs.formIntersection([tab.id])
        selectedContentTabID = .file(tab.id)
    }

    mutating func setDirty(_ tabID: String, isDirty: Bool) {
        if isDirty {
            dirtyTabIDs.insert(tabID)
        } else {
            dirtyTabIDs.remove(tabID)
        }
    }
}
