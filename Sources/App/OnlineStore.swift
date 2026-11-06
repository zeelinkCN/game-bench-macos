import CryptoKit
import Foundation
import SwiftUI

struct StoreCollection: Codable, Identifiable {
    var id: String
    var title: String
    var description: String
    var gameIDs: [String]
}

struct StoreManifest: Codable {
    var schemaVersion: Int
    var libraryVersion: String
    var title: String
    var catalog: String
    var contentBaseURL: String
    var collections: [StoreCollection]
}

@MainActor final class OnlineStore: ObservableObject {
    @Published var manifest: StoreManifest?
    @Published var games=[Game]()
    @Published var loading=false
    @Published var error: String?
    @Published var installing=Set<String>()
    @Published var progress: String?
    private let manifestURL=URL(string:ProcessInfo.processInfo.environment["GAMEBENCH_STORE_URL"] ?? "https://raw.githubusercontent.com/zeelinkCN/game-bench-library/main/store.json")!
    private var baseURL: URL?

    func refresh() async {
        guard !loading else { return }
        loading=true; error=nil
        do {
            let manifestData=try await fetch(url:manifestURL,repositoryPath:"store.json")
            let decoded=try JSONDecoder().decode(StoreManifest.self,from:manifestData)
            guard decoded.schemaVersion==1,let base=URL(string:decoded.contentBaseURL) else { throw LibraryFailure.message("线上目录版本暂不支持") }
            let catalogURL=base.appendingPathComponent(decoded.catalog)
            let catalogData=try await fetch(url:catalogURL,repositoryPath:decoded.catalog)
            manifest=decoded; baseURL=base; games=try JSONDecoder().decode([Game].self,from:catalogData)
        } catch {
            self.error="暂时无法读取游戏市场：\(error.localizedDescription)"
        }
        loading=false
    }

    func install(_ game: Game, into library: GameLibrary) async {
        guard !installing.contains(game.id),!library.games.contains(where:{ $0.id==game.id }),let base=baseURL else { return }
        installing.insert(game.id); error=nil
        do {
            let rom=try await fetch(url:base.appendingPathComponent(game.filename),repositoryPath:game.filename)
            var coverData: Data?
            if let cover=game.cover { coverData=try? await fetch(url:base.appendingPathComponent(cover),repositoryPath:cover) }
            try library.installStoreGame(game,romData:rom,coverData:coverData)
            progress="已安装《\(game.displayTitle)》"
        } catch { self.error="安装《\(game.displayTitle)》失败：\(error.localizedDescription)" }
        installing.remove(game.id)
    }

    func install(_ collection: StoreCollection, into library: GameLibrary) async {
        let wanted=Set(collection.gameIDs)
        let pending=games.filter { game in
            wanted.contains(game.id) && !library.games.contains(where:{ $0.id==game.id })
        }
        for (index,game) in pending.enumerated() {
            progress="正在安装 \(collection.title) · \(index+1)/\(pending.count)"
            await install(game,into:library)
        }
        progress=pending.isEmpty ? "这个合集已经全部安装" : "\(collection.title)安装完成"
    }

    func coverURL(_ game: Game) -> URL? { game.cover.flatMap { baseURL?.appendingPathComponent($0) } }

    private func fetch(url: URL,repositoryPath: String) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf:url) }
        do {
            var request=URLRequest(url:url); request.cachePolicy = .reloadRevalidatingCacheData
            let (data,response)=try await URLSession.shared.data(for:request)
            if let http=response as? HTTPURLResponse,200..<300 ~= http.statusCode { return data }
        } catch { }
        return try await privateGitHub(path:repositoryPath)
    }

    private func privateGitHub(path: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos:.utility).async {
                let candidates=[FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/gh").path,"/opt/homebrew/bin/gh","/usr/local/bin/gh"]
                guard let executable=candidates.first(where:{ FileManager.default.isExecutableFile(atPath:$0) }) else { continuation.resume(throwing:LibraryFailure.message("资源仓库仍为 Private；公开后可直接访问，或先安装并登录 GitHub CLI")); return }
                let process=Process(); process.executableURL=URL(fileURLWithPath:executable)
                process.arguments=["api","repos/zeelinkCN/game-bench-library/contents/"+path,"-H","Accept: application/vnd.github.raw+json"]
                let output=Pipe(); process.standardOutput=output; process.standardError=FileHandle.nullDevice
                do {
                    try process.run(); let data=output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                    guard process.terminationStatus==0,!data.isEmpty else { throw LibraryFailure.message("GitHub 私有仓库读取失败") }
                    continuation.resume(returning:data)
                } catch { continuation.resume(throwing:error) }
            }
        }
    }
}

