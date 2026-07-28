require 'xcodeproj'

project_path = './HereIsland.xcodeproj'
scheme_path = Xcodeproj::XCScheme.shared_data_dir(project_path) + 'HereIsland.xcscheme'

scheme = Xcodeproj::XCScheme.new(scheme_path)
project = Xcodeproj::Project.open(project_path)

ui_test_target = project.targets.find { |t| t.name == 'HereIslandUITests' }

testable_ref = Xcodeproj::XCScheme::TestAction::TestableReference.new(ui_test_target)
scheme.test_action.add_testable(testable_ref)
scheme.save!

puts "Successfully added to HereIsland.xcscheme"
