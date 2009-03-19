#import "BirthdaySyncer.h"
#import "BirthdaySyncConstants.h"
#import "PasswordStorage.h"

@interface BirthdaySyncer (Private)
-(void)runSync;
-(void)runSyncWithCallback:(id)data;
-(void)setupCalendarData;
-(NSString*)targetCalendarName;
-(GDataEntryCalendar*)getTargetCalendar;
-(GDataEntryCalendar*)createTargetCalendar;
-(void)deleteTargetCalendar;
-(id)waitForTicket:(GDataServiceTicketBase*)ticket;
@end

@interface SyncerCallback : NSObject {
	id callbackObject_;
	SEL callbackSelector_;
}
-(id)initWithObject:(id)ojbect selector:(SEL)selector;
-(void)invoke:(BirthdaySyncer*)bs;
@end

@implementation SyncerCallback
-(id)initWithObject:(id)object selector:(SEL)selector {
	if (self = [super init]) {
		callbackObject_ = object;
		callbackSelector_ = selector;
	}
	return self;
}

-(void)invoke:(BirthdaySyncer*)bs {
	[callbackObject_ performSelector:callbackSelector_ withObject:bs];
}
@end

@implementation BirthdaySyncer

+ (void) registerWithSyncServices {
    ISyncClient *client = [[ISyncManager sharedManager]
						   clientWithIdentifier:kSyncServicesClientId];
    if (client != nil) {
        return;
    }
	
	[[ISyncManager sharedManager]
	 registerClientWithIdentifier:kSyncServicesClientId 
			  descriptionFilePath:[[NSBundle mainBundle] pathForResource:@"ClientDescription" ofType:@"plist"]];
}

+ (void) unregisterFromSyncServices {
	ISyncClient *client = [[ISyncManager sharedManager]
						   clientWithIdentifier:kSyncServicesClientId];
    if (client == nil) {
        return;
    }
	
	[[ISyncManager sharedManager] unregisterClient:client];
}

-(id)init {
	if (self = [super init]) {
		//[GDataHTTPFetcher setIsLoggingEnabled:YES];
		queue_ = [[NSOperationQueue alloc] init];
		clientId_ = NULL;
		entityNames_ = NULL;
		
		NSString *username = [[NSUserDefaults standardUserDefaults] stringForKey:@"googleUsername"];
		NSString *password = getBirthdaySyncPassword();

		calendarService_ = [[GDataServiceGoogleCalendar alloc] init];
		[calendarService_ setUserAgent:kBirthdaySyncUserAgent];
		[calendarService_ setShouldCacheDatedData:YES];
		[calendarService_ setServiceShouldFollowNextLinks:YES];
		//[calendarService_ setShouldUseMethodOverrideHeader:YES];
		[calendarService_ setUserCredentialsWithUsername:username
												password:password];
	}
	return self;
}

-(id)initWithClient:(NSString*)client
		   entityNames:(NSArray*)entities {
	if (self = [super init]) {
		clientId_ = [client retain];
		entityNames_ = [entities retain];
	}
	return self;
}

-(void)dealloc {
	[queue_ release];
	[clientId_ release];
	[entityNames_ release];
	[calendarService_ release];
	[targetCalendar_ release];
	[super dealloc];
}

- (void) runSynchronousSync {
	NSOperationQueue *q = [[NSOperationQueue alloc] init];
	NSInvocationOperation* op = [[NSInvocationOperation alloc] initWithTarget:self
																	 selector:@selector(runSync)
																	   object:nil];
	@try {
		[q addOperation:op];
		[q waitUntilAllOperationsAreFinished];
	}
	@finally {
		[op release];
		[q release];
	}
}

- (void) runAsynchronousSyncAndCall:(id)object
						   selector:(SEL)sel {
	SyncerCallback *cb = [[SyncerCallback alloc] initWithObject:object selector:sel];
	NSInvocationOperation* op = [[NSInvocationOperation alloc] initWithTarget:self
																	 selector:@selector(runSyncWithCallback:)
																	   object:cb];
    [queue_ addOperation:op];
	[op release];
	[cb release];
}

- (NSString *)clientIdentifier {
	return clientId_? clientId_ : kSyncServicesClientId;
}

- (NSURL *)clientDescriptionURL {
	return [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"ClientDescription"
																  ofType:@"plist"]];
}

- (NSArray *)schemaBundleURLs {
	return [NSArray array];
}

- (ISyncSessionDriverMode)preferredSyncModeForEntityName:(NSString *)entity {
	return ISyncSessionDriverModeFast;
}

