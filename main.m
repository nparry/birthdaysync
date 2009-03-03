#import <Cocoa/Cocoa.h>
#import "BirthdaySyncer.h"

int main(int argc, char *argv[])
{
	NSString *clientId = 0;
	NSArray *entityNames = 0;
	
	for (int i = 0; i < argc; i++) {
		NSString *arg = [NSString stringWithCString:argv[i]];
		if ([arg isEqualToString:@"--sync"]) {
			clientId = [NSString stringWithCString:argv[i+1]];
		}
		else if ([arg isEqualToString:@"--entitynames"]) {
			NSString *entities = [NSString stringWithCString:argv[i+1]];
			entityNames = [entities componentsSeparatedByString:@","];
		}
	}
	
	if (clientId && entityNames) {
		BirthdaySyncer *bs = [[BirthdaySyncer alloc] initWithClient:clientId
														entityNames:entityNames];
		[bs runSynchronousSync];
	}
	else {
		return NSApplicationMain(argc,  (const char **) argv);
	}
}
