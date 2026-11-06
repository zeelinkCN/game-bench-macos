import AppKit
import Foundation
import SwiftUI

enum ClassicSeries: String, CaseIterable, Identifiable {
    case contra, mario
    var id: String { rawValue }
    var section: String { "series-"+rawValue }
    var title: String { self == .contra ? "魂斗罗系列" : "超级玛丽系列" }
    var color: Color { self == .contra ? .orange : Color(red:0.80,green:0.94,blue:0.51) }
    static func section(_ value: String) -> ClassicSeries? { allCases.first { $0.section==value } }
    var entries: [SeriesEntry] { SeriesCatalog.entries.filter { $0.series==self } }
}

struct SeriesEntry: Identifiable {
    var id: String
    var series: ClassicSeries
    var title: String
    var original: String
    var system: GameSystem
    var note: String = ""
    var translationURL: String?
    var translationLabel: String = "汉化资料"
}

enum SeriesCatalog {
    static let translationIndex="https://github.com/nanL/RetroGamesZH"
    static let entries: [SeriesEntry] = [
        .init(id:"contra-nes",series:.contra,title:"魂斗罗",original:"Contra",system:.nes,note:"红白机初代",translationURL:"https://jixun.moe/localisation/fc-contra-1/",translationLabel:"Jixun 汉化补丁说明"),
        .init(id:"super-contra-nes",series:.contra,title:"超级魂斗罗",original:"Super C / Super Contra",system:.nes,note:"红白机续作"),
        .init(id:"contra-force",series:.contra,title:"魂斗罗力量",original:"Contra Force",system:.nes,note:"国内也常称魂斗罗 3"),
        .init(id:"operation-c",series:.contra,title:"魂斗罗：行动 C",original:"Operation C",system:.gameboy),
        .init(id:"contra-3",series:.contra,title:"魂斗罗精神",original:"Contra III: The Alien Wars",system:.snes),
        .init(id:"contra-hard-corps",series:.contra,title:"魂斗罗：铁血兵团",original:"Contra: Hard Corps",system:.sega),
        .init(id:"contra-arcade",series:.contra,title:"魂斗罗（街机）",original:"Contra / Gryzor",system:.arcade),
        .init(id:"super-contra-arcade",series:.contra,title:"超级魂斗罗（街机）",original:"Super Contra",system:.arcade),
        .init(id:"smb-1",series:.mario,title:"超级玛丽：马里奥兄弟",original:"Super Mario Bros.",system:.nes),
        .init(id:"smb-lost-levels",series:.mario,title:"超级玛丽 2：失落的关卡",original:"Super Mario Bros. 2 (Japan)",system:.nes,note:"日版磁碟机版，运行 .fds 需要 disksys.rom BIOS"),
        .init(id:"smb-2-usa",series:.mario,title:"超级玛丽 2：美版",original:"Super Mario Bros. 2 / USA",system:.nes,note:"与日版失落的关卡为不同作品"),
        .init(id:"smb-3",series:.mario,title:"超级玛丽 3",original:"Super Mario Bros. 3",system:.nes,translationURL:"https://wannimei.com/forum.php?mod=viewthread&tid=5655",translationLabel:"汉化版本发布信息"),
        .init(id:"super-mario-world",series:.mario,title:"超级马里奥世界",original:"Super Mario World",system:.snes),
        .init(id:"super-mario-allstars",series:.mario,title:"超级马里奥全明星",original:"Super Mario All-Stars",system:.snes,note:"超任重制合集"),
        .init(id:"super-mario-land",series:.mario,title:"超级马里奥大陆",original:"Super Mario Land",system:.gameboy),
        .init(id:"super-mario-land-2",series:.mario,title:"超级马里奥大陆 2：六个金币",original:"Super Mario Land 2: 6 Golden Coins",system:.gameboy),
        .init(id:"wario-land",series:.mario,title:"超级马里奥大陆 3：瓦里奥大陆",original:"Wario Land: Super Mario Land 3",system:.gameboy,note:"瓦里奥支线")
    ]
    static func entry(for game: Game) -> SeriesEntry? {
        guard let id=game.seriesEntryID ?? identify(title:game.title,system:game.system) else { return nil }
        return entries.first { $0.id==id }
    }
    static func identify(title: String, system: GameSystem) -> String? {
        let t=title.lowercased().replacingOccurrences(of:"ⅲ",with:"3").replacingOccurrences(of:"ⅱ",with:"2")
        func has(_ words: String...) -> Bool { words.contains(where:t.contains) }
        let contra=has("contra","魂斗罗","魂斗羅","probotector","gryzor") || t.range(of:"^super[ _-]*c(?:\\b|_)",options:.regularExpression) != nil
        if system == .nes && contra {
            if has("空中魂斗罗","星际魂斗罗","魂斗罗4","魂斗罗5","魂斗罗6","魂斗罗7","魂斗罗8") { return nil }
            if has("force","力量","魂斗罗3","魂斗罗 3") { return "contra-force" }
            if has("super c","超级","超級","魂斗罗2","魂斗罗 2") { return "super-contra-nes" }
            return "contra-nes"
        }
        if system == .arcade && (contra || has("scontra","scontraj")) { return has("super","scontra","超级","超級") ? "super-contra-arcade" : "contra-arcade" }
        if system == .gameboy && (contra || has("operation c","行动c","行动 c")) { return "operation-c" }
        if system == .snes && contra { return "contra-3" }
        if system == .sega && contra { return "contra-hard-corps" }
        guard has("mario","mariou","wario","马里奥","馬里奧","马力欧","瑪利歐","玛利欧","超级玛丽","超級瑪麗","瓦里奥","瓦利欧") else { return nil }
        if system == .gameboy {
            if has("wario","瓦里奥","瓦利欧","大陆3","大陆 3","land 3") { return "wario-land" }
            if has("land 2","land2","大陆2","大陆 2","六个金币") { return "super-mario-land-2" }
            if has("land","大陆") { return "super-mario-land" }
        }
        if system == .snes {
            if has("all-stars","all stars","allstars","全明星") { return "super-mario-allstars" }
            if has("world","世界") && !has("yoshi","耀西","yossy") { return "super-mario-world" }
        }
        if system == .nes {
            if has("kart","doctor","dr.","医生","赛车","拆屋","wrecking","is missing","time machine","时间机器") { return nil }
            if has("lost levels","lostlevels","失落","japan) (fds","日版磁碟") { return "smb-lost-levels" }
            if t.range(of:"(bros[. ]*|玛丽 *|马里奥 *|兄弟 *)(3|iii)([^a-z0-9]|$)",options:.regularExpression) != nil { return "smb-3" }
            if t.range(of:"(bros[. ]*|玛丽 *|马里奥 *|兄弟 *)(2|ii)([^a-z0-9]|$)",options:.regularExpression) != nil { return has("japan","jpn","日版") ? "smb-lost-levels" : "smb-2-usa" }
            if has("super mario","超级玛丽","超级马里奥","超級瑪麗","超级马力欧") { return "smb-1" }
        }
        return nil
    }
}

