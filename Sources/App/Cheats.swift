import Foundation
import SwiftUI

struct GameCheat: Identifiable, Codable {
    var id=UUID()
    var name: String
    var code: String
    var enabled=false
}

enum CheatFiles {
    static func path(_ game: Game) -> URL { LibraryPaths.saves.appendingPathComponent(game.id+".cheats.json") }
    static func read(_ game: Game) -> [GameCheat] {
        guard let data=try? Data(contentsOf:path(game)) else { return [] }
        return (try? JSONDecoder().decode([GameCheat].self,from:data)) ?? []
    }
    static func write(_ cheats: [GameCheat], game: Game) throws {
        let encoder=JSONEncoder(); encoder.outputFormatting = .prettyPrinted
        try encoder.encode(cheats).write(to:path(game),options:.atomic)
    }
    static func apply(_ cheats: [GameCheat]) {
        gb_cheat_reset()
        // FCEUmm ignores the enabled argument, so disabled codes are omitted.
        for (index,cheat) in cheats.filter(\.enabled).enumerated() { _=gb_cheat_set(UInt32(index),cheat.code) }
    }
    static func validate(_ code: String, system: GameSystem) -> Bool {
        guard !code.isEmpty,code.utf8.count<=128,code.unicodeScalars.allSatisfy({ $0.isASCII }) else { return false }
        if system == .nes {
            let parts=code.components(separatedBy:CharacterSet(charactersIn:"+,; ")).filter { !$0.isEmpty }
            guard !parts.isEmpty else { return false }
            let pattern="^([APZLGITYEOXUKSVN]{6}|[APZLGITYEOXUKSVN]{8}|[0-9A-F]{4}:[0-9A-F]{2}|[0-9A-F]{4}\\?[0-9A-F]{2}:[0-9A-F]{2}|[0-9A-F]{8})$"
            return parts.allSatisfy { $0.range(of:pattern,options:.regularExpression) != nil }
        }
        return code.range(of:"^[A-Z0-9:+? ,;\\-]+$",options:.regularExpression) != nil
    }
}

struct CheatPanel: View {
    @ObservedObject var engine: Emulator
    var close: ()->Void
    @State<String> private var name=""
    @State<String> private var code=""
    @State<String?> private var validation=nil
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { VStack(alignment:.leading,spacing:6) { Text("金手指").font(.system(size:24,weight:.semibold)); Text(engine.game?.title ?? "当前游戏").font(.system(size:12)).foregroundStyle(Palette.muted) }; Spacer(); Button("完成",action:close).keyboardShortcut(.cancelAction) }
            Text("无限生命、无敌、无限子弹等效果由具体游戏代码决定。启用后会持续应用，关闭后停止应用；已经改变的生命数或道具不会自动回退。").font(.system(size:12)).foregroundStyle(Palette.muted).lineSpacing(5)
            if let game=engine.game,game.system == .nes {
                if game.isDemo {
                    Button("添加试玩预设：1P / 2P 分数保持为 9") {
                        engine.addPreset([GameCheat(name:"1P 分数保持 9",code:"0007:09"),GameCheat(name:"2P 分数保持 9",code:"0008:09")])
                    }.buttonStyle(.bordered)
                } else {
                    HStack {
                        Button("魂斗罗（USA）预设") { engine.addPreset([GameCheat(name:"无限生命 · Contra USA",code:"SLAIUZ"),GameCheat(name:"死亡保留武器 · Contra USA",code:"GXIIUX"),GameCheat(name:"敌人忽略玩家 · Contra USA",code:"SLTIYG")]) }
                        Button("马里奥（World）预设") { engine.addPreset([GameCheat(name:"无限生命 · SMB World",code:"SXIOPO"),GameCheat(name:"受伤保留道具 · SMB World",code:"SXULKNSE")]) }
                    }.buttonStyle(.bordered).font(.system(size:11))
                    Text("仅在 ROM 版本与预设名称一致时使用。预设添加后默认关闭。").font(.system(size:10)).foregroundStyle(Palette.muted)
                }
            }
            ScrollView {
                VStack(spacing:9) {
                    if engine.cheats.isEmpty { Text("还没有金手指，添加对应游戏的代码即可。").font(.system(size:12)).foregroundStyle(Palette.muted).frame(maxWidth:.infinity).padding(25) }
                    ForEach(engine.cheats) { cheat in
                        HStack(spacing:12) {
                            Toggle(isOn:Binding(get:{ engine.cheats.first(where:{ $0.id==cheat.id })?.enabled ?? false },set:{ value in engine.setCheat(cheat.id,enabled:value) })) { VStack(alignment:.leading,spacing:5) { Text(cheat.name).font(.system(size:12,weight:.medium)); Text(cheat.code).font(.system(size:10,design:.monospaced)).foregroundStyle(Palette.muted) } }.toggleStyle(.switch)
                            Button { engine.deleteCheat(cheat.id) } label: { Image(systemName:"trash").foregroundStyle(Palette.muted) }.buttonStyle(.plain)
                        }.padding(13).background(Palette.panel,in:RoundedRectangle(cornerRadius:8))
                    }
                }
            }.frame(height:180)
            Divider()
            HStack { TextField("名称，例如：无限生命",text:$name).textFieldStyle(.roundedBorder); TextField("金手指代码",text:$code).textFieldStyle(.roundedBorder).font(.system(size:12,design:.monospaced)) }
            HStack {
                Text(engine.game?.system == .nes ? "FC 支持 Game Genie、PAR、地址:数值，如 0010:09。" : "填写当前核心支持的金手指格式。").font(.system(size:10)).foregroundStyle(Palette.muted)
                Spacer()
                Button("添加代码") {
                    guard let game=engine.game else { return }
                    let value=code.trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
                    guard !name.trimmingCharacters(in:.whitespaces).isEmpty,CheatFiles.validate(value,system:game.system) else { validation="请填写名称和有效代码（最多 128 个字符）。"; return }
                    engine.addPreset([GameCheat(name:String(name.prefix(60)),code:value)])
                    name=""; code=""; validation=nil
                }.buttonStyle(.borderedProminent)
            }
            if let validation=validation { Text(validation).font(.system(size:11)).foregroundStyle(.orange) }
            HStack { Text("按游戏保存 · 下次启动保留开关状态").font(.system(size:10)).foregroundStyle(Palette.muted); Spacer(); Button("全部关闭") { engine.disableCheats() }.font(.system(size:11)) }
        }.padding(29).frame(width:630).background(Palette.background)
    }
}
