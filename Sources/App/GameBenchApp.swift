import AppKit
import SwiftUI

enum Palette {
    static let background=Color(red:0.065,green:0.073,blue:0.083)
    static let panel=Color(red:0.095,green:0.105,blue:0.12)
    static let tile=Color(red:0.12,green:0.13,blue:0.15)
    static let muted=Color(red:0.54,green:0.58,blue:0.61)
    static let accent=Color(red:0.80,green:0.94,blue:0.51)
    static let line=Color.white.opacity(0.08)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onQuit: (()->Void)?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let url=Bundle.main.url(forResource:"AppIcon",withExtension:"icns"),let icon=NSImage(contentsOf:url) {
            // Refresh the running Dock tile as well as the Finder bundle icon.
            NSApp.applicationIconImage=icon
            NSApp.dockTile.display()
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { onQuit?(); return .terminateNow }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct GameBenchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var library=GameLibrary()
    @StateObject private var engine=Emulator()
    @StateObject private var controllers=ControllerCenter()
    var body: some Scene {
        Window("拾光游戏厅",id:"main") {
            ContentView(library:library,engine:engine,controllers:controllers)
                .preferredColorScheme(.dark).tint(Palette.accent)
                .onAppear {
                    delegate.onQuit={ engine.shutdown() }
                    engine.onLaunch={ library.markPlayed($0) }
                    NSApp.setActivationPolicy(.regular)
                }
        }
        .windowStyle(.hiddenTitleBar).defaultSize(width:1180,height:790)
        .commands {
            CommandGroup(replacing:.newItem) {
                Button("导入游戏…") { library.chooseImport() }.keyboardShortcut("o")
                Button("导入游戏文件夹…") { library.chooseImport(folder:true) }.keyboardShortcut("o",modifiers:[.command,.shift])
            }
            CommandMenu("游戏") {
                Button(engine.paused ? "继续游戏" : "暂停游戏") { engine.togglePause() }.keyboardShortcut("p").disabled(engine.game==nil)
                Button("保存进度") { engine.quickSave() }.keyboardShortcut("s").disabled(engine.game==nil)
                Button("读取进度") { engine.quickLoad() }.keyboardShortcut("l").disabled(engine.game==nil)
                Divider()
                Button("切换全屏") { NSApp.keyWindow?.toggleFullScreen(nil) }.keyboardShortcut("f",modifiers:[.command,.control])
                Button("返回游戏库") { engine.stop() }.disabled(engine.game==nil)
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var library: GameLibrary
    @ObservedObject var engine: Emulator
    @ObservedObject var controllers: ControllerCenter
    @StateObject private var store=OnlineStore()
    @State<String> private var section="all"
    @State<String> private var search=""
    @State<String> private var selected=Game.demo.id
    @State<Bool> private var sortRecent=false
    @State<String?> private var sheet=nil
    @State<Int> private var columns=3
    @State<Bool> private var dropTarget=false
    @AppStorage("screenMode") private var screenMode=ScreenMode.original.rawValue
    @AppStorage("smooth") private var smooth=false
    @AppStorage("scanlines") private var scanlines=false
    @AppStorage("preferChinese") private var preferChinese=true
    @State<Bool> private var chineseOnly=false
    var filtered: [Game] {
        var games=library.games.filter { game in
            let seriesMatch=ClassicSeries.section(section).map { SeriesCatalog.entry(for:game)?.series==$0 } ?? false
            let sectionMatch=section=="all" || (section=="classics" && game.featuredRank != nil) || (section=="favorites" && game.favorite) || (section=="recent" && game.lastPlayed != nil) || section==game.system.rawValue || seriesMatch
            return sectionMatch && (!chineseOnly || game.hasChineseLabel) && game.matchesSearch(search)
        }
        if sortRecent || section=="recent" { games.sort { ($0.lastPlayed ?? .distantPast)>($1.lastPlayed ?? .distantPast) } }
        else { games.sort {
            if search.isEmpty && ["all","classics","nes"].contains(section) && $0.featuredRank != $1.featuredRank { return ($0.featuredRank ?? Int.max) < ($1.featuredRank ?? Int.max) }
            if preferChinese && $0.hasChineseLabel != $1.hasChineseLabel { return $0.hasChineseLabel }
            if $0.isDemo != $1.isDemo { return !$0.isDemo }
            return $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
        } }
        return games
    }
    var heading: String {
        if section=="favorites" { return "我的收藏" }
        if section=="recent" { return "最近玩过" }
        if section=="classics" { return "童年经典" }
        if section=="store" { return "游戏市场" }
        if let series=ClassicSeries.section(section) { return series.title }
        return GameSystem(rawValue:section)?.title ?? "全部游戏"
    }
    var body: some View {
        HStack(spacing:0) {
            if engine.game==nil { sidebar }
            ZStack {
                if let game=engine.game { player(game) } else { libraryView }
                if engine.loading {
                    ZStack { Color.black.opacity(0.65); ProgressView("正在载入…").padding(30).background(Palette.panel,in:RoundedRectangle(cornerRadius:16)) }
                }
                if let toast=engine.toast {
                    VStack { Spacer(); Text(toast).font(.system(size:13,weight:.medium)).padding(.horizontal,20).padding(.vertical,12).background(.ultraThinMaterial,in:Capsule()).padding(.bottom,65) }.allowsHitTesting(false)
                }
            }
        }
        .frame(minWidth:980,minHeight:650).background(Palette.background)
        .overlay { if dropTarget { RoundedRectangle(cornerRadius:14).stroke(Palette.accent,lineWidth:3).padding(5).allowsHitTesting(false) } }
        .onDrop(of:["public.file-url"],isTargeted:$dropTarget) { providers in
            let group=DispatchGroup(), lock=NSLock()
            var urls=[URL]()
            for provider in providers {
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier:"public.file-url") { data,_ in
                    defer { group.leave() }
                    if let data=data, let url=URL(dataRepresentation:data,relativeTo:nil) { lock.lock(); urls.append(url); lock.unlock() }
                }
            }
            group.notify(queue:.main) { library.importURLs(urls) }
            return true
        }
        .sheet(item:Binding(get:{ sheet.map(SheetItem.init) },set:{ sheet=$0?.id })) { item in
            if item.id=="controllers" { ControllerPanel(controllers:controllers,close:{ sheet=nil }) }
            else if item.id=="cheats" { CheatPanel(engine:engine,close:{ sheet=nil }) }
            else { settings }
        }
        .onChange(of:sheet) { _,value in controllers.modalOpen=value != nil }
        .onChange(of:engine.game) { _,value in controllers.inGame=value != nil }
        .onChange(of:engine.paused) { _,value in controllers.isPaused=value }
        .onChange(of:filtered.map(\.id)) { _,ids in if !ids.contains(selected) { selected=ids.first ?? "" } }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didResignActiveNotification)) { _ in if engine.game != nil { engine.setPaused(true) } }
        .onAppear { controllers.onAction=handleAction }
        .alert("提示",isPresented:Binding(get:{ engine.error != nil || library.error != nil },set:{ if !$0 { engine.error=nil; library.error=nil } })) {
            Button("知道了") { engine.error=nil; library.error=nil }
        } message: { Text(engine.error ?? library.error ?? "") }
    }
    private var sidebar: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:10) {
                Image(systemName:"dpad.fill").font(.system(size:24)).foregroundStyle(Palette.accent)
                VStack(alignment:.leading,spacing:3) { Text("拾光游戏厅").font(.system(size:17,weight:.bold)); Text("GAME BENCH").font(.system(size:8,weight:.semibold,design:.monospaced)).tracking(3).foregroundStyle(Palette.muted) }
            }.padding(.top,51).padding(.horizontal,23).padding(.bottom,38)
            ScrollView(showsIndicators:false) {
            VStack(alignment:.leading,spacing:0) {
            Text("我的游戏").font(.system(size:10,weight:.medium)).foregroundStyle(Palette.muted).padding(.horizontal,25).padding(.bottom,10)
            nav("all",icon:"square.grid.2x2",title:"全部游戏",count:library.games.count)
            nav("store",icon:"shippingbox",title:"游戏市场",count:nil)
            nav("classics",icon:"sparkles",title:"童年经典",count:library.games.filter { $0.featuredRank != nil }.count)
            nav("favorites",icon:"heart",title:"我的收藏",count:library.games.filter(\.favorite).count)
            nav("recent",icon:"clock",title:"最近玩过",count:nil)
            Text("经典系列").font(.system(size:10,weight:.medium)).foregroundStyle(Palette.muted).padding(.horizontal,25).padding(.top,22).padding(.bottom,10)
            ForEach(ClassicSeries.allCases) { series in
                nav(series.section,icon:"rectangle.stack",title:series.title,count:library.games.filter { SeriesCatalog.entry(for:$0)?.series==series }.count)
            }
            Rectangle().fill(Palette.line).frame(height:1).padding(.horizontal,24).padding(.vertical,24)
            Text("游戏平台").font(.system(size:10,weight:.medium)).foregroundStyle(Palette.muted).padding(.horizontal,25).padding(.bottom,10)
            ForEach(GameSystem.allCases) { system in
                nav(system.rawValue,icon:system == .arcade ? "arcade.stick.console" : "gamecontroller",title:system.title,count:library.games.filter { $0.system==system }.count,dot:system.color)
            }
            }
            }
            Spacer(minLength:12)
            Button { sheet="controllers" } label: {
                HStack(spacing:9) {
                    Circle().fill(controllers.pads[0].connected ? Palette.accent : Palette.muted).frame(width:6,height:6)
                    VStack(alignment:.leading,spacing:4) { Text(controllers.pads[0].connected ? "\(controllers.pads.filter(\.connected).count) 只手柄已连接" : "键盘已就绪").font(.system(size:12,weight:.medium)); Text("连接与双人设置").font(.system(size:10)).foregroundStyle(Palette.muted) }
                    Spacer(); Image(systemName:"chevron.right").font(.system(size:10)).foregroundStyle(Palette.muted)
                }.padding(13).background(Palette.tile,in:RoundedRectangle(cornerRadius:10))
            }.buttonStyle(.plain).padding(.horizontal,17)
            Button { sheet="settings" } label: { Label("画面与设置",systemImage:"slider.horizontal.3").font(.system(size:12)).foregroundStyle(Palette.muted).padding(.vertical,19).padding(.horizontal,25) }.buttonStyle(.plain)
        }.frame(width:210).background(Palette.panel).overlay(alignment:.trailing) { Rectangle().fill(Palette.line).frame(width:1) }
    }
    private func nav(_ id: String,icon: String,title: String,count: Int?,dot: Color?=nil) -> some View {
        Button { section=id } label: {
            HStack(spacing:11) {
                if let dot=dot { RoundedRectangle(cornerRadius:2).fill(dot).frame(width:7,height:7).padding(.horizontal,4) }
                else { Image(systemName:icon).font(.system(size:14)).frame(width:15) }
                Text(title).font(.system(size:12,weight:section==id ? .semibold : .regular))
                Spacer()
                if let count=count { Text("\(count)").font(.system(size:10,design:.monospaced)).foregroundStyle(section==id ? Palette.accent : Palette.muted) }
            }.foregroundStyle(section==id ? .white : Color.white.opacity(0.57)).padding(.horizontal,13).frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle()).background(section==id ? Color.white.opacity(0.065) : .clear,in:RoundedRectangle(cornerRadius:8))
        }.buttonStyle(.plain).frame(maxWidth:.infinity).contentShape(Rectangle()).padding(.horizontal,12).padding(.vertical,2)
    }
    private var libraryView: some View {
        VStack(spacing:0) {
            HStack {
                Text("游戏库").font(.system(size:13,weight:.semibold)); Text("/  \(heading)").font(.system(size:12)).foregroundStyle(Palette.muted)
                Spacer()
                HStack(spacing:7) { Image(systemName:"magnifyingglass").font(.system(size:12)); TextField("搜索游戏",text:$search).textFieldStyle(.plain).font(.system(size:12)).frame(width:145) }.foregroundStyle(Palette.muted).padding(.horizontal,12).padding(.vertical,9).background(Palette.tile,in:RoundedRectangle(cornerRadius:8))
                Button { library.chooseImport() } label: { Label(library.importing ? "导入中…" : "导入游戏",systemImage:"plus").font(.system(size:12,weight:.semibold)).padding(.horizontal,13).padding(.vertical,9).foregroundStyle(.black).background(Palette.accent,in:RoundedRectangle(cornerRadius:8)) }.buttonStyle(.plain).disabled(library.importing)
            }.padding(.horizontal,30).padding(.top,37).padding(.bottom,22)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment:.leading,spacing:25) {
                        if section=="store" {
                            OnlineStoreView(store:store,library:library,search:search)
                        } else if let series=ClassicSeries.section(section) {
                            SeriesCollectionView(series:series,library:library,engine:engine,search:search,preferChinese:preferChinese,selected:$selected)
                        } else {
                        if section=="all" && search.isEmpty { hero }
                        if let notice=library.notice {
                            HStack { Text(notice).font(.system(size:12)).foregroundStyle(Palette.accent); Spacer(); Button { library.notice=nil } label: { Image(systemName:"xmark").font(.system(size:10)) }.buttonStyle(.plain) }.padding(13).background(Palette.accent.opacity(0.07),in:RoundedRectangle(cornerRadius:9))
                        }
                        HStack(alignment:.firstTextBaseline) {
                            Text(heading).font(.system(size:20,weight:.semibold))
                            Text("\(filtered.count) 款").font(.system(size:11)).foregroundStyle(Palette.muted)
                            Spacer()
                            Toggle("中文版本",isOn:$chineseOnly).toggleStyle(.button).font(.system(size:11)).help("按游戏版本标识筛选；中文译名不代表游戏内已汉化")
                            Button { sortRecent.toggle() } label: { Label(sortRecent ? "最近游玩" : "名称排序",systemImage:"arrow.up.arrow.down").font(.system(size:11)).foregroundStyle(Palette.muted) }.buttonStyle(.plain)
                        }
                        if filtered.isEmpty {
                            VStack(spacing:14) { Image(systemName:section=="favorites" ? "heart" : "square.stack.3d.up").font(.system(size:36,weight:.ultraLight)).foregroundStyle(Palette.muted); Text(chineseOnly ? "还没有标注中文的游戏版本" : (search.isEmpty ? "下一段冒险，等你放进来" : "没有找到这个游戏")).font(.system(size:16,weight:.medium)); Text("将游戏文件拖进窗口，或点击右上角导入。").font(.system(size:12)).foregroundStyle(Palette.muted) }.frame(maxWidth:.infinity).frame(height:230)
                        } else {
                            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:18),count:columns),alignment:.leading,spacing:22) {
                                ForEach(filtered) { game in
                                    GameCard(game:game,selected:selected==game.id,launch:{ engine.launch(game) },select:{ selected=game.id },favorite:{ library.toggleFavorite(game) })
                                        .id(game.id)
                                        .contextMenu {
                                            Button("开始 / 继续游戏") { engine.launch(game) }
                                            Button("从头开始") { engine.launch(game,resume:false) }
                                            Button(game.favorite ? "取消收藏" : "收藏游戏") { library.toggleFavorite(game) }
                                            Button("应用 IPS 汉化补丁…") { library.chooseTranslationPatch(for:game) }.disabled(game.system == .arcade)
                                            Menu("归入经典系列") {
                                                ForEach(SeriesCatalog.entries) { entry in Button(entry.title+" · "+entry.system.title) { library.assign(game,to:entry) }.disabled(game.system != entry.system) }
                                            }
                                            if SeriesCatalog.entry(for:game) != nil { Button("移出经典系列") { library.assign(game,to:nil) } }
                                            if let source=game.source,let url=URL(string:source) { Button("查看游戏来源") { NSWorkspace.shared.open(url) } }
                                            if !game.isDemo && !game.isBundled { Button("从游戏库移除") { library.remove(game) } }
                                        }
                                }
                            }
                        }
                        if library.games.count==1 && section=="all" && search.isEmpty { importGuide }
                        }
                        Text("本地运行 · 游戏与存档保存在这台 Mac").font(.system(size:10)).foregroundStyle(Palette.muted.opacity(0.65)).padding(.top,4)
                    }.padding(.horizontal,30).padding(.bottom,28)
                }
                .onChange(of:selected) { _,id in withAnimation(.easeOut(duration:0.15)) { proxy.scrollTo(id,anchor:.center) } }
            }
            .background(GeometryReader { geo in Color.clear.onAppear { updateColumns(geo.size.width) }.onChange(of:geo.size.width) { _,width in updateColumns(width) } })
            HStack(spacing:21) {
                KeyHint(key:"A",text:"选择并开始",color:Palette.accent); KeyHint(key:"X",text:"收藏"); KeyHint(key:"Y",text:"手柄测试")
                Spacer(); Text("支持本地双人").font(.system(size:11)).foregroundStyle(Palette.muted); Image(systemName:"person.2").font(.system(size:12)).foregroundStyle(Palette.accent)
            }.padding(.horizontal,30).frame(height:44).background(Palette.panel).overlay(alignment:.top) { Rectangle().fill(Palette.line).frame(height:1) }
        }
    }
    private func updateColumns(_ width: CGFloat) { columns=max(2,Int((width-60+18)/198)) }
    private var hero: some View {
        ZStack(alignment:.leading) {
            RoundedRectangle(cornerRadius:16).fill(LinearGradient(colors:[Color(red:0.14,green:0.19,blue:0.16),Color(red:0.11,green:0.14,blue:0.14)],startPoint:.leading,endPoint:.trailing))
            HStack {
                VStack(alignment:.leading,spacing:13) {
                    HStack(spacing:6) { Circle().fill(Palette.accent).frame(width:5,height:5); Text("再按一次，开始键。").font(.system(size:10,weight:.medium)).tracking(2).foregroundStyle(Palette.accent) }
                    Text("把快乐，接回来了。").font(.system(size:29,weight:.semibold))
                    Text("熟悉的像素，熟悉的按键。\n一个人闯关，两个人一起通关。").font(.system(size:12)).lineSpacing(6).foregroundStyle(Color.white.opacity(0.48))
                    Button { engine.launch(.demo) } label: { HStack(spacing:8) { Image(systemName:"play.fill").font(.system(size:9)); Text("试一局双人小游戏").font(.system(size:11,weight:.semibold)); Image(systemName:"arrow.up.right").font(.system(size:9)) }.foregroundStyle(Palette.accent).padding(.top,3) }.buttonStyle(.plain)
                }.padding(27)
                Spacer(minLength:0)
                RetroArt(style:.nes,demo:true).frame(width:230,height:175).rotationEffect(.degrees(-6)).opacity(0.9).padding(.trailing,26)
            }
        }.frame(height:220).overlay { RoundedRectangle(cornerRadius:16).stroke(Palette.accent.opacity(0.09),lineWidth:1) }
    }
    private var importGuide: some View {
        VStack(alignment:.leading,spacing:13) {
            HStack { Image(systemName:"tray.and.arrow.down").foregroundStyle(Palette.accent); Text("把你的童年放进游戏库").font(.system(size:13,weight:.medium)); Spacer(); Button("选择文件夹") { library.chooseImport(folder:true) }.buttonStyle(.borderless).font(.system(size:11)) }
            Text("支持批量导入和子文件夹扫描，自动去重。红白机 .nes、超任 .sfc / .smc、掌机 .gb / .gbc、世嘉 .md / .gen，以及 FBNeo 街机 .zip。").font(.system(size:11)).lineSpacing(5).foregroundStyle(Palette.muted)
            Text("内置「星光试航」为自制双人游戏；经典游戏通过自己的 ROM 文件导入。街机游戏需匹配 FBNeo ROM 版本，部分游戏需要 BIOS。").font(.system(size:10)).lineSpacing(4).foregroundStyle(Palette.muted.opacity(0.8))
        }.padding(19).background(Palette.panel,in:RoundedRectangle(cornerRadius:12)).overlay { RoundedRectangle(cornerRadius:12).stroke(Palette.line,lineWidth:1) }
    }
    private func player(_ game: Game) -> some View {
        VStack(spacing:0) {
            HStack(spacing:17) {
                Button { engine.stop() } label: { Label("游戏库",systemImage:"chevron.left").font(.system(size:12)) }.buttonStyle(.plain).foregroundStyle(Palette.muted)
                Rectangle().fill(Palette.line).frame(width:1,height:18)
                Text(game.displayTitle).font(.system(size:13,weight:.semibold)).help(game.title+" · "+game.languageLabel); Text(game.system.subtitle).font(.system(size:9,design:.monospaced)).foregroundStyle(Palette.muted)
                Spacer()
                Text("\(engine.sourceWidth) × \(engine.sourceHeight)  ·  \(engine.fps) FPS").font(.system(size:10,design:.monospaced)).foregroundStyle(Palette.muted)
                Button { engine.setPaused(true); sheet="cheats" } label: { Image(systemName:"wand.and.stars").frame(width:25) }.buttonStyle(.plain).help("金手指 / 作弊模式")
                Button { engine.togglePause() } label: { Image(systemName:engine.paused ? "play.fill" : "pause.fill").frame(width:25) }.buttonStyle(.plain).help("暂停 / 继续 · Esc")
                Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: { Image(systemName:"arrow.up.left.and.arrow.down.right").frame(width:25) }.buttonStyle(.plain).help("全屏 · ⌃⌘F")
            }.padding(.horizontal,24).padding(.top,32).padding(.bottom,15).background(Palette.panel)
            GeometryReader { geo in
                let box=screenSize(geo.size)
                ZStack {
                    Color.black
                    GameScreen(presenter:engine.presenter,smooth:smooth).frame(width:box.width,height:box.height)
                        .overlay { if scanlines { Canvas { context,size in for y in stride(from:0.0,to:size.height,by:4) { context.fill(Path(CGRect(x:0,y:y,width:size.width,height:1)),with:.color(.black.opacity(0.24))) } }.allowsHitTesting(false) } }
                    if engine.paused { pauseMenu(game) }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            }
            HStack(spacing:18) {
                Text("1P").font(.system(size:10,weight:.bold,design:.monospaced)).foregroundStyle(Palette.accent)
                Text(controllers.pads[0].connected ? controllers.pads[0].name : "方向键 · Z / X · Enter").font(.system(size:10)).foregroundStyle(Palette.muted)
                Text("2P").font(.system(size:10,weight:.bold,design:.monospaced)).foregroundStyle(.cyan)
                Text(controllers.pads[1].connected ? controllers.pads[1].name : "WASD · J / K · T").font(.system(size:10)).foregroundStyle(Palette.muted)
                Spacer()
                Text("LB + RB / Esc 暂停").font(.system(size:10)).foregroundStyle(Palette.muted)
                Menu { ForEach(ScreenMode.allCases) { mode in Button(mode.rawValue) { screenMode=mode.rawValue } }; Divider(); Toggle("柔和显示",isOn:$smooth); Toggle("CRT 扫描线",isOn:$scanlines) } label: { Image(systemName:"display").font(.system(size:13)) }.menuStyle(.borderlessButton).frame(width:25)
            }.padding(.horizontal,24).frame(height:44).background(Palette.panel)
        }
    }
    private func screenSize(_ available: CGSize) -> CGSize {
        if screenMode==ScreenMode.fill.rawValue { return available }
        if screenMode==ScreenMode.integer.rawValue {
            let w=CGFloat(engine.sourceWidth),h=CGFloat(engine.sourceHeight)
            let scale=min(available.width/w,available.height/h)
            let integerScale=scale>=1 ? floor(scale) : scale
            return CGSize(width:w*integerScale,height:h*integerScale)
        }
        let a=engine.aspect
        let w=min(available.width,available.height*a)
        return CGSize(width:w,height:w/a)
    }
    private func pauseMenu(_ game: Game) -> some View {
        ZStack {
            Color.black.opacity(0.66)
            VStack(spacing:19) {
                Text("休息一下，快乐不散场。").font(.system(size:22,weight:.semibold))
                Text(game.displayTitle).font(.system(size:12)).foregroundStyle(Palette.muted)
                Button { engine.setPaused(false) } label: { Label("继续游戏    A",systemImage:"play.fill").font(.system(size:13,weight:.semibold)).frame(width:240,height:42).foregroundStyle(.black).background(Palette.accent,in:RoundedRectangle(cornerRadius:9)) }.buttonStyle(.plain)
                HStack(spacing:12) { Button("保存进度  X") { engine.quickSave() }; Button("读取进度  Y") { engine.quickLoad() } }.buttonStyle(.bordered).font(.system(size:12))
                HStack(spacing:20) { Button("手柄与双人") { sheet="controllers" }; Button("画面设置") { sheet="settings" }; Button("金手指") { sheet="cheats" }; Button("重启游戏") { engine.reset(); engine.setPaused(false) } }.buttonStyle(.plain).font(.system(size:11)).foregroundStyle(Palette.muted)
                Button("返回游戏库  B") { engine.stop() }.buttonStyle(.plain).font(.system(size:12)).foregroundStyle(Palette.muted)
                Text("返回时自动保存进度，下次启动可继续。").font(.system(size:10)).foregroundStyle(Palette.muted.opacity(0.65))
            }.padding(35).background(Palette.panel,in:RoundedRectangle(cornerRadius:18)).overlay { RoundedRectangle(cornerRadius:18).stroke(Palette.line,lineWidth:1) }
        }
    }
    private var settings: some View {
        VStack(alignment:.leading,spacing:22) {
            HStack { Text("画面与设置").font(.system(size:22,weight:.semibold)); Spacer(); Button("完成") { sheet=nil }.keyboardShortcut(.cancelAction) }
            Text("让像素保持你记忆里的样子。").font(.system(size:12)).foregroundStyle(Palette.muted)
            Toggle("优先排列中文游戏版本",isOn:$preferChinese)
            Text("游戏库提供中文译名，原名保留以便搜索。游戏内语言以版本标识为准；文件名标注的汉化版尚未进行内容校验。").font(.system(size:11)).foregroundStyle(Palette.muted).lineSpacing(4)
            Picker("画面比例",selection:$screenMode) { ForEach(ScreenMode.allCases) { Text($0.rawValue).tag($0.rawValue) } }.pickerStyle(.segmented)
            Text("原始比例保持主机的显示比例；整数倍保持方形像素；铺满屏幕可能拉伸画面。全屏时会跟随显示器尺寸缩放。").font(.system(size:11)).foregroundStyle(Palette.muted).lineSpacing(4)
            Toggle("柔和显示",isOn:$smooth)
            Toggle("CRT 扫描线",isOn:$scanlines)
            Divider()
            Text("快捷键").font(.system(size:13,weight:.semibold))
            HStack { Text("全屏  ⌃⌘F     暂停  Esc     保存  ⌘S     读档  ⌘L").font(.system(size:12,design:.monospaced)) }
            Divider()
            Text("本地文件").font(.system(size:13,weight:.semibold))
            HStack { Button("打开游戏与存档目录") { NSWorkspace.shared.open(LibraryPaths.root) }; Button("打开 BIOS 目录") { NSWorkspace.shared.open(LibraryPaths.bios) } }.buttonStyle(.bordered)
            Text("街机 ROM 需要与 FBNeo 版本匹配。将需要的 BIOS 放入 BIOS 目录；neogeo.zip 也可放在这里。游戏运行和存档无需网络。").font(.system(size:11)).foregroundStyle(Palette.muted).lineSpacing(4)
            Text("Game Bench · 本地版 0.4.1 · Apple Silicon").font(.system(size:10,design:.monospaced)).foregroundStyle(Palette.muted)
        }.padding(30).frame(width:550).background(Palette.background)
    }
    private func handleAction(_ action: PadAction) {
        if engine.game != nil {
            switch action {
            case .pause: engine.togglePause()
            case .confirm: if engine.paused { engine.setPaused(false) }
            case .back: if engine.paused { engine.stop() }
            case .save: engine.quickSave()
            case .load: engine.quickLoad()
            default: break
            }
            return
        }
        let games=filtered
        let index=games.firstIndex { $0.id==selected } ?? 0
        switch action {
        case .confirm: if games.indices.contains(index) { engine.launch(games[index]) }
        case .favorite: if games.indices.contains(index) { library.toggleFavorite(games[index]) }
        case .diagnostics: sheet="controllers"
        case .up: if !games.isEmpty { selected=games[max(0,index-columns)].id }
        case .down: if !games.isEmpty { selected=games[min(games.count-1,index+columns)].id }
        case .left: if !games.isEmpty { selected=games[max(0,index-1)].id }
        case .right: if !games.isEmpty { selected=games[min(games.count-1,index+1)].id }
        default: break
        }
    }
}

