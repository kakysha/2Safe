//
//  Synchronization.m
//  2Safe
//
//  Created by Dan on 1/13/13.
//  Copyright (c) 2013 zaopark. All rights reserved.
//

#import "Synchronization.h"
#import "NSMutableArray+Stack.h"
#import "Database.h"
#import "FSElement.h"
#import "ApiRequest.h"

@implementation Synchronization{
    NSMutableArray *_folderStack;
    NSMutableArray *_uploadFolderStack;
    NSMutableArray *_downloadFolderStack;
    NSFileManager *_fm;
    NSMutableDictionary *_serverMoves;
    Database *_db;
    NSMutableArray *_serverInsertionsQueue;
    NSMutableArray *_serverDeletionsQueue;
    NSMutableArray *_clientInsertionsQueue;
    NSMutableArray *_clientDeletionsQueue;
    NSString *_folder;
}

- (id) init {
    if (self = [super init]) {
        _fm = [NSFileManager defaultManager];
        _db = [Database databaseForAccount:@"kakysha"];
        _folderStack = [NSMutableArray arrayWithCapacity:100];
        _uploadFolderStack = [NSMutableArray arrayWithCapacity:50];
        _downloadFolderStack = [NSMutableArray arrayWithCapacity:50];
        _serverInsertionsQueue = [NSMutableArray arrayWithCapacity:50];
        _serverDeletionsQueue = [NSMutableArray arrayWithCapacity:50];
        _clientInsertionsQueue = [NSMutableArray arrayWithCapacity:50];
        _clientDeletionsQueue = [NSMutableArray arrayWithCapacity:50];
        _serverMoves = [NSMutableDictionary dictionaryWithCapacity:50];
        _folder = @"/Users/Drunk/Downloads/2safe/";
        return self;
    }
    return nil;
}

