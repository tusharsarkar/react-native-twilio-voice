#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
#import <TwilioVoice/TwilioVoice.h>
#import <AVFoundation/AVFoundation.h>
#import <PushKit/PushKit.h>


@interface RNTwilio : RCTEventEmitter <RCTBridgeModule, TVOCallDelegate, TVONotificationDelegate, AVAudioPlayerDelegate, PKPushRegistryDelegate>

+ (void)rnPushRegistry:(NSString *)pushToken;

@end
  
