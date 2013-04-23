//
//  DataDispatcher.m
//  DataDispatcher
//
//  Created by Huaming Rao on 4/23/13.
//  Copyright (c) 2013 Huaming Rao. All rights reserved.
//

#import "DataDispatcher.h"

static DataDispatcher* _dataDispatcher = nil;
static NSString* kWebSocketServerURLString = @"ws:yourserver:port/websocket";
static int kWebSocketSendDataBufferSize = 5;

#pragma mark - Private

@interface DataDispatcher()

@property (nonatomic, strong) NSMutableArray* connected_callbacks;
@property (nonatomic, strong) SRWebSocket* webSocket;
@property (nonatomic, strong) NSMutableDictionary* callbacks;
@property (nonatomic, strong) dispatch_queue_t eventQueue;
@property (nonatomic, strong) dispatch_queue_t triggerQueue;
@property (nonatomic, strong) NSMutableArray* sendDataBuffer;
@property (nonatomic, assign) bool isCallOpenSocket;
@property (nonatomic, strong) NSString* connection_id;

@end

#pragma mark - Inplementation

@implementation DataDispatcher

+ (DataDispatcher*) sharedDataDispatcher
{
    @synchronized(self)
    {
        if(!_dataDispatcher)
        {
            _dataDispatcher = [[super allocWithZone:NULL] init];
        }
    }
    return _dataDispatcher;
}

+ (id)allocWithZone:(NSZone *)zone
{
    return [self sharedDataDispatcher];
}

- (void) initWebSocket
{
    self.webSocket = [[SRWebSocket alloc] initWithURLRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:kWebSocketServerURLString]]];
    self.webSocket.delegate = self;
}

- (id) init
{
    if (_dataDispatcher) return _dataDispatcher;
    self = [super init];
    if (self)
    {
        [self initWebSocket];
        self.callbacks = [NSMutableDictionary dictionary];
        self.eventQueue = dispatch_queue_create("your domain", DISPATCH_QUEUE_SERIAL);
        self.triggerQueue = dispatch_queue_create("your domain", DISPATCH_QUEUE_SERIAL);
        self.sendDataBuffer = [NSMutableArray array];
        self.isCallOpenSocket = NO;
        self.connected_callbacks = [NSMutableArray array];
    }
    return self;
}

- (void) openSocket
{
    if(self.isCallOpenSocket == NO)
    {
        self.isCallOpenSocket = YES;
        [self.webSocket open];
    }
}

- (void)closeSocket
{
    if(self.isCallOpenSocket == YES)
    {
        self.isCallOpenSocket = NO;
        [self.webSocket close];
        self.webSocket = nil;
    }
}

- (BOOL)isReady
{
    return (self.webSocket.readyState == SR_OPEN);
}

- (void)reconnectWebSocket
{
    if (self.isCallOpenSocket == YES)
    {
        [self.webSocket close];
        [self initWebSocket];
        [self.webSocket open];
    }
}


#pragma mark - support for websocket-rails
- (void)bindEvent:(NSString *)eventName withSuccess:(event_callback)successBlock failure: (event_callback)failedBlock
{
    if ([self.callbacks objectForKey:eventName] == nil)
    {
        [self.callbacks setValue:[NSMutableArray arrayWithCapacity:2] forKey:eventName];
    }
    NSMutableArray* callbacks = (NSMutableArray*)[self.callbacks objectForKey:eventName];
    if(successBlock == nil) successBlock = ^(NSDictionary* m){};
    if(failedBlock == nil) failedBlock = ^(NSDictionary* m){};
    [callbacks setObject:successBlock atIndexedSubscript:0];
    [callbacks setObject:failedBlock atIndexedSubscript:1];
}

- (void) bindEvent:(NSString*)eventName with:(event_callback)block
{
    [self bindEvent:eventName withSuccess:nil failure:block];
}

- (void)bindEventToConnectWithBlock:(connected_callback)block
{
    [self.connected_callbacks addObject:block];
}

