//
//  Synchronization.m
//  2Safe
//
//  Created by Dan on 1/13/13.
//  Copyright (c) 2013 zaopark. All rights reserved.
//

#import "Synchronization.h"
#import "FileHandler.h"
#import "NSMutableArray+Stack.h"

@implementation Synchronization{
    NSMutableArray *_stack;
}

-(void)getModificationDatesAtPath:(NSString*) folder {
	_stack = [NSMutableArray arrayWithCapacity:100];
    [_stack addObject:folder];
    while([_stack count] != 0){
        [self lookUp:[_stack pop]];
    }
}

-(void)lookUp:(NSString*) folder {
    NSFileManager *fm = [NSFileManager defaultManager];
    FileHandler *fh = [[FileHandler alloc] init];
    NSError *err;
	NSArray* files = [fm contentsOfDirectoryAtPath:folder error:&err];
    NSString* mDate;
    
	for(NSString *file in files) {
		NSString *path = [folder stringByAppendingPathComponent:file];
		BOOL isDir = NO;
		[fm fileExistsAtPath:path isDirectory:(&isDir)];
		//if(isDir) {
		//	[directoryList addObject:file];
		//}
        if(isDir){
            [_stack push:path];
        }
        mDate = [fh getModificationDate:path];
        NSLog(@"Modification Date: %@ of %@", mDate, path);
	}

}

@end
