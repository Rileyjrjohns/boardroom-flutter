Pod::Spec.new do |s|
  s.name             = 'screen_protection'
  s.version          = '0.1.0'
  s.summary          = 'Blocks screenshots and screen recording and reports attempts.'
  s.description      = <<-DESC
A privacy cover in the app switcher, the detection of screenshots and recordings, and a secure view
that leaves its content out of captures.
                       DESC
  s.homepage         = 'https://github.com/'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Boardroom' => 'noreply@example.invalid' }
  s.source           = { :path => '.' }
  s.source_files = 'screen_protection/Sources/screen_protection/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
