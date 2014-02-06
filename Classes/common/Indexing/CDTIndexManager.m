//
//  CDTIndexManager.m
//
//
//  Created by Thomas Blench on 27/01/2014.
//
//

#import "CDTIndexManager.h"

#import "CDTSQLiteHelpers.h"
#import "CDTDocumentRevision.h"
#import "CDTFieldIndexer.h"
#import "CDTDatastore.h"

#import "TD_Database.h"

#import "FMResultSet.h"
#import "FMDatabase.h"

static NSString* const CDTIndexManagerErrorDomain = @"CDTIndexManagerErrorDomain";

static NSString* const INDEX_TABLE_PREFIX = @"_t_cloudant_sync_index_";
static NSString* const EXTENSION_NAME = @"com.cloudant.indexing";
static NSString* const INDEX_METADATA_TABLE_NAME = @"_t_cloudant_sync_indexes_metadata";
static NSString* const INDEX_FIELD_NAME_PATTERN = @"^[a-zA-Z][a-zA-Z0-9_]*$";

static const int VERSION = 1;


@interface CDTIndexManager()

-(CDTIndex*)getIndexWithName:(NSString*)indexName;

-(NSDictionary*)getAllIndexes;

-(NSString*)createIndexTable:(NSString*)indexName
                        type:(CDTIndexType)type;

-(BOOL)updateIndex:(CDTIndex*)index
             error:(NSError * __autoreleasing *)error;

-(BOOL)updateIndex:(CDTIndex*)index
           changes:(TD_RevisionList*)changes
      lastSequence:(long*)lastSequence;

-(BOOL)ensureIndexedWithIndexName:(NSString*)indexName
                             type:(CDTIndexType)type
                    indexFunction:(NSObject<CDTIndexer>*)indexFunction
                            error:(NSError * __autoreleasing *)error;

-(BOOL)updateSchema:(int)currentVersion;

@end


@implementation CDTIndexManager

#pragma mark Public methods

-(id)initWithDatastore:(CDTDatastore*)datastore
                 error:(NSError * __autoreleasing *)error
{
    BOOL success = YES;
    self = [super init];
    if (self) {
        _datastore = datastore;
        _indexFunctionMap = [[NSMutableDictionary alloc] init];
        _validFieldRegexp = [[NSRegularExpression alloc] initWithPattern:INDEX_FIELD_NAME_PATTERN options:0 error:error];

        NSString *dir = [datastore extensionDataFolder:EXTENSION_NAME];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:TRUE attributes:nil error:nil];
        NSString *filename = [NSString pathWithComponents:@[dir,@"indexes.sqlite"]];
        _database = [[FMDatabaseQueue alloc]initWithPath:filename];
        if (! _database) {
            // raise error
            NSDictionary *userInfo = @{
                                       NSLocalizedDescriptionKey: NSLocalizedString(@"Problem opening or creating database.", nil),
                                       };
            *error = [NSError errorWithDomain:CDTIndexManagerErrorDomain
                                         code:CDTIndexErrorSqlError
                                     userInfo:userInfo];
            return nil;
        }

        success = [self updateSchema:VERSION];
        if (!success) {
            // raise error
            NSDictionary *userInfo = @{
                                       NSLocalizedDescriptionKey: NSLocalizedString(@"Problem updating database schema.", nil),
                                       };
            *error = [NSError errorWithDomain:CDTIndexManagerErrorDomain
                                         code:CDTIndexErrorSqlError
                                     userInfo:userInfo];
            return nil;
        }
    }
    return self;
}

-(BOOL)ensureIndexedWithIndexName:(NSString*)indexName
                            fieldName:(NSString*)fieldName
                                error:(NSError * __autoreleasing *)error
{
    return [self ensureIndexedWithIndexName:indexName fieldName:fieldName type:CDTIndexTypeString error:error];
}

