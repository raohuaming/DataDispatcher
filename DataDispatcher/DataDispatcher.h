//
//  DataDispatcher.h
//  DataDispatcher
//
//  Created by Huaming Rao on 4/23/13.
//  Copyright (c) 2013 Huaming Rao. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SocketRocket/SRWebSocket.h"

@interface DataDispatcher : NSObject<SRWebSocketDelegate>

+ (DataDispatcher*) sharedDataDispatcher;

- (void) openSocket;
- (void) closeSocket;
- (BOOL) isReady;

typedef void (^event_callback)(NSDictionary*);
- (void) bindEvent:(NSString*)eventName with:(event_callback)block;
- (void)bindEvent:(NSString *)eventName withSuccess:(event_callback)successBlock failure: (event_callback)failedBlock;
- (void) triggerEvent:(NSString*)eventName withData:(NSDictionary*)data success:(event_callback)success failure:(event_callback)failure;

- (void) triggerEvent:(NSString*)eventName withData:(NSDictionary*)data;

typedef void (^connected_callback)();
- (void) bindEventToConnectWithBlock:(connected_callback)block;

@end


@interface WebSocketEvent : NSObject

@property (nonatomic, strong) NSString* ID;
@property (nonatomic, strong) NSString* name;
@property (nonatomic, strong) NSString* channel;
@property (nonatomic, strong) NSString* connectionID;
@property (nonatomic, assign) Boolean success;
@property (nonatomic, strong) id result;
@property (nonatomic, strong) NSDictionary* data;

- (id)initWithDataArray:(NSArray*)dataArray;
- (NSString*)serialize;
- (NSDictionary*)attributes;

- (BOOL) isConnectedEvent;
- (BOOL) isPingEvent;

@end

