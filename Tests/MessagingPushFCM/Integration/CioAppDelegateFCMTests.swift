@testable import CioInternalCommon
@_spi(Internal) @testable import CioMessagingPush
@testable import CioMessagingPushFCM
import FirebaseMessaging
import SharedTests
import UIKit
import UserNotifications
import XCTest

class CioAppDelegateFCMTests: XCTestCase {
    var appDelegateFCM: CioAppDelegate!

    // Mock Classes
    var mockMessagingPush: MessagingPushFCMMock!
    var mockAppDelegate: MockAppDelegate!
    var mockNotificationCenter: UserNotificationCenterIntegrationMock!
    var mockNotificationCenterDelegate: MockNotificationCenterDelegate!
    var mockMessaging: FirebaseMessagingIntegrationMock!
    var mockMessagingDelegate: MockMessagingDelegate!
    var mockLogger: LoggerMock!

    // Mock config for testing
    func createMockConfig(autoFetchDeviceToken: Bool = true, autoTrackPushEvents: Bool = true) -> MessagingPushConfigOptions {
        MessagingPushConfigOptions(
            logLevel: .info,
            cdpApiKey: "test-api-key",
            region: .US,
            autoFetchDeviceToken: autoFetchDeviceToken,
            autoTrackPushEvents: autoTrackPushEvents,
            showPushAppInForeground: false
        )
    }

    override func setUp() {
        super.setUp()

        UNUserNotificationCenter.swizzleNotificationCenter()
        Messaging.swizzleMessaging()

        mockMessagingPush = MessagingPushFCMMock()

        mockAppDelegate = MockAppDelegate()

        mockNotificationCenter = UserNotificationCenterIntegrationMock()
        mockNotificationCenterDelegate = MockNotificationCenterDelegate()
        mockNotificationCenter.delegate = mockNotificationCenterDelegate

        mockMessaging = FirebaseMessagingIntegrationMock()
        mockMessagingDelegate = MockMessagingDelegate()
        mockMessaging.delegate = mockMessagingDelegate

        mockLogger = LoggerMock()

        appDelegateFCM = CioAppDelegate(
            messagingPush: mockMessagingPush,
            userNotificationCenter: { self.mockNotificationCenter },
            firebaseMessaging: { self.mockMessaging },
            appDelegate: mockAppDelegate,
            config: { self.createMockConfig() },
            logger: mockLogger
        )
    }

    override func tearDown() {
        mockMessagingPush = nil
        mockAppDelegate = nil
        mockNotificationCenter = nil
        mockNotificationCenterDelegate = nil
        mockMessaging = nil
        mockMessagingDelegate = nil
        mockLogger = nil
        appDelegateFCM = nil

        Messaging.unswizzleMessaging()
        UNUserNotificationCenter.unswizzleNotificationCenter()

        MessagingPush.appDelegateIntegratedExplicitly = false

        super.tearDown()
    }

    // MARK: - Tests for FCM-specific functionality

    func testDidFinishLaunching_whenCalled_thenSuperIsCalled() {
        // Call the method
        let result = appDelegateFCM.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Verify behavior
        XCTAssertTrue(result)
        XCTAssertTrue(mockAppDelegate.didFinishLaunchingCalled)
        // -- `registerForRemoteNotifications` is called
        XCTAssertTrue(mockLogger.debugReceivedInvocations.contains {
            $0.message.contains("CIO: Registering for remote notifications")
        })
    }

    func testDidFinishLaunching_whenCalled_thenMessagingDelegateIsSet() {
        // Call the method
        _ = appDelegateFCM.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Verify behavior
        XCTAssertTrue(mockMessaging.delegate === appDelegateFCM)
    }

