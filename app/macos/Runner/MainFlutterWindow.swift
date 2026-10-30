import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Open at the desktop breakpoint; smaller windows fall back to the
    // phone layout.
    self.setContentSize(NSSize(width: 1180, height: 820))
    self.minSize = NSSize(width: 480, height: 640)
    self.center()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