-(BOOL)ensureIndexedWithIndexName:(NSString*)indexName
                        fieldName:(NSString*)fieldName
                             type:(CDTIndexType)type
                            error:(NSError * __autoreleasing *)error
{
    CDTFieldIndexer *fi = [[CDTFieldIndexer alloc] initWithFieldName:fieldName type:type];
    return [self ensureIndexedWithIndexName:indexName type:type indexFunction:fi error:error];
}

-(BOOL)deleteIndexWithIndexName:(NSString*)indexName
                          error:(NSError * __autoreleasing *)error
{
    __block BOOL success = YES;
    
    NSString *sqlDelete = [NSString stringWithFormat:@"delete from %@ where name = :name;",INDEX_METADATA_TABLE_NAME];
    NSString *sqlDrop   = [NSString stringWithFormat:@"drop table %@%@;",INDEX_TABLE_PREFIX,indexName];
    
    [_database inTransaction:^(FMDatabase *db, BOOL* rollback) {
        NSDictionary *v = @{@"name": indexName};
        success = success && [db executeUpdate:sqlDelete withParameterDictionary:v];
        success = success && [db executeUpdate:sqlDrop];
        if (!success) {
            *rollback = YES;
        }
    }];
    
    if (success) {
        [_indexFunctionMap removeObjectForKey:indexName];
    }
    else {
        NSDictionary *userInfo = @{
                                   NSLocalizedDescriptionKey: NSLocalizedString(@"Problem deleting index.", nil),
                                   };
        *error = [NSError errorWithDomain:CDTIndexManagerErrorDomain
                                     code:CDTIndexErrorSqlError
                                 userInfo:userInfo];
    }
    
    return success;
}

-(BOOL)updateAllIndexes:(NSError * __autoreleasing *)error
{
    BOOL ok = TRUE;
    NSDictionary *indexes = [self getAllIndexes];
    for (CDTIndex *index in [indexes allValues]) {
        [self updateIndex:index error:error];
    }
    return ok;
}

-(CDTQueryResult*) queryWithDictionary:(NSDictionary*)query
                                 error:(NSError * __autoreleasing *)error
{
    return [self queryWithDictionary:query options:nil error:error];
}

