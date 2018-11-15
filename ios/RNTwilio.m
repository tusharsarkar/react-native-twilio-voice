
#import "RNTwilio.h"
#import "Constant.h"
#import <React/RCTBridgeModule.h>


@interface RNTwilio()

typedef void (^RingtonePlaybackCallback)(void);
@property (nonatomic, strong) AVAudioPlayer *ringtonePlayer;
@property (nonatomic, strong) RingtonePlaybackCallback ringtonePlaybackCallback;

@end


@implementation RNTwilio {
    TVOCall* _call;
    TVOCallInvite* _callInvite;
    TVOError* _error;
    NSString* _deviceTokenString;
    NSString* _accessToken;
    PKPushRegistry* _voipRegistry;
}

@synthesize bridge = _bridge;

+ (void)rnPushRegistry:(NSString *)pushToken{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handlePushRegistryNotification:) name:@"PUSH" object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"PUSH" object:pushToken];
}

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

RCT_EXPORT_MODULE(@"TwilioConnect")

- (void)handlePushRegistryNotification:(NSNotification *)notification {
    [self sendEventWithName:kRnPushToken body:notification.userInfo[@"data"]];
}

- (NSArray<NSString *> *)supportedEvents
{
    return @[kCallSuccessfullyRegistered,kCallSuccessfullyUnRegistered,kCallConnected,kCallDisconnected,kCallFailedToConnectOnNetworkError,kCallFailedOnNetworkError,kCallInviteReceived,kCallInviteCancelled,kCallStateAccepted,kCallStateRejected,kCallStateCancelled,kRnPushToken];
}

#pragma mark - RegisterCall & Configuration

RCT_EXPORT_METHOD(registerWithAccessToken:(nonnull NSString *)accessToken pushToken:(nonnull NSString *)pushDeviceToken){
    [TwilioVoice registerWithAccessToken:accessToken deviceToken:pushDeviceToken completion:^(NSError * _Nullable error) {
        if (error == nil){
            [self sendEventWithName:kCallSuccessfullyRegistered body:nil];
            [self registerPushRegistory];
        }
    }];
}

RCT_EXPORT_METHOD(unregisterWithAccessToken:(nonnull NSString *)accessToken pushToken:(nonnull NSString *)pushDeviceToken){
    [TwilioVoice unregisterWithAccessToken:accessToken deviceToken:pushDeviceToken completion:^(NSError * _Nullable error) {
        [self sendEventWithName:kCallSuccessfullyUnRegistered body:nil];
        [self unregisterPushRegistory];
    }];
}

RCT_EXPORT_METHOD(handleNotification:(nonnull NSDictionary *)payload){
    [TwilioVoice handleNotification:payload delegate:self];
}

#pragma mark - Making Outgoing Calls

RCT_EXPORT_METHOD(call:(nonnull NSString *)accessToken params:(nullable NSDictionary<NSString *,NSString *> *)callParams){
    _call = [TwilioVoice call:accessToken params:callParams delegate:self];
}

#pragma mark - CallKitIntegration Methods

RCT_EXPORT_METHOD(call:(nonnull NSString *)accessToken params:(nullable NSDictionary<NSString *,NSString *> *)callParams uuid:(nonnull NSString *)uuidString){
    NSUUID *uuidObj = [[NSUUID alloc] initWithUUIDString:uuidString];
    _call = [TwilioVoice call:accessToken params:callParams uuid:uuidObj delegate:self];
}

RCT_EXPORT_METHOD(configureAudioSession){
    [TwilioVoice configureAudioSession];
}

RCT_EXPORT_METHOD(disconnectCall){
    if (_call){
        [_call disconnect];
        [self sendEventWithName:kCallDisconnected body:[self callBody:_call]];
        [self callDisconnected];
    }
}

#pragma mark - UtilityMethods

- (void)registerPushRegistory{
    _voipRegistry = [[PKPushRegistry alloc] initWithQueue:dispatch_get_main_queue()];
    _voipRegistry.delegate = self;
    _voipRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
}

- (void)unregisterPushRegistory{
    _voipRegistry = nil;
    _voipRegistry.delegate = nil;
}

- (NSString *)callState:(TVOCallInviteState )state{
    NSString *status = @"";
    switch (state) {
        case TVOCallInviteStatePending:
            status = kCallStatePending;
            break;
        case TVOCallInviteStateAccepted:
            status = kCallStateAccepted;
            break;
        case TVOCallInviteStateCanceled:
            status = kCallStateCancelled;
            break;
        case TVOCallInviteStateRejected:
            status = kCallStateRejected;
            break;
        default:
            status = kCallStateRejected;
            break;
    }
    return status;
}

- (NSDictionary *)tvoCallObject:(TVOCallInvite *)callInvite{
    return @{@"":callInvite.from,@"state":[self callState:callInvite.state],@"callsid":callInvite.callSid};
}

