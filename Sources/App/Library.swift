import AppKit
import CryptoKit
import Foundation
import SwiftUI

enum GameSystem: String, Codable, CaseIterable, Identifiable {
    case nes, snes, arcade, gameboy, sega
    var id: String { rawValue }
    var title: String {
        switch self { case .nes: return "红白机"; case .snes: return "超级任天堂"; case .arcade: return "街机"; case .gameboy: return "Game Boy"; case .sega: return "世嘉" }
    }
    var subtitle: String {
        switch self { case .nes: return "FC / NES"; case .snes: return "SFC / SNES"; case .arcade: return "ARCADE · FBNeo"; case .gameboy: return "GB / GBC"; case .sega: return "MD / SMS / GG" }
    }
    var core: String {
        switch self { case .nes: return "fceumm"; case .snes: return "snes9x"; case .arcade: return "fbneo"; case .gameboy: return "gambatte"; case .sega: return "genesis_plus_gx" }
    }
    var color: Color {
        switch self { case .nes: return Color(red:0.78,green:0.92,blue:0.49); case .snes: return Color(red:0.70,green:0.63,blue:0.98); case .arcade: return Color(red:1,green:0.66,blue:0.41); case .gameboy: return Color(red:0.41,green:0.82,blue:0.72); case .sega: return Color(red:0.48,green:0.71,blue:0.99) }
    }
    static func detect(_ ext: String) -> GameSystem? {
        switch ext.lowercased() {
        case "nes", "fds": return .nes
        case "sfc", "smc": return .snes
        case "gb", "gbc": return .gameboy
        case "md", "gen", "bin", "sms", "gg": return .sega
        case "zip": return .arcade
        default: return nil
        }
    }
}

struct Game: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var system: GameSystem
    var filename: String
    var favorite = false
    var addedAt = Date()
    var lastPlayed: Date?
    var playCount = 0
    var isDemo = false
    var bundled: Bool?
    var source: String?
    var author: String?
    var cover: String?
    var chineseTitle: String?
    var language: String?
    var languageEvidence: String?
    var seriesEntryID: String?
    var featuredRank: Int?
    var compatibilityNote: String?
    var sha256: String?
    var isBundled: Bool { bundled == true }
    var displayTitle: String { chineseTitle ?? ChineseNames.titles[title] ?? SeriesCatalog.entry(for:self)?.title ?? title }
    var hasChineseLabel: Bool { language == "zh-Hans" || language == "zh-Hant" || language == "zh-label" || language == "zh-patch" }
    var languageLabel: String {
        if language == "zh-Hans" { return "简体中文" }
        if language == "zh-Hant" { return "繁体中文" }
        if language == "zh-label" { return "中文 · 文件名标注，未校验" }
        if language == "zh-patch" { return "汉化补丁副本 · 未人工验证" }
        return "原版 · 游戏内语言未核实"
    }
    func matchesSearch(_ query: String) -> Bool { query.isEmpty || [title,displayTitle,filename,system.title].contains { $0.localizedCaseInsensitiveContains(query) } }
    mutating func recognizeEdition() {
        if seriesEntryID == nil { seriesEntryID=SeriesCatalog.identify(title:title,system:system) }
        if language == nil {
            let label=title.lowercased()
            if ["汉化","漢化","中文版","简体","繁体","繁體","[chs]","[cht]","(chinese)","(zh)","(ch)","[ch]","zh-hans","zh-hant"].contains(where:label.contains) {
                language="zh-label"; languageEvidence="文件名标注；尚未通过内容校验"
            }
        }
    }
    static let demo = Game(id:"star-pilot-demo-v1", title:"星光试航", system:.nes, filename:"StarPilot.nes", isDemo:true)
}

struct LibraryDocument: Codable {
    var version = 1
    var games: [Game]
}

enum LibraryFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