- (void)triggerEvent:(NSString *)eventName withData:(NSDictionary *)message success:(event_callback)success failure:(event_callback)failure
{
    
    NSMutableArray* to_sent = [NSMutableArray arrayWithObjects:eventName,nil];
    
    //    NSString* eventID = [NSString stringWithFormat:@"%d", 100000 + arc4random()%(999999-100000+1)];
    if(message == nil) message = [NSDictionary dictionary];
    NSDictionary* data = [NSDictionary dictionaryWithObjectsAndKeys:self.connection_id, @"id", message, @"data", nil];
    [to_sent addObject:data];
    NSError* error;
    NSData* jsonData = [NSJSONSerialization dataWithJSONObject:to_sent options:kNilOptions error:&error];
    
    if(success || failure) [self bindEvent:eventName withSuccess:success failure:failure];
    NSString* sendData = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    if (self.isReady)
    {
        dispatch_async(self.triggerQueue,^{
            [self.webSocket send: sendData];
        });
    }else
    {
        if(sendData)
        {
            if (self.sendDataBuffer.count >= kWebSocketSendDataBufferSize) [self.sendDataBuffer removeObjectAtIndex:0];
            [self.sendDataBuffer addObject:sendData];
        }
    }
}

- (void)triggerEvent:(NSString *)eventName withData:(NSDictionary *)data
{
    [self triggerEvent:eventName withData:data success:nil failure:nil];
}

#pragma mark - SRWebSocketDelegate

- (void)flushSendDataBuffer
{
    for (NSString* sendData in self.sendDataBuffer)
    {
        [self.webSocket send:sendData];
    }
    [self.sendDataBuffer removeAllObjects];
}

- (void)webSocketDidOpen:(SRWebSocket *)webSocket;
{
    NSLog(@"Websocket Connected");
    
    for (connected_callback callback in self.connected_callbacks) {
        callback();
    }
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error;
{
    NSLog(@":( Websocket Failed With Error %@", error);
    [self reconnectWebSocket];
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message;
{
    NSLog(@"Received \"%@\"", message);
    NSError* error;
    NSArray* dataArray = [NSJSONSerialization JSONObjectWithData:[message dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:&error];
    WebSocketEvent* event = [[WebSocketEvent alloc] initWithDataArray:[dataArray objectAtIndex:0]];
    
    if(event.isConnectedEvent)
    {
        self.connection_id = [event.data objectForKey:@"connection_id"];
        [self flushSendDataBuffer];
    }
    else if(event.isPingEvent)
    {
        [self triggerEvent:@"websocket_rails.pong" withData:nil];
    }
    else
    {
        NSArray* blocks = [self.callbacks valueForKey:event.name];
        if([event.name isEqual:@"get_needle_position"])
        {
            NSLog(@"dfjdkfj");
        }
        event_callback block = nil;
        NSLog(@"%c", event.success == YES);
        if(event.success) block = blocks[0];
        else block = blocks[1];
        if (block)
        {
            dispatch_async(self.eventQueue,^{
                block(event.data);
            });
        }
    }
    
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean;
{
    NSLog(@":( WebSocket closed with Code %@", reason);
    [self reconnectWebSocket];
}

@end


@implementation WebSocketEvent

- (id)initWithDataArray:(NSArray *)dataArray
{
    self = [super init];
    if(self)
    {
        self.name = dataArray[0];
        NSDictionary* attr = dataArray[1];
        if (attr)
        {
            self.ID = [attr valueForKey:@"id"];
            if (self.ID == nil) {
                self.ID = [NSString stringWithFormat:@"%d", 100000 + arc4random()%(999999-100000+1)];
            }
            self.channel = [attr valueForKey:@"channel"];
            self.data = [attr valueForKey:@"data"];
            if (self.data == nil) {
                self.data = attr;
            }
            self.connectionID = [attr valueForKey:@"connection_id"];
            if ([[attr valueForKey:@"success"] isEqual: [NSNumber numberWithInt:1]]) self.success = true;
            else self.success = false;
        }
        
    }
    
    return self;
}

- (NSString*)serialize
{
    NSArray* toSerialize = [NSArray arrayWithObjects:self.name, self.attributes, nil];
    NSError* error;
    NSData* jsonData = [NSJSONSerialization dataWithJSONObject:toSerialize options:kNilOptions error:&error];
    if (error) {
        NSLog(@"Error: %@", error);
        return @"";
    }
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (NSDictionary *)attributes
{
    NSDictionary* result = [NSDictionary dictionaryWithObjectsAndKeys:
                            self.ID, @"id",
                            self.channel, @"channel",
                            self.data, @"data",
                            nil];
    return result;
}

-(BOOL)isConnectedEvent
{
    return ([self.name isEqual: @"client_connected"]);
}

- (BOOL)isPingEvent
{
    return ([self.name isEqual:@"websocket_rails.ping"]);
}

@end
