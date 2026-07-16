# Adds the two iOS app-extension targets Phase 12 needs to Runner.xcodeproj.
#
# Done with the `xcodeproj` gem (which CocoaPods already vendors) rather than by
# hand-editing project.pbxproj: a target is ~10 interlinked object graphs — native
# target, build phases, configuration list, container proxy, dependency, and the
# embed phase on Runner — each keyed by a 24-hex UUID that must be unique and
# cross-referenced correctly. Hand-writing that is how you corrupt a project file.
#
# Idempotent: re-running removes and recreates the targets rather than adding a
# second copy.

require 'xcodeproj'

PROJECT   = 'ios/Runner.xcodeproj'
GROUP_ID  = 'group.com.karthik.everythingApp'
APP_ID    = 'com.karthik.everythingApp'
# Must match `ios/Podfile`'s `platform :ios` and the Runner target's
# IPHONEOS_DEPLOYMENT_TARGET. Raised 14.0 → 16.0 in Phase 13: flutter_gemma needs
# 16.0, and an extension left below the app it embeds in fails to link against
# the same pods.
DEPLOY    = '16.0'

SHARE_NAME  = 'Share Extension'
WIDGET_NAME = 'EverythingWidget'

project = Xcodeproj::Project.open(PROJECT)
runner  = project.targets.find { |t| t.name == 'Runner' }
raise 'Runner target not found' unless runner

# --- Clean out any previous run -------------------------------------------------
[SHARE_NAME, WIDGET_NAME].each do |name|
  project.targets.select { |t| t.name == name }.each do |target|
    # Drop the embed-phase entry and the dependency Runner holds on it first,
    # or removing the target leaves dangling references that Xcode reports as a
    # corrupt project.
    runner.build_phases.grep(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase).each do |phase|
      phase.files.dup.each do |f|
        phase.remove_build_file(f) if f.display_name.to_s.include?(name)
      end
    end
    runner.dependencies.dup.each do |dep|
      dep.remove_from_project if dep.target == target
    end
    target.remove_from_project
  end
  project.main_group.children.dup.each do |child|
    child.remove_from_project if child.display_name == name
  end
end

# --- Runner: app group entitlement + the group id as a build setting ------------
runner.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
  # Read by the share extension's Info.plist as $(CUSTOM_GROUP_ID), so the id is
  # written once and cannot drift between targets.
  config.build_settings['CUSTOM_GROUP_ID'] = GROUP_ID
end

# --- Helper ---------------------------------------------------------------------
def configure(target, name, bundle_suffix, entitlements, deploy, group_id, app_id)
  target.build_configurations.each do |config|
    s = config.build_settings
    s['PRODUCT_BUNDLE_IDENTIFIER'] = "#{app_id}.#{bundle_suffix}"
    s['PRODUCT_NAME']              = '$(TARGET_NAME)'
    s['IPHONEOS_DEPLOYMENT_TARGET'] = deploy
    s['CODE_SIGN_ENTITLEMENTS']    = "#{name}/#{entitlements}"
    s['INFOPLIST_FILE']            = "#{name}/Info.plist"
    s['CUSTOM_GROUP_ID']           = group_id
    s['SWIFT_VERSION']             = '5.0'
    s['TARGETED_DEVICE_FAMILY']    = '1,2'
    s['SKIP_INSTALL']              = 'YES'
    # An app extension is loaded into a host process, so it must be able to find
    # its frameworks relative to the containing app rather than to itself.
    s['LD_RUNPATH_SEARCH_PATHS']   = [
      '$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'
    ]
    s['CODE_SIGN_STYLE'] = 'Automatic'
  end
end

# --- Share Extension ------------------------------------------------------------
share = project.new_target(
  :app_extension, SHARE_NAME, :ios, DEPLOY, nil, :swift
)
configure(share, SHARE_NAME, 'ShareExtension', 'Share Extension.entitlements',
          DEPLOY, GROUP_ID, APP_ID)

share_group = project.main_group.new_group(SHARE_NAME, SHARE_NAME)
share.add_file_references([
  share_group.new_reference('ShareViewController.swift')
])
share.add_resources([
  share_group.new_reference('Base.lproj/MainInterface.storyboard')
])
share_group.new_reference('Info.plist')
share_group.new_reference('Share Extension.entitlements')