-(CDTQueryResult*) queryWithDictionary:(NSDictionary*)query
                               options:(NSDictionary*)options
                                 error:(NSError * __autoreleasing *)error
{
    // TODO support empty query body for just ordering without where clause
    BOOL first = TRUE;
    
    NSString *tables;
    CDTStringJoiner *tablesJoiner = [[CDTStringJoiner alloc] initWithSeparator:@", "];
    NSString *firstTable;
    NSString *currentTable;
    NSString *valueWhereClause;
    CDTStringJoiner *valueWhereClauseJoiner = [[CDTStringJoiner alloc] initWithSeparator:@" and "];
    NSString *idWhereClause;
    CDTStringJoiner *idWhereClauseJoiner = [[CDTStringJoiner alloc] initWithSeparator:@" and "];
    NSMutableArray *queryValues = [[NSMutableArray alloc] init];
    
    // iterate through query terms and build SQL
    for(NSString *indexName in [query keyEnumerator]) {
        
        // validate index name
        if (![self isValidIndexName:indexName error:error]) {
            return nil;
        }
        // ... and check it exists
        if (![self getIndexWithName:indexName]) {
            NSDictionary *userInfo = @{
                                       NSLocalizedDescriptionKey: NSLocalizedString(@"Index named in query does not exist.", nil),
                                       NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"There is no index with the name \"%@\".", indexName],
                                       NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Call one of the ensureIndexed… methods to create the index as required.", nil)
                                       };
            *error = [NSError errorWithDomain:CDTIndexManagerErrorDomain
                                         code:CDTIndexErrorIndexDoesNotExist
                                     userInfo:userInfo];
            return nil;
        }
        
        NSObject *value = [query objectForKey:indexName];
        
        NSString *valueWhereClauseFragment;
        
        // keep track of which table we are on
        currentTable = [NSString stringWithFormat:@"%@%@", INDEX_TABLE_PREFIX, indexName];
        if (first) {
            firstTable = currentTable;
        }
        
        // keep track of all the tables
        [tablesJoiner add:currentTable];
        
        if ([value isKindOfClass: [NSArray class]]) {
            // key: [value1, value2, ..., valuen] -> where clause of = statements joined by OR
            CDTStringJoiner *orWhereClauseJoiner = [[CDTStringJoiner alloc] initWithSeparator:@" or "];
            for (NSString *theValue in (NSArray*)value) {
                NSString *orWhereClauseFragment = [NSString stringWithFormat:@"%@.value = ?", currentTable];
                [orWhereClauseJoiner add:orWhereClauseFragment];
                // accumulate values in array
                [queryValues addObject:theValue];
            }
            valueWhereClauseFragment = [NSString stringWithFormat:@"( %@ )", [orWhereClauseJoiner string]];
        } else if ([value isKindOfClass: [NSDictionary class]]) {
            // key: {min: minVal, max: maxVal} -> where clause of >= and <= statements joined by AND
            CDTStringJoiner *minMaxWhereClauseJoiner = [[CDTStringJoiner alloc] initWithSeparator:@" and "];
            NSObject *minValue = [(NSDictionary*)value objectForKey:@"min"];
            NSObject *maxValue = [(NSDictionary*)value objectForKey:@"max"];
            if (!minValue && !maxValue) {
                // ERROR
            }
            if (minValue) {
                NSString *minValueFragment = [NSString stringWithFormat:@"%@.value >= ?", currentTable];
                [minMaxWhereClauseJoiner add:minValueFragment];
                // accumulate values in array
                [queryValues addObject:minValue];
            }
            if (maxValue) {
                NSString *maxValueFragment = [NSString stringWithFormat:@"%@.value <= ?", currentTable];
                [minMaxWhereClauseJoiner add:maxValueFragment];
                // accumulate values in array
                [queryValues addObject:maxValue];
            }
            valueWhereClauseFragment = [NSString stringWithFormat:@"( %@ )", [minMaxWhereClauseJoiner string]];
        } else {
            // key: {value} -> where clause of one = statement
            // NB we are assuming a simple type eg NSString or NSNumber
            valueWhereClauseFragment = [NSString stringWithFormat:@"%@.value = ?", currentTable];
            // accumulate values in array
            [queryValues addObject:value];
        }
        
        // make where clause for values
        [valueWhereClauseJoiner add:valueWhereClauseFragment];
        
        // make where clause for ids
        if (!first) {
            NSString *idWhereClauseFragment = [NSString stringWithFormat:@"%@.docid = %@.docid", firstTable, currentTable];
            [idWhereClauseJoiner add:idWhereClauseFragment];
        }
        
        first = FALSE;
    }
    
    NSMutableArray *docids = [[NSMutableArray alloc] init];
    
    // ascending unless told otherwsie
    BOOL descending = NO;
    
    if (options && [options valueForKey:@"descending"]) {
        descending = [[options valueForKey:@"descending"] boolValue];
    }
    else if (options && [options valueForKey:@"ascending"]) {
        descending = ![[options valueForKey:@"ascending"] boolValue];
    }
    
    NSString *orderByClause = @"";
    if (options && [options valueForKey:@"sort_by"]) {
        NSString *sort = [options valueForKey:@"sort_by"];

        // validate index name
        if (![self isValidIndexName:sort error:error]) {
            return nil;
        }
        // ... and check it exists
        if (![self getIndexWithName:sort]) {
            NSDictionary *userInfo = @{
                                       NSLocalizedDescriptionKey: NSLocalizedString(@"Index named in sort_by option does not exist.", nil),
                                       NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"There is no index with the name \"%@\".", sort],
                                       NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Call one of the ensureIndexed… methods to create the index as required.", nil)
                                       };
            *error = [NSError errorWithDomain:CDTIndexManagerErrorDomain
                                         code:CDTIndexErrorIndexDoesNotExist
                                     userInfo:userInfo];
            return nil;
        }
        
        currentTable = [NSString stringWithFormat:@"%@%@", INDEX_TABLE_PREFIX,  sort];

        // if the sort by wasn't mentioned in the 'where query' part we'll need to add it here
        // so that the table gets mentioned in the from clause and is joined on docid correctly
        if (![query valueForKey:sort]) {
            
            [tablesJoiner add:currentTable];
            
            // make where clause for ids
            if (!first) {
                NSString *idWhereClauseFragment = [NSString stringWithFormat:@"%@.docid = %@.docid", firstTable, currentTable];
                [idWhereClauseJoiner add:idWhereClauseFragment];
            }
        }
        orderByClause = [NSString stringWithFormat:@"order by %@.value %@", currentTable, descending ? @"desc" : @"asc"];
    }

    // now make the query
    NSString *whereClause;
    tables = [tablesJoiner string];
    valueWhereClause = [valueWhereClauseJoiner string];
    idWhereClause = [idWhereClauseJoiner string];
    
    // do we need to join on ids?
    if ([[idWhereClauseJoiner string] length] > 0) {
        whereClause = [NSString stringWithFormat:@"(%@) and (%@)", valueWhereClause, idWhereClause];
    } else {
        whereClause = valueWhereClause;
    }
    
    NSString *sqlJoin = [NSString stringWithFormat:@"select %@.docid from %@ where %@ %@;", firstTable, tables, whereClause, orderByClause];

    int offset=0;
    int limitCount=0;
    BOOL limit = NO;
    
    if ([options valueForKey:@"offset"]) {
        offset = [[options valueForKey:@"offset"] intValue];
    }
    if ([options valueForKey:@"limit"]) {
        limitCount = [[options valueForKey:@"limit"] intValue];
        limit = YES;
    }
    
    [_database inTransaction:^(FMDatabase *db, BOOL *rollback) {
        FMResultSet *results = [db executeQuery:sqlJoin withArgumentsInArray:queryValues];
        
        int n=0;
        [results next];
        for (int i=0; [results hasAnotherRow]; i++) {
            if (i >= offset && (!limit || n < limitCount)) {
                NSString *docid = [results stringForColumnIndex:0];
                [docids addObject:docid];
                n++;
            }
            [results next];
        }
        [results close];
    }];
    
    // now return CDTQueryResult which is an iterator over the documents for these ids
    CDTQueryResult *result = [[CDTQueryResult alloc] initWithDocIds:docids datastore:_datastore];
    return result;
}