-(void) getServerQueues {
    ApiRequest *getEvents = [[ApiRequest alloc] initWithAction:@"get_events" params:@{@"after":@"1360425536689870"} withToken:YES];
    [getEvents performRequestWithBlock:^(NSDictionary *response, NSError *e) {
        if (!e) {
            NSString *elementPath;
            /*for(id key in response){
                NSLog(@"%@ = %@",key,[response objectForKey:key]);
            }*/
            for (NSDictionary *dict in [response objectForKey:@"events"]) {
                if(([[dict objectForKey:@"event"] isEqualTo:@"file_uploaded"] && [dict objectForKey:@"size"]) ||
                   [[dict objectForKey:@"event"] isEqualTo:@"dir_created"]){
                    NSUInteger objId = [_serverInsertionsQueue indexOfObjectPassingTest:^(id obj, NSUInteger objId, BOOL *stop){if ([[obj id] isEqualToString:[dict objectForKey:@"id"]]){*stop = YES;return YES;} return NO;}];
                    if (objId == NSNotFound){
                        //trying to locate element's parent
                        FSElement *parentElement = [_db getElementById:[dict objectForKey:@"parent_id"] withFullFilePath:YES];
                        if (parentElement)
                            //db returns full path only starting from the application folder root
                            elementPath = [[_folder stringByAppendingPathComponent:parentElement.filePath] stringByAppendingPathComponent:[dict objectForKey:@"name"]];
                        else {
                            NSUInteger ind = [_serverInsertionsQueue indexOfObjectPassingTest:^(id obj, NSUInteger idx, BOOL *stop){if ([[obj id] isEqualToString:[dict objectForKey:@"parent_id"]]){*stop = YES;return YES;} return NO;}];
                            if (ind != NSNotFound) {
                                //in _serverInsertionsQueue we already have elements with absolute file paths
                                elementPath = [[[_serverInsertionsQueue objectAtIndex:ind] filePath] stringByAppendingPathComponent:[dict objectForKey:@"name"]];
                            }
                        }
                        if (!elementPath) continue; //nothing found neither in db nor in serverQueue - that innormal, but we must do with it anyway
                        FSElement *elementToAdd = [[FSElement alloc] init];
                        elementToAdd.filePath = elementPath;
                        elementToAdd.id = [dict objectForKey:@"id"];
                        elementToAdd.pid = [dict objectForKey:@"parent_id"];
                        if ([[dict objectForKey:@"event"] isEqualTo:@"dir_created"]) elementToAdd.hash = @"NULL";
                        [_serverInsertionsQueue addObject:elementToAdd];
                    }
                }
                /** the principle on which the algorithm relies when moving files/fodlers:
                 move = deletion (from the old location) + creation (at the new location)
                 three queues are created: deletion queue, creation queue and move queue
                 deletion queue stores the elements that were moved out
                 creation queue stores the elements which will be created at the destination location
                 move queue matches the elements from deletion queue to insertion queue. If found the match then the file is moved, 
                    elsewere two actions are accomplished separately - one element is deleted and the other element is created
                 **/
                if ([[dict objectForKey:@"event"] isEqualTo:@"file_moved"] ||
                         [[dict objectForKey:@"event"] isEqualTo:@"dir_moved"]){
                    NSString *oldId = [[dict objectForKey:@"event"] isEqualTo:@"file_moved"] ? [dict objectForKey:@"old_id"] : [dict objectForKey:@"id"];
                    NSString *newId = [[dict objectForKey:@"event"] isEqualTo:@"file_moved"] ? [dict objectForKey:@"new_id"] : [dict objectForKey:@"id"];
                    FSElement *elementToDel = [_db getElementById:oldId withFullFilePath:YES];
                    if (!elementToDel) {
                        NSUInteger ind = [_serverInsertionsQueue indexOfObjectPassingTest:^(id obj, NSUInteger idx, BOOL *stop){if ([[obj id] isEqualToString:oldId]){*stop = YES;return YES;} return NO;}];
                        if (ind == NSNotFound) continue; //nothing found, return
                        elementToDel = [_serverInsertionsQueue objectAtIndex:ind];
                        [_serverInsertionsQueue removeObjectAtIndex:ind];
                    }
                    else {
                        elementToDel.filePath = [_folder stringByAppendingPathComponent:elementToDel.filePath];
                        [_serverDeletionsQueue addObject:elementToDel];
                        [_serverMoves setObject:elementToDel.id forKey:elementToDel.id];
                    }
                    //move or rename
                    if ([[dict objectForKey:@"new_parent_id"] isNotEqualTo:@"1108987033540"]){ //TODO: Trash ID HERE!
                        FSElement *elementToAdd = [[FSElement alloc] init];
                        FSElement *newParent = [_db getElementById:[dict objectForKey:@"new_parent_id"] withFullFilePath:YES];
                        NSString *newParentFP;
                        if(newParent) {
                            newParentFP = [_folder stringByAppendingPathComponent:newParent.filePath];
                        } else {
                            NSUInteger pind = [_serverInsertionsQueue indexOfObjectPassingTest:^(id obj, NSUInteger idx, BOOL *stop){if ([[obj id] isEqualToString:[dict objectForKey:@"new_parent_id"]]){*stop = YES;return YES;} return NO;}];
                            newParentFP = [[_serverInsertionsQueue objectAtIndex:pind] filePath];
                        }
                        elementToAdd.name = [dict objectForKey:@"new_name"];
                        elementToAdd.filePath = [newParentFP stringByAppendingPathComponent:elementToAdd.name];
                        elementToAdd.id = newId;
                        elementToAdd.pid = [dict objectForKey:@"new_parent_id"];
                        elementToAdd.hash = elementToDel.hash;
                        [_serverInsertionsQueue addObject:elementToAdd];
                        //find the deletion id corresponding to the moving file: //TODO: swap keys and values in _serverMoves
                        NSArray *delIdAr = [_serverMoves allKeysForObject:elementToDel.id];
                        if ([delIdAr count])
                            [_serverMoves setObject:elementToAdd.id forKey:[delIdAr objectAtIndex:0]];
                    //delete
                    } else {
                        
                    }
                }
            }
            for (FSElement *el in _serverInsertionsQueue) {
                NSLog(@"+%@ %@ %@", el.id, el.filePath, el.pid);
            }
            for (FSElement *el in _serverDeletionsQueue) {
                NSLog(@"-%@ %@ %@", el.id, el.filePath, el.pid);
            }
            for (id key in [_serverMoves allKeys]) {
                NSLog(@"move:%@ %@", key, [_serverMoves objectForKey:key]);
            }
            
            [self performServerInsertionQueue];
            [self performServerDeletionQueue];
            
        } else NSLog(@"Error code:%ld description:%@",[e code],[e localizedDescription]);
    }];
}