struct SheetItem: Identifiable { var id: String; init(_ id: String) { self.id=id } }

struct KeyHint: View {
    let key: String
    let text: String
    var color: Color=Palette.muted
    var body: some View { HStack(spacing:6) { Text(key).font(.system(size:9,weight:.bold,design:.monospaced)).foregroundStyle(color).frame(width:18,height:18).overlay(Circle().stroke(color.opacity(0.45),lineWidth:1)); Text(text).font(.system(size:10)).foregroundStyle(Palette.muted) } }
}

struct GameCard: View {
    let game: Game
    var selected: Bool
    let launch: ()->Void
    let select: ()->Void
    let favorite: ()->Void
    @State<Bool> private var hover=false
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            ZStack(alignment:.topLeading) {
                if let coverURL=LibraryPaths.cover(game),let image=CoverCache.image(coverURL.path) {
                    GeometryReader { geo in Image(nsImage:image).resizable().interpolation(.none).scaledToFill().frame(width:geo.size.width,height:geo.size.height).clipped() }
                } else { RetroArt(style:game.system,demo:game.isDemo,seed:game.title) }
                HStack { Text(game.isDemo ? "自制 · 双人" : game.system.subtitle).font(.system(size:8,weight:.medium,design:.monospaced)).padding(.horizontal,7).padding(.vertical,5).background(.black.opacity(0.4),in:Capsule()); Spacer(); Button(action:favorite) { Image(systemName:game.favorite ? "heart.fill" : "heart").font(.system(size:11)).foregroundStyle(game.favorite ? .pink : .white.opacity(0.7)).padding(7).background(.black.opacity(0.3),in:Circle()) }.buttonStyle(.plain) }.padding(10)
                if hover { Color.black.opacity(0.15); Image(systemName:"play.fill").font(.system(size:22)).foregroundStyle(.white).frame(maxWidth:.infinity,maxHeight:.infinity) }
            }.frame(height:150).contentShape(Rectangle()).clipShape(RoundedRectangle(cornerRadius:10)).overlay { RoundedRectangle(cornerRadius:10).stroke(selected ? Palette.accent : .clear,lineWidth:2) }
                .onTapGesture { select(); launch() }
                .onHover { hover=$0 }
                .accessibilityLabel(game.displayTitle).accessibilityAddTraits(.isButton)
                .accessibilityAction { launch() }
            HStack { Text(game.displayTitle).font(.system(size:13,weight:.medium)).lineLimit(1).help(game.title); Spacer(); Button(action:launch) { Image(systemName:"play.fill").font(.system(size:11)).foregroundStyle(Palette.accent).frame(width:30,height:30).contentShape(Rectangle()) }.buttonStyle(.plain).help("开始游戏") }
            if !game.isDemo { Text(game.languageLabel).font(.system(size:9)).foregroundStyle(game.hasChineseLabel ? Palette.accent : Palette.muted).lineLimit(1) }
            Text(game.isDemo ? "STAR PILOT  ·  1–2 PLAYERS" : (game.lastPlayed == nil ? (game.compatibilityNote != nil ? "兼容性待验证  ·  可尝试启动" : (game.featuredRank != nil ? "童年经典  ·  即点即玩" : "已安装  ·  \(game.system.title)")) : "已玩 \(game.playCount) 次  ·  可继续进度")).font(.system(size:9,design:.monospaced)).foregroundStyle(Palette.muted).lineLimit(1)
        }.padding(.bottom,3)
    }
}

