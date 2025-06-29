import CioInternalCommon
import UIKit

public typealias CioAppDelegateType = NSObject & UIApplicationDelegate

public typealias ConfigInstance = () -> MessagingPushConfigOptions

public typealias UserNotificationCenterInstance = () -> UserNotificationCenterIntegration

// sourcery: AutoMockable
public protocol UserNotificationCenterIntegration {
    var delegate: UNUserNotificationCenterDelegate? { get set }
}

extension UNUserNotificationCenter: UserNotificationCenterIntegration {}

private extension UIApplication {
    func cioRegisterForRemoteNotifications(logger: Logger) {
        logger.debug("CIO: Registering for remote notifications")
        registerForRemoteNotifications()
    }
}

@available(iOSApplicationExtension, unavailable)
open class CioProviderAgnosticAppDelegate: CioAppDelegateType, UNUserNotificationCenterDelegate {
    @_spi(Internal) public let messagingPush: MessagingPushInstance
    @_spi(Internal) public let logger: Logger
    @_spi(Internal) public var implementedOptionalMethods: Set<Selector> = [
        // UIApplicationDelegate
        #selector(UIApplicationDelegate.application(_:didFinishLaunchingWithOptions:)),
        #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)),
        #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:)),
        #selector(UIApplicationDelegate.application(_:continue:restorationHandler:)),
        // UNUserNotificationCenterDelegate
        #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:)),
        #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)),
        #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:openSettingsFor:))
    ]

    @_spi(Internal) public var config: ConfigInstance?

    private var userNotificationCenter: UserNotificationCenterInstance?
    private let wrappedAppDelegate: UIApplicationDelegate?
    private var wrappedNotificationCenterDelegate: UNUserNotificationCenterDelegate?

    override public convenience init() {
        DIGraphShared.shared.logger.error("CIO: This no-argument initializer should not to be used. Added since UIKit's AppDelegate initialization process crashes if for no-arg init is missing.")
        self.init(
            messagingPush: MessagingPush.shared,
            userNotificationCenter: { UNUserNotificationCenter.current() },
            appDelegate: nil,
            config: nil,
            logger: DIGraphShared.shared.logger
        )
    }

    public init(
        messagingPush: MessagingPushInstance,
        userNotificationCenter: UserNotificationCenterInstance?,
        appDelegate: CioAppDelegateType? = nil,
        config: ConfigInstance? = nil,
        logger: Logger
    ) {
        self.messagingPush = messagingPush
        self.userNotificationCenter = userNotificationCenter
        self.logger = logger
        self.config = config
        self.wrappedAppDelegate = appDelegate
        super.init()
    }

    open func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        MessagingPush.appDelegateIntegratedExplicitly = true

        let result = wrappedAppDelegate?.application?(application, didFinishLaunchingWithOptions: launchOptions)

        if config?().autoFetchDeviceToken ?? false {
            application.cioRegisterForRemoteNotifications(logger: logger)
        }

        if config?().autoTrackPushEvents ?? false,
           var center = userNotificationCenter?() {
            wrappedNotificationCenterDelegate = center.delegate
            center.delegate = self
        }

        return result ?? true
    }

    open func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        wrappedAppDelegate?.application?(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    open func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        wrappedAppDelegate?.application?(application, didFailToRegisterForRemoteNotificationsWithError: error)

        logger.error("CIO: Device token is deleted for current user. Failed to register for remote notifications: \(error.localizedDescription)")
        if config?().autoFetchDeviceToken ?? false {
            messagingPush.deleteDeviceToken()
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    open func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // `completionHandlerCalled` is used to overcome limitation of `responds(to:)` when working with optional methods from protocol.
        // Component may implement the protocol, but not specific optional method. In this case `responds(to:)` will return true.
        // Explicit flag, `completionHandlerCalled` in this case, allows us to detect if method is implemented, since it's required by Apple to
        // call `completionHandler` before returning.
        var completionHandlerCalled = false
        if let wrappedNotificationCenterDelegate = wrappedNotificationCenterDelegate,
           wrappedNotificationCenterDelegate.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))) {
            wrappedNotificationCenterDelegate.userNotificationCenter?(
                center,
                willPresent: notification,
                withCompletionHandler: { options in
                    completionHandler(options)
                    completionHandlerCalled = true
                }
            )
        }

        guard !completionHandlerCalled else { return }

        if config?().showPushAppInForeground ?? false {
            if #available(iOS 14.0, *) {
                completionHandler([.list, .banner, .badge, .sound])
            } else {
                completionHandler([.alert, .badge, .sound])
            }
        } else {
            // Don't show the notification in the foreground
            completionHandler([])
        }
    }

    // Function called when a push notification is clicked or swiped away.
    open func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        _ = messagingPush.userNotificationCenter(center, didReceive: response)

        // `completionHandlerCalled` is used to overcome limitation of `responds(to:)` when working with optional methods from protocol.
        // Component may implement the protocol, but not specific optional method. In this case `responds(to:)` will return true.
        // Explicit flag, `completionHandlerCalled` in this case, allows us to detect if method is implemented, since it's required by Apple to
        // call `completionHandler` before returning.
        var completionHandlerCalled = false
        if let wrappedNotificationCenterDelegate = wrappedNotificationCenterDelegate,
           wrappedNotificationCenterDelegate.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))) {
            wrappedNotificationCenterDelegate.userNotificationCenter?(
                center,
                didReceive: response,
                withCompletionHandler: {
                    completionHandler()
                    completionHandlerCalled = true
                }
            )
        }

        guard !completionHandlerCalled else { return }

        completionHandler()
    }

    // MARK: - method forwarding

    @objc
    override public func responds(to aSelector: Selector!) -> Bool {
        if implementedOptionalMethods.contains(aSelector), super.responds(to: aSelector) {
            return true
        }
        return wrappedAppDelegate?.responds(to: aSelector) ?? false
    }

    @objc
    override public func forwardingTarget(for aSelector: Selector!) -> Any? {
        if implementedOptionalMethods.contains(aSelector), super.responds(to: aSelector) {
            return self
        }
        if let wrappedAppDelegate = wrappedAppDelegate,
           wrappedAppDelegate.responds(to: aSelector) {
            return wrappedAppDelegate
        }
        return nil
    }
}

/// Prevent issues caused by swizzling in various SDKs:
/// - those are not using `responds(to:)` and `forwardingTarget(for:)`,  but only check does original implementation exist
///     - this is the case with FirebaseMassaging
/// - for this reason, empty methods are added and forwarding to wrapper is possible
@available(iOSApplicationExtension, unavailable)
extension CioProviderAgnosticAppDelegate {
    open func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        wrappedNotificationCenterDelegate?.userNotificationCenter?(center, openSettingsFor: notification)
    }

    @objc
    open func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([any UIUserActivityRestoring]?) -> Void) -> Bool {
        wrappedAppDelegate?.application?(application, continue: userActivity, restorationHandler: restorationHandler) ?? false
    }
}