- (NSDictionary *)callBody:(TVOCall *)call{
    return @{@"from":call.from,@"to":call.to,@"sid":call.sid,@"mute":[NSNumber numberWithBool:call.isMuted],@"onhold":[NSNumber numberWithBool:call.isOnHold]};
}

#pragma mark - PKPushRegistryDelegate

- (void)pushRegistry:(PKPushRegistry *)registry didUpdatePushCredentials:(PKPushCredentials *)credentials forType:(NSString *)type {
    NSLog(@"pushRegistry:didUpdatePushCredentials:forType:");
    
    if ([type isEqualToString:PKPushTypeVoIP]) {
        _deviceTokenString = [credentials.token description];
        NSString *accessToken = _accessToken;
        
        [TwilioVoice registerWithAccessToken:accessToken
                                 deviceToken:_deviceTokenString
                                  completion:^(NSError *error) {
                                      if (error) {
                                          NSLog(@"An error occurred while registering: %@", [error localizedDescription]);
                                      }
                                      else {
                                          NSLog(@"Successfully registered for VoIP push notifications.");
                                      }
                                  }];
    }
}

- (void)pushRegistry:(PKPushRegistry *)registry didInvalidatePushTokenForType:(PKPushType)type {
    NSLog(@"pushRegistry:didInvalidatePushTokenForType:");
    
    if ([type isEqualToString:PKPushTypeVoIP]) {
        NSString *accessToken = _accessToken;
        
        [TwilioVoice unregisterWithAccessToken:accessToken
                                   deviceToken:_deviceTokenString
                                    completion:^(NSError * _Nullable error) {
                                        if (error) {
                                            NSLog(@"An error occurred while unregistering: %@", [error localizedDescription]);
                                        }
                                        else {
                                            NSLog(@"Successfully unregistered for VoIP push notifications.");
                                        }
                                    }];
        
        _deviceTokenString = nil;
    }
}

/**
 * Try using the `pushRegistry:didReceiveIncomingPushWithPayload:forType:withCompletionHandler:` method if
 * your application is targeting iOS 11. According to the docs, this delegate method is deprecated by Apple.
 */
- (void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(NSString *)type {
    NSLog(@"pushRegistry:didReceiveIncomingPushWithPayload:forType:");
    if ([type isEqualToString:PKPushTypeVoIP]) {
        [TwilioVoice handleNotification:payload.dictionaryPayload
                               delegate:self];
    }
}

/**
 * This delegate method is available on iOS 11 and above. Call the completion handler once the
 * notification payload is passed to the `TwilioVoice.handleNotification()` method.
 */
- (void)pushRegistry:(PKPushRegistry *)registry
didReceiveIncomingPushWithPayload:(PKPushPayload *)payload
             forType:(PKPushType)type
withCompletionHandler:(void (^)(void))completion {
    NSLog(@"pushRegistry:didReceiveIncomingPushWithPayload:forType:withCompletionHandler:");
    if ([type isEqualToString:PKPushTypeVoIP]) {
        [TwilioVoice handleNotification:payload.dictionaryPayload
                               delegate:self];
    }
    
    //TODO: Handle completion();
}


#pragma mark - TVONotificationDelegate
- (void)callInviteReceived:(TVOCallInvite *)callInvite {
    if (callInvite.state == TVOCallInviteStatePending) {
        [self handleCallInviteReceived:callInvite];
    } else if (callInvite.state == TVOCallInviteStateCanceled) {
        [self handleCallInviteCanceled:callInvite];
    }
}

- (void)handleCallInviteReceived:(TVOCallInvite *)callInvite {
    NSLog(@"callInviteReceived:");
    [self sendEventWithName:kCallInviteReceived body:[self tvoCallObject:callInvite]];
    if (_callInvite && _callInvite.state == TVOCallInviteStatePending) {
        NSLog(@"Already a pending call invite. Ignoring incoming call invite from %@", callInvite.from);
        return;
    }
    if (_call && _call.state == TVOCallStateConnected) {
        NSLog(@"Already an active call. Ignoring incoming call invite from %@", callInvite.from);
        return;
    }
    
    _callInvite = callInvite;
    
    //NSString *from = callInvite.from;
    //NSString *alertMessage = [NSString stringWithFormat:@"From %@", from];
    //TODO: Alert message notification
    [self playIncomingRingtone];
    
    //TODO: Send Notifcation with Accept Ignore Reject
    
    // If the application is not in the foreground, post a local notification
    if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) {
        //TODO : Add Local Notification
    }
}

