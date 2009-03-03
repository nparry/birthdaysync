#import <Cocoa/Cocoa.h>

@interface AppController : NSObject {
	IBOutlet NSTextField *gui_password;
	BOOL syncInProgress;
}

@property BOOL syncInProgress;

- (IBAction) syncNow:(id) sender;

@end
