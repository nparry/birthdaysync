#import <Cocoa/Cocoa.h>
#import <SyncServices/SyncServices.h>

@interface BirthdaySyncer : NSObject <ISyncSessionDriverDataSource> {
	NSOperationQueue *queue;
	NSString  *clientId;
	NSArray *entityNames;
}

+ (void) registerWithSyncServices;
+ (void) unregisterFromSyncServices;

- (id)init;
- (id)initWithClient:(NSString*)client
		   entityNames:(NSArray*)entities;

- (void) runSynchronousSync;
- (void) runAsynchronousSyncAndCall:(id)object
						   selector:(SEL)sel;

@end
