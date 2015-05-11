//
//  CDTBlobData.h
//  CloudantSync
//
//  Created by Enrique de la Torre Fernandez on 05/05/2015.
//  Copyright (c) 2015 IBM Cloudant. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//  http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//

#import <Foundation/Foundation.h>

#import "CDTBlobReader.h"
#import "CDTBlobWriter.h"

extern NSString *const CDTBlobDataErrorDomain;

typedef NS_ENUM(NSInteger, CDTBlobDataError) {
    CDTBlobDataErrorOperationNotPossibleIfBlobIsOpen
};

/**
 Use this class to read from/write to an attachment. The data read from an attachment is returned
 as it is, so make sure that the attachment is not encrypted. In the same way, the data provided is
 written to the attachment without further processing.
 
 To accomplish this purpose, this class conforms to 2 related protocols: CDTBlobReader &
 CDTBlobWriter. About CDTBlobWriter:
 
 - 'openBlobToAddData'.- Call this method before calling 'CDTBlobWriter:addData:'. The file informed
 during the initialisation must exist on advance or it will fail.
 - 'isBlobOpen'.- It will return YES after calling 'CDTBlobWriter:openBlobToAddData' and NO after
 calling 'CDTBlobWriter:closeBlob'. By default, a newly initialised blob is closed.
 - 'closeBlob'.- Call it after adding all data to the attachment.
 - 'addData:'.- It will fail if 'CDTBlobWriter:isBlobOpen' is false.
 - 'createBlobWithData:error:'.- This method overwrites the content of the file supplied during the
 initialisation or creates it if it does not exist. However, it will fail if the blob is open.
 
 And CDTBlobReader:
 
 - 'dataWithError:'.- It will fail if the blob is open.
 - 'inputStreamWithOutputLength:'.- As the previous method, it will fail if the blob is open.
 
 @see CDTBlobReader
 @see CDTBlobWriter
 */
@interface CDTBlobData : NSObject <CDTBlobReader, CDTBlobWriter>

- (instancetype)init UNAVAILABLE_ATTRIBUTE;

- (instancetype)initWithPath:(NSString *)path NS_DESIGNATED_INITIALIZER;

+ (instancetype)blobWithPath:(NSString *)path;

@end
