import Foundation
import libgit2

/// Thin Swift wrapper around the operations Minimalist needs from an
/// embedded libgit2 — replacing the `/usr/bin/git` subprocess calls that
/// App Sandbox forbids. All calls are synchronous and safe to run from
/// any single thread at a time; call sites invoke them off the main
/// thread, mirroring the old subprocess pattern.
final class GitClient {
    enum ClientError: Error, LocalizedError {
        case libgit2(String)
        var errorDescription: String? {
            if case .libgit2(let message) = self { return message }
            return nil
        }
    }

    /// One commit touching a specific file, as surfaced by `fileLog`.
    struct FileCommit {
        let sha: String
        let author: String
        let date: Date
        let subject: String
    }

    private let repo: OpaquePointer

    private init(repo: OpaquePointer) {
        self.repo = repo
    }

    deinit {
        git_repository_free(repo)
    }

    // MARK: - Library lifecycle

    /// libgit2 must be initialized once per process before any other call.
    private static let initializeOnce: Void = {
        git_libgit2_init()
    }()

    // MARK: - Opening / creating

    /// Open the repository containing `url`, searching parent directories
    /// the way `git rev-parse` does. Returns nil when there is no
    /// repository (or only a bare one, which has no work tree to show).
    static func open(containing url: URL) -> GitClient? {
        _ = initializeOnce
        var repo: OpaquePointer?
        let code = url.path.withCString { path in
            git_repository_open_ext(&repo, path, 0, nil)
        }
        guard code == 0, let opened = repo else { return nil }
        guard git_repository_is_bare(opened) == 0 else {
            git_repository_free(opened)
            return nil
        }
        return GitClient(repo: opened)
    }

    /// Open the repository exactly at `url` — no parent-directory search.
    /// Used for the private `.minimal/files` mirror, where falling back
    /// to an enclosing user repository would be actively harmful.
    static func open(at url: URL) -> GitClient? {
        _ = initializeOnce
        var repo: OpaquePointer?
        let code = url.path.withCString { path in
            git_repository_open_ext(&repo, path, GIT_REPOSITORY_OPEN_NO_SEARCH.rawValue, nil)
        }
        guard code == 0, let opened = repo else { return nil }
        return GitClient(repo: opened)
    }

    /// Absolute path of the repository's work-tree root, or nil for a
    /// bare repository.
    var workTreePath: String? {
        guard let raw = git_repository_workdir(repo) else { return nil }
        return String(cString: raw)
    }

