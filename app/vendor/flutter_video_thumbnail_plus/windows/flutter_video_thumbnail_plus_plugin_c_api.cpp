#include "include/flutter_video_thumbnail_plus/flutter_video_thumbnail_plus_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_video_thumbnail_plus_plugin.h"

void FlutterVideoThumbnailPlusPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_video_thumbnail_plus::FlutterVideoThumbnailPlusPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