enum LibraryPaths {
    static var root: URL {
        if let custom = ProcessInfo.processInfo.environment["GAMEBENCH_DATA_DIR"] { return URL(fileURLWithPath:custom) }
        return FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("GameBench", isDirectory:true)
    }
    static var roms: URL { root.appendingPathComponent("ROMs",isDirectory:true) }
    static var saves: URL { root.appendingPathComponent("Saves",isDirectory:true) }
    static var covers: URL { root.appendingPathComponent("Covers",isDirectory:true) }
    static var bios: URL { root.appendingPathComponent("BIOS",isDirectory:true) }
    static var index: URL { root.appendingPathComponent("library.json") }
    static func prepare() throws {
        for dir in [root,roms,saves,bios,covers] { try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true) }
    }
    static func rom(_ game: Game) -> URL {
        if game.isDemo { return Bundle.main.resourceURL!.appendingPathComponent("Demo/StarPilot.nes") }
        if game.isBundled { return Bundle.main.resourceURL!.appendingPathComponent("Games/"+game.filename) }
        return roms.appendingPathComponent(game.filename)
    }
    static func state(_ game: Game) -> URL { saves.appendingPathComponent(game.id+".state") }
    static func cover(_ game: Game) -> URL? {
        guard let cover=game.cover else { return nil }
        if game.isBundled { return Bundle.main.resourceURL?.appendingPathComponent("Games/"+cover) }
        return covers.appendingPathComponent(cover)
    }
}

struct ImportReport {
    var added = [Game]()
    var duplicates = 0
    var errors = [String]()
    var summary: String {
        var s="已导入 \(added.count) 款游戏"
        if duplicates>0 { s += "，跳过 \(duplicates) 个重复文件" }
        if !errors.isEmpty { s += "。\(errors.count) 个文件未导入：" + errors.prefix(3).joined(separator:"；") }
        return s
    }
}

