#import <Cocoa/Cocoa.h>
#import <SyncServices/SyncServices.h>
#import "GData/GData.h"

@interface BirthdaySyncer : NSObject <ISyncSessionDriverDataSource> {
	NSOperationQueue *queue_;
	NSString  *clientId_;
	NSArray *entityNames_;
	GDataServiceGoogleCalendar *calendarService_;
	GDataEntryCalendar *targetCalendar_;
	NSMutableDictionary *events_;
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
