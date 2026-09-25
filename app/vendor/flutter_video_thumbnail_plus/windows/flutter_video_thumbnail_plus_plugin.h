#ifndef FLUTTER_PLUGIN_FLUTTER_VIDEO_THUMBNAIL_PLUS_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_VIDEO_THUMBNAIL_PLUS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace flutter_video_thumbnail_plus {

class FlutterVideoThumbnailPlusPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  FlutterVideoThumbnailPlusPlugin();
  ~FlutterVideoThumbnailPlusPlugin() override;

  FlutterVideoThumbnailPlusPlugin(const FlutterVideoThumbnailPlusPlugin&) = delete;
  FlutterVideoThumbnailPlusPlugin& operator=(const FlutterVideoThumbnailPlusPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace flutter_video_thumbnail_plus

#endif  // FLUTTER_PLUGIN_FLUTTER_VIDEO_THUMBNAIL_PLUS_PLUGIN_H_