-(void) getClientQueues {
    FSElement *root = [[FSElement alloc] initWithPath:_folder];
    root.id = @"1108986033540";
    [_folderStack push:root];
    while([_folderStack count] != 0){
        FSElement *stackElem = [_folderStack pop];
        NSMutableArray* bdfiles = [NSMutableArray arrayWithArray:[_db childElementsOfId:[stackElem id]]];
        NSArray* files = [_fm contentsOfDirectoryAtPath:stackElem.filePath error:nil];
        for(NSString *file in files) {
            NSString *path = [stackElem.filePath stringByAppendingPathComponent:file];
            FSElement *elementToAdd = [[FSElement alloc] initWithPath:path];
            elementToAdd.pid = stackElem.id;
            BOOL isDir = NO;
            [_fm fileExistsAtPath:elementToAdd.filePath isDirectory:&isDir];
            NSUInteger foundIndex = [bdfiles indexOfObjectPassingTest:^(id obj, NSUInteger idx, BOOL *stop){if ([[obj name] isEqualToString:elementToAdd.name]){*stop = YES;return YES;} return NO;}];
            if (foundIndex == NSNotFound) {
                [_clientInsertionsQueue addObject:elementToAdd];
            }
            else {
                FSElement *dbElem = bdfiles[foundIndex];
                if(isDir){
                    dbElem.filePath = elementToAdd.filePath;
                    [_folderStack push:dbElem];
                } else
                if (![elementToAdd.mdate isEqualToString:dbElem.mdate]){
                    elementToAdd.id = dbElem.id;
                    [_clientInsertionsQueue addObject:elementToAdd];
                }
                [bdfiles removeObjectAtIndex:foundIndex];
            }
        }
        if (bdfiles.count != 0)
            for(FSElement *fse in bdfiles) [_clientDeletionsQueue addObject:fse];
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ [self performClientInsertionQueue]; });
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ [self performClientDeletionQueue]; });
}

