#import "PasswordStorage.h"
#import <Security/Security.h>

static NSString *kServer = @"BirthdaySync";
static NSString *kUser = @"BirthdaySync";

NSString* getBirthdaySyncPassword() {
	void *passwordBuf = NULL;
	UInt32 passwordLength;
	
	OSStatus status = SecKeychainFindGenericPassword(
		NULL,
		[kServer length],
		[kServer UTF8String],
		[kUser length],
		[kUser UTF8String],
		&passwordLength,
		&passwordBuf,
		NULL);
	
	if (status != noErr) {
		return NULL;
	}
	
	NSData *data = [NSData dataWithBytes:passwordBuf length:passwordLength]; 
	SecKeychainItemFreeContent(NULL, passwordBuf);
	
	return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
}

void saveBirthdaySyncPassword(NSString *password) {
	SecKeychainItemRef item = 0;
	
	SecKeychainFindGenericPassword(
		NULL,
		[kServer length],
		[kServer UTF8String],
		[kUser length],
		[kUser UTF8String],
		NULL,
		NULL,
		&item);
	
	if (item) {
		SecKeychainItemModifyAttributesAndData(
			item,
			NULL,
			[password length],
			[password UTF8String]);
	}
	else {
		SecKeychainAddGenericPassword (
			NULL,
			[kServer length],
			[kServer UTF8String],
			[kUser length],
			[kUser UTF8String],
			[password length],
			[password UTF8String],
			NULL);
	}
}