# The extension subclasses RSIShareViewController, which lives in the plugin's
# Swift package — so the target has to link that package's product. This mirrors
# exactly what the plugin's own example project does: a local package reference
# into Flutter's generated SPM checkout, plus a product dependency on the target.
#
# The path is Flutter's `ephemeral` directory, which is regenerated on every build
# and is gitignored. That much is fine — `flutter build` regenerates it before
# xcodebuild resolves packages, so a fresh clone works.
#
# The version in the path is NOT fine, and is worth knowing about: Flutter names
# these checkouts `<plugin>-<version>` from pubspec.lock, so bumping
# receive_sharing_intent renames the directory and this reference stops resolving.
# It fails loudly at build time ("cannot be accessed ... doesn't exist in file
# system") rather than silently, which is the only reason it is acceptable to pin.
# On upgrade, re-run this script with the new version.
#
# Read from the generated package rather than hardcoded, so the version here is
# whatever pub actually resolved rather than whatever was true when this was
# written.
generated = File.join(File.dirname(PROJECT),
                      'Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift')
version_match = File.exist?(generated) &&
                File.read(generated).match(%r{\.packages/(receive_sharing_intent-[\d.]+)})
raise 'receive_sharing_intent not found in the generated SPM package — run `flutter build ios` first' unless version_match

package_path = "Flutter/ephemeral/Packages/.packages/#{version_match[1]}"
puts "OK: linking share extension against #{package_path}"

pkg_ref = project.root_object.package_references.find do |ref|
  ref.is_a?(Xcodeproj::Project::Object::XCLocalSwiftPackageReference) &&
    ref.relative_path == package_path
end

unless pkg_ref
  pkg_ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
  pkg_ref.relative_path = package_path
  project.root_object.package_references << pkg_ref
end

product_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
product_dep.product_name = 'receive-sharing-intent'
share.package_product_dependencies << product_dep

share_link = share.frameworks_build_phase.add_file_reference(nil)
share_link.product_ref = product_dep

# --- Widget Extension -----------------------------------------------------------
widget = project.new_target(
  :app_extension, WIDGET_NAME, :ios, DEPLOY, nil, :swift
)
configure(widget, WIDGET_NAME, 'EverythingWidget', 'EverythingWidget.entitlements',
          DEPLOY, GROUP_ID, APP_ID)

widget.build_configurations.each do |config|
  # WidgetKit extensions are SwiftUI-only and have no UIKit entry point; without
  # this the linker cannot resolve the @main WidgetBundle.
  config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] ||= '$(inherited)'
end

widget_group = project.main_group.new_group(WIDGET_NAME, WIDGET_NAME)
widget.add_file_references([
  widget_group.new_reference('EverythingWidget.swift')
])
widget_group.new_reference('Info.plist')
widget_group.new_reference('EverythingWidget.entitlements')

# WidgetKit and SwiftUI are weak-linked: the extension targets iOS 14 but the
# containing app can run on a device where the widget is simply never loaded.
%w[WidgetKit.framework SwiftUI.framework].each do |fw|
  ref = project.frameworks_group.new_reference("System/Library/Frameworks/#{fw}")
  ref.source_tree = 'SDKROOT'
  build_file = widget.frameworks_build_phase.add_file_reference(ref)
  build_file.settings = { 'ATTRIBUTES' => ['Weak'] }
end

# --- Embed both into Runner -----------------------------------------------------
# dst_subfolder_spec 13 is "PlugIns", where iOS expects .appex bundles. Without
# this the extensions build but never ship inside the app, and nothing errors.
embed = runner.build_phases.find do |phase|
  phase.is_a?(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase) &&
    phase.name == 'Embed App Extensions'
end

unless embed
  embed = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  embed.name = 'Embed App Extensions'
  embed.symbol_dst_subfolder_spec = :plug_ins

  # Position matters, and appending is wrong. Flutter's "Thin Binary" script phase
  # rewrites the built .app, and Xcode declares a dependency cycle if a copy phase
  # mutates the bundle after it ("Cycle inside Runner; building could produce
  # unreliable results"). Embedding before it — right after Embed Frameworks, where
  # Xcode itself puts this phase — breaks the cycle.
  thin_binary = runner.build_phases.index do |phase|
    phase.respond_to?(:name) && phase.name.to_s.include?('Thin Binary')
  end

  if thin_binary
    runner.build_phases.insert(thin_binary, embed)
  else
    runner.build_phases << embed
  end
end

[share, widget].each do |target|
  runner.add_dependency(target)
  build_file = embed.add_file_reference(target.product_reference)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end

project.save

puts "OK: targets now = #{project.targets.map(&:name).join(', ')}"
puts "OK: Runner phases = #{runner.build_phases.map { |p| p.display_name }.join(' | ')}"