-(void)resolveConflicts{
    for(FSElement *serverInsertionElement in _serverInsertionsQueue){
        NSUInteger foundIndex = [_clientInsertionsQueue indexOfObjectPassingTest:^(id obj, NSUInteger idx, BOOL *stop){if ([[obj name] isEqualToString:serverInsertionElement.name] && [[obj pid] isEqualToString:serverInsertionElement.pid]){*stop = YES;return YES;} return NO;}];
        if (foundIndex != NSNotFound && [serverInsertionElement.hash isNotEqualTo:@"NULL"]){
            __block NSString *sInsHash;
            ApiRequest *getHashRequest = [[ApiRequest alloc] initWithAction:@"get_props" params:@{@"id":serverInsertionElement.id} withToken:YES];
            [getHashRequest performRequestWithBlock:^(NSDictionary *response, NSError *e){
                if (!e) {
                    for(id obj in [response objectForKey:@"object"]){
                        if([[obj key] isEqualToString:@"chksum"]){
                            sInsHash = [obj value];
                        }else continue;
                    }
                    serverInsertionElement.hash = sInsHash;
                    FSElement *clientInsertionElement = _clientInsertionsQueue[foundIndex];
                    if([clientInsertionElement.hash isEqualTo:sInsHash]){
                        [_serverInsertionsQueue removeObject:serverInsertionElement];
                    }
                    

                }else NSLog(@"Error code:%ld description:%@",[e code],[e localizedDescription]);
            }];
        }
    }
    
    NSMutableArray *nonDeletableIds = [NSMutableArray arrayWithCapacity:50];
    for(FSElement *serverInsertionElement in _serverInsertionsQueue){
        FSElement *p = serverInsertionElement;
        while([p.pid isNotEqualTo:@"<null>"]){
            [nonDeletableIds addObject:p.pid];
            p = [_db getElementById:p.pid];
        }
    }
    //TODO: check not only del.id = insert.id, but the del elem's child ids also!
    for (FSElement *clientDeletionElement in _clientDeletionsQueue){
        NSUInteger foundIndex = [nonDeletableIds indexOfObjectPassingTest:^(id obj, NSUInteger idx, BOOL *stop){if ([obj isEqualToString:clientDeletionElement.id]){*stop = YES;return YES;} return NO;}];
        if (foundIndex != NSNotFound){
            [_clientDeletionsQueue removeObject:clientDeletionElement];
        }
    }
    [nonDeletableIds removeAllObjects];
    for(FSElement *clientInsertionElement in _clientInsertionsQueue){
        FSElement *p = clientInsertionElement;
        while([p.pid isNotEqualTo:@"<null>"]){
            [nonDeletableIds addObject:p.pid];
            p = [_db getElementById:p.pid];
        }
    }
    //TODO: check not only del.id = insert.id, but the del elem's child ids also!
    for (FSElement *serverDeletionElement in _serverDeletionsQueue){
        NSUInteger foundIndex = [nonDeletableIds indexOfObjectPassingTest:^(id obj, NSUInteger idx, BOOL *stop){if ([obj isEqualToString:serverDeletionElement.id]){*stop = YES;return YES;} return NO;}];
        if (foundIndex != NSNotFound){
            [_serverDeletionsQueue removeObject:serverDeletionElement];
        }
    }
}

-(void) performClientInsertionQueue{
    for(FSElement *fse in _clientInsertionsQueue) {
        if ([fse.hash isEqualToString:@"NULL"]) { // directory, recursively hop in it and it's contents
            [_uploadFolderStack push:fse];
            
            while ([_uploadFolderStack count] > 0) {
                __block FSElement *curDirEl = [_uploadFolderStack pop];
                
                //firstly, create a dir on the server to get it's id [respectively block thread to wait for execution of request]
                ApiRequest *folderUploadRequest = [[ApiRequest alloc] initWithAction:@"make_dir" params:@{@"dir_id":curDirEl.pid, @"dir_name":curDirEl.name} withToken:YES];
                [folderUploadRequest performRequestWithBlock:^(NSDictionary *response, NSError *e){
                    
                    if (!e) {
                        curDirEl.id = [response valueForKey:@"dir_id"];
                        [_db insertElement:curDirEl];
                        
                        //iterate through files
                        NSArray* files = [_fm contentsOfDirectoryAtPath:curDirEl.filePath error:nil];
                        for(NSString *file in files) {
                            NSString *path = [curDirEl.filePath stringByAppendingPathComponent:file];
                            FSElement *childEl = [[FSElement alloc] initWithPath:path];
                            childEl.pid = curDirEl.id;
                            
                            BOOL isDir = NO;
                            [_fm fileExistsAtPath:childEl.filePath isDirectory:&isDir];
                            
                            if (isDir) { //directory - just push it into stack for upload
                                [_uploadFolderStack push:childEl];
                            } else { //file - upload ad store it in db
                                ApiRequest *fileUploadRequest2 = [[ApiRequest alloc] initWithAction:@"put_file" params:@{@"dir_id" : childEl.pid , @"file" : childEl, @"versioned":@"1"} withToken:YES];
                                [fileUploadRequest2 performRequestWithBlock:^(NSDictionary *response, NSError *e) {
                                    if (!e) {
                                        childEl.id = [[response valueForKey:@"file"] valueForKey:@"id"];
                                        [_db insertElement:childEl];
                                    } else NSLog(@"%ld: %@",[e code],[e localizedDescription]);
                                }];
                            }
                        }
                    } else NSLog(@"%ld: %@",[e code],[e localizedDescription]);
                } synchronous:YES];
            }
        } else {
            ApiRequest *fileUploadRequest = [[ApiRequest alloc] initWithAction:@"put_file" params:@{@"dir_id" : fse.pid , @"file" : fse, @"overwrite":@"1"} withToken:YES];
            [fileUploadRequest performRequestWithBlock:^(NSDictionary *response, NSError *e) {
                
                if (!e) {
                    if (fse.id) [_db updateElementWithId:fse.id withValues:fse];
                    else {
                        fse.id = [[response valueForKey:@"file"] valueForKey:@"id"];
                        [_db insertElement:fse];
                    }
                } else NSLog(@"%ld: %@",[e code],[e localizedDescription]);
            }];
        }
    }
}

