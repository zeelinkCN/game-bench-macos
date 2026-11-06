import AppKit
import Foundation
import UniformTypeIdentifiers

enum IPSPatch {
    /// IPS offsets address the complete input file, including any copier header.
    static func apply(_ patch: Data, to source: Data) throws -> Data {
        let bytes=[UInt8](patch)
        guard bytes.count>=8,Array(bytes.prefix(5))==Array("PATCH".utf8) else { throw LibraryFailure.message("不是有效的 IPS 补丁") }
        let limit=32*1024*1024
        guard source.count<=limit else { throw LibraryFailure.message("此补丁功能最多支持 32 MB 游戏文件") }
        var output=source, cursor=5
        func number(_ count: Int) throws -> Int {
            guard cursor+count<=bytes.count else { throw LibraryFailure.message("IPS 补丁不完整") }
            var value=0
            for _ in 0..<count { value=(value<<8)|Int(bytes[cursor]); cursor+=1 }
            return value
        }
        func prepare(_ end: Int) throws {
            guard end<=limit else { throw LibraryFailure.message("补丁输出超过 32 MB") }
            if output.count<end { output.append(Data(repeating:0,count:end-output.count)) }
        }
        while true {
            guard cursor+3<=bytes.count else { throw LibraryFailure.message("IPS 补丁缺少 EOF 标记") }
            if Array(bytes[cursor..<cursor+3])==Array("EOF".utf8) {
                cursor+=3
                if bytes.count-cursor==3 {
                    let size=try number(3); try prepare(size)
                    if output.count>size { output.removeSubrange(size..<output.count) }
                } else if cursor != bytes.count { throw LibraryFailure.message("IPS 补丁尾部格式不正确") }
                return output
            }
            let offset=try number(3), size=try number(2)
            if size>0 {
                guard cursor+size<=bytes.count else { throw LibraryFailure.message("IPS 补丁数据被截断") }
                try prepare(offset+size)
                output.replaceSubrange(offset..<offset+size,with:bytes[cursor..<cursor+size]); cursor+=size
            } else {
                let count=try number(2), value=try number(1)
                guard count>0 else { throw LibraryFailure.message("IPS 重复记录长度为零") }
                try prepare(offset+count)
                output.replaceSubrange(offset..<offset+count,with:repeatElement(UInt8(value),count:count))
            }
        }
    }
}

extension GameLibrary {
    func chooseTranslationPatch(for game: Game) {
        let panel=NSOpenPanel(); panel.title="选择与这个 ROM 版本匹配的 IPS 汉化补丁"
        panel.message="生成独立游戏副本；原始游戏和原存档会保留。IPS 不包含原版校验值，请按补丁发布说明选择版本。"
        panel.canChooseDirectories=false; panel.allowsMultipleSelection=false
        panel.allowedContentTypes=[UTType(filenameExtension:"ips") ?? .data]
        panel.prompt="应用补丁"
        guard panel.runModal() == .OK,let url=panel.url else { return }
        do {
            let source=try Data(contentsOf:LibraryPaths.rom(game))
            let patch=try Data(contentsOf:url)
            let result=try IPSPatch.apply(patch,to:source)
            let staging=FileManager.default.temporaryDirectory.appendingPathComponent("GameBenchPatch-"+UUID().uuidString,isDirectory:true)
            try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:true)
            defer { try? FileManager.default.removeItem(at:staging) }
            let filename=game.title.replacingOccurrences(of:"/",with:"-")+" [汉化补丁]."+LibraryPaths.rom(game).pathExtension
            let newROM=staging.appendingPathComponent(filename)
            try result.write(to:newROM)
            let report=ROMImporter.importFiles([newROM],existing:games)
            if let imported=report.added.first {
                var translated=imported
                translated.seriesEntryID=game.seriesEntryID ?? SeriesCatalog.identify(title:game.title,system:game.system)
                translated.language="zh-patch"; translated.languageEvidence="用户选择 IPS 汉化补丁；尚未人工验证游戏内容"
                translated.source=game.source
                games.append(translated); persist()
            }
            if report.added.isEmpty && !report.errors.isEmpty { throw LibraryFailure.message(report.summary) }
            notice=report.added.isEmpty ? "这个补丁结果已在游戏库中" : "已生成汉化补丁副本，请启动检查游戏文字和画面。"
        } catch { self.error="应用补丁失败："+error.localizedDescription }
    }
}
