Pod::Spec.new do |s|
  s.name             = 'flutter_video_thumbnail_plus'
  s.version          = '1.0.0'
  s.summary          = 'A Flutter package for generating thumbnails from videos.'
  s.description      = <<-DESC
Generate thumbnails from video files on macOS.
                       DESC
  s.homepage         = 'https://github.com/rahulsaryam285/flutter_video_thumbnail_plus'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Flutter Team' => 'flutter-dev@googlegroups.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'flutter_video_thumbnail_plus/Sources/flutter_video_thumbnail_plus/**/*.swift'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'
  s.swift_version = '5.0'
end