- (NSDictionary *)recordsForEntityName:(NSString *)entity
								   moreComing:(BOOL *)moreComing
										error:(NSError **)outError {
	*moreComing = NO;
	return [NSDictionary dictionary];
}

- (NSDictionary *)changedRecordsForEntityName:(NSString *)entity
							moreComing:(BOOL *)moreComing
								 error:(NSError **)outError {
	*moreComing = NO;
	return [NSDictionary dictionary];
}

- (ISyncSessionDriverChangeResult)applyChange:(ISyncChange *)change
								forEntityName:(NSString *)entityName
					 remappedRecordIdentifier:(NSString **)outRecordIdentifier
							  formattedRecord:(NSDictionary **)outRecord
										error:(NSError **)outError {
	return ISyncSessionDriverChangeAccepted;
}

- (BOOL)deleteAllRecordsForEntityName:(NSString *)entityName
								error:(NSError **)outError {
	BOOL success = YES;
	@try {
		[self deleteTargetCalendar];
		[targetCalendar_ release];
		targetCalendar_ = [[self createTargetCalendar] retain];
	} @catch (NSException *error) {
		NSLog(@"Error during deleteAllRecordsForEntityName: %@", [error reason]);
		success =  NO;
	}
	
	return success;
}

@end

@implementation BirthdaySyncer (Private)

-(void)runSyncWithCallback:(id)object {
	[self runSync];
	SyncerCallback *cb = object;
	[cb invoke:self];
}

-(void)runSync {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	@try {
		[self setupCalendarData];
		ISyncSessionDriver *syncDriver = [ISyncSessionDriver sessionDriverWithDataSource:self];
		[syncDriver sync];
	} @catch (NSException *error) {
		NSLog(@"Error during sync: %@", [error reason]);
	}
	
	[pool release];
}

-(void)setupCalendarData {
	targetCalendar_ = [self getTargetCalendar];
	if (!targetCalendar_) {
		targetCalendar_ = [self createTargetCalendar];
	}
	[targetCalendar_ retain];	
}

-(NSString*)targetCalendarName {
	return  [[NSUserDefaults standardUserDefaults] stringForKey:@"googleCalendar"];
}

-(GDataEntryCalendar*)getTargetCalendar {
	NSString *targetName = [self targetCalendarName];
	
	GDataServiceTicket *ticket =
		[calendarService_ fetchCalendarFeedWithURL:[NSURL URLWithString:kGDataGoogleCalendarDefaultOwnCalendarsFeed]
										  delegate:NULL
								 didFinishSelector:NULL
								   didFailSelector:NULL];
	
	GDataFeedCalendar *feed = [self waitForTicket:ticket];
	NSEnumerator *enumerator = [[feed entries] objectEnumerator];
	GDataEntryCalendar *calendar;
	while (calendar = [enumerator nextObject]) {
		if ([targetName isEqualToString:[[calendar title] stringValue]]) {
			return calendar;
		}
	}
	
	return NULL;
}
	
-(GDataEntryCalendar*)createTargetCalendar {			
	GDataEntryCalendar *newEntry = [GDataEntryCalendar calendarEntry];
	[newEntry setTitleWithString:[self targetCalendarName]];
	[newEntry setIsSelected:YES]; // check the calendar in the web display
	
	// as of Dec. '07 the server requires a color, 
	// or returns a 404 (Not Found) error
	[newEntry setColor:[GDataColorProperty valueWithString:@"#2952A3"]];
	
	GDataServiceTicket *ticket =
		[calendarService_ fetchCalendarEntryByInsertingEntry:newEntry
												  forFeedURL:[NSURL URLWithString:kGDataGoogleCalendarDefaultOwnCalendarsFeed] 
													delegate:NULL
										   didFinishSelector:NULL
											 didFailSelector:NULL];
	
	GDataEntryCalendar *calendar = [self waitForTicket:ticket];
	return calendar;
}

-(void)deleteTargetCalendar {
	[calendarService_ setShouldUseMethodOverrideHeader:YES];

	GDataServiceTicket *ticket = 
	[calendarService_ deleteCalendarEntry:targetCalendar_
								 delegate:NULL
						didFinishSelector:NULL
						  didFailSelector:NULL];
	[self waitForTicket:ticket];
}

-(id)waitForTicket:(GDataServiceTicketBase*)ticket {
	NSError *error = NULL;
	id result = NULL;
	
	BOOL success = [calendarService_ waitForTicket:ticket
										   timeout:30
									 fetchedObject:&result
											 error:&error];
	
	[calendarService_ setShouldUseMethodOverrideHeader:NO];

	if (success) {
		return result;
	}
	
	@throw error;
}

@end

