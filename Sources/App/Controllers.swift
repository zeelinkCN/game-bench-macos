import AppKit
import GameController
import IOKit.hid
import SwiftUI

struct PadStatus: Equatable {
    var name="未连接手柄"
    var detail="可使用键盘"
    var connected=false
    var buttons=Set<String>()
    var leftX: Float=0
    var leftY: Float=0
    var battery: Int?
}

enum PadAction: Equatable { case up, down, left, right, confirm, back, favorite, diagnostics, pause, save, load }

final class ControllerCenter: ObservableObject {
    @Published var pads=[PadStatus(),PadStatus()]
    @Published var swapAB=false
    @Published var keyboardEnabled=true
    var onAction: ((PadAction)->Void)?
    var inGame=false {
        didSet {
            if inGame && !oldValue {
                startAssistArmed=true
                startAssistDeadline=ProcessInfo.processInfo.systemUptime+60
            } else if !inGame { startAssistArmed=false }
        }
    }
    var isPaused=false
    var modalOpen=false
    private var slots: [GCController?]=[nil,nil]
    private var observer: [NSObjectProtocol]=[]
    private var timer: Timer?
    private var keys=Set<UInt16>()
    private var monitor: Any?
    private var releaseObserver: NSObjectProtocol?
    private var lastButtons=[Set<String>(),Set<String>()]
    private var heldDirection: PadAction?
    private var nextRepeat: TimeInterval=0
    private var chordWasDown=false
    private var startAssistArmed=false
    private var startAssistDeadline: TimeInterval=0
    init(monitorDevices: Bool=true) {
        swapAB=UserDefaults.standard.bool(forKey:"swapAB")
        guard monitorDevices else { return }
        GCController.shouldMonitorBackgroundEvents=false
        for name in [NSNotification.Name.GCControllerDidConnect,.GCControllerDidDisconnect] {
            observer.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in self?.refresh() })
        }
        releaseObserver=NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:nil,queue:.main) { [weak self] _ in
            self?.keys.removeAll()
            for i in 0..<4 { gb_set_input(UInt32(i),0) }
        }
        monitor=NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.keyUp,.flagsChanged]) { [weak self] event in
            guard let self=self else { return event }
            if event.type == .flagsChanged {
                if event.modifierFlags.contains(.shift) { self.keys.insert(56) } else { self.keys.remove(56); self.keys.remove(60) }
                return event
            }
            guard self.inGame, !self.modalOpen else { return event }
            if event.modifierFlags.intersection([.command,.option,.control]).isEmpty {
                if event.type == .keyDown {
                    if event.keyCode==53 && !event.isARepeat { self.onAction?(.pause); return nil }
                    self.keys.insert(event.keyCode)
                } else { self.keys.remove(event.keyCode) }
                return nil
            }
            return event
        }
        refresh()
        timer=Timer.scheduledTimer(withTimeInterval:1.0/60,repeats:true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer!,forMode:.common)
    }
    func refresh() {
        let all=GCController.controllers().filter { $0.extendedGamepad != nil }
        for i in 0..<2 {
            if let pad=slots[i],!all.contains(where: { $0 === pad }) { slots[i]=nil; lastButtons[i]=[]; if inGame && !isPaused { onAction?(.pause) } }
        }
        for pad in all where !slots.contains(where: { $0 === pad }) {
            if let i=slots.firstIndex(where: { $0 == nil }) { slots[i]=pad; pad.playerIndex=i==0 ? .index1 : .index2 }
        }
        let usb=usbGamepadName()
        for i in 0..<2 {
            if let c=slots[i] {
                pads[i].connected=true
                pads[i].name=c.productCategory==GCProductCategoryXboxOne ? "Xbox 手柄" : (c.vendorName ?? "游戏手柄")
                pads[i].detail=(all.count==1 && usb != nil) ? "USB 有线" : "已就绪"
            } else { pads[i]=PadStatus(name:"\(i+1)P · 键盘", detail:i==0 ? "方向键 · Z / X" : "WASD · J / K") }
        }
    }
    private func usbGamepadName() -> String? {
        let manager=IOHIDManagerCreate(kCFAllocatorDefault,IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager,[kIOHIDDeviceUsagePageKey:1,kIOHIDDeviceUsageKey:5] as CFDictionary)
        guard let devices=IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return nil }
        return devices.first(where: { (IOHIDDeviceGetProperty($0,kIOHIDTransportKey as CFString) as? String)=="USB" }).map { IOHIDDeviceGetProperty($0,kIOHIDProductKey as CFString) as? String ?? "USB 手柄" }
    }
    private func poll() {
        guard NSApp.isActive else { return }
        var states=[Set<String>(),Set<String>()]
        var masks=[UInt16(0),UInt16(0)]
        for i in 0..<2 {
            guard let g=slots[i]?.extendedGamepad else { continue }
            var b=Set<String>()
            for (name,button) in [("A",g.buttonA),("B",g.buttonB),("X",g.buttonX),("Y",g.buttonY),("LB",g.leftShoulder),("RB",g.rightShoulder),("LT",g.leftTrigger),("RT",g.rightTrigger),("Start",g.buttonMenu)] where button.isPressed { b.insert(name) }
            if g.buttonOptions?.isPressed==true { b.insert("Select") }
            if g.leftThumbstickButton?.isPressed==true { b.insert("L3") }
            if g.rightThumbstickButton?.isPressed==true { b.insert("R3") }
            if g.dpad.up.isPressed || g.leftThumbstick.yAxis.value>0.40 { b.insert("↑") }
            if g.dpad.down.isPressed || g.leftThumbstick.yAxis.value < -0.40 { b.insert("↓") }
            if g.dpad.left.isPressed || g.leftThumbstick.xAxis.value < -0.40 { b.insert("←") }
            if g.dpad.right.isPressed || g.leftThumbstick.xAxis.value>0.40 { b.insert("→") }
            states[i]=b
            let newStatus=PadStatus(name:pads[i].name,detail:pads[i].detail,connected:true,buttons:b,leftX:(g.leftThumbstick.xAxis.value*20).rounded()/20,leftY:(g.leftThumbstick.yAxis.value*20).rounded()/20,battery:slots[i]?.battery.map { Int($0.batteryLevel*100) })
            updateStatus(newStatus,at:i)
            for (name,bit) in [("A",0),("X",1),("Select",2),("Start",3),("↑",4),("↓",5),("←",6),("→",7),("B",8),("Y",9),("LB",10),("RB",11),("LT",12),("RT",13),("L3",14),("R3",15)] where b.contains(name) { masks[i] |= UInt16(1)<<bit }
            if swapAB {
                let a=(masks[i]>>0)&1, b=(masks[i]>>8)&1
                masks[i] &= ~((1<<0)|(1<<8)); masks[i] |= (a<<8)|b
            }
        }
        if keyboardEnabled && inGame && !modalOpen {
            let mapping: [[(UInt16,Int)]]=[[(126,4),(125,5),(123,6),(124,7),(6,0),(7,8),(8,1),(9,9),(36,3),(56,2),(3,10),(5,11)],[(13,4),(1,5),(0,6),(2,7),(38,0),(40,8),(32,1),(34,9),(17,3),(15,2),(31,10),(37,11)]]
            for i in 0..<2 { for (key,bit) in mapping[i] where keys.contains(key) { masks[i] |= UInt16(1)<<bit } }
        }
        // The first Xbox A press after launch also sends one Start pulse. This
        // makes library selection flow directly into the title screen while
        // disarming immediately so gameplay actions never trigger Start again.
        if inGame && startAssistArmed {
            if (masks[0] & (UInt16(1)<<3)) != 0 || ProcessInfo.processInfo.systemUptime>startAssistDeadline {
                startAssistArmed=false
            } else if states[0].contains("A") {
                masks[0] |= UInt16(1)<<3
                startAssistArmed=false
            }
        }
        let chord=states.contains(where:{ $0.contains("LB") && $0.contains("RB") })
        if chord && !chordWasDown && inGame && !modalOpen { onAction?(.pause) }
        chordWasDown=chord
        if inGame && !isPaused && !modalOpen {
            for i in 0..<2 { gb_set_input(UInt32(i),masks[i]) }
        } else {
            for i in 0..<2 { gb_set_input(UInt32(i),0) }
            if !modalOpen {
                let b=states[0].union(states[1]), old=lastButtons[0].union(lastButtons[1])
                if b.contains("A") && !old.contains("A") { onAction?(.confirm) }
                if b.contains("B") && !old.contains("B") { onAction?(.back) }
                if b.contains("X") && !old.contains("X") { onAction?(inGame ? .save : .favorite) }
                if b.contains("Y") && !old.contains("Y") { onAction?(inGame ? .load : .diagnostics) }
                var direction: PadAction?
                if b.contains("↑") { direction = .up } else if b.contains("↓") { direction = .down } else if b.contains("←") { direction = .left } else if b.contains("→") { direction = .right }
                let now=ProcessInfo.processInfo.systemUptime
                if let d=direction {
                    if direction != heldDirection { onAction?(d); nextRepeat=now+0.34 }
                    else if now>=nextRepeat { onAction?(d); nextRepeat=now+0.14 }
                }
                heldDirection=direction
            }
        }
        lastButtons=states
    }
    func savePreferences() { UserDefaults.standard.set(swapAB,forKey:"swapAB") }
    func updateStatus(_ status: PadStatus, at index: Int) {
        // Raw buttons/axes go directly to the core above. Publishing them also
        // invalidates the entire SwiftUI player, so only the diagnostics panel
        // needs to observe those values while a game is running.
        var visible=status
        if inGame && !modalOpen {
            visible.buttons=[]; visible.leftX=0; visible.leftY=0
        }
        if pads[index] != visible { pads[index]=visible }
    }
}
