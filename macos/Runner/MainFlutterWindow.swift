import Cocoa
import FlutterMacOS
import audio_session
import desktop_multi_window
import file_picker
import hotkey_manager_macos
import just_audio
import media_kit_libs_macos_video
import media_kit_video
import package_info_plus
import screen_retriever_macos
import shared_preferences_foundation
import volume_controller
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
      MediaKitLibsMacosVideoPlugin.register(
        with: controller.registrar(forPlugin: "MediaKitLibsMacosVideoPlugin")
      )
      MediaKitVideoPlugin.register(
        with: controller.registrar(forPlugin: "MediaKitVideoPlugin")
      )
      VolumeControllerPlugin.register(
        with: controller.registrar(forPlugin: "VolumeControllerPlugin")
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
