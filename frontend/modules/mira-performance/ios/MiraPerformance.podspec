Pod::Spec.new do |s|
  s.name           = 'MiraPerformance'
  s.version        = '1.0.0'
  s.summary        = 'Native performance helpers for MIRA'
  s.description    = 'Small Swift helpers for stable media cache keys and lightweight feed scoring.'
  s.author         = ''
  s.homepage       = 'https://docs.expo.dev/modules/'
  s.platforms      = {
    :ios => '15.1',
    :tvos => '15.1'
  }
  s.source         = { git: '' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  # Swift/Objective-C compatibility
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
  }

  s.source_files = "**/*.{h,m,mm,swift,hpp,cpp}"
end
