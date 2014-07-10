//
//  CloudantReplicationBase.m
//  ReplicationAcceptance
//
//  Created by Michael Rhodes on 29/01/2014.
//
//

#import "CloudantReplicationBase.h"

#import "CDTDatastoreManager.h"
#import "CDTDatastore.h"

#import <UNIRest.h>

@implementation CloudantReplicationBase

- (void)setUp
{
    [super setUp];
    // Put setup code here; it will be run once, before the first test case.

    self.factoryPath = [self createTemporaryDirectoryAndReturnPath];

    NSError *error;
    self.factory = [[CDTDatastoreManager alloc] initWithDirectory:self.factoryPath error:&error];

    STAssertNil(error, @"CDTDatastoreManager had error");
    STAssertNotNil(self.factory, @"Factory is nil");

    self.remoteRootURL = [NSURL URLWithString:@"http://localhost:5984"]; //[NSURL URLWithString:@"http://rhyshort.cloudant.com:80"]; //
    self.remoteDbPrefix = @"replication-acceptance";
}

- (void)tearDown
{
    self.factory = nil;

    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:self.factoryPath error:&error];
    STAssertNil(error, @"Error deleting temporary directory.");

    // Put teardown code here; it will be run once, after the last test case.
    [super tearDown];
}

#pragma mark Setup helpers

+(NSString*)generateRandomString:(int)num {
    NSMutableString* string = [NSMutableString stringWithCapacity:num];
    for (int i = 0; i < num; i++) {
        [string appendFormat:@"%C", (unichar)('a' + arc4random_uniform(25))];
    }
    return string;
}

- (NSString*)createTemporaryDirectoryAndReturnPath
{
    NSString *tempDirectoryTemplate =
    [NSTemporaryDirectory() stringByAppendingPathComponent:@"cloudant_sync_ios_tests.XXXXXX"];
    const char *tempDirectoryTemplateCString = [tempDirectoryTemplate fileSystemRepresentation];
    char *tempDirectoryNameCString =  (char *)malloc(strlen(tempDirectoryTemplateCString) + 1);
    strcpy(tempDirectoryNameCString, tempDirectoryTemplateCString);
    
    char *result = mkdtemp(tempDirectoryNameCString);
    if (!result)
    {
        STFail(@"Couldn't create temporary directory");
    }
    
    NSString *path = [[NSFileManager defaultManager]
                      stringWithFileSystemRepresentation:tempDirectoryNameCString
                      length:strlen(result)];
    free(tempDirectoryNameCString);
    
    NSLog(@"Database path: %@", path);
    
    return path;
}

#pragma mark Remote database operations

/**
 Create a remote database.
 */
-(void) createRemoteDatabase:(NSString*)name
                 instanceURL:(NSURL*)instanceURL
{
    NSURL *remoteDatabaseURL = [instanceURL URLByAppendingPathComponent:name];
    
    NSDictionary* headers = @{@"accept": @"application/json"};
    UNIHTTPJsonResponse* response = [[UNIRest putEntity:^(UNIBodyRequest* request) {
        [request setUrl:[remoteDatabaseURL absoluteString]];
        [request setHeaders:headers];
        [request setBody:[NSData data]];
    }] asJson];
    STAssertTrue([response.body.object objectForKey:@"ok"] != nil, @"Remote db create failed");
}

/**
 Delete a remote database.
 */
-(void) deleteRemoteDatabase:(NSString*)name
                 instanceURL:(NSURL*)instanceURL
{
    NSURL *remoteDatabaseURL = [instanceURL URLByAppendingPathComponent:name];
    
    NSDictionary* headers = @{@"accept": @"application/json"};
    UNIHTTPJsonResponse* response = [[UNIRest delete:^(UNISimpleRequest* request) {
        [request setUrl:[remoteDatabaseURL absoluteString]];
        [request setHeaders:headers];
    }] asJson];
    STAssertTrue([response.body.object objectForKey:@"ok"] != nil, @"Remote db delete failed");
}


/**
 Create a remote document with a given ID, returning the revId
 */
- (NSString*)createRemoteDocumentWithId:(NSString*)docId
                                   body:(NSDictionary*)body
                            databaseURL:(NSURL*)dbUrl
{
    NSURL *docURL = [dbUrl URLByAppendingPathComponent:docId];
    NSDictionary *headers = @{@"accept": @"application/json",
                              @"content-type": @"application/json"};
    UNIHTTPJsonResponse* response = [[UNIRest putEntity:^(UNIBodyRequest* request) {
        [request setUrl:[docURL absoluteString]];
        [request setHeaders:headers];
        [request setBody:[NSJSONSerialization dataWithJSONObject:body
                                                         options:0
                                                           error:nil]];
    }] asJson];
    STAssertTrue([response.body.object objectForKey:@"ok"] != nil, @"Create document failed");
    NSString *revId = [response.body.object objectForKey:@"rev"];
    return revId;
}

/**
 Add an attachment to a document with a given ID, returning the revId
 */
- (NSString*)addAttachmentToRemoteDocumentWithId:(NSString*)docId
                                           revId:(NSString*)revId
                                  attachmentName:(NSString*)attachmentName
                                     contentType:(NSString*)contentType
                                            data:(NSData*)data
                                     databaseURL:(NSURL*)dbUrl
{
    NSURL *docURL = [dbUrl URLByAppendingPathComponent:docId];
    NSString *contentLength = [NSString stringWithFormat:@"%lu", (unsigned long)data.length];
    NSDictionary *headers = @{@"accept": @"application/json",
                              @"content-type": contentType,
                              @"If-Match": revId,
                              @"Content-Length": contentLength};
    UNIHTTPJsonResponse* response = [[UNIRest putEntity:^(UNIBodyRequest* request) {
        NSURL *attachmentURL = [docURL URLByAppendingPathComponent:attachmentName];
        [request setUrl:[attachmentURL absoluteString]];
        [request setHeaders:headers];
        [request setBody:data];
    }] asJson];
    STAssertTrue([response.body.object objectForKey:@"rev"] != nil, @"Adding attachment failed");
    NSString *newRevId = [response.body.object objectForKey:@"rev"];
    return newRevId;
}

/**
 Copy a remote document using HTTP COPY.
 */
- (NSString*)copyRemoteDocumentWithId:(NSString*)fromId
                                 toId:(NSString*)toId
                          databaseURL:(NSURL*)dbUrl
{
    NSURL *docURL = [dbUrl URLByAppendingPathComponent:fromId];
    NSDictionary *headers = @{@"accept": @"application/json",
                              @"content-type": @"application/json",
                              @"Destination": toId};
    UNIHTTPJsonResponse* response;
    response = [[[UNIHTTPRequestWithBody alloc] initWithSimpleRequest:COPY
                                                                  url:[docURL absoluteString] 
                                                              headers:headers
                                                             username:nil 
                                                             password:nil] asJson];
    STAssertTrue([response.body.object objectForKey:@"ok"] != nil, @"Copy document failed");
    NSString *revId = [response.body.object objectForKey:@"rev"];
    return revId;
}

@end
