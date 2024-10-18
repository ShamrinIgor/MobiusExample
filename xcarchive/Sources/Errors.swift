struct NeitherWorkspacePathNorProjectPathAreSpecifiedError: Error, CustomStringConvertible {
    var description: String {
        "Neither \"--workspace-path\" nor \"--project-path\" are specified."
    }
}
