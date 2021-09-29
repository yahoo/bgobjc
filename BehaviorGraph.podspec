#
# Be sure to run `pod lib lint BehaviorGraph.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'BehaviorGraph'
  s.version          = '0.5.0'
  s.summary          = 'Behavior Graph is a software library that greatly enhances our ability to program user facing software and control systems.'

  s.description      = <<-DESC
Behavior Graph  is a software library that greatly enhances our ability to program user facing software and control systems. Programs of this type quickly scale up in complexity as features are added. Behavior Graph directly addresses this complexity by shifting more of the burden to the computer. It works by offering the programmer a new unit of code organization called a behavior. Behaviors are blocks of code enriched with additional information about their stateful relationships. Using this information, Behavior Graph enforces _safe use of mutable state_, arguably the primary source of complexity in this class of software. It does this by taking on the responsibility of control flow between behaviors, ensuring they are are _run at the correct time and in the correct order_.
                       DESC

  s.homepage         = 'https://github.com/yahoo/bgobjc'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'apache-2.0', :file => 'LICENSE' }
  s.author           = { 'Sean Levin' => 'slevin@yahooinc.com',
                         'James Lou' => 'jlou@yahooinc.com' }
  s.source           = { :git => 'https://github.com/yahoo/bgobjc.git', :tag => s.version.to_s }

  s.ios.deployment_target = '9.0'

  s.source_files = 'BehaviorGraph/Classes/**/*'
  s.public_header_files = 'BehaviorGraph/Classes/Public/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
end
