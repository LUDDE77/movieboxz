import UIKit

// main.swift replaces the @main attribute on MovieBoxZApp.
// It boots UIApplication with our AppDelegate, which wires SceneDelegate
// through UIApplicationSceneManifest in Info.plist.
// This is the entry point — Swift requires it to be in main.swift (not a @main type).
UIApplicationMain(
    CommandLine.argc,
    CommandLine.unsafeArgv,
    nil,
    NSStringFromClass(AppDelegate.self)
)