- (void)handleCallInviteCanceled:(TVOCallInvite *)callInvite {
    [self sendEventWithName:kCallInviteCancelled body:@{@"from":callInvite.from,@"state":[self callState:callInvite.state]}];
    NSLog(@"callInviteCanceled:");
    
    if (![callInvite.callSid isEqualToString:_callInvite.callSid]) {
        NSLog(@"Incoming (but not current) call invite from \"%@\" canceled. Just ignore it.", callInvite.from);
        return;
    }
    
    [self stopIncomingRingtone];
    [self playDisconnectSound];
    
    //TODO: Handle incoming call
    
    _callInvite = nil;
    
    [[UIApplication sharedApplication] cancelAllLocalNotifications];
}

- (void)notificationError:(NSError *)error {
    NSLog(@"notificationError: %@", [error localizedDescription]);
}




#pragma mark - TVOCallDelegate

- (void)callDidConnect:(TVOCall *)call {
    NSLog(@"callDidConnect:");
    _call = call;
    [self sendEventWithName:kCallConnected body:[self callBody:call]];
    [self toggleAudioRoute:YES];
}

- (void)call:(TVOCall *)call didFailToConnectWithError:(NSError *)error {
    NSLog(@"Call failed to connect: %@", error);
    [self sendEventWithName:kCallFailedToConnectOnNetworkError body:[self callBody:call]];
    [self callDisconnected];
}

- (void)call:(TVOCall *)call didDisconnectWithError:(NSError *)error {
    if (error) {
        NSLog(@"Call failed: %@", error);
    } else {
        NSLog(@"Call disconnected");
    }
    [self sendEventWithName:kCallFailedOnNetworkError body:[self callBody:call]];
    [self callDisconnected];
}

- (void)callDisconnected {
    _call = nil;
    [self playDisconnectSound];
    //UI
    //Stop spin
}

#pragma mark - AVAudioSession
- (void)toggleAudioRoute:(BOOL)toSpeaker {
    // The mode set by the Voice SDK is "VoiceChat" so the default audio route is the built-in receiver. Use port override to switch the route.
    NSError *error = nil;
    if (toSpeaker) {
        if (![[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&error]) {
            NSLog(@"Unable to reroute audio: %@", [error localizedDescription]);
        }
    } else {
        if (![[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:&error]) {
            NSLog(@"Unable to reroute audio: %@", [error localizedDescription]);
        }
    }
}

#pragma mark - Ringtone player & AVAudioPlayerDelegate
- (void)playOutgoingRingtone:(RingtonePlaybackCallback)completion {
    self.ringtonePlaybackCallback = completion;
    
    NSString *ringtonePath = [[NSBundle mainBundle] pathForResource:@"outgoing" ofType:@"wav"];
    if ([ringtonePath length] <= 0) {
        NSLog(@"Can't find outgoing sound file");
        if (self.ringtonePlaybackCallback) {
            self.ringtonePlaybackCallback();
        }
        return;
    }
    
    self.ringtonePlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL URLWithString:ringtonePath] error:nil];
    self.ringtonePlayer.delegate = self;
    
    [self playRingtone];
}

- (void)playIncomingRingtone {
    NSString *ringtonePath = [[NSBundle mainBundle] pathForResource:@"incoming" ofType:@"wav"];
    if ([ringtonePath length] <= 0) {
        NSLog(@"Can't find incoming sound file");
        return;
    }
    
    self.ringtonePlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL URLWithString:ringtonePath] error:nil];
    self.ringtonePlayer.delegate = self;
    self.ringtonePlayer.numberOfLoops = -1;
    
    [self playRingtone];
}

- (void)stopIncomingRingtone {
    if (!self.ringtonePlayer.isPlaying) {
        return;
    }
    
    [self.ringtonePlayer stop];
    NSError *error = nil;
    if (![[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord
                                                error:&error]) {
        NSLog(@"Failed to reset AVAudioSession category: %@", [error localizedDescription]);
    }
}

- (void)playDisconnectSound {
    NSString *ringtonePath = [[NSBundle mainBundle] pathForResource:@"disconnect" ofType:@"wav"];
    if ([ringtonePath length] <= 0) {
        NSLog(@"Can't find disconnect sound file");
        return;
    }
    
    self.ringtonePlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL URLWithString:ringtonePath] error:nil];
    self.ringtonePlayer.delegate = self;
    self.ringtonePlaybackCallback = nil;
    
    [self playRingtone];
}

- (void)playRingtone {
    NSError *error = nil;
    if (![[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
                                                error:&error]) {
        NSLog(@"Unable to reroute audio: %@", [error localizedDescription]);
    }
    
    self.ringtonePlayer.volume = 1.0f;
    [self.ringtonePlayer play];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    if (self.ringtonePlaybackCallback) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(self) strongSelf = weakSelf;
            strongSelf.ringtonePlaybackCallback();
        });
        
        NSError *error = nil;
        if (![[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord
                                                    error:&error]) {
            NSLog(@"Unable to reroute audio: %@", [error localizedDescription]);
        }
    }
}



@end
  