-(NSArray*) uniqueValuesForIndex:(NSString*)indexName
                           error:(NSError * __autoreleasing *)error
{
    // validate index name
    if (![self isValidIndexName:indexName error:error]) {
        return nil;
    }
    // ... and check it exists
    if (![self getIndexWithName:indexName]) {
        NSDictionary *userInfo = @{
                                   NSLocalizedDescriptionKey: NSLocalizedString(@"Index named does not exist.", nil),
                                   NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"There is no index with the name \"%@\".", indexName],
                                   NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Call one of the ensureIndexed… methods to create the index as required.", nil)
                                   };
        *error = [NSError errorWithDomain:CDTIndexManagerErrorDomain
                                     code:CDTIndexErrorIndexDoesNotExist
                                 userInfo:userInfo];
        return nil;
    }

    NSString *table = [NSString stringWithFormat:@"%@%@", INDEX_TABLE_PREFIX, indexName];
    NSString *sql = [NSString stringWithFormat:@"select distinct value from %@;", table];
    NSMutableArray *values = [[NSMutableArray alloc] init];
    
    [_database inTransaction:^(FMDatabase *db, BOOL *rollback) {
        FMResultSet *results = [db executeQuery:sql];
        
        [results next];
        while ([results hasAnotherRow]) {
            [values addObject:[results objectForColumnIndex:0]];
            [results next];
        }
        [results close];
    }];
    return values;
}

#pragma mark Private methods