- (void) performClientDeletionQueue {
    for(FSElement *fse in _clientDeletionsQueue) {
        if ([fse.hash isEqualToString:@"NULL"]) { // directory, delete it recursively
            ApiRequest *delDirectory = [[ApiRequest alloc] initWithAction:@"remove_dir" params:@{@"dir_id" : fse.id, @"recursive":@"1"} withToken:YES];
            [delDirectory performRequestWithBlock:^(NSDictionary *response, NSError *e) {
                if (!e) {
                    [_db deleteElementById:fse.id];
                } else NSLog(@"%ld: %@",[e code],[e localizedDescription]);
            }];
        } else { // file
            ApiRequest *delFile = [[ApiRequest alloc] initWithAction:@"remove_file" params:@{@"id" : fse.id} withToken:YES];
            [delFile performRequestWithBlock:^(NSDictionary *response, NSError *e) {
                if (!e) {
                    [_db deleteElementById:fse.id];
                } else NSLog(@"%ld: %@",[e code],[e localizedDescription]);
            }];
        }
    }
}

-(void) performServerInsertionQueue{
    for(FSElement *fse in _serverInsertionsQueue) {
        NSArray *delIdAr = [_serverMoves allKeysForObject:fse.id];
        //move file
        if ([delIdAr count]) {
            NSString *delId = [delIdAr objectAtIndex:0];
            NSInteger delInd = [_serverDeletionsQueue indexOfObjectPassingTest:^(FSElement *obj, NSUInteger idx, BOOL *stop){if ([obj.id isEqualToString:delId]){*stop = YES;return YES;} return NO;}];
            FSElement *delEl = [_serverDeletionsQueue objectAtIndex:delInd];
            [_fm moveItemAtPath:delEl.filePath toPath:fse.filePath error:nil];
            [_serverDeletionsQueue removeObjectAtIndex:delInd];
            [_serverMoves removeObjectForKey:delId];
            [_db updateElementWithId:delId withValues:fse];
        //insert file
        } else {
            if ([fse.hash isEqualToString:@"NULL"]) {
                //create dir
                [_fm createDirectoryAtPath:fse.filePath withIntermediateDirectories:YES attributes:nil error:nil];
                [_db insertElement:fse];
            } else {
                ApiRequest *fileDownloadRequest = [[ApiRequest alloc] initWithAction:@"get_file" params:@{@"id" : fse.id} withToken:YES];
                [fileDownloadRequest performStreamRequest:[[NSOutputStream alloc] initToFileAtPath:fse.filePath append:NO] withBlock:^(NSData *response, NSHTTPURLResponse *h, NSError *e) {
                    if (!e) {
                        if ([_db getElementById:fse.id]) {
                            [_db updateElementWithId:fse.id withValues:fse];
                        } else
                            [_db insertElement:fse];
                    } else NSLog(@"%ld: %@",[e code],[e localizedDescription]);
                }];
            }
        }
    }
}

-(void) performServerDeletionQueue{
    for(FSElement *fse in _serverDeletionsQueue) {
        [_fm removeItemAtPath:fse.filePath error:nil];
        [_db deleteElementById:fse.id];
    }
}

@end
