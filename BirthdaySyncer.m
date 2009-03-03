#import "BirthdaySyncer.h"
#import "BirthdaySyncConstants.h"

@interface BirthdaySyncer (Private)
-(void)runSync;
-(void)runSyncWithCallback:(id)data;
@end

@interface SyncerCallback : NSObject {
	id callbackObject;
	SEL callbackSelector;
}
-(id)initWithObject:(id)ojbect selector:(SEL)selector;
-(void)invoke:(BirthdaySyncer*)bs;
@end

@implementation SyncerCallback
-(id)initWithObject:(id)object selector:(SEL)selector {
	if (self = [super init]) {
		callbackObject = object;
		callbackSelector = selector;
	}
	return self;
}

-(void)invoke:(BirthdaySyncer*)bs {
	[callbackObject performSelector:callbackSelector withObject:bs];
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
		queue = [[NSOperationQueue alloc] init];
		clientId = 0;
		entityNames = 0;
	}
	return self;
}

-(id)initWithClient:(NSString*)client
		   entityNames:(NSArray*)entities {
	if (self = [super init]) {
		clientId = [client retain];
		entityNames = [entities retain];
	}
	return self;
}

-(void)dealloc {
	[queue release];
	[clientId release];
	[entityNames release];
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
    [queue addOperation:op];
	[op release];
	[cb release];
}

- (NSString *)clientIdentifier {
	return clientId? clientId : kSyncServicesClientId;
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

- (ISyncSessionDriverChangeResult)applyChange:(ISyncChange *)change
								forEntityName:(NSString *)entityName
					 remappedRecordIdentifier:(NSString **)outRecordIdentifier
							  formattedRecord:(NSDictionary **)outRecord
										error:(NSError **)outError {
	return ISyncSessionDriverChangeAccepted;
}

- (BOOL)deleteAllRecordsForEntityName:(NSString *)entityName
								error:(NSError **)outError {
	return YES;
}

@end

@implementation BirthdaySyncer (Private)

-(void)runSyncWithCallback:(id)object {
	[self runSync];
	SyncerCallback *cb = object;
	[cb invoke:self];
}

-(void)runSync {
	ISyncSessionDriver *syncDriver = [ISyncSessionDriver sessionDriverWithDataSource:self];
	BOOL success = [syncDriver sync];
}

@end

