//
//  CDTQIndexManager.h
//
//  Created by Mike Rhodes on 2014-09-27
//  Copyright (c) 2014 Cloudant. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import <Foundation/Foundation.h>

extern NSString * __nonnull const CDTQIndexManagerErrorDomain;
extern NSString * __nonnull const kCDTQIndexTablePrefix;
extern NSString * __nonnull const kCDTQIndexMetadataTableName;

@class CDTDatastore;
@class CDTQResultSet;
@class CDTDocumentRevision;
@class FMDatabaseQueue;
@class FMDatabase;

@interface CDTQSqlParts : NSObject

@property (nonatomic, strong,nonnull) NSString *sqlWithPlaceholders;
@property (nonatomic, strong,nonnull) NSArray *placeholderValues;

+ (nullable CDTQSqlParts *)partsForSql:(nonnull NSString *)sql parameters:(nullable NSArray *)parameters;

@end

/**
 * Indexing and query erors.
 */
typedef NS_ENUM(NSInteger, CDTQQueryError) {
    /**
     * Index name not valid. Names can only contain letters,
     * digits and underscores. They must not start with a digit.
     */
    CDTQIndexErrorInvalidIndexName = 1,
    /**
     * An SQL error occurred during indexing or querying.
     */
    CDTQIndexErrorSqlError = 2,
    /**
     * No index with this name was found.
     */
    CDTQIndexErrorIndexDoesNotExist = 3,
    /**
     * Key provided could not be used to initialize index manager
     */
    CDTQIndexErrorEncryptionKeyError = 4
};

/**
 Main interface to Cloudant query.

 Use the manager to:

 - create indexes
 - delete indexes
 - execute queries
 - update indexes (usually done automatically)
 */
@interface CDTQIndexManager : NSObject

@property (nonatomic, strong, nonnull) CDTDatastore *datastore;
@property (nonatomic, strong, nonnull) FMDatabaseQueue *database;
@property (nonatomic, readonly, getter = isTextSearchEnabled) BOOL textSearchEnabled;

/**
 Constructs a new CDTQIndexManager which indexes documents in `datastore`
 */
+ (nullable CDTQIndexManager *)managerUsingDatastore:(nonnull CDTDatastore *)datastore
                                      error:(NSError *__nullable __autoreleasing * __nullable)error;

- (nullable instancetype)initUsingDatastore:(nonnull CDTDatastore *)datastore
                             error:(NSError *__nullable __autoreleasing * __nullable)error;

- (nonnull NSDictionary * /* NSString -> NSArray[NSString]*/)listIndexes;

/** Internal */
+ (nonnull NSDictionary /* NSString -> NSArray[NSString]*/ *)listIndexesInDatabaseQueue:
        (nonnull FMDatabaseQueue *)db;
/** Internal */
+ (nonnull NSDictionary /* NSString -> NSArray[NSString]*/ *)listIndexesInDatabase:(nonnull FMDatabase *)db;

- (nullable NSString *)ensureIndexed:(nonnull NSArray * /* NSString */)fieldNames withName:(nonnull NSString *)indexName;

- (nullable NSString *)ensureIndexed:(nonnull NSArray * /* NSString */)fieldNames
                            withName:(nonnull NSString *)indexName
                                type:(nonnull NSString *)type;

- (nullable NSString *)ensureIndexed:(nonnull NSArray * /* NSString */)fieldNames
                            withName:(nonnull NSString *)indexName
                                type:(nonnull NSString *)type
                            settings:(nullable NSDictionary *)indexSettings;

- (BOOL)deleteIndexNamed:(nonnull NSString *)indexName;

- (BOOL)updateAllIndexes;

- (nullable CDTQResultSet *)find:(nonnull NSDictionary *)query;

- (nullable CDTQResultSet *)find:(nonnull NSDictionary *)query
                            skip:(NSUInteger)skip
                           limit:(NSUInteger)limit
                          fields:(nullable NSArray *)fields
                            sort:(nullable NSArray *)sortDocument;

/** Internal */
+ (nullable NSString *)tableNameForIndex:(nonnull NSString *)indexName;

/** Internal */
+ (BOOL)ftsAvailableInDatabase:(nonnull FMDatabaseQueue *)db;

@end