    /// Translate an absolute file URL into a path relative to the
    /// repository root — the form libgit2's tree lookups and pathspecs
    /// expect. Returns nil when the file lies outside the work tree.
    func repoRelativePath(of url: URL) -> String? {
        guard let root = workTreePath else { return nil }
        let rootPath = URL(fileURLWithPath: root).standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else { return nil }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    /// `git init` (non-bare) at `url`, creating directories as needed.
    static func create(at url: URL) throws -> GitClient {
        _ = initializeOnce
        var repo: OpaquePointer?
        try check(url.path.withCString { path in
            git_repository_init(&repo, path, 0)
        }, "Couldn't initialize repository")
        guard let created = repo else {
            throw ClientError.libgit2("Couldn't initialize repository")
        }
        return GitClient(repo: created)
    }

    // MARK: - Branches

    /// Current branch name; short commit SHA when HEAD is detached; nil
    /// for an unborn HEAD (fresh repo with no commits) — matching
    /// `git rev-parse --abbrev-ref HEAD` as the app used it.
    func currentBranch() -> String? {
        guard git_repository_head_unborn(repo) != 1 else { return nil }
        var ref: OpaquePointer?
        guard git_repository_head(&ref, repo) == 0, let head = ref else { return nil }
        defer { git_reference_free(head) }

        if git_repository_head_detached(repo) == 1 {
            var object: OpaquePointer?
            guard git_reference_peel(&object, head, GIT_OBJECT_COMMIT) == 0,
                  let commit = object
            else { return nil }
            defer { git_object_free(commit) }
            var buf = git_buf()
            guard git_object_short_id(&buf, commit) == 0 else { return nil }
            defer { git_buf_dispose(&buf) }
            return buf.ptr.map { String(cString: $0) }
        }

        guard let short = git_reference_shorthand(head) else { return nil }
        return String(cString: short)
    }

    func localBranches() -> [String] {
        var iterator: OpaquePointer?
        guard git_branch_iterator_new(&iterator, repo, GIT_BRANCH_LOCAL) == 0,
              let iter = iterator
        else { return [] }
        defer { git_branch_iterator_free(iter) }

        var names: [String] = []
        var ref: OpaquePointer?
        var kind = GIT_BRANCH_LOCAL
        while git_branch_next(&ref, &kind, iter) == 0 {
            guard let branch = ref else { continue }
            var name: UnsafePointer<CChar>?
            if git_branch_name(&name, branch) == 0, let n = name {
                names.append(String(cString: n))
            }
            git_reference_free(branch)
        }
        return names
    }

    /// `git checkout <branch>` — safe checkout (refuses to clobber local
    /// modifications, like the CLI), then repoints HEAD.
    func checkout(branch name: String) throws {
        var ref: OpaquePointer?
        try Self.check(name.withCString { n in
            git_branch_lookup(&ref, repo, n, GIT_BRANCH_LOCAL)
        }, "No local branch named '\(name)'")
        guard let branch = ref else { throw ClientError.libgit2("No local branch named '\(name)'") }
        defer { git_reference_free(branch) }

        var object: OpaquePointer?
        try Self.check(git_reference_peel(&object, branch, GIT_OBJECT_COMMIT),
                       "Couldn't resolve branch '\(name)'")
        guard let commit = object else { throw ClientError.libgit2("Couldn't resolve branch '\(name)'") }
        defer { git_object_free(commit) }

        var options = git_checkout_options()
        git_checkout_options_init(&options, UInt32(GIT_CHECKOUT_OPTIONS_VERSION))
        options.checkout_strategy = GIT_CHECKOUT_SAFE.rawValue

        try Self.check(git_checkout_tree(repo, commit, &options),
                       "Checkout would overwrite local changes")

        guard let fullName = git_reference_name(branch) else {
            throw ClientError.libgit2("Couldn't resolve branch '\(name)'")
        }
        try Self.check(git_repository_set_head(repo, fullName),
                       "Couldn't switch HEAD to '\(name)'")
    }

    /// `git checkout -b <name>` — create a branch at HEAD and switch to it.
    func createBranch(named name: String) throws {
        var headObject: OpaquePointer?
        try Self.check(git_revparse_single(&headObject, repo, "HEAD"),
                       "Repository has no commits yet")
        guard let head = headObject else { throw ClientError.libgit2("Repository has no commits yet") }
        defer { git_object_free(head) }

        var ref: OpaquePointer?
        try Self.check(name.withCString { n in
            git_branch_create(&ref, repo, n, head, 0)
        }, "Couldn't create branch '\(name)'")
        guard let branch = ref else { throw ClientError.libgit2("Couldn't create branch '\(name)'") }
        defer { git_reference_free(branch) }

        guard let fullName = git_reference_name(branch) else {
            throw ClientError.libgit2("Couldn't create branch '\(name)'")
        }
        // The new branch points at HEAD's commit, so the work tree is
        // already correct — only HEAD needs to move.
        try Self.check(git_repository_set_head(repo, fullName),
                       "Couldn't switch HEAD to '\(name)'")
    }

    // MARK: - Staging and committing

    /// `git add -- <path>` (path relative to the repo root).
    func stage(relativePath: String) throws {
        var indexPointer: OpaquePointer?
        try Self.check(git_repository_index(&indexPointer, repo), "Couldn't open index")
        guard let index = indexPointer else { throw ClientError.libgit2("Couldn't open index") }
        defer { git_index_free(index) }

        try Self.check(relativePath.withCString { p in
            git_index_add_bypath(index, p)
        }, "Couldn't stage '\(relativePath)'")
        try Self.check(git_index_write(index), "Couldn't write index")
    }

    /// `git commit --allow-empty -m <message>` with an explicit identity
    /// (no dependence on user-level git config, which doesn't exist in
    /// the sandbox container).
    func commit(message: String, authorName: String, authorEmail: String) throws {
        var indexPointer: OpaquePointer?
        try Self.check(git_repository_index(&indexPointer, repo), "Couldn't open index")
        guard let index = indexPointer else { throw ClientError.libgit2("Couldn't open index") }
        defer { git_index_free(index) }

        var treeOid = git_oid()
        try Self.check(git_index_write_tree(&treeOid, index), "Couldn't write tree")

        var treePointer: OpaquePointer?
        try Self.check(git_tree_lookup(&treePointer, repo, &treeOid), "Couldn't read tree")
        guard let tree = treePointer else { throw ClientError.libgit2("Couldn't read tree") }
        defer { git_tree_free(tree) }

        var signature: UnsafeMutablePointer<git_signature>?
        try Self.check(git_signature_now(&signature, authorName, authorEmail),
                       "Couldn't create signature")
        defer { git_signature_free(signature) }

        var parent: OpaquePointer?
        if git_repository_head_unborn(repo) != 1 {
            try Self.check(git_revparse_single(&parent, repo, "HEAD"), "Couldn't resolve HEAD")
        }
        defer { if let parent { git_object_free(parent) } }

        var commitOid = git_oid()
        var parents: [OpaquePointer?] = parent.map { [$0] } ?? []
        try Self.check(parents.withUnsafeMutableBufferPointer { buffer in
            git_commit_create(
                &commitOid, repo, "HEAD",
                signature, signature,
                nil, message,
                tree,
                buffer.count, buffer.baseAddress
            )
        }, "Couldn't create commit")
    }

    // MARK: - History

    /// `git log -n <limit> -- <path>`: walk from HEAD, newest first,
    /// keeping commits where the file's blob differs from the first
    /// parent (or appears/disappears). `scanCap` bounds the walk on huge
    /// repositories.
    func fileLog(relativePath: String, limit: Int, scanCap: Int = 10_000) -> [FileCommit] {
        var walkPointer: OpaquePointer?
        guard git_revwalk_new(&walkPointer, repo) == 0, let walk = walkPointer else { return [] }
        defer { git_revwalk_free(walk) }
        // Time-ordered like `git log`, with the topological guarantee
        // that a child always precedes its parent — plain TIME sorting
        // can invert commits that share the same one-second timestamp.
        git_revwalk_sorting(walk, GIT_SORT_TOPOLOGICAL.rawValue | GIT_SORT_TIME.rawValue)
        guard git_revwalk_push_head(walk) == 0 else { return [] }

        var results: [FileCommit] = []
        var oid = git_oid()
        var scanned = 0

        while results.count < limit, scanned < scanCap, git_revwalk_next(&oid, walk) == 0 {
            scanned += 1
            var commitPointer: OpaquePointer?
            guard git_commit_lookup(&commitPointer, repo, &oid) == 0,
                  let commit = commitPointer
            else { continue }
            defer { git_commit_free(commit) }

            let entryOid = treeEntryOid(ofCommit: commit, at: relativePath)
            let parentEntryOid: git_oid? = {
                guard git_commit_parentcount(commit) > 0 else { return nil }
                var parentPointer: OpaquePointer?
                guard git_commit_parent(&parentPointer, commit, 0) == 0,
                      let parent = parentPointer
                else { return nil }
                defer { git_commit_free(parent) }
                return treeEntryOid(ofCommit: parent, at: relativePath)
            }()

            let changed: Bool
            switch (entryOid, parentEntryOid) {
            case (nil, nil):
                changed = false
            case (let a?, let b?):
                changed = !oidsEqual(a, b)
            default:
                changed = true
            }
            guard changed else { continue }

            results.append(FileCommit(
                sha: Self.hexString(of: &oid),
                author: git_commit_author(commit).map { String(cString: $0.pointee.name) } ?? "",
                date: Date(timeIntervalSince1970: TimeInterval(git_commit_time(commit))),
                subject: git_commit_summary(commit).map { String(cString: $0) } ?? ""
            ))
        }
        return results
    }

    /// `git show <sha>:<path>` — the file's content at that commit.
    func blobContent(commitSHA: String, relativePath: String) -> String? {
        guard let commit = revparseCommit(commitSHA) else { return nil }
        defer { git_object_free(commit) }

        var treePointer: OpaquePointer?
        guard git_commit_tree(&treePointer, commit) == 0, let tree = treePointer else { return nil }
        defer { git_tree_free(tree) }

        var entryPointer: OpaquePointer?
        guard relativePath.withCString({ p in
            git_tree_entry_bypath(&entryPointer, tree, p)
        }) == 0, let entry = entryPointer else { return nil }
        defer { git_tree_entry_free(entry) }

        var blobPointer: OpaquePointer?
        guard git_blob_lookup(&blobPointer, repo, git_tree_entry_id(entry)) == 0,
              let blob = blobPointer
        else { return nil }
        defer { git_blob_free(blob) }

        let size = Int(git_blob_rawsize(blob))
        guard size > 0, let raw = git_blob_rawcontent(blob) else { return "" }
        let data = Data(bytes: raw, count: size)
        return String(data: data, encoding: .utf8)
    }

    /// `git show <sha> -- <path>` — the unified diff this commit applied
    /// to one file (against its first parent; against the empty tree for
    /// root commits).
    func patch(commitSHA: String, relativePath: String) -> String? {
        guard let commit = revparseCommit(commitSHA) else { return nil }
        defer { git_object_free(commit) }

        var newTreePointer: OpaquePointer?
        guard git_commit_tree(&newTreePointer, commit) == 0, let newTree = newTreePointer else { return nil }
        defer { git_tree_free(newTree) }

        var oldTree: OpaquePointer?
        if git_commit_parentcount(commit) > 0 {
            var parentPointer: OpaquePointer?
            if git_commit_parent(&parentPointer, commit, 0) == 0, let parent = parentPointer {
                defer { git_commit_free(parent) }
                var oldTreePointer: OpaquePointer?
                if git_commit_tree(&oldTreePointer, parent) == 0 {
                    oldTree = oldTreePointer
                }
            }
        }
        defer { if let oldTree { git_tree_free(oldTree) } }

        var result: String?
        relativePath.withCString { path in
            var mutablePath: UnsafeMutablePointer<CChar>? = UnsafeMutablePointer(mutating: path)
            withUnsafeMutablePointer(to: &mutablePath) { pathArray in
                var options = git_diff_options()
                git_diff_options_init(&options, UInt32(GIT_DIFF_OPTIONS_VERSION))
                options.pathspec = git_strarray(strings: pathArray, count: 1)
                options.context_lines = 3

                var diffPointer: OpaquePointer?
                guard git_diff_tree_to_tree(&diffPointer, repo, oldTree, newTree, &options) == 0,
                      let diff = diffPointer
                else { return }
                defer { git_diff_free(diff) }

                guard git_diff_num_deltas(diff) > 0 else {
                    result = ""
                    return
                }
                var patchPointer: OpaquePointer?
                guard git_patch_from_diff(&patchPointer, diff, 0) == 0,
                      let patch = patchPointer
                else { return }
                defer { git_patch_free(patch) }

                var buf = git_buf()
                guard git_patch_to_buf(&buf, patch) == 0 else { return }
                defer { git_buf_dispose(&buf) }
                result = buf.ptr.map { String(cString: $0) }
            }
        }
        return result
    }

    // MARK: - Helpers

    private func revparseCommit(_ sha: String) -> OpaquePointer? {
        var objectPointer: OpaquePointer?
        guard sha.withCString({ s in
            git_revparse_single(&objectPointer, repo, s)
        }) == 0, let object = objectPointer else { return nil }
        guard git_object_type(object) == GIT_OBJECT_COMMIT else {
            git_object_free(object)
            return nil
        }
        return object
    }

    /// OID of the tree entry at `path` in the commit's tree, or nil when
    /// the path doesn't exist there.
    private func treeEntryOid(ofCommit commit: OpaquePointer, at path: String) -> git_oid? {
        var treePointer: OpaquePointer?
        guard git_commit_tree(&treePointer, commit) == 0, let tree = treePointer else { return nil }
        defer { git_tree_free(tree) }
        var entryPointer: OpaquePointer?
        guard path.withCString({ p in
            git_tree_entry_bypath(&entryPointer, tree, p)
        }) == 0, let entry = entryPointer else { return nil }
        defer { git_tree_entry_free(entry) }
        return git_tree_entry_id(entry)?.pointee
    }

    private func oidsEqual(_ a: git_oid, _ b: git_oid) -> Bool {
        var a = a
        var b = b
        return git_oid_cmp(&a, &b) == 0
    }

    private static func hexString(of oid: inout git_oid) -> String {
        var chars = [CChar](repeating: 0, count: Int(GIT_OID_MAX_HEXSIZE) + 1)
        git_oid_fmt(&chars, &oid)
        return String(cString: chars)
    }

    @discardableResult
    private static func check(_ code: Int32, _ fallback: String) throws -> Int32 {
        guard code >= 0 else {
            let message: String
            if let last = git_error_last(), let raw = last.pointee.message {
                message = String(cString: raw)
            } else {
                message = fallback
            }
            throw ClientError.libgit2(message)
        }
        return code
    }
}
