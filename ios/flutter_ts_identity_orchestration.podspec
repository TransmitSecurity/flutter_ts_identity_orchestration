#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_ts_identity_orchestration.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_ts_identity_orchestration'
  s.version          = '0.0.5'
  s.summary          = 'A flutter plugin for identity orchestration'
  s.description      = <<-DESC
A flutter plugin for identity orchestration.
                       DESC
  s.homepage         = 'https://www.transmitsecurity.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Transmit Security' => 'transmitsecurity.com' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_ts_identity_orchestration/Sources/flutter_ts_identity_orchestration/**/*'
  s.dependency 'Flutter'
  
  # Since IdentityOrchestration might not be on CocoaPods, remove this line
  # s.dependency 'IdentityOrchestration'
  
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  s.prepare_command = <<-CMD
    if [ -f Package.swift ]; then
      echo "SPM Package.swift found"
    fi
  CMD

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'flutter_ts_identity_orchestration_privacy' => ['flutter_ts_identity_orchestration/Sources/flutter_ts_identity_orchestration/PrivacyInfo.xcprivacy']}
end
