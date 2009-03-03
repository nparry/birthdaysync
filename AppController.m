#import "AppController.h"
#import "PasswordStorage.h"
#import "BirthdaySyncer.h"
#import "BirthdaySyncConstants.h"

@interface AppController (Private)
- (void) startSync;
- (void) endSync:(BirthdaySyncer*)bs;
@end

@implementation AppController

@synthesize syncInProgress;

- (void)awakeFromNib {
	NSString *pw = getBirthdaySyncPassword();
	if (pw) {
		[gui_password setStringValue:pw];
	}
	[gui_password setDelegate:self];
	
	[[NSUserDefaults standardUserDefaults]
						 addObserver:self
						  forKeyPath:kEnableSyncPref
							 options:NSKeyValueObservingOptionNew
							 context:NULL];
}

-(void) controlTextDidEndEditing:(NSNotification *)aNotification {
	saveBirthdaySyncPassword([gui_password stringValue]);
}

- (void) observeValueForKeyPath:(NSString *)keyPath 
					   ofObject:(id)object
					     change:(NSDictionary *)change
					    context:(void *)context {
	BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:kEnableSyncPref];
	if (enabled) {
		[BirthdaySyncer registerWithSyncServices];
	}
	else {
		[BirthdaySyncer unregisterFromSyncServices];
	}
}

- (IBAction) syncNow:(id)sender {
	[self startSync];
}

@end

@implementation AppController (Private)

- (void) startSync {
	[self setSyncInProgress:YES];
	BirthdaySyncer *bs = [[BirthdaySyncer alloc] init];
	[bs runAsynchronousSyncAndCall:self
						 selector:@selector(endSync:)];
}

- (void) endSync:(BirthdaySyncer*)bs {
	[bs release];
	[self setSyncInProgress:NO];
}

@end

