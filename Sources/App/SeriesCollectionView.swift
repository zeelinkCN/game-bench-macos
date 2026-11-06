import AppKit
import SwiftUI

struct SeriesCollectionView: View {
    var series: ClassicSeries
    @ObservedObject var library: GameLibrary
    @ObservedObject var engine: Emulator
    var search: String
    var preferChinese: Bool
    @Binding var selected: String
    private var installed: [Game] { library.games.filter { SeriesCatalog.entry(for:$0)?.series==series } }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Image(systemName:"rectangle.stack.fill").foregroundStyle(series.color); Text(series.title).font(.system(size:25,weight:.semibold)); Spacer(); Text("已安装 \(installed.count) 个版本").font(.system(size:12)).foregroundStyle(Palette.muted) }
            Text("经典 8／16 位作品 · 按代数整理 · 汉化优先\n当前清单不包含现代主机作品。待导入条目不计入已安装游戏数。").font(.system(size:12)).foregroundStyle(Palette.muted).lineSpacing(5)
            HStack { Button("导入本系列游戏") { library.chooseImport() }.buttonStyle(.borderedProminent); Button("导入游戏文件夹") { library.chooseImport(folder:true) }.buttonStyle(.bordered); Spacer() }
            ForEach(series.entries.filter { entry in search.isEmpty || entry.title.localizedCaseInsensitiveContains(search) || entry.original.localizedCaseInsensitiveContains(search) || installed.contains(where:{ $0.seriesEntryID==entry.id && $0.matchesSearch(search) }) }) { entry in
                let versions=installed.filter { SeriesCatalog.entry(for:$0)?.id==entry.id }.sorted { a,b in
                    if preferChinese && a.hasChineseLabel != b.hasChineseLabel { return a.hasChineseLabel }
                    return a.displayTitle.localizedStandardCompare(b.displayTitle) == .orderedAscending
                }
                VStack(alignment:.leading,spacing:12) {
                    HStack(alignment:.top,spacing:14) {
                        Text(entry.system.subtitle).font(.system(size:9,weight:.semibold,design:.monospaced)).foregroundStyle(entry.system.color).padding(9).background(entry.system.color.opacity(0.08),in:RoundedRectangle(cornerRadius:6))
                        VStack(alignment:.leading,spacing:5) { Text(entry.title).font(.system(size:15,weight:.semibold)); Text(entry.original).font(.system(size:10)).foregroundStyle(Palette.muted); if !entry.note.isEmpty { Text(entry.note).font(.system(size:10)).foregroundStyle(Palette.muted) } }
                        Spacer()
                        if versions.isEmpty { Text("待导入").font(.system(size:11)).foregroundStyle(Palette.muted).padding(.horizontal,10).padding(.vertical,6).background(Palette.background,in:Capsule()) }
                        else { Text("\(versions.count) 个版本").font(.system(size:11)).foregroundStyle(Palette.accent) }
                    }
                    ForEach(versions) { game in
                        HStack { VStack(alignment:.leading,spacing:5) { Text(game.displayTitle).font(.system(size:12)); Text(game.title).font(.system(size:10)).foregroundStyle(Palette.muted); Text(game.languageLabel).font(.system(size:10)).foregroundStyle(game.hasChineseLabel ? Palette.accent : Palette.muted) }; Spacer(); Button("开始游戏") { engine.launch(game) }.buttonStyle(.bordered) }.padding(8).background(selected==game.id ? Palette.accent.opacity(0.08) : .clear,in:RoundedRectangle(cornerRadius:6)).onTapGesture { selected=game.id }.id(game.id)
                    }
                    if let source=entry.translationURL,let url=URL(string:source) { Link(entry.translationLabel,destination:url).font(.system(size:10)).foregroundStyle(series.color) }
                }.padding(18).background(Palette.panel,in:RoundedRectangle(cornerRadius:12))
            }
        }
    }
}
