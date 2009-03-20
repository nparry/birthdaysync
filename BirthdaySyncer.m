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
-(void)deleteTargetCalendar:(GDataEntryCalendar*)calendar;
-(void)getCalendarEvents:(NSMutableDictionary*)eventSink;
-(GDataEntryCalendarEvent*)createEventForRecord:(NSDictionary*)record;
-(GDataEntryCalendarEvent*)modifyEvent:(GDataEntryCalendarEvent*)event withRecord:(NSDictionary*)record;
-(void)setNameOnEvent:(GDataEntryCalendarEvent*)event fromRecord:(NSDictionary*)record;
-(void)setDateOnEvent:(GDataEntryCalendarEvent*)event fromRecord:(NSDictionary*)record;
-(BOOL)deleteEvent:(GDataEntryCalendarEvent*)event;
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
		
		targetCalendar_ = NULL;
		events_ = [[NSMutableDictionary dictionaryWithCapacity:50] retain];
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
	[events_ release];
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
	
	ISyncSessionDriverChangeResult result = ISyncSessionDriverChangeIgnored;
	@try {
		switch ([change type]) {
			case ISyncChangeTypeAdd: {
				GDataEntryCalendarEvent *event = [self createEventForRecord:[change record]];
				if (event) {
					[events_ setObject:event forKey:[event identifier]];
					*outRecordIdentifier = [event identifier];
					result = ISyncSessionDriverChangeAccepted;
				}
			} break;
			case ISyncChangeTypeModify: {
				GDataEntryCalendarEvent *event = [events_ objectForKey:[change recordIdentifier]];
				if (event) {
					GDataEntryCalendarEvent *newEvent = [self modifyEvent:event withRecord:[change record]];
					if (newEvent) {
						[events_ setObject:newEvent forKey:[newEvent identifier]];
						*outRecordIdentifier = [newEvent identifier];
						result = ISyncSessionDriverChangeAccepted;;
					}
				}
			} break;
			case ISyncChangeTypeDelete: {
				GDataEntryCalendarEvent *event = [events_ objectForKey:[change recordIdentifier]];
				if (event) {
					BOOL ok = [self deleteEvent:event];
					if (ok) {
						[events_ removeObjectForKey:[change recordIdentifier]];
						result = ISyncSessionDriverChangeAccepted;
					}
				}
			} break;
		}
	} @catch (NSException *error) {
		NSLog(@"Error during applyChange: %@", [error reason]);
	}
	
	return result;
}

- (BOOL)deleteAllRecordsForEntityName:(NSString *)entityName
								error:(NSError **)outError {
	BOOL success = YES;
	@try {
		[self deleteTargetCalendar:targetCalendar_];
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
	[self getCalendarEvents:events_];
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

-(void)deleteTargetCalendar:(GDataEntryCalendar*)calendar {
	[calendarService_ setShouldUseMethodOverrideHeader:YES];

	GDataServiceTicket *ticket = 
	[calendarService_ deleteCalendarEntry:calendar
								 delegate:NULL
						didFinishSelector:NULL
						  didFailSelector:NULL];
	[self waitForTicket:ticket];
}


-(void)getCalendarEvents:(NSMutableDictionary*)eventSink {
	GDataServiceTicket *ticket =
	[calendarService_ fetchCalendarEventFeedWithURL:[[targetCalendar_ alternateLink] URL]
										   delegate:NULL
								  didFinishSelector:NULL
									didFailSelector:NULL];
	GDataFeedCalendarEvent *events = [self waitForTicket:ticket];
	NSEnumerator *enumerator = [[events entries] objectEnumerator];
	GDataEntryCalendarEvent *event;
	while ((event = [enumerator nextObject])) {
		[eventSink setObject:event forKey:[event identifier]];
	}
}

-(GDataEntryCalendarEvent*)createEventForRecord:(NSDictionary*)record {
	GDataEntryCalendarEvent *event = [GDataEntryCalendarEvent calendarEvent];
	[self setNameOnEvent:event fromRecord:record];
	[self setDateOnEvent:event fromRecord:record];
	
	GDataServiceTicket *ticket =
		[calendarService_ fetchCalendarEventByInsertingEntry:event
												  forFeedURL:[[targetCalendar_ alternateLink] URL]
													delegate:NULL
										   didFinishSelector:NULL
											 didFailSelector:NULL];
	
	GDataEntryCalendarEvent *newEvent = [self waitForTicket:ticket];
	return newEvent;
}

-(GDataEntryCalendarEvent*)modifyEvent:(GDataEntryCalendarEvent*)event
							withRecord:(NSDictionary*)record {
	[self setNameOnEvent:event fromRecord:record];
	[self setDateOnEvent:event fromRecord:record];
	
	GDataServiceTicket *ticket =
		[calendarService_ fetchCalendarEventEntryByUpdatingEntry:event
													 forEntryURL:[[event editLink] URL]
														delegate:NULL
											   didFinishSelector:NULL
												 didFailSelector:NULL];
	
	GDataEntryCalendarEvent *updatedEvent = [self waitForTicket:ticket];
	return updatedEvent;
}

-(void)setNameOnEvent:(GDataEntryCalendarEvent*)event fromRecord:(NSDictionary*)record {
	NSString *firstName = [record objectForKey:@"first name"];
	NSString *lastName = [record objectForKey:@"last name"];
	
	if (firstName && lastName) {
		NSString *fullName = [[firstName stringByAppendingString:@" "] stringByAppendingString:lastName];
		[event setTitleWithString:fullName];
	}
	else if (firstName) {
		[event setTitleWithString:firstName];
	}
	else if (lastName) {
		[event setTitleWithString:lastName];
	}
	else {
		[event setTitleWithString:@"Unknown contact"];
	}
}

-(void)setDateOnEvent:(GDataEntryCalendarEvent*)event fromRecord:(NSDictionary*)record {
	NSDate *birthday = [record objectForKey:@"birthday"];
	GDataRecurrence * r;
	
	if (birthday) {
		NSDate *nextDay = [birthday addTimeInterval:(24*60*60)];
		NSString *dateFormat = @"%Y%m%d";
		NSString *start = [birthday descriptionWithCalendarFormat:dateFormat
														 timeZone:NULL
														   locale:NULL];
		NSString *end = [nextDay descriptionWithCalendarFormat:dateFormat
													  timeZone:NULL
														locale:NULL];
		NSString *recurrFormat = @"DTSTART;VALUE=DATE:%@\nDTEND;VALUE=DATE:%@\nRRULE:FREQ=YEARLY";
		NSString *recurr = [NSString stringWithFormat:recurrFormat, start, end];
		r = [GDataRecurrence recurrenceWithString:recurr];
	}
	else {
		// For now, if we don't have a birthday just set the entry to a date in
		// the past with no repeating
		NSString *recurr =  @"DTSTART;VALUE=DATE:18010101\nDTEND;VALUE=DATE:18010102\nRRULE:FREQ=YEARLY;COUNT=1";
		r = [GDataRecurrence recurrenceWithString:recurr];
	}
	
	// Seems to be a bug in calling setRecurrence directly
	[event setObject:r forExtensionClass:[GDataRecurrence class]];
}

-(BOOL)deleteEvent:(GDataEntryCalendarEvent*)event {
	[calendarService_ setShouldUseMethodOverrideHeader:YES];
	
	GDataServiceTicket *ticket =
		[calendarService_ deleteCalendarEventEntry:event
										  delegate:NULL
								 didFinishSelector:NULL
								   didFailSelector:NULL];
	[self waitForTicket:ticket];
	return YES;
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