-(CDTIndex*)getIndexWithName:(NSString*)indexName
{
    // TODO validate index name
    
    NSString *SQL_SELECT_INDEX_BY_NAME = [NSString stringWithFormat:@"SELECT name, type, last_sequence FROM %@ WHERE name = ?;",INDEX_METADATA_TABLE_NAME];

    __block CDTIndexType type;
    __block long lastSequence;
    __block BOOL success = false;
    
    [_database  inTransaction:^(FMDatabase *db, BOOL *rollback) {
        FMResultSet *results = [db executeQuery:SQL_SELECT_INDEX_BY_NAME, indexName];
        [results next];
        if ([results hasAnotherRow]) {
            type = [results longForColumnIndex:1];
            lastSequence = [results longForColumnIndex:2];
            success = true;
        }
        [results close];
    }];
    if (success) {
        return [[CDTIndex alloc] initWithIndexName:indexName lastSequence:lastSequence fieldType:type];
    } else {
        return nil;
    }
}

-(NSDictionary*)getAllIndexes
{
    NSString *SQL_SELECT_INDEX_BY_NAME = [NSString stringWithFormat:@"SELECT name, type, last_sequence FROM %@;",INDEX_METADATA_TABLE_NAME];
    
    NSMutableDictionary *indexes = [[NSMutableDictionary alloc] init];
    
    __block NSString *indexName;
    __block CDTIndexType type;
    __block long lastSequence;
  
    [_database inTransaction:^(FMDatabase *db, BOOL *rollback) {
        FMResultSet *results = [db executeQuery:SQL_SELECT_INDEX_BY_NAME];
        [results next];
        while ([results hasAnotherRow]) {
            indexName = [results stringForColumnIndex:0];
            type = [results longForColumnIndex:1];
            lastSequence = [results longForColumnIndex:2];
            CDTIndex *index = [[CDTIndex alloc] initWithIndexName:indexName lastSequence:lastSequence fieldType:type];
            [indexes setObject:index forKey:indexName];
            [results next];
        }
        [results close];
    }];
    return indexes;
}

-(NSString*)createIndexTable:(NSString*)indexName
                             type:(CDTIndexType)type
{
    CDTIndexHelper *helper = [[CDTIndexHelper alloc] initWithType:type];
    if (helper) {
        NSString *sql = [helper createSQLTemplateWithPrefix:INDEX_TABLE_PREFIX indexName:indexName];
        return sql;
    }
    return nil;
}

-(BOOL)updateIndex:(CDTIndex*)index
             error:(NSError * __autoreleasing *)error
{
    BOOL success = TRUE;
    TDChangesOptions options = {
        .limit = 10000,
        .contentOptions = 0,
        .includeDocs = TRUE,
        .includeConflicts = FALSE,
        .sortBySequence = TRUE
    };
    
    TD_RevisionList *changes;
    long lastSequence = [index lastSequence];
    
    do {
        changes = [[_datastore database] changesSinceSequence:lastSequence options:&options filter:nil params:nil];
        success = success && [self updateIndex:index changes:changes lastSequence:&lastSequence];
    } while (success && [changes count] > 0);
    
    // raise error
    if (!success) {
        NSDictionary *userInfo = @{
                                   NSLocalizedDescriptionKey: NSLocalizedString(@"Problem updating index.", nil),
                                   };
        *error = [NSError errorWithDomain:CDTIndexManagerErrorDomain
                                     code:CDTIndexErrorSqlError
                                 userInfo:userInfo];
    }
    return success;
}