struct RetroArt: View {
    var style: GameSystem
    var demo=false
    var seed=""
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors:[style.color.opacity(0.20),Color(red:0.08,green:0.11,blue:0.13)],startPoint:.topLeading,endPoint:.bottomTrailing)
                Canvas { context,size in
                    let cell: CGFloat=6
                    for x in stride(from:CGFloat(0),to:size.width,by:cell) { for y in stride(from:CGFloat(0),to:size.height,by:cell) {
                        if (Int(x/cell)*17+Int(y/cell)*31+seed.utf8.reduce(0){$0+Int($1)})%97==0 { context.fill(Path(CGRect(x:x,y:y,width:2,height:2)),with:.color(style.color.opacity(0.25))) }
                    } }
                    let pattern=demo ? ["00011000","00111100","00122100","01122110","11122111","11011011","00011000","00100100"] : ["01111110","11111111","11011011","10000001","11011011","11111111","11100111","11000011"]
                    let pixel=min(size.width/18,size.height/13)
                    let origin=CGPoint(x:(size.width-8*pixel)/2,y:(size.height-8*pixel)/2+8)
                    for (y,row) in pattern.enumerated() { for (x,ch) in row.enumerated() where ch != "0" {
                        context.fill(Path(CGRect(x:origin.x+CGFloat(x)*pixel,y:origin.y+CGFloat(y)*pixel,width:pixel-0.5,height:pixel-0.5)),with:.color(ch=="2" ? .white.opacity(0.9) : style.color))
                    } }
                    if demo { let rect=CGRect(x:size.width*0.76,y:size.height*0.32,width:7,height:7); context.fill(Path(rect),with:.color(.yellow.opacity(0.8))) }
                }
                Text(demo ? "STAR PILOT" : style.subtitle).font(.system(size:geo.size.width>200 ? 12 : 10,weight:.bold,design:.monospaced)).tracking(3).foregroundStyle(style.color.opacity(0.8)).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.bottom).padding(.bottom,15)
            }
        }
    }
}