    func testDidFinishLaunchings_whenAutoFetchDeviceTokenIsDesabled_thenMessagingDelegateIsNotSet() {
        appDelegateFCM = CioAppDelegate(
            messagingPush: mockMessagingPush,
            userNotificationCenter: { self.mockNotificationCenter },
            firebaseMessaging: { self.mockMessaging },
            appDelegate: mockAppDelegate,
            config: { self.createMockConfig(autoFetchDeviceToken: false) },
            logger: mockLogger
        )
        mockMessaging.delegate = nil

        // Call didFinishLaunching
        let result = appDelegateFCM.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Verify behavior
        XCTAssertTrue(result)
        XCTAssertTrue(mockAppDelegate.didFinishLaunchingCalled)
        XCTAssertNil(mockMessaging.delegate)
    }

    // MARK: - Test MessagingDelegate

    func testMessagingDidReceiveRegistrationToken_whenCalled_thenWrappedMessagingDelegateIsCalled() {
        // Setup
        let fcmToken = "test-fcm-token"
        _ = appDelegateFCM.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Call method directly
        appDelegateFCM.messaging(Messaging.messagingMock(), didReceiveRegistrationToken: fcmToken)

        // Verify behavior
        XCTAssertTrue(mockMessagingDelegate.didReceiveRegistrationTokenCalled)
        XCTAssertEqual(mockMessagingDelegate.fcmTokenReceived, fcmToken)
    }

    func testMessagingDidReceiveRegistrationToken_whenCalled_thenTokenIsForwardedToCIO() {
        // Setup
        let fcmToken = "test-fcm-token"
        _ = appDelegateFCM.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Call method directly
        appDelegateFCM.messaging(Messaging.messagingMock(), didReceiveRegistrationToken: fcmToken)

        // Verify behavior
        XCTAssertTrue(mockMessagingPush.registerDeviceTokenFCMCalled)
        XCTAssertEqual(mockMessagingPush.registerDeviceTokenFCMReceivedArguments, fcmToken)
    }

    // MARK: - Tests for inherited AppDelegate functionality

    func testDidFailToRegisterForRemoteNotifications_whenCalled_thenSuperIsCalled() {
        // Setup
        let application = UIApplication.shared
        let error = NSError(domain: "test", code: 123, userInfo: nil)

        // Call the method
        appDelegateFCM.application(application, didFailToRegisterForRemoteNotificationsWithError: error)

        // Verify behavior
        XCTAssertTrue(mockAppDelegate.didFailToRegisterForRemoteNotificationsCalled)
        XCTAssertEqual((mockAppDelegate.errorReceived as NSError?)?.domain, "test")
        XCTAssertTrue(mockMessagingPush.deleteDeviceTokenCalled == true)
    }

    // MARK: - Tests for UNUserNotificationCenterDelegate methods

    func testDidRegisterForRemoteNotifications_whenCalled_thenSuperIsCalled() {
        // Setup
        let deviceToken = "device_token".data(using: .utf8)!
        _ = appDelegateFCM.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Call the method
        appDelegateFCM.application(UIApplication.shared, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)

        // Verify behavior
        XCTAssertTrue(mockAppDelegate.didRegisterForRemoteNotificationsCalled)
        XCTAssertEqual(mockAppDelegate.deviceTokenReceived, deviceToken)
    }

    func testUserNotificationCenterDidReceive_whenCalled_thenSuperIsCalled() {
        // Setup
        mockMessagingPush.userNotificationCenterReturnValue = nil
        _ = appDelegateFCM.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        var completionHandlerCalled = false
        let completionHandler = {
            completionHandlerCalled = true
        }

        // Call the method
        appDelegateFCM.userNotificationCenter(UNUserNotificationCenter.current(), didReceive: UNNotificationResponse.testInstance, withCompletionHandler: completionHandler)

        // Verify behavior
        XCTAssertTrue(mockMessagingPush.userNotificationCenterCalled == true)
        XCTAssertTrue(mockNotificationCenterDelegate.didReceiveNotificationResponseCalled)
        XCTAssertTrue(completionHandlerCalled)
    }
}
