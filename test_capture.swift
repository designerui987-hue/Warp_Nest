import Cocoa
import CoreGraphics
import ImageIO

let windowID = CGWindowID(1328)
let imageRef = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming, .bestResolution])

if let img = imageRef {
    let destURL = URL(fileURLWithPath: "/Volumes/Personal/WarpNest/scratch/steam_window.png")
    if let dest = CGImageDestinationCreateWithURL(destURL as CFURL, kUTTypePNG, 1, nil) {
        CGImageDestinationAddImage(dest, img, nil)
        if CGImageDestinationFinalize(dest) {
            print("Successfully saved steam_window.png: \(img.width)x\(img.height)")
        } else {
            print("Failed to finalize image destination")
        }
    } else {
        print("Failed to create image destination")
    }
} else {
    print("CGWindowListCreateImage returned nil (Screen Recording TCC permission likely required)")
}