struct ControllerPanel: View {
    @ObservedObject var controllers: ControllerCenter
    let close: ()->Void
    var body: some View {
        VStack(alignment:.leading,spacing:21) {
            HStack { VStack(alignment:.leading,spacing:7) { Text("一起通关，才够快乐。").font(.system(size:22,weight:.semibold)); Text("本地双人 · 插入第二只手柄即可加入").font(.system(size:12)).foregroundStyle(Palette.muted) }; Spacer(); Button("完成",action:close).keyboardShortcut(.cancelAction) }
            HStack(alignment:.top,spacing:16) {
                ForEach(0..<2,id:\.self) { i in
                    let pad=controllers.pads[i]
                    VStack(alignment:.leading,spacing:17) {
                        HStack { Text("\(i+1)P").font(.system(size:14,weight:.bold,design:.monospaced)).foregroundStyle(i==0 ? Palette.accent : .cyan); Spacer(); Circle().fill(pad.connected ? Palette.accent : Palette.muted).frame(width:6,height:6); Text(pad.connected ? "已连接" : "键盘").font(.system(size:10)).foregroundStyle(Palette.muted) }
                        Text(pad.name).font(.system(size:16,weight:.semibold)); Text(pad.detail).font(.system(size:11)).foregroundStyle(Palette.muted)
                        ZStack { Image(systemName:"gamecontroller").font(.system(size:100,weight:.ultraLight)).foregroundStyle(pad.connected ? Color.white.opacity(0.6) : Palette.muted.opacity(0.4)); Circle().fill(Palette.accent.opacity(0.85)).frame(width:8,height:8).offset(x:CGFloat(pad.leftX)*32-23,y: -CGFloat(pad.leftY)*20+9).opacity(pad.connected ? 1 : 0) }.frame(maxWidth:.infinity).frame(height:100)
                        HStack(spacing:9) { ForEach(["A","B","X","Y"],id:\.self) { key in Text(key).font(.system(size:12,weight:.semibold,design:.monospaced)).frame(width:30,height:30).background(pad.buttons.contains(key) ? Palette.accent : Palette.background,in:Circle()).foregroundStyle(pad.buttons.contains(key) ? .black : Palette.muted) } }
                        Text(pad.buttons.isEmpty ? "按下按键，查看实时响应" : pad.buttons.sorted().joined(separator:"  ")).font(.system(size:10,design:.monospaced)).foregroundStyle(Palette.accent).frame(height:28,alignment:.leading)
                        if let battery=pad.battery { Text("电量 \(battery)%").font(.system(size:10)).foregroundStyle(Palette.muted) }
                    }.padding(19).frame(maxWidth:.infinity,alignment:.leading).background(Palette.panel,in:RoundedRectangle(cornerRadius:12))
                }
            }
            Toggle("交换手柄 A / B 键",isOn:$controllers.swapAB).onChange(of:controllers.swapAB) { _,_ in controllers.savePreferences() }.font(.system(size:12))
            Text("默认按位置映射：Xbox A → 红白机 B，Xbox B → 红白机 A；可在上方交换。方向键和左摇杆均可移动。").font(.system(size:11)).foregroundStyle(Palette.muted).lineSpacing(4)
            Divider()
            HStack(alignment:.top,spacing:25) {
                VStack(alignment:.leading,spacing:7) { Text("1P 键盘").font(.system(size:11,weight:.semibold)); Text("方向键 移动 · Z / X 动作\nEnter 开始 · Shift 选择 / 投币").font(.system(size:11)).foregroundStyle(Palette.muted).lineSpacing(5) }
                VStack(alignment:.leading,spacing:7) { Text("2P 键盘").font(.system(size:11,weight:.semibold)); Text("WASD 移动 · J / K 动作\nT 开始 · R 选择 / 投币").font(.system(size:11)).foregroundStyle(Palette.muted).lineSpacing(5) }
            }
            Text("手柄：进入游戏后第一次按 A 可直接开始；View 选择 / 投币，Menu 也可开始；LB + RB 打开暂停菜单。双人同时玩或轮流玩取决于游戏本身。").font(.system(size:11)).foregroundStyle(Palette.muted).lineSpacing(4)
        }.padding(29).frame(width:650).background(Palette.background)
    }
}