struct OnlineStoreView: View {
    @ObservedObject var store: OnlineStore
    @ObservedObject var library: GameLibrary
    var search: String
    @State private var collectionID="childhood"
    private var collection: StoreCollection? { store.manifest?.collections.first { $0.id==collectionID } }
    private var visible: [Game] {
        let wanted=collection.map { Set($0.gameIDs) }
        return store.games.filter { (wanted == nil || wanted!.contains($0.id)) && $0.matchesSearch(search) }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {
                VStack(alignment:.leading,spacing:5) { Text("游戏市场").font(.system(size:20,weight:.semibold)); Text("按单款或系列安装 · 下载后校验 SHA-256").font(.system(size:11)).foregroundStyle(Palette.muted) }
                Spacer()
                if let collection { Button("安装本合集（\(visible.filter { game in !library.games.contains(where:{ $0.id==game.id }) }.count)）") { Task { await store.install(collection,into:library) } }.buttonStyle(.borderedProminent).tint(Palette.accent).foregroundStyle(.black) }
                Button("刷新") { Task { await store.refresh() } }.buttonStyle(.bordered)
            }
            if let message=store.error { Text(message).font(.system(size:12)).foregroundStyle(.orange).padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.orange.opacity(0.08),in:RoundedRectangle(cornerRadius:9)) }
            if let progress=store.progress { Text(progress).font(.system(size:12)).foregroundStyle(Palette.accent) }
            if let manifest=store.manifest {
                ScrollView(.horizontal,showsIndicators:false) { HStack { ForEach(manifest.collections) { item in Button(item.title) { collectionID=item.id }.buttonStyle(.plain).padding(.horizontal,13).padding(.vertical,9).background(collectionID==item.id ? Palette.accent.opacity(0.18) : Palette.tile,in:Capsule()).contentShape(Capsule()) } } }
            }
            if store.loading { ProgressView("正在读取线上游戏目录…").frame(maxWidth:.infinity).padding(.vertical,80) }
            else if !visible.isEmpty {
                LazyVGrid(columns:[GridItem(.adaptive(minimum:190),spacing:18)],spacing:20) {
                    ForEach(visible) { game in
                        VStack(alignment:.leading,spacing:10) {
                            AsyncImage(url:store.coverURL(game)) { phase in
                                if let image=phase.image { image.resizable().interpolation(.none).scaledToFill() }
                                else { RetroArt(style:game.system,seed:game.title) }
                            }.frame(height:130).frame(maxWidth:.infinity).clipped().clipShape(RoundedRectangle(cornerRadius:10))
                            Text(game.displayTitle).font(.system(size:13,weight:.medium)).lineLimit(1)
                            let installed=library.games.contains(where:{ $0.id==game.id })
                            Button(installed ? "已安装" : (store.installing.contains(game.id) ? "安装中…" : "安装游戏")) { Task { await store.install(game,into:library) } }.buttonStyle(.bordered).frame(maxWidth:.infinity).disabled(installed || store.installing.contains(game.id))
                        }.padding(12).background(Palette.tile,in:RoundedRectangle(cornerRadius:12))
                    }
                }
            } else if store.error==nil { Text("线上目录尚未载入").foregroundStyle(Palette.muted).frame(maxWidth:.infinity).padding(.vertical,80) }
        }.task { if store.manifest==nil { await store.refresh() } }
    }
}
