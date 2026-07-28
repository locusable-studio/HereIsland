require 'xcodeproj'

project_path = './HereIsland.xcodeproj'
project = Xcodeproj::Project.open(project_path)

ui_test_target = project.targets.find { |t| t.name == 'HereIslandUITests' }

ui_test_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = 'HereIslandUITests'
  config.build_settings['PRODUCT_MODULE_NAME'] = 'HereIslandUITests'
end

project.save
puts "Successfully updated build settings."