enum ROMImporter {
    static func importFiles(_ urls: [URL], existing: [Game]) -> ImportReport {
        var report=ImportReport()
        var known=Set(existing.map(\.id))
        let fm=FileManager.default
        var files=[URL]()
        for url in urls {
            var isDir: ObjCBool=false
            guard fm.fileExists(atPath:url.path,isDirectory:&isDir) else { report.errors.append("\(url.lastPathComponent)：文件不存在"); continue }
            if isDir.boolValue {
                let enumerator=fm.enumerator(at:url,includingPropertiesForKeys:[.isRegularFileKey],options:[.skipsHiddenFiles,.skipsPackageDescendants])
                while let f=enumerator?.nextObject() as? URL {
                    if GameSystem.detect(f.pathExtension) != nil, (try? f.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true { files.append(f) }
                }
            } else if GameSystem.detect(url.pathExtension) != nil { files.append(url) }
            else { report.errors.append("\(url.lastPathComponent)：不支持的格式") }
        }
        for url in files.sorted(by: { $0.path<$1.path }) {
            do {
                let (data, ext, title, system)=try readROM(url)
                let digest=SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
                // Same bytes may be valid for different systems (.bin is ambiguous).
                let id=system.rawValue+"-"+digest
                guard known.insert(id).inserted else { report.duplicates+=1; continue }
                let folderName=system == .arcade ? "Arcade" : id
                let folder=LibraryPaths.roms.appendingPathComponent(folderName,isDirectory:true)
                try fm.createDirectory(at:folder,withIntermediateDirectories:true)
                // Arcade lookup uses the original ZIP basename (e.g. game.zip).
                let leaf=system == .arcade ? url.lastPathComponent : "game."+ext
                let destination=folder.appendingPathComponent(leaf)
                if system == .arcade, fm.fileExists(atPath:destination.path), try Data(contentsOf:destination) != data { throw LibraryFailure.message("存在内容不同的同名街机 ROM，请先在本地游戏目录处理版本冲突") }
                try data.write(to:destination,options:.atomic)
                var game=Game(id:id,title:title,system:system,filename:folderName+"/"+leaf)
                game.recognizeEdition()
                report.added.append(game)
            } catch { report.errors.append(url.lastPathComponent+"："+error.localizedDescription) }
        }
        if files.isEmpty && report.errors.isEmpty { report.errors.append("没有找到可导入的游戏文件") }
        return report
    }
    private static func readROM(_ url: URL) throws -> (Data,String,String,GameSystem) {
        let limit=512*1024*1024
        let size=(try url.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
        guard size>0 && size<=limit else { throw LibraryFailure.message("文件为空或超过 512 MB") }
        var ext=url.pathExtension.lowercased()
        var system=GameSystem.detect(ext)!
        var title=url.deletingPathExtension().lastPathComponent
        var data: Data
        if ext == "zip" {
            let list=try unzip(["-Z1",url.path],maxBytes:2*1024*1024)
            let entries=String(decoding:list,as:UTF8.self).split(separator:"\n").map(String.init)
            let roms=entries.filter { name in
                let parts=name.split(separator:"/")
                let ext=URL(fileURLWithPath:name).pathExtension.lowercased()
                return !name.hasPrefix("__MACOSX/") && !parts.contains(where: { $0.hasPrefix(".") }) && ext != "bin" && GameSystem.detect(ext).map { $0 != .arcade } == true
            }
            if roms.count == 1, let member=roms.first {
                guard !member.contains(where:{ "*?[]".contains($0) }) else { throw LibraryFailure.message("请先解压这个压缩包再导入") }
                ext=URL(fileURLWithPath:member).pathExtension.lowercased()
                system=GameSystem.detect(ext)!
                title=URL(fileURLWithPath:member).deletingPathExtension().lastPathComponent
                data=try unzip(["-p",url.path,member],maxBytes:limit)
            } else if roms.count>1 {
                throw LibraryFailure.message("包含多个主机游戏，请解压后导入整个文件夹")
            } else { data=try Data(contentsOf:url,options:.mappedIfSafe) }
        } else { data=try Data(contentsOf:url,options:.mappedIfSafe) }
        if system == .nes && (data.count<16 || data.prefix(4) != Data([0x4e,0x45,0x53,0x1a])) { throw LibraryFailure.message("不是有效的 iNES 游戏文件") }
        guard !data.isEmpty else { throw LibraryFailure.message("游戏文件为空") }
        return (data,ext,title,system)
    }
    private static func unzip(_ args: [String], maxBytes: Int) throws -> Data {
        let process=Process(); process.executableURL=URL(fileURLWithPath:"/usr/bin/unzip"); process.arguments=args
        let pipe=Pipe(); process.standardOutput=pipe; process.standardError=FileHandle.nullDevice
        try process.run()
        var output=Data()
        while true {
            let chunk=pipe.fileHandleForReading.readData(ofLength:65536)
            if chunk.isEmpty { break }
            if output.count+chunk.count>maxBytes { process.terminate(); pipe.fileHandleForReading.closeFile(); process.waitUntilExit(); throw LibraryFailure.message("解压后大小超出限制") }
            output.append(chunk)
        }
        process.waitUntilExit()
        guard process.terminationStatus==0 else { throw LibraryFailure.message("压缩包损坏或无法读取") }
        return output
    }
}

final class GameLibrary: ObservableObject {
    @Published var games=[Game.demo]
    @Published var importing=false
    @Published var notice: String?
    @Published var error: String?
    init() {
        do {
            try LibraryPaths.prepare()
            var bundled=[Game]()
            if let url=Bundle.main.resourceURL?.appendingPathComponent("Games/catalog.json"),let data=try? Data(contentsOf:url) {
                bundled=try JSONDecoder().decode([Game].self,from:data)
            }
            games=[.demo]+bundled
            if FileManager.default.fileExists(atPath:LibraryPaths.index.path) {
                let doc=try JSONDecoder().decode(LibraryDocument.self,from:Data(contentsOf:LibraryPaths.index))
                guard doc.version==1 else { throw LibraryFailure.message("游戏库版本暂不支持") }
                let old=Dictionary(doc.games.map { ($0.id,$0) },uniquingKeysWith:{ first,_ in first })
                games=games.map { builtIn in
                    var game=builtIn
                    if let previous=old[game.id] { game.favorite=previous.favorite; game.lastPlayed=previous.lastPlayed; game.playCount=previous.playCount; game.seriesEntryID=previous.seriesEntryID }
                    return game
                }
                let bundledIDs=Set(games.map(\.id))
                games.append(contentsOf:doc.games.filter { !bundledIDs.contains($0.id) && !$0.isBundled })
            }
            for i in games.indices { games[i].recognizeEdition() }
        } catch { self.error="读取游戏库失败：\(error.localizedDescription)。原始文件已保留。" }
    }
    func persist() {
        do {
            let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            // A corrupt index is never overwritten without preserving a copy.
            if let data=try? Data(contentsOf:LibraryPaths.index), (try? JSONDecoder().decode(LibraryDocument.self,from:data))==nil {
                let copy=LibraryPaths.root.appendingPathComponent("library-backup-\(Int(Date().timeIntervalSince1970)).json")
                try data.write(to:copy,options:.atomic)
            }
            try encoder.encode(LibraryDocument(games:games)).write(to:LibraryPaths.index,options:.atomic)
        } catch { self.error="保存游戏库失败："+error.localizedDescription }
    }
    func toggleFavorite(_ game: Game) {
        guard let i=games.firstIndex(where: { $0.id==game.id }) else { return }
        games[i].favorite.toggle(); persist()
    }
    func assign(_ game: Game, to entry: SeriesEntry?) {
        guard let i=games.firstIndex(where:{ $0.id==game.id }), entry == nil || entry?.system==game.system else { return }
        games[i].seriesEntryID=entry?.id ?? "none"; persist()
    }
    func markPlayed(_ game: Game) {
        guard let i=games.firstIndex(where: { $0.id==game.id }) else { return }
        games[i].lastPlayed=Date(); games[i].playCount+=1; persist()
    }
    func remove(_ game: Game) {
        guard !game.isDemo && !game.isBundled else { return }
        // Removing from the library leaves the managed ROM and saves recoverable.
        games.removeAll { $0.id==game.id }; persist()
    }
    func installStoreGame(_ remote: Game, romData: Data, coverData: Data?) throws {
        guard !games.contains(where:{ $0.id==remote.id }) else { return }
        guard let expected=remote.sha256 else { throw LibraryFailure.message("线上目录缺少校验值") }
        let actual=SHA256.hash(data:romData).map { String(format:"%02x",$0) }.joined()
        guard actual==expected else { throw LibraryFailure.message("下载校验失败，文件未安装") }
        if remote.system == .nes && (romData.count<16 || romData.prefix(4) != Data([0x4e,0x45,0x53,0x1a])) { throw LibraryFailure.message("下载的文件不是有效 iNES 游戏") }
        let folder=LibraryPaths.roms.appendingPathComponent("Store/"+remote.id,isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let ext=URL(fileURLWithPath:remote.filename).pathExtension.isEmpty ? "nes" : URL(fileURLWithPath:remote.filename).pathExtension
        try romData.write(to:folder.appendingPathComponent("game."+ext),options:.atomic)
        var game=remote
        game.bundled=false; game.filename="Store/"+remote.id+"/game."+ext; game.addedAt=Date()
        game.favorite=false; game.playCount=0; game.lastPlayed=nil
        if let data=coverData {
            let leaf=remote.id+".png"
            try data.write(to:LibraryPaths.covers.appendingPathComponent(leaf),options:.atomic)
            game.cover=leaf
        } else { game.cover=nil }
        game.recognizeEdition(); games.append(game); persist()
    }
    func chooseImport(folder: Bool=false) {
        let panel=NSOpenPanel(); panel.title=folder ? "选择游戏文件夹（包含子文件夹）" : "导入游戏文件、ZIP 或文件夹"
        panel.canChooseFiles = !folder; panel.canChooseDirectories=true; panel.allowsMultipleSelection=true
        panel.prompt="导入游戏"
        if panel.runModal() == .OK { importURLs(panel.urls) }
    }
    func importURLs(_ urls: [URL]) {
        guard !importing else { return }
        importing=true
        let existing=games
        DispatchQueue.global(qos:.userInitiated).async {
            let report=ROMImporter.importFiles(urls,existing:existing)
            DispatchQueue.main.async {
                self.games.append(contentsOf:report.added); self.importing=false
                if !report.added.isEmpty { self.persist() }
                self.notice=report.summary
            }
        }
    }
}
