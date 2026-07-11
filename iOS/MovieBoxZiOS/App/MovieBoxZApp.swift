import SwiftUI
import UIKit

// MARK: - Landscape-locked hosting controller
// The root UIViewController MUST return .landscape from supportedInterfaceOrientations.
// This is the only mechanism iOS reliably honours from the very first frame.
final class LandscapeHostingController<Content: View>: UIHostingController<Content> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .landscape
    }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        .landscapeRight
    }
    override var shouldAutorotate: Bool { true }
    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }
}

// MARK: - AppDelegate
final class AppDelegate: NSObject, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UIWindow.appearance().backgroundColor = .black
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .landscape
    }
}

// MARK: - Scene Delegate
// We use a UIWindowSceneDelegate to create the window ourselves and install
// LandscapeHostingController as the root VC before the first frame.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let hostingController = LandscapeHostingController(rootView: RootEntryView())

        let win = UIWindow(windowScene: windowScene)
        win.backgroundColor = .black
        win.rootViewController = hostingController
        win.makeKeyAndVisible()

        // Request landscape after window is visible so geometry update applies to correct bounds
        let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .landscape)
        windowScene.requestGeometryUpdate(prefs) { _ in }
        self.window = win
    }
}

// MARK: - Root entry view
struct RootEntryView: View {
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    private var isUITesting: Bool {
        CommandLine.arguments.contains("UI_TESTING_SKIP_WELCOME")
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if hasSeenWelcome || isUITesting {
                SplashScreenView()
                    .ignoresSafeArea()
            } else {
                WelcomeView(hasSeenWelcome: $hasSeenWelcome)
                    .ignoresSafeArea()
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}