-(BOOL)updateIndex:(CDTIndex*)index
           changes:(TD_RevisionList*)changes
      lastSequence:(long*)lastSequence
{
    __block bool success = YES;
    
    NSString *tableName = [INDEX_TABLE_PREFIX stringByAppendingString:[index indexName]];
    
    NSString *strDelete = @"delete from %@ where docid = :docid;";
    NSString *sqlDelete = [NSString stringWithFormat:strDelete, tableName];
    
    NSString *strInsert = @"insert into %@ (docid, value) values (:docid, :value);";
    NSString *sqlInsert = [NSString stringWithFormat:strInsert, tableName];
    
    NSObject<CDTIndexer>* f = (NSObject<CDTIndexer>*)[_indexFunctionMap valueForKey:[index indexName]];
    
    [_database inTransaction:^(FMDatabase *db, BOOL *rollback) {
        
        for(TD_Revision *rev in changes) {
            NSString *docID = [rev docID];
        
            // delete
            NSDictionary *dictDelete = @{@"docid": docID};
            [db executeUpdate:sqlDelete withParameterDictionary:dictDelete];
            // insert
            NSArray *valuesInsert = [f indexWithIndexName:[index indexName] revision:[[CDTDocumentRevision alloc] initWithTDRevision:rev]];
            for (NSObject *value in valuesInsert) {
                NSDictionary *dictInsert = @{@"docid": docID,
                                             @"value": value};
                success = success && [db executeUpdate:sqlInsert withParameterDictionary:dictInsert];
            }
            if (!success) {
                // TODO fill in error
                *rollback = true;
                break;
            }
            *lastSequence = [rev sequence];
        }
    }];
    
    // if there was a problem, we rolled back, so the sequence won't be updated
    if (success) {
        return [self updateIndexLastSequence:[index indexName] lastSequence:*lastSequence];
    } else {
        return FALSE;
    }
}

-(BOOL)updateIndexLastSequence:(NSString*)indexName
                  lastSequence:(long)lastSequence
{
    __block BOOL success = TRUE;

    NSDictionary *v = @{@"name": indexName,
                        @"last_sequence": [NSNumber numberWithLong:lastSequence]};
    NSString *template = @"update %@ set last_sequence = :last_sequence where name = :name;";
    NSString *sql = [NSString stringWithFormat:template, INDEX_METADATA_TABLE_NAME];
    
    [_database inTransaction:^(FMDatabase *db, BOOL *rollback) {
        success = success && [db executeUpdate:sql withParameterDictionary:v];
        if (!success){
            *rollback = YES;
        }
    }];
    return success;
}

-(BOOL)ensureIndexedWithIndexName:(NSString*)indexName
                             type:(CDTIndexType)type
                    indexFunction:(NSObject<CDTIndexer>*)indexFunction
                            error:(NSError * __autoreleasing *)error
{
    // validate index name
    if (![self isValidIndexName:indexName error:error]) {
        return NO;
    }
    // already registered?
    if ([_indexFunctionMap objectForKey:indexName]) {
        NSDictionary *userInfo = @{
                                   NSLocalizedDescriptionKey: NSLocalizedString(@"Index already registered with a call to ensureIndexed this session.", nil),
                                   NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"Index already registered?", nil),
                                   NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Index already registered?", nil)
                                   };
        *error = [NSError errorWithDomain:CDTIndexManagerErrorDomain
                                     code:CDTIndexErrorIndexAlreadyRegistered
                                 userInfo:userInfo];
        return NO;
    }
    
    __block CDTIndex *index = [self getIndexWithName:indexName];
    __block BOOL success = YES;
    NSMutableDictionary *indexFunctionMap = _indexFunctionMap;
    __weak CDTIndexManager *weakSelf = self;
    
    [_database inTransaction:^(FMDatabase *db, BOOL *rollback) {
        if (index == nil) {
            NSString *sqlCreate = [weakSelf createIndexTable:indexName type:type];
            // TODO splitting up statement, should do somewhere else?
            for (NSString * str in [sqlCreate componentsSeparatedByString:@";"]) {
                if ([str length] != 0) {
                    success = success && [db executeUpdate:str];
                }
            }
            
            CDTIndexHelper *helper = [[CDTIndexHelper alloc] initWithType:type];
            // same as insertIndexMetaData
            NSDictionary *v = @{@"name": indexName,
                                @"last_sequence": [NSNumber numberWithInt:0],
                                @"type": [helper typeName]};
            NSString *strInsert = @"insert into %@ values (%@);";
            NSString *sqlInsert = [NSString stringWithFormat:strInsert, INDEX_METADATA_TABLE_NAME, [CDTSQLiteHelpers makeInsertPlaceholders:v]];

            success = success && [db executeUpdate:sqlInsert withParameterDictionary:v];
        } else {
            NSLog(@"not creating index, it was there already");
        }
        if (success) {
            [indexFunctionMap setObject:indexFunction forKey:indexName];
        } else {
            // raise error, either creating the table or doing the insert
            *rollback = YES;
        }
    }];

    // this has to happen outside that tx
    if (success) {
        if (index == nil) {
            // we just created it, re-get it
            index = [self getIndexWithName:indexName];
        }
        // update index will populate error if necessary
        success = success && [self updateIndex:index error:error];
    }
    
    return success;
}

