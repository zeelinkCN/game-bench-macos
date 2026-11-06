import Foundation

@main struct LibrarySmoke {
    static func main() throws {
        let fm=FileManager.default
        let base=URL(fileURLWithPath:fm.currentDirectoryPath).appendingPathComponent("build/LibraryTests-"+UUID().uuidString)
        setenv("GAMEBENCH_DATA_DIR",base.appendingPathComponent("data").path,1)
        try LibraryPaths.prepare()
        let editions: [(String,GameSystem,String)] = [
            ("Contra (Japan) [Jixun汉化]",.nes,"contra-nes"),
            ("Super C (USA)",.nes,"super-contra-nes"),
            ("超级魂斗罗 [汉化版]",.nes,"super-contra-nes"),
            ("Contra Force (USA)",.nes,"contra-force"),
            ("魂斗罗3 (中文版)",.nes,"contra-force"),
            ("Contra III - The Alien Wars",.snes,"contra-3"),
            ("Contra - Hard Corps",.sega,"contra-hard-corps"),
            ("Operation C (World)",.gameboy,"operation-c"),
            ("Super Mario Bros. (World)",.nes,"smb-1"),
            ("Super Mario Bros. 2 (Japan)",.nes,"smb-lost-levels"),
            ("Super Mario Bros. 2 (USA)",.nes,"smb-2-usa"),
            ("超级马力欧兄弟3 [简体中文]",.nes,"smb-3"),
            ("Super Mario World",.snes,"super-mario-world"),
            ("Super Mario All-Stars",.snes,"super-mario-allstars"),
            ("Super Mario Land 2 - 6 Golden Coins",.gameboy,"super-mario-land-2"),
            ("Wario Land - Super Mario Land 3",.gameboy,"wario-land")
        ]
        for (title,system,id) in editions { precondition(SeriesCatalog.identify(title:title,system:system)==id,"Misclassified: "+title) }
        for title in ["星际魂斗罗","空中魂斗罗","Dr. Mario","Wrecking Crew","Super Mario Kart"] { precondition(SeriesCatalog.identify(title:title,system:.nes)==nil) }
        var localized=Game(id:"fixture",title:"魂斗罗1 [汉化]",system:.nes,filename:"fixture.nes")
        localized.recognizeEdition()
        precondition(localized.hasChineseLabel && localized.language=="zh-label")
        precondition(Game(id:"original",title:"Flappy Bird",system:.nes,filename:"x.nes").displayTitle=="飞翔的小鸟")
        precondition(!Game(id:"original",title:"Flappy Bird",system:.nes,filename:"x.nes").hasChineseLabel)
        print("PASS: 16 series editions, non-series exclusions, Chinese title search, language labels")
        let ips=Data(Array("PATCH".utf8)+[0,0,1,0,2,0x41,0x42,0,0,5,0,0,0,3,0x43]+Array("EOF".utf8))
        let patched=try IPSPatch.apply(ips,to:Data([0,1,2,3]))
        precondition(patched==Data([0,0x41,0x42,3,0,0x43,0x43,0x43]))
        let truncate=ips+Data([0,0,3])
        let truncated=try IPSPatch.apply(truncate,to:Data([0,1,2,3]))
        precondition(truncated==Data([0,0x41,0x42]))
        do { _=try IPSPatch.apply(Data(Array("PATCH".utf8)+[0,0,0,0,8,1]),to:Data([0])); fatalError("Accepted truncated IPS") } catch {}
        print("PASS: IPS literal records, RLE expansion, output truncation, corrupt patch rejection")
        let source=base.appendingPathComponent("incoming/nested")
        try fm.createDirectory(at:source,withIntermediateDirectories:true)
        let demo=try Data(contentsOf:URL(fileURLWithPath:"Resources/Demo/StarPilot.nes"))
        let start=Date()
        for i in 0..<1000 {
            var data=demo; data[data.count-2]=UInt8(i&255); data[data.count-1]=UInt8(i>>8)
            try data.write(to:source.appendingPathComponent("Test-\(i).nes"))
        }
        let report=ROMImporter.importFiles([base.appendingPathComponent("incoming")],existing:[])
        precondition(report.added.count==1000 && report.errors.isEmpty)
        let dupes=ROMImporter.importFiles([source],existing:report.added)
        precondition(dupes.added.isEmpty && dupes.duplicates==1000)
        let bad=source.appendingPathComponent("broken.nes"); try Data("not a ROM".utf8).write(to:bad)
        precondition(ROMImporter.importFiles([bad],existing:[]).errors.count==1)
        let lib=GameLibrary(); lib.games.append(contentsOf:report.added)
        lib.toggleFavorite(report.added[0]); lib.markPlayed(report.added[0]); lib.persist()
        let restored=GameLibrary()
        precondition(restored.games.count==1001)
        precondition(restored.games.first(where:{$0.id==report.added[0].id})?.favorite==true)
        precondition(restored.games.first(where:{$0.id==report.added[0].id})?.playCount==1)
        print(String(format:"PASS: 1,000-game nested import, deduplication, invalid file, favorites and library persistence (%.2fs)",Date().timeIntervalSince(start)))
        try fm.removeItem(at:base)
    }
}
