//
//  CDTMutableDocumentRevision.h
//
//
//  Created by Rhys Short on 22/07/2014.
//
//

#import "CDTDocumentRevision.h"

@interface CDTMutableDocumentRevision : CDTDocumentRevision

@property (nonatomic, strong, readwrite, nullable) NSString *sourceRevId;
@property (nonatomic, strong, readwrite, nonnull) NSString *docId;
@property (nonatomic,strong, readwrite, nullable) NSString *revId;

+ (nullable CDTMutableDocumentRevision *)revision;

- (nullable instancetype)initWithDocumentId:(nonnull NSString *)documentId body:(nonnull NSMutableDictionary *)body;

- (nullable instancetype)initWithSourceRevisionId:(nonnull NSString *)sourceRevId;

- (void)setBody:(nonnull NSDictionary *)body;

- (nonnull NSMutableDictionary *)body;

- (nonnull NSMutableDictionary *)attachments;

- (void)setAttachments:(nonnull NSDictionary *)attachments;

@end
