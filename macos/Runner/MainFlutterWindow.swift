import Cocoa
import FlutterMacOS
import audio_session
import desktop_multi_window
import file_picker
import hotkey_manager_macos
import just_audio
import package_info_plus
import screen_retriever_macos
import shared_preferences_foundation
import video_player_avfoundation
import wakelock_plus
import window_manager

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      // Do not register FlutterMultiWindowPlugin again in sub windows.
      AudioSessionPlugin.register(
        with: controller.registrar(forPlugin: "AudioSessionPlugin")
      )
      FilePickerPlugin.register(
        with: controller.registrar(forPlugin: "FilePickerPlugin")
      )
      HotkeyManagerMacosPlugin.register(
        with: controller.registrar(forPlugin: "HotkeyManagerMacosPlugin")
      )
      JustAudioPlugin.register(
        with: controller.registrar(forPlugin: "JustAudioPlugin")
      )
      FPPPackageInfoPlusPlugin.register(
        with: controller.registrar(forPlugin: "FPPPackageInfoPlusPlugin")
      )
      ScreenRetrieverMacosPlugin.register(
        with: controller.registrar(forPlugin: "ScreenRetrieverMacosPlugin")
      )
      SharedPreferencesPlugin.register(
        with: controller.registrar(forPlugin: "SharedPreferencesPlugin")
      )
      FVPVideoPlayerPlugin.register(
        with: controller.registrar(forPlugin: "FVPVideoPlayerPlugin")
      )
      WakelockPlusMacosPlugin.register(
        with: controller.registrar(forPlugin: "WakelockPlusMacosPlugin")
      )
      WindowManagerPlugin.register(
        with: controller.registrar(forPlugin: "WindowManagerPlugin")
      )
    }

    super.awakeFromNib()
  }
}