-(BOOL)updateSchema:(int)currentVersion
{
    NSString* SCHEMA_INDEX = @"CREATE TABLE _t_cloudant_sync_indexes_metadata ( "
    @"        name TEXT NOT NULL, "
    @"        type TEXT NOT NULL, "
    @"        last_sequence INTEGER NOT NULL);";

    __block BOOL success = YES;

    // get current version
    [_database  inTransaction:^(FMDatabase *db, BOOL *rollback) {
        FMResultSet *results= [db executeQuery:@"pragma user_version;"];
        [results next];
        int version = 0;
        if ([results hasAnotherRow]) {
            version = [results intForColumnIndex:0];
        }
        if (version < currentVersion) {
            // update version in pragma
            // NB we format the entire sql here because pragma doesn't seem to allow ? placeholders
            success = success && [db executeUpdate:[NSString stringWithFormat:@"pragma user_version = %d", currentVersion]];
            success = success && [db executeUpdate:SCHEMA_INDEX];
            if (!success) {
                *rollback = YES;
            }
        } else {
            success = YES;
        }
        [results close];
    }];
    
    return success;
}

-(BOOL)isValidIndexName:(NSString*)indexName
                  error:(NSError * __autoreleasing *)error
{
    if ([_validFieldRegexp numberOfMatchesInString:indexName options:0 range:NSMakeRange(0,[indexName length])] == 0) {
        NSDictionary *userInfo = @{
                                   NSLocalizedDescriptionKey: NSLocalizedString(@"Index name is not valid.", nil),
                                   NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"Index name \"%@\" does not match regex ^[a-zA-Z][a-zA-Z0-9_]*$", indexName],
                                   NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Use an index which matches regex ^[a-zA-Z][a-zA-Z0-9_]*$?", nil)
                                   };
        *error = [NSError errorWithDomain:CDTIndexManagerErrorDomain
                                     code:CDTIndexErrorInvalidIndexName
                                 userInfo:userInfo];
        return NO;
    }
    return YES;
}


@end


#pragma mark CDTQueryResult class

@implementation CDTQueryResult

-(id)initWithDocIds:(NSArray*)docIds
          datastore:(CDTDatastore*)datastore
{
    self = [super init];
    if (self) {
        _documentIds = docIds;
        _datastore   = datastore;
    }
    return self;
}

-(NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained [])buffer count:(NSUInteger)len
{

    if(state->state == 0) {
        state->state = 1;
        // this is our index into docids list
        state->extra[0] = 0;
        // number of mutations, although we ignore this
        state->mutationsPtr = &state->extra[1];
    }
    // get our current index for this batch
    unsigned long *index = &state->extra[0];
    
    NSRange range;
    range.location = (unsigned int)*index;
    range.length   = MIN((len), ([_documentIds count]-range.location));

    // get documents for this batch of documentids
    NSArray *batchIds = [_documentIds subarrayWithRange:range];
    __unsafe_unretained NSArray *docs = [_datastore getDocumentsWithIds:batchIds];

    int i;
    for (i=0; i < range.length; i++){
        buffer[i] = docs[i];
    }
    // update index ready for next time round
    (*index) += i;

    state->itemsPtr = buffer;
    return i;
}

@end