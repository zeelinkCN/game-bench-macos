import AppKit
let root=URL(fileURLWithPath:CommandLine.arguments[1])
let image=NSImage(size:NSSize(width:1024,height:1024))
image.lockFocus()
NSColor.clear.setFill(); NSRect(x:0,y:0,width:1024,height:1024).fill()
NSColor(calibratedRed:0.10,green:0.13,blue:0.13,alpha:1).setFill()
NSBezierPath(roundedRect:NSRect(x:70,y:70,width:884,height:884),xRadius:195,yRadius:195).fill()
let rows=["00100100","00011000","00111100","01111110","11011011","11111111","00100100","01000010"]
NSColor(calibratedRed:0.8,green:0.94,blue:0.51,alpha:1).setFill()
for (y,row) in rows.enumerated() { for (x,c) in row.enumerated() where c=="1" { NSRect(x:256+x*64,y:704-y*64,width:60,height:60).fill() } }
image.unlockFocus()
let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!
try rep.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("build/icon.png"))
