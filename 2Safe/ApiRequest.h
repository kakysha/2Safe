//
//  HTTPApi.h
//  2Safe
//
//  Created by Drunk on 09.12.12.
//  Copyright (c) 2012 zaopark. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ApiRequest : NSObject

//request
@property NSString *action;
@property NSDictionary *requestparams;
@property BOOL withToken;
//response
@property NSHTTPURLResponse *responseHeaders;
@property NSDictionary *response;
@property NSError *error;

- (id)initWithAction:(NSString *)action params:(NSDictionary *)params;
- (id)initWithAction:(NSString *)action params:(NSDictionary *)params withToken:(BOOL)withToken;
- (void) performRequestWithBlock:(void (^)(NSDictionary *r, NSError *e))block synchronous:(BOOL)sync;
- (void) performDataRequestWithBlock:(void (^)(NSData *r, NSHTTPURLResponse* h, NSError *e))block synchronous:(BOOL)sync;
- (void) performStreamRequest:(NSOutputStream *)stream withBlock:(void (^)(NSData *r, NSHTTPURLResponse* h, NSError *e))block synchronous:(BOOL)sync;
- (void) performRequestWithBlock:(void (^)(NSDictionary *r, NSError *e))block;
- (void) performDataRequestWithBlock:(void (^)(NSData *r, NSHTTPURLResponse* h, NSError *e))block;
- (void) performStreamRequest:(NSOutputStream *)stream withBlock:(void (^)(NSData *r, NSHTTPURLResponse* h, NSError *e))block;

@end
